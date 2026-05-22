create table if not exists public.sms_processing_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  sms_hash text not null,
  sender_id text,
  status text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, sms_hash)
);

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
