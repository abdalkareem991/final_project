-- Performance APIs for FinMind.
-- Run this migration in Supabase before switching production traffic fully to
-- the new Flutter API callers.

create table if not exists public.sms_processing_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  sms_hash text not null,
  sender_id text,
  status text not null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, sms_hash)
);

alter table public.sms_processing_logs
  add column if not exists details jsonb not null default '{}'::jsonb;

alter table public.sms_processing_logs
  add column if not exists sender_id text;

alter table public.sms_processing_logs
  add column if not exists status text;

alter table public.sms_processing_logs
  add column if not exists created_at timestamptz not null default now();

alter table public.sms_processing_logs
  add column if not exists updated_at timestamptz not null default now();

update public.sms_processing_logs
set status = 'pending'
where status is null;

alter table public.sms_processing_logs
  alter column status set not null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.sms_processing_logs'::regclass
      and contype = 'u'
      and pg_get_constraintdef(oid) = 'UNIQUE (user_id, sms_hash)'
  ) then
    alter table public.sms_processing_logs
      add constraint sms_processing_logs_user_id_sms_hash_key unique (user_id, sms_hash);
  end if;
end $$;

alter table public.sms_processing_logs enable row level security;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'sms_processing_logs'
      and policyname = 'Users can manage their SMS processing logs'
  ) then
    create policy "Users can manage their SMS processing logs"
    on public.sms_processing_logs
    for all
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);
  end if;
end $$;

create index if not exists idx_transactions_user_id
  on public.transactions (user_id);

create index if not exists idx_transactions_created_at
  on public.transactions (created_at);

create index if not exists idx_transactions_wallet_id
  on public.transactions (wallet_id);

create index if not exists idx_transactions_user_date
  on public.transactions (user_id, date desc);

create index if not exists idx_transactions_user_sms_hash
  on public.transactions (user_id, sms_hash)
  where sms_hash is not null;

do $$
begin
  if not exists (
    select 1
    from public.transactions
    where sms_hash is not null
    group by user_id, sms_hash
    having count(*) > 1
  ) and not exists (
    select 1
    from pg_indexes
    where schemaname = 'public'
      and indexname = 'idx_transactions_user_sms_hash_unique'
  ) then
    execute 'create unique index idx_transactions_user_sms_hash_unique on public.transactions (user_id, sms_hash) where sms_hash is not null';
  end if;
end $$;

create index if not exists idx_tasks_user_id
  on public.tasks (user_id);

create index if not exists idx_sms_processing_logs_user_id
  on public.sms_processing_logs (user_id);

create index if not exists idx_sms_processing_logs_sms_hash
  on public.sms_processing_logs (sms_hash);

