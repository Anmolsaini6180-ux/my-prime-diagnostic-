-- ============================================================
-- Migration: 0002_security_hardening_fixes
-- ============================================================
-- Fixes two issues surfaced by Supabase's own security advisor
-- immediately after 0001 was applied:
--   1. CRITICAL: public.main_admin_locks was created without RLS
--      enabled — fully exposed to anon/authenticated via PostgREST.
--   2. WARN: public.set_updated_at() had a mutable search_path.
--
-- (A third, lower-severity advisory — several SECURITY DEFINER
-- helper functions being callable directly via /rest/v1/rpc/... —
-- is tracked as a known follow-up; see SECURITY.md. The correct fix
-- is relocating those functions to a non-PostgREST-exposed schema
-- and repointing every RLS policy that calls them, which touches
-- ~16 policies and deserves its own careful, isolated migration
-- rather than being rushed in alongside unrelated work.)
-- ============================================================

alter table public.main_admin_locks enable row level security;

create policy "main_admin_locks_main_admin_read" on public.main_admin_locks
  for select using (public.is_main_admin());

-- No insert/update/delete policy is defined deliberately: with RLS
-- enabled and no policy for those commands, every role (including
-- main_admin) is denied direct writes from the client. The only
-- writer is handle_new_auth_user(), a SECURITY DEFINER trigger
-- function that bypasses RLS via its owner's privileges — mirroring
-- the original app's "immutable once created" guarantee for
-- system_meta/main_admins/locked/{uid}.

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;
