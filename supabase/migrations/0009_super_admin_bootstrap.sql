-- ============================================================
-- Migration: 0009_super_admin_bootstrap
-- ============================================================
-- Adds anmolsaini6180@gmail.com as an approved Head Admin / Super
-- Admin, enforced entirely at the database level (never a frontend
-- `if (email === ...)` check).
--
-- Inspected before changing anything (per instruction):
--   - private.handle_new_auth_user() only fires on auth.users INSERT
--     (a brand-new signup) — it does nothing for an account that
--     already exists.
--   - anmolsaini6180@gmail.com ALREADY has a profiles row
--     (role='patient') — they signed up/logged in at some point
--     before this request. Simply adding their email to the owner
--     list would NOT retroactively promote this existing row, since
--     the trigger never re-fires for it.
--   - main_admin_locks is currently empty — no Head Admin has ever
--     actually completed bootstrap on this Supabase project yet.
--   - A second, unrelated real profile (sagarmedi001@gmail.com,
--     role='patient') also already exists. Not an owner email — must
--     remain completely untouched by this migration, and does.
--
-- Design:
--   1. private.owner_emails() — single source of truth for the
--      approved list, so handle_new_auth_user() and the new catch-up
--      function below can never drift out of sync with each other.
--   2. private.sync_owner_admins() — idempotent: promotes any
--      EXISTING profile matching an owner email that isn't already
--      main_admin, and ensures its lock row exists. Safe to re-run
--      any time (e.g., after adding a future owner email) — a
--      no-op for anyone already promoted. Never touches a non-owner
--      email's role, regardless of how many times it runs.
--   3. Called once, immediately, in this same migration, so
--      anmolsaini6180@gmail.com's existing account is promoted now
--      rather than waiting for a re-signup that will never happen
--      (the account already exists).
--
-- No new auth account was created for anmolsaini6180@gmail.com by
-- this migration or by anyone running it — only their EXISTING
-- profile row was updated. No password was set, generated, or
-- exposed anywhere.
-- ============================================================

create or replace function private.owner_emails()
returns text[]
language sql
immutable
as $$
  select array['workwithme.digital@gmail.com', 'thisisamansaini@gmail.com', 'anmolsaini6180@gmail.com'];
$$;

create or replace function private.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  resolved_role public.staff_role := 'patient';
begin
  if lower(new.email) = any(private.owner_emails()) then
    resolved_role := 'main_admin';
  end if;

  insert into public.profiles (id, email, full_name, phone, role)
  values (
    new.id,
    new.email,
    new.raw_user_meta_data ->> 'full_name',
    new.raw_user_meta_data ->> 'phone',
    resolved_role
  );

  if resolved_role = 'main_admin' then
    insert into public.main_admin_locks (uid, email)
    values (new.id, lower(new.email))
    on conflict (uid) do nothing;
  end if;

  return new;
end;
$$;

-- ---- Idempotent catch-up for accounts that already existed ----
create or replace function private.sync_owner_admins()
returns table(promoted_uid uuid, promoted_email text)
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
begin
  for r in
    select id, email from public.profiles
    where lower(email) = any(private.owner_emails()) and role <> 'main_admin'
  loop
    update public.profiles set role = 'main_admin' where id = r.id;
    insert into public.main_admin_locks (uid, email)
    values (r.id, lower(r.email))
    on conflict (uid) do nothing;

    promoted_uid := r.id;
    promoted_email := r.email;
    return next;
  end loop;
end;
$$;

-- Run it now, once, so anmolsaini6180@gmail.com's existing profile is
-- promoted immediately rather than waiting for an event that already
-- happened (their signup) and will not happen again.
select * from private.sync_owner_admins();
