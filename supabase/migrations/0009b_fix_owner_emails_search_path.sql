-- ============================================================
-- Migration: 0009b_fix_owner_emails_search_path
-- ============================================================
-- Caught immediately via get_advisors after 0009: private.owner_emails()
-- was missing `set search_path`. Low practical risk (the body is a
-- constant array literal with no table/column references at all), but
-- fixed for consistency with every other function in this project.
-- ============================================================

create or replace function private.owner_emails()
returns text[]
language sql
immutable
set search_path = public
as $$
  select array['workwithme.digital@gmail.com', 'thisisamansaini@gmail.com', 'anmolsaini6180@gmail.com'];
$$;