create or replace function public.process_sms_transaction_atomic(
  p_sms_hash text,
  p_sender_id text,
  p_sms_body text default null,
  p_received_at timestamptz default null,
  p_wallet_id uuid default null,
  p_amount numeric default null,
  p_type text default null,
  p_available_balance numeric default null,
  p_transaction_date timestamptz default null,
  p_sms_kind text default null,
  p_merchant_name text default null,
  p_counterparty text default null,
  p_is_cliq boolean default false
)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_log_id uuid;
  v_existing_status text;
  v_existing_transaction_id uuid;
  v_existing_wallet_id uuid;
  v_wallet record;
  v_amount numeric;
  v_type text;
  v_transaction_date timestamptz;
  v_category_id int;
  v_category_name text;
  v_category_type text;
  v_category_icon text;
  v_category_color text;
  v_description text;
  v_party text;
  v_sms_kind text := coalesce(nullif(trim(p_sms_kind), ''), 'Bank Transaction');
  v_transaction_id uuid;
  v_delta numeric;
  v_balance_after numeric;
  v_is_internal_transfer boolean := false;
  v_transfer_match record;
  v_transfer_group_id text;
  v_transfer_category_id int;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  p_sms_hash := nullif(trim(coalesce(p_sms_hash, '')), '');
  p_sender_id := nullif(trim(coalesce(p_sender_id, '')), '');

  if p_sms_hash is null then
    raise exception 'invalid_sms_hash';
  end if;

  insert into public.sms_processing_logs (
    user_id,
    sms_hash,
    sender_id,
    status,
    details,
    updated_at
  )
  values (
    v_user_id,
    p_sms_hash,
    p_sender_id,
    'pending',
    jsonb_build_object(
      'received_at', p_received_at,
      'wallet_id', p_wallet_id
    ),
    now()
  )
  on conflict (user_id, sms_hash) do nothing
  returning id into v_log_id;

  if v_log_id is null then
    select status
    into v_existing_status
    from public.sms_processing_logs
    where user_id = v_user_id
      and sms_hash = p_sms_hash
    limit 1;

    select id, wallet_id
    into v_existing_transaction_id, v_existing_wallet_id
    from public.transactions
    where user_id = v_user_id
      and sms_hash = p_sms_hash
    limit 1;

    return jsonb_build_object(
      'status', 'duplicate',
      'transaction_id', v_existing_transaction_id,
      'wallet_id', v_existing_wallet_id,
      'message', 'SMS already processed or already logged.',
      'log_status', coalesce(v_existing_status, 'unknown')
    );
  end if;

  select id, wallet_id
  into v_existing_transaction_id, v_existing_wallet_id
  from public.transactions
  where user_id = v_user_id
    and sms_hash = p_sms_hash
  limit 1;

  if v_existing_transaction_id is not null then
    update public.sms_processing_logs
    set status = 'processed',
        details = details || jsonb_build_object(
          'transaction_id', v_existing_transaction_id,
          'wallet_id', v_existing_wallet_id,
          'duplicate_transaction_found', true
        ),
        updated_at = now()
    where user_id = v_user_id
      and sms_hash = p_sms_hash;

    return jsonb_build_object(
      'status', 'duplicate',
      'transaction_id', v_existing_transaction_id,
      'wallet_id', v_existing_wallet_id,
      'message', 'SMS transaction already exists.'
    );
  end if;

  v_amount := abs(coalesce(p_amount, 0));
  v_type := case lower(trim(coalesce(p_type, '')))
    when 'income' then 'Income'
    when 'expense' then 'Expense'
    else null
  end;

  if v_amount <= 0 or v_type is null then
    update public.sms_processing_logs
    set status = 'failed_parse',
        details = details || jsonb_build_object(
          'reason', 'amount_or_type_not_detected',
          'sms_body_present', p_sms_body is not null
        ),
        updated_at = now()
    where user_id = v_user_id
      and sms_hash = p_sms_hash;

    return jsonb_build_object(
      'status', 'failed_parse',
      'transaction_id', null,
      'wallet_id', null,
      'message', 'SMS could not be parsed into a valid transaction.'
    );
  end if;

  if p_wallet_id is not null then
    select id, name, balance
    into v_wallet
    from public.wallets
    where user_id = v_user_id
      and id = p_wallet_id
    limit 1;
  else
    select id, name, balance
    into v_wallet
    from public.wallets
    where user_id = v_user_id
      and sms_sender_id = p_sender_id
      and account_mode = 'AUTOMATED'
      and is_active_monitoring = true
    limit 1;
  end if;

  if not found then
    update public.sms_processing_logs
    set status = 'failed_wallet',
        details = details || jsonb_build_object('reason', 'no_linked_wallet'),
        updated_at = now()
    where user_id = v_user_id
      and sms_hash = p_sms_hash;

    return jsonb_build_object(
      'status', 'failed_wallet',
      'transaction_id', null,
      'wallet_id', null,
      'message', 'No linked monitored wallet was found for this SMS.'
    );
  end if;

  v_transaction_date := coalesce(p_transaction_date, p_received_at, now());

  if v_type = 'Income' then
    v_category_name := 'Income';
    v_category_type := 'Income';
    v_category_icon := 'trending_up';
    v_category_color := '#22C55E';
  elsif lower(v_sms_kind) like '%transfer%' or lower(v_sms_kind) like '%cliq%' then
    v_category_name := 'Transfer';
    v_category_type := 'Transfer';
    v_category_icon := 'swap_horiz';
    v_category_color := '#3B82F6';
  elsif lower(v_sms_kind) like '%bill%' then
    v_category_name := 'Bills';
    v_category_type := 'Expense';
    v_category_icon := 'receipt';
    v_category_color := '#F59E0B';
  elsif lower(v_sms_kind) like '%card%' or lower(v_sms_kind) like '%pos%' then
    v_category_name := 'Card Payment';
    v_category_type := 'Expense';
    v_category_icon := 'credit_card';
    v_category_color := '#8B5CF6';
  else
    v_category_name := 'General';
    v_category_type := 'Expense';
    v_category_icon := 'category';
    v_category_color := '#94A3B8';
  end if;

  select id
  into v_category_id
  from public.categories
  where user_id = v_user_id
    and lower(name) = lower(v_category_name)
  order by id
  limit 1;

  if v_category_id is null then
    insert into public.categories (user_id, name, type, icon, color)
    values (v_user_id, v_category_name, v_category_type, v_category_icon, v_category_color)
    returning id into v_category_id;
  end if;

  v_party := nullif(trim(coalesce(p_counterparty, p_merchant_name, '')), '');

  if p_is_cliq then
    if v_party is not null then
      v_description := case when v_type = 'Income' then 'CliQ from ' else 'CliQ to ' end || v_party;
    else
      v_description := case when v_type = 'Income' then 'CliQ Transfer In' else 'CliQ Transfer Out' end;
    end if;
  elsif nullif(trim(coalesce(p_merchant_name, '')), '') is not null then
    v_description := v_sms_kind || ' - ' || trim(p_merchant_name);
  else
    v_description := v_sms_kind || ' - ' || coalesce(v_wallet.name, p_sender_id, 'Account');
  end if;

  begin
    insert into public.transactions (
      user_id,
      wallet_id,
      amount,
      type,
      description,
      category_id,
      sms_hash,
      is_internal_transfer,
      merchant_name,
      sms_kind,
      date
    )
    values (
      v_user_id,
      v_wallet.id,
      v_amount,
      v_type,
      v_description,
      v_category_id,
      p_sms_hash,
      false,
      nullif(trim(coalesce(p_merchant_name, '')), ''),
      v_sms_kind,
      v_transaction_date
    )
    returning id into v_transaction_id;
  exception
    when unique_violation then
      select id, wallet_id
      into v_existing_transaction_id, v_existing_wallet_id
      from public.transactions
      where user_id = v_user_id
        and sms_hash = p_sms_hash
      limit 1;

      update public.sms_processing_logs
      set status = 'processed',
          details = details || jsonb_build_object(
            'transaction_id', v_existing_transaction_id,
            'wallet_id', v_existing_wallet_id,
            'duplicate_transaction_found', true
          ),
          updated_at = now()
      where user_id = v_user_id
        and sms_hash = p_sms_hash;

      return jsonb_build_object(
        'status', 'duplicate',
        'transaction_id', v_existing_transaction_id,
        'wallet_id', v_existing_wallet_id,
        'message', 'SMS transaction already exists.'
      );
    when others then
      update public.sms_processing_logs
      set status = 'failed_transaction',
          details = details || jsonb_build_object('error', sqlerrm),
          updated_at = now()
      where user_id = v_user_id
        and sms_hash = p_sms_hash;

      return jsonb_build_object(
        'status', 'failed_transaction',
        'transaction_id', null,
        'wallet_id', v_wallet.id,
        'message', 'Transaction insert failed.'
      );
  end;

  select id, wallet_id
  into v_transfer_match
  from public.transactions
  where user_id = v_user_id
    and id <> v_transaction_id
    and wallet_id <> v_wallet.id
    and type = case when v_type = 'Income' then 'Expense' else 'Income' end
    and amount = v_amount
    and coalesce(is_internal_transfer, false) = false
    and date >= v_transaction_date - interval '10 minutes'
    and date <= v_transaction_date + interval '10 minutes'
  order by date desc
  limit 1;

  if found then
    v_is_internal_transfer := true;
    v_transfer_group_id := 'transfer_' || replace(gen_random_uuid()::text, '-', '');

    select id
    into v_transfer_category_id
    from public.categories
    where user_id = v_user_id
      and lower(name) = lower('Transfer')
    order by id
    limit 1;

    if v_transfer_category_id is null then
      insert into public.categories (user_id, name, type, icon, color)
      values (v_user_id, 'Transfer', 'Transfer', 'swap_horiz', '#3B82F6')
      returning id into v_transfer_category_id;
    end if;

    update public.transactions
    set is_internal_transfer = true,
        transfer_group_id = v_transfer_group_id,
        category_id = v_transfer_category_id
    where user_id = v_user_id
      and id in (v_transaction_id, v_transfer_match.id);
  end if;

  if p_available_balance is not null then
    update public.wallets
    set balance = p_available_balance
    where user_id = v_user_id
      and id = v_wallet.id
    returning balance into v_balance_after;
  else
    v_delta := case when v_type = 'Income' then v_amount else -v_amount end;

    update public.wallets
    set balance = coalesce(balance, 0) + v_delta
    where user_id = v_user_id
      and id = v_wallet.id
    returning balance into v_balance_after;
  end if;

  begin
    update public.users
    set total_net_worth = (
      select coalesce(sum(balance), 0)
      from public.wallets
      where user_id = v_user_id
    )
    where id = v_user_id;
  exception
    when others then
      null;
  end;

  update public.sms_processing_logs
  set status = 'processed',
      details = details || jsonb_build_object(
        'transaction_id', v_transaction_id,
        'wallet_id', v_wallet.id,
        'amount', v_amount,
        'type', v_type,
        'is_internal_transfer', v_is_internal_transfer
      ),
      updated_at = now()
  where user_id = v_user_id
    and sms_hash = p_sms_hash;

  return jsonb_build_object(
    'status', 'processed',
    'transaction_id', v_transaction_id,
    'wallet_id', v_wallet.id,
    'wallet_name', v_wallet.name,
    'amount', v_amount,
    'type', v_type,
    'description', v_description,
    'balance_after', v_balance_after,
    'is_internal_transfer', v_is_internal_transfer,
    'message', 'SMS transaction processed.'
  );
