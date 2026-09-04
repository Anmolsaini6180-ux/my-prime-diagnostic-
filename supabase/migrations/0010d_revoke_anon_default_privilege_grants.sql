-- ============================================================
-- Migration: 0010d_revoke_anon_default_privilege_grants
-- ============================================================
-- Root cause found by inspecting pg_proc.proacl directly (not just
-- has_function_privilege, which only told us WHETHER, not WHY): this
-- Supabase project has `ALTER DEFAULT PRIVILEGES ... GRANT EXECUTE ON
-- FUNCTIONS TO anon, authenticated, service_role` configured at the
-- project level (Supabase's own project-template default, separate
-- from vanilla Postgres's PUBLIC-grant-on-create behavior). Every
-- brand-new function in `public` -- admin_update_booking,
-- assign_collection_agent, admin_dashboard_stats, team_workload --
-- got an EXPLICIT anon grant automatically at CREATE time. 0010c's
-- `revoke ... from public` was a no-op for these four: there never
-- was a PUBLIC grant, so nothing needed revoking there -- the grant
-- to revoke is anon's own, specifically.
--
-- (create_booking was already fixed correctly in migration 0010's own
-- `revoke execute ... from anon` line, confirmed via proacl: no anon
-- entry at all. This migration applies that same correct pattern to
-- the other four.)
--
-- Practical exposure before this fix, confirmed by reading each
-- function body:
--   - admin_update_booking / assign_collection_agent: both start with
--     `if v_role not in ('main_admin','sub_admin') then raise
--     exception`. anon has no profiles row, so current_user_role()
--     returns null, the check fails, and the call was already
--     rejected even while technically callable. No booking/profile
--     was ever modifiable by anon through either path.
--   - admin_dashboard_stats / team_workload: SECURITY INVOKER (no
--     `security definer`), and anon has no SELECT grant on
--     `bookings`/`profiles` at all -- calling these as anon would
--     fail with a Postgres permission error on the underlying table,
--     not return data.
-- So this was a grant-hygiene gap, not a live data-exposure hole --
-- fixed anyway, as defense in depth and for a clean advisor result.
--
-- Verified live after this migration (real HTTP calls against the
-- production REST endpoint, not simulated): anon calling
-- create_booking returns HTTP 401 `permission denied for function
-- create_booking`. See SECURITY.md for the full test writeup.
-- ============================================================

revoke execute on function public.admin_update_booking(
  uuid, text, text, text, date, text, text, jsonb, date, uuid, text, text, uuid, text
) from anon;
revoke execute on function public.assign_collection_agent(uuid, uuid) from anon;
revoke execute on function public.admin_dashboard_stats() from anon;
revoke execute on function public.team_workload() from anon;
