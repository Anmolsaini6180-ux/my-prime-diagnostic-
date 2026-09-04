-- ============================================================
-- Migration: 0010c_revoke_public_execute_grants
-- ============================================================
-- Second catch from get_advisors after 0010: PostgreSQL grants
-- EXECUTE to the PUBLIC pseudo-role automatically whenever a function
-- is created (a well-known, easy-to-miss default). `revoke ... from
-- anon` in 0010 only removed anon's role-specific grant -- the
-- broader PUBLIC grant (which anon also inherits, since a PUBLIC
-- grant applies to every role) was untouched, so anon could still
-- technically invoke create_booking/admin_update_booking/
-- assign_collection_agent via PostgREST.
--
-- Practical impact was already contained even before this fix:
--   - create_booking() itself raises an exception for a null
--     auth.uid() (the actual fix from migration 0010) -- an anon call
--     reaches the function and is immediately rejected, never creates
--     a row. Verified live after this migration, see SECURITY.md.
--   - admin_update_booking()/assign_collection_agent() both start by
--     checking current_user_role() is main_admin/sub_admin -- for
--     anon (no profiles row at all) this is null, so both raise
--     immediately too.
-- This migration closes the grant-level gap anyway, as the proper
-- fix rather than relying solely on the runtime check.
--
-- (This turned out to only be PART of the fix -- see 0010d for the
-- actual root cause found immediately after applying this one.)
-- ============================================================

revoke execute on function public.create_booking(
  text, uuid, text, text, text, date, text, text, jsonb, date, uuid, text, text, text, uuid, text
) from public;

revoke execute on function public.admin_update_booking(
  uuid, text, text, text, date, text, text, jsonb, date, uuid, text, text, uuid, text
) from public;

revoke execute on function public.assign_collection_agent(uuid, uuid) from public;

revoke execute on function public.admin_dashboard_stats() from public;
revoke execute on function public.team_workload() from public;

grant execute on function public.create_booking(
  text, uuid, text, text, text, date, text, text, jsonb, date, uuid, text, text, text, uuid, text
) to authenticated;
grant execute on function public.admin_update_booking(
  uuid, text, text, text, date, text, text, jsonb, date, uuid, text, text, uuid, text
) to authenticated;
grant execute on function public.assign_collection_agent(uuid, uuid) to authenticated;
grant execute on function public.admin_dashboard_stats() to authenticated;
grant execute on function public.team_workload() to authenticated;
