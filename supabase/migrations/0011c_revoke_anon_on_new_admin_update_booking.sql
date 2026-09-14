-- ============================================================
-- Migration: 0011c_revoke_anon_on_new_admin_update_booking
-- ============================================================
-- Third catch from get_advisors, same root cause 0010d already
-- documented for this project: `ALTER DEFAULT PRIVILEGES ... GRANT
-- EXECUTE ON FUNCTIONS TO anon, authenticated, service_role` is set
-- project-wide, so the NEW admin_update_booking(...,p_amount_received)
-- function object created in migration 0011 (a distinct signature,
-- not a true replacement -- see 0011b) got an automatic anon grant at
-- CREATE time, exactly like 0010d found for the original function.
-- 0011 only added `grant ... to authenticated`, which doesn't remove
-- an already-present anon grant. Closing that gap here.
--
-- Same practical-exposure note as 0010d: admin_update_booking's own
-- first check (`if v_role not in ('main_admin','sub_admin') then
-- raise exception`) already rejects anon (no profiles row => null
-- role) before touching any data -- this is a grant-hygiene fix, not
-- a live data-exposure hole, done anyway for a clean advisor result
-- and to keep this function's grants identical to every other
-- staff-only RPC in the project.
-- ============================================================

revoke execute on function public.admin_update_booking(
  uuid, text, text, text, date, text, text, jsonb, date, uuid, text, text, uuid, text, numeric
) from public, anon;
