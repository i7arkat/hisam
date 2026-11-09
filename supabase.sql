-- Live sync for the Chemistry Hub lesson. Safe to run more than once.
-- Supabase dashboard -> SQL Editor -> paste this file -> Run.

create table if not exists public.responses (
  lesson     text not null check (lesson ~ '^RL-[0-9]{4}$'),
  code       text not null check (code ~ '^CH[0-9]{1,3}$'),
  answers    jsonb not null default '{}'::jsonb
             check (jsonb_typeof(answers) = 'object' and pg_column_size(answers) < 2000),
  level      text check (level in ('g', 'y', 'r')),
  updated_at timestamptz not null default now(),
  primary key (lesson, code)
);

create table if not exists public.sessions (
  lesson     text primary key check (lesson ~ '^RL-[0-9]{4}$'),
  size       int not null default 25 check (size between 1 and 60),
  -- teacher's merged results, so manual backup codes survive a change of device
  results    jsonb not null default '{}'::jsonb
             check (jsonb_typeof(results) = 'object' and pg_column_size(results) < 200000),
  updated_at timestamptz not null default now()
);

-- Server time, so a student's wrong device clock cannot reorder answers.
create or replace function public.touch_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists touch_updated_at on public.responses;
create trigger touch_updated_at before insert or update on public.responses
  for each row execute function public.touch_updated_at();

drop trigger if exists touch_updated_at on public.sessions;
create trigger touch_updated_at before insert or update on public.sessions
  for each row execute function public.touch_updated_at();

-- No delete access: a visitor can never wipe a class's results.
grant select, insert, update on public.responses, public.sessions to anon, authenticated;

alter table public.responses enable row level security;
alter table public.sessions  enable row level security;

drop policy if exists responses_select on public.responses;
drop policy if exists responses_insert on public.responses;
drop policy if exists responses_update on public.responses;
create policy responses_select on public.responses for select to anon, authenticated using (true);
create policy responses_insert on public.responses for insert to anon, authenticated with check (true);
create policy responses_update on public.responses for update to anon, authenticated using (true) with check (true);

drop policy if exists sessions_select on public.sessions;
drop policy if exists sessions_insert on public.sessions;
drop policy if exists sessions_update on public.sessions;
create policy sessions_select on public.sessions for select to anon, authenticated using (true);
create policy sessions_insert on public.sessions for insert to anon, authenticated with check (true);
create policy sessions_update on public.sessions for update to anon, authenticated using (true) with check (true);

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'responses'
  ) then
    alter publication supabase_realtime add table public.responses;
  end if;
end $$;
