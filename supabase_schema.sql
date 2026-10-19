-- Class Tracker database schema for Supabase
-- Run the full script in Supabase Dashboard > SQL Editor as the project owner.
-- This script protects student calendars with Row Level Security.

create extension if not exists pgcrypto;
create schema if not exists private;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  uid text,
  full_name text,
  phone text,
  role text default 'student',
  created_at timestamptz not null default now()
);

-- Migrate the earlier prototype's `name` column if this database already has it.
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'profiles' and column_name = 'name'
  ) and not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'profiles' and column_name = 'full_name'
  ) then
    alter table public.profiles rename column name to full_name;
  end if;
end;
$$;

alter table public.profiles add column if not exists uid text;
alter table public.profiles add column if not exists full_name text;
alter table public.profiles add column if not exists phone text;
alter table public.profiles add column if not exists role text default 'student';
alter table public.profiles add column if not exists created_at timestamptz not null default now();

-- Existing prototype accounts may have role='viewer' and a required phone field.
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles alter column phone drop not null;
alter table public.profiles alter column full_name set default 'Student';
alter table public.profiles alter column role set default 'student';
update public.profiles set full_name = 'Student' where full_name is null or trim(full_name) = '';
update public.profiles set role = 'student' where role is null or role = 'viewer';
update public.profiles
set uid = 'CT-' || upper(substr(replace(id::text, '-', ''), 1, 8))
where uid is null or trim(uid) = '';
alter table public.profiles alter column full_name set not null;
alter table public.profiles alter column role set not null;
alter table public.profiles alter column uid set not null;
alter table public.profiles add constraint profiles_role_check check (role in ('student', 'admin'));
create unique index if not exists profiles_uid_unique_idx on public.profiles(uid);
create index if not exists profiles_role_name_idx on public.profiles(role, full_name);

create table if not exists public.app_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.calendar_marks (
  user_id uuid not null references public.profiles(id) on delete cascade,
  mark_date date not null,
  marked_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  primary key (user_id, mark_date)
);

create index if not exists calendar_marks_mark_date_idx on public.calendar_marks(mark_date);
-- Disable client access to the previous prototype's global calendar if it exists.
-- This table does not belong to any one student, so the new app does not use it.
do $$
begin
  if to_regclass('public.calendar_ticks') is not null then
    execute 'alter table public.calendar_ticks enable row level security';
    execute 'revoke all on table public.calendar_ticks from anon, authenticated';
    execute 'drop policy if exists "Signed-in users can view calendar ticks" on public.calendar_ticks';
    execute 'drop policy if exists "Admins can add calendar ticks" on public.calendar_ticks';
    execute 'drop policy if exists "Admins can update calendar ticks" on public.calendar_ticks';
    execute 'drop policy if exists "Admins can remove calendar ticks" on public.calendar_ticks';
  end if;
end;
$$;

-- Server-controlled profile creation. A UID is generated for every new account.
create or replace function public.handle_new_class_tracker_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, uid, full_name, phone, role)
  values (
    new.id,
    'CT-' || upper(substr(replace(new.id::text, '-', ''), 1, 8)),
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''), nullif(split_part(coalesce(new.email, ''), '@', 1), ''), 'Student'),
    nullif(coalesce(new.phone, new.raw_user_meta_data ->> 'phone'), ''),
    'student'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

revoke all on function public.handle_new_class_tracker_user() from public, anon, authenticated;

drop trigger if exists on_auth_user_created_class_tracker on auth.users;
create trigger on_auth_user_created_class_tracker
after insert on auth.users
for each row execute function public.handle_new_class_tracker_user();

-- Internal helper. It is not exposed as a public API endpoint.
create or replace function private.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.app_admins a
    where a.user_id = (select auth.uid())
  );
$$;

revoke all on function private.is_admin() from public, anon;
grant usage on schema private to authenticated;
grant execute on function private.is_admin() to authenticated;

-- The browser calls this only to decide which dashboard to render.
-- It returns a boolean for the current user and does not expose the admin list.
create or replace function public.is_class_tracker_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_admin();
$$;

revoke all on function public.is_class_tracker_admin() from public, anon;
grant execute on function public.is_class_tracker_admin() to authenticated;

alter table public.profiles enable row level security;
alter table public.app_admins enable row level security;
alter table public.calendar_marks enable row level security;

-- Keep client-side access limited to the operations actually used by the app.
revoke all on table public.profiles from anon, authenticated;
revoke all on table public.app_admins from anon, authenticated;
revoke all on table public.calendar_marks from anon, authenticated;

grant select on table public.profiles to authenticated;
grant update (full_name) on table public.profiles to authenticated;
grant select, insert, delete on table public.calendar_marks to authenticated;

-- Remove policies with these names first, so this script can safely be rerun.
drop policy if exists "profiles_select_own_or_admin" on public.profiles;
drop policy if exists "profiles_update_own_name" on public.profiles;
drop policy if exists "Users can read own profile" on public.profiles;
drop policy if exists "Users can create own viewer profile" on public.profiles;
drop policy if exists "marks_select_own_or_admin" on public.calendar_marks;
drop policy if exists "marks_insert_admin_only" on public.calendar_marks;
drop policy if exists "marks_delete_admin_only" on public.calendar_marks;

create policy "profiles_select_own_or_admin"
on public.profiles for select
to authenticated
using (id = (select auth.uid()) or (select private.is_admin()));

create policy "profiles_update_own_name"
on public.profiles for update
to authenticated
using (id = (select auth.uid()) and role = 'student')
with check (id = (select auth.uid()) and role = 'student');

create policy "marks_select_own_or_admin"
on public.calendar_marks for select
to authenticated
using (user_id = (select auth.uid()) or (select private.is_admin()));

create policy "marks_insert_admin_only"
on public.calendar_marks for insert
to authenticated
with check (
  (select private.is_admin())
  and marked_by = (select auth.uid())
);

create policy "marks_delete_admin_only"
on public.calendar_marks for delete
to authenticated
using ((select private.is_admin()));

-- IMPORTANT: create the admin Auth user first, then replace the email below and
-- run the two statements in the Supabase SQL Editor. Do NOT put this email into
-- the public website config. This grants administrator access to that account.
--
-- insert into public.app_admins (user_id)
-- select id from auth.users where lower(email) = lower('YOUR_ADMIN_EMAIL@example.com')
-- on conflict (user_id) do nothing;
--
-- update public.profiles
-- set role = 'admin'
-- where id = (select id from auth.users where lower(email) = lower('YOUR_ADMIN_EMAIL@example.com'));
--
-- Only accounts listed in app_admins are admins; changing a client-side value
-- or editing the visible profile role cannot grant admin database permissions.
