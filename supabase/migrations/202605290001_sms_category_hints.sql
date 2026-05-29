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
  p_category_hint text default null,
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
  v_result jsonb;
  v_transaction_id uuid;
  v_category_hint text := lower(nullif(trim(coalesce(p_category_hint, '')), ''));
  v_category_id int;
  v_category_name text;
  v_category_type text;
  v_category_icon text;
  v_category_color text;
begin
  v_result := public.process_sms_transaction_atomic(
    p_sms_hash,
    p_sender_id,
    p_sms_body,
    p_received_at,
    p_wallet_id,
    p_amount,
    p_type,
    p_available_balance,
    p_transaction_date,
    p_sms_kind,
    p_merchant_name,
    p_counterparty,
    p_is_cliq
  );

  if v_user_id is null
    or coalesce(v_result->>'status', '') <> 'created'
    or coalesce((v_result->>'is_internal_transfer')::boolean, false)
  then
    return v_result;
  end if;

  v_transaction_id := nullif(v_result->>'transaction_id', '')::uuid;
  if v_transaction_id is null then
    return v_result;
  end if;

  v_category_name := case v_category_hint
    when 'income' then 'Income'
    when 'bank credit' then 'Bank Credit'
    when 'cliq transfer in' then 'CliQ Transfer In'
    when 'wallet transfer in' then 'Wallet Transfer In'
    when 'atm deposit' then 'ATM Deposit'
    when 'refund' then 'Refund'
    when 'cliq transfer out' then 'CliQ Transfer Out'
    when 'wallet transfer out' then 'Wallet Transfer Out'
    when 'atm withdrawal' then 'ATM Withdrawal'
    when 'bank fees' then 'Bank Fees'
    when 'card payment' then 'Card Payment'
    when 'bills - telecom' then 'Bills - Telecom'
    when 'bills - electricity' then 'Bills - Electricity'
    when 'bills - water' then 'Bills - Water'
    when 'bills - internet' then 'Bills - Internet'
    when 'education' then 'Education'
    when 'healthcare' then 'Healthcare'
    when 'services' then 'Services'
    when 'financing / installments' then 'Financing / Installments'
    when 'food & delivery' then 'Food & Delivery'
    when 'online services' then 'Online Services'
    when 'gaming / vouchers' then 'Gaming / Vouchers'
    when 'shopping' then 'Shopping'
    when 'general expense' then 'General Expense'
    else null
  end;

  if v_category_name is null then
    return v_result;
  end if;

  v_category_type := case
    when v_category_name in (
      'Income',
      'Bank Credit',
      'CliQ Transfer In',
      'Wallet Transfer In',
      'ATM Deposit',
      'Refund'
    ) then 'Income'
    else 'Expense'
  end;

  v_category_icon := case
    when v_category_name in ('Income', 'Bank Credit') then 'trending_up'
    when v_category_name like 'CliQ Transfer%' then 'swap_horiz'
    when v_category_name like 'Wallet Transfer%' then 'account_balance_wallet'
    when v_category_name like 'ATM%' then 'account_balance'
    when v_category_name = 'Refund' then 'undo'
    when v_category_name = 'Bank Fees' then 'account_balance_wallet'
    when v_category_name like 'Bills -%' then 'receipt'
    when v_category_name = 'Education' then 'school'
    when v_category_name = 'Healthcare' then 'local_hospital'
    when v_category_name = 'Food & Delivery' then 'restaurant'
    when v_category_name = 'Online Services' then 'language'
    when v_category_name = 'Gaming / Vouchers' then 'sports_esports'
    when v_category_name = 'Shopping' then 'shopping_bag'
    else 'category'
  end;

  v_category_color := case
    when v_category_type = 'Income' then '#22C55E'
    when v_category_name like 'Bills -%' then '#F59E0B'
    when v_category_name in ('CliQ Transfer Out', 'Wallet Transfer Out') then '#3B82F6'
    when v_category_name = 'Food & Delivery' then '#EF4444'
    when v_category_name = 'Online Services' then '#6366F1'
    else '#8B5CF6'
  end;

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

  update public.transactions
  set category_id = v_category_id,
      sms_kind = coalesce(nullif(trim(p_sms_kind), ''), sms_kind)
  where user_id = v_user_id
    and id = v_transaction_id
    and coalesce(is_internal_transfer, false) = false
    and lower(coalesce(type, '')) <> 'transfer';

  return v_result || jsonb_build_object('category_name', v_category_name);
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
  text,
  boolean
) to authenticated;
