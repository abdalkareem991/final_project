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

create index if not exists idx_tasks_user_id
  on public.tasks (user_id);

create index if not exists idx_sms_processing_logs_user_id
  on public.sms_processing_logs (user_id);

create index if not exists idx_sms_processing_logs_sms_hash
  on public.sms_processing_logs (sms_hash);

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
      t.type,
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
      and t.type in ('Income', 'Expense')
  )
  select
    coalesce(sum(abs(amount)) filter (where type = 'Income'), 0),
    coalesce(sum(abs(amount)) filter (where type = 'Expense'), 0)
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
      and t.type = 'Income'
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
      and t.type = 'Expense'
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