end;
$$;

create or replace function public.get_monthly_analytics(
  p_start_date timestamptz,
  p_end_date timestamptz,
  p_wallet_id uuid default null
)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_total_income numeric := 0;
  v_total_expenses numeric := 0;
  v_income_categories jsonb := '[]'::jsonb;
  v_expense_categories jsonb := '[]'::jsonb;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  with filtered as (
    select
      t.amount,
      lower(coalesce(t.type, '')) as transaction_type,
      t.category_id,
      c.name as category_name,
      c.icon,
      c.color
    from public.transactions t
    left join public.categories c on c.id = t.category_id
    where t.user_id = v_user_id
      and coalesce(t.is_hidden, false) = false
      and coalesce(t.is_internal_transfer, false) = false
      and t.date >= p_start_date
      and t.date <= p_end_date
      and (p_wallet_id is null or t.wallet_id = p_wallet_id)
      and lower(coalesce(t.type, '')) in ('income', 'expense')
  )
  select
    coalesce(sum(abs(amount)) filter (where transaction_type = 'income'), 0),
    coalesce(sum(abs(amount)) filter (where transaction_type = 'expense'), 0)
  into v_total_income, v_total_expenses
  from filtered;

  with income_buckets as (
    select
      coalesce(t.category_id::text, 'uncategorized') as category_id,
      coalesce(c.name, 'Uncategorized') as category_name,
      max(c.icon) as icon,
      max(c.color) as color,
      sum(abs(t.amount)) as total_amount
    from public.transactions t
    left join public.categories c on c.id = t.category_id
    where t.user_id = v_user_id
      and coalesce(t.is_hidden, false) = false
      and coalesce(t.is_internal_transfer, false) = false
      and t.date >= p_start_date
      and t.date <= p_end_date
      and (p_wallet_id is null or t.wallet_id = p_wallet_id)
      and lower(coalesce(t.type, '')) = 'income'
    group by coalesce(t.category_id::text, 'uncategorized'), coalesce(c.name, 'Uncategorized')
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'category_id', category_id,
        'category_name', category_name,
        'total_amount', total_amount,
        'percentage', case when v_total_income > 0 then round((total_amount / v_total_income) * 100, 1) else 0 end,
        'type', 'Income',
        'icon', icon,
        'color', color
      )
      order by total_amount desc
    ),
    '[]'::jsonb
  )
  into v_income_categories
  from income_buckets;

  with expense_buckets as (
    select
      coalesce(t.category_id::text, 'uncategorized') as category_id,
      coalesce(c.name, 'Uncategorized') as category_name,
      max(c.icon) as icon,
      max(c.color) as color,
      sum(abs(t.amount)) as total_amount
    from public.transactions t
    left join public.categories c on c.id = t.category_id
    where t.user_id = v_user_id
      and coalesce(t.is_hidden, false) = false
      and coalesce(t.is_internal_transfer, false) = false
      and t.date >= p_start_date
      and t.date <= p_end_date
      and (p_wallet_id is null or t.wallet_id = p_wallet_id)
      and lower(coalesce(t.type, '')) = 'expense'
    group by coalesce(t.category_id::text, 'uncategorized'), coalesce(c.name, 'Uncategorized')
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'category_id', category_id,
        'category_name', category_name,
        'total_amount', total_amount,
        'percentage', case when v_total_expenses > 0 then round((total_amount / v_total_expenses) * 100, 1) else 0 end,
        'type', 'Expense',
        'icon', icon,
        'color', color
      )
      order by total_amount desc
    ),
    '[]'::jsonb
  )
  into v_expense_categories
  from expense_buckets;

  return jsonb_build_object(
    'summary', jsonb_build_object(
      'total_income', v_total_income,
      'total_expenses', v_total_expenses
    ),
    'income_categories', v_income_categories,
    'expense_categories', v_expense_categories,
    'start_date', p_start_date,
    'end_date', p_end_date,
    'wallet_id', p_wallet_id
  );
