alter table public.transactions
drop column if exists category_hint;

drop index if exists public.idx_transactions_user_category_hint;

drop function if exists public.process_sms_transaction_atomic(
  text,
  text,
  text,
  timestamp with time zone,
  uuid,
  numeric,
  text,
  numeric,
  timestamp with time zone,
  text,
  text,
  text,
  text,
  boolean
);
