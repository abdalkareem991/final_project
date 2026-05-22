alter table if exists public.tasks
  add column if not exists reminder_enabled boolean not null default false,
  add column if not exists reminder_time timestamptz,
  add column if not exists due_time text,
  add column if not exists notification_id integer;

update public.tasks
set
  reminder_enabled = coalesce(has_notification, false),
  reminder_time = case
    when coalesce(has_notification, false) and due_time is not null
      then date_trunc('day', due_date)::date + due_time::time
    else reminder_time
  end,
  due_time = coalesce(due_time, to_char(due_date, 'HH24:MI'))
where due_time is null
   or reminder_time is null
   or reminder_enabled is distinct from coalesce(has_notification, false);