end;
$$;

create or replace function public.get_dashboard_summary(
  p_recent_limit int default 10,
  p_include_hidden boolean default false
)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_month_start timestamptz := date_trunc('month', now());
  v_month_end timestamptz := date_trunc('month', now()) + interval '1 month' - interval '1 millisecond';
  v_total_balance numeric := 0;
  v_bank_balance numeric := 0;
  v_cash_balance numeric := 0;
  v_analytics jsonb := '{}'::jsonb;
  v_recent_transactions jsonb := '[]'::jsonb;
  v_debtor_total numeric := 0;
  v_creditor_total numeric := 0;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  select
    coalesce(sum(balance), 0),
    coalesce(sum(balance) filter (where lower(coalesce(type, '')) = 'cash'), 0),
    coalesce(sum(balance) filter (where lower(coalesce(type, '')) <> 'cash'), 0)
  into v_total_balance, v_cash_balance, v_bank_balance
  from public.wallets
  where user_id = v_user_id;

  v_analytics := public.get_monthly_analytics(v_month_start, v_month_end, null);

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', tx.id,
        'user_id', tx.user_id,
        'wallet_id', tx.wallet_id,
        'wallet_name', coalesce(w.name, 'Unknown Account'),
        'category_id', tx.category_id,
        'category_name', coalesce(c.name, 'Uncategorized'),
        'amount', tx.amount,
        'type', tx.type,
        'description', tx.description,
        'date', tx.date,
        'created_at', tx.created_at,
        'is_hidden', coalesce(tx.is_hidden, false),
        'is_internal_transfer', coalesce(tx.is_internal_transfer, false),
        'transfer_group_id', tx.transfer_group_id,
        'merchant_name', tx.merchant_name,
        'sms_kind', tx.sms_kind
      )
      order by tx.date desc nulls last, tx.created_at desc
    ),
    '[]'::jsonb
  )
  into v_recent_transactions
  from (
    select *
    from public.transactions
    where user_id = v_user_id
      and (p_include_hidden or coalesce(is_hidden, false) = false)
    order by date desc nulls last, created_at desc
    limit greatest(1, least(coalesce(p_recent_limit, 10), 50))
  ) tx
  left join public.wallets w on w.id = tx.wallet_id
  left join public.categories c on c.id = tx.category_id;

  select
    coalesce(sum(amount) filter (where type = 'debtor'), 0),
    coalesce(sum(amount) filter (where type = 'creditor'), 0)
  into v_debtor_total, v_creditor_total
  from public.debts
  where user_id = v_user_id
    and status = 'active';

  return jsonb_build_object(
    'total_balance', v_total_balance,
    'bank_balance', v_bank_balance,
    'cash_balance', v_cash_balance,
    'monthly_income', coalesce((v_analytics->'summary'->>'total_income')::numeric, 0),
    'monthly_expenses', coalesce((v_analytics->'summary'->>'total_expenses')::numeric, 0),
    'recent_transactions', v_recent_transactions,
    'income_category_summary', coalesce(v_analytics->'income_categories', '[]'::jsonb),
    'expense_category_summary', coalesce(v_analytics->'expense_categories', '[]'::jsonb),
    'debts_summary', jsonb_build_object(
      'total_debtor_amount', v_debtor_total,
      'total_creditor_amount', v_creditor_total,
      'net_debt', v_debtor_total - v_creditor_total
    ),
    'generated_at', now()
  );
end;
$$;

grant execute on function public.process_sms_transaction_atomic(
  text,
  text,
  text,
  timestamptz,
  uuid,
  numeric,
  text,
  numeric,
  timestamptz,
  text,
  text,
  text,
  boolean
) to authenticated;

grant execute on function public.get_monthly_analytics(
  timestamptz,
  timestamptz,
  uuid
) to authenticated;

grant execute on function public.get_dashboard_summary(
  int,
  boolean
) to authenticated;
