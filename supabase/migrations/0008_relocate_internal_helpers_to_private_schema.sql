-- ============================================================
-- Migration: 0008_relocate_internal_helpers_to_private_schema
-- ============================================================
-- Closes the known SECURITY.md issue: is_main_admin(), is_staff(),
-- current_user_role(), handle_new_auth_user(), prevent_self_role_escalation(),
-- and can_view_booking() were meant to be internal-only but were
-- reachable via PostgREST's auto-generated /rest/v1/rpc/<name> for
-- every function in the `public` schema.
--
-- Why this is safe (traced through, not assumed):
--   - RLS policies reference a function by OID in their compiled
--     USING/WITH CHECK expression (like a view or check constraint
--     does), not by re-parsed name text. `ALTER FUNCTION ... SET
--     SCHEMA` preserves the OID, so all ~27 existing policies that
--     call these functions keep working with ZERO changes.
--   - Function BODIES written as classic `AS $$ ... $$` text (as
--     these all are) DO re-resolve schema-qualified names at each
--     call. Three functions call these helpers from inside their own
--     body text: can_view_booking() (calls is_main_admin/
--     current_user_role), prevent_self_role_escalation() (calls
--     is_main_admin), and update_booking_stage() (calls
--     current_user_role). Those three are recreated below with
--     `private.` prefixes so they keep resolving correctly.
--   - Moving schema does not touch existing GRANTs — the PUBLIC
--     execute grant every function gets by default stays intact,
--     which is exactly what RLS policy evaluation still needs. What
--     actually closes the public-RPC hole is that PostgREST only
--     auto-exposes functions in its configured schema list (public
--     by default) — a function living in `private` is simply never
--     turned into a /rest/v1/rpc/... route, regardless of its grants.
--
-- Verified after applying: get_advisors shows these 6 no longer flagged
-- as anon/authenticated-callable; full re-test of self-escalation
-- blocking, cross-user booking visibility, and collection_agent stage
-- authorization (the exact same Phase 2 tests) confirmed nothing broke.
-- ============================================================

create schema if not exists private;
grant usage on schema private to anon, authenticated;
comment on schema private is 'Never exposed to PostgREST. Holds internal RLS/trigger helper functions that must remain callable from policies but not from the public REST API.';

-- ---- Move the 6 functions (OID-preserving; policies/triggers keep working) ----
alter function public.is_main_admin() set schema private;
alter function public.is_staff() set schema private;
alter function public.current_user_role() set schema private;
alter function public.handle_new_auth_user() set schema private;
alter function public.prevent_self_role_escalation() set schema private;
alter function public.can_view_booking(uuid) set schema private;

-- ---- Recreate the 3 bodies that call these helpers by qualified name ----

create or replace function private.can_view_booking(p_booking_id uuid)
returns boolean
language sql security definer stable set search_path = public
as $$
  select exists (
    select 1 from public.bookings b
    where b.id = p_booking_id
    and (
      b.user_id = auth.uid()
      or private.is_main_admin()
      or (private.current_user_role() = 'sub_admin' and b.parent_sub_admin_id = auth.uid())
      or (private.current_user_role() = 'collection_agent' and (b.assigned_collection_agent_id = auth.uid() or b.created_by_user_id = auth.uid()))
    )
  );
$$;

create or replace function private.prevent_self_role_escalation()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if auth.uid() = old.id and not private.is_main_admin() then
    if new.role <> old.role
       or new.status <> old.status
       or new.parent_sub_admin_id is distinct from old.parent_sub_admin_id then
      raise exception 'Not allowed to change role, status, or reporting line on your own profile.';
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.update_booking_stage(p_booking_id uuid, p_new_stage text, p_note text default null)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_old_stage text;
  v_valid_stages text[] := array['booked','dispatched','collected','processing','report_ready','completed','cancelled','no_show'];
  v_agent_allowed_stages text[] := array['dispatched','collected','cancelled','no_show'];
  v_role public.staff_role := private.current_user_role();
  v_uid uuid := auth.uid();
  v_name text;
begin
  if v_role not in ('main_admin','sub_admin','collection_agent') then
    raise exception 'Only staff can update booking stage';
  end if;

  if p_new_stage <> all(v_valid_stages) then
    raise exception 'Invalid stage: %', p_new_stage;
  end if;

  if v_role = 'collection_agent' and p_new_stage <> all(v_agent_allowed_stages) then
    raise exception 'Collection agents can only set: dispatched, collected, cancelled, or no_show';
  end if;

  if v_role = 'collection_agent' and not exists (
    select 1 from public.bookings
    where id = p_booking_id and (assigned_collection_agent_id = v_uid or created_by_user_id = v_uid)
  ) then
    raise exception 'You are not assigned to this booking';
  end if;

  select stage into v_old_stage from public.bookings where id = p_booking_id;
  if v_old_stage is null then
    raise exception 'Booking not found';
  end if;

  select coalesce(full_name, email) into v_name from public.profiles where id = v_uid;

  update public.bookings
    set stage = p_new_stage,
        status = case when p_new_stage = 'completed' then 'completed'
                      when p_new_stage in ('cancelled','no_show') then 'cancelled'
                      else status end,
        assigned_collection_agent_id = coalesce(assigned_collection_agent_id, case when p_new_stage = 'dispatched' then v_uid end),
        updated_at = now()
    where id = p_booking_id;

  insert into public.booking_status_history (booking_id, old_status, new_status, changed_by, changed_by_name, note)
  values (p_booking_id, v_old_stage, p_new_stage, v_uid, coalesce(v_name, 'Staff'), p_note);
end;
$$;
grant execute on function public.update_booking_stage(uuid, text, text) to authenticated;
