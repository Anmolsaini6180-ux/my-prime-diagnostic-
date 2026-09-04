// ============================================================
// Shared post-login routing — used by both pages/login.html and
// admin/login.html so "where does this session belong" is decided in
// exactly one place, driven entirely by a fresh database read of
// profiles.role (never a value trusted from the client/URL/storage).
// Used for: a normal password login, a fresh Google OAuth callback,
// and an already-existing session found on page load — all three
// funnel through this same function.
// ============================================================
import { supabase } from './supabase-client.js';

const STAFF_ROLES = ['main_admin', 'sub_admin', 'collection_agent'];

/**
 * Returns the URL this session should land on, or null if there is no
 * session at all. Never navigates itself — the caller decides when.
 */
export async function getPostLoginDestination(patientRedirect) {
  const { data: sessionData } = await supabase.auth.getSession();
  if (!sessionData.session) return null;

  const { data: profile } = await supabase
    .from('profiles')
    .select('role, status')
    .eq('id', sessionData.session.user.id)
    .maybeSingle();

  if (profile && STAFF_ROLES.includes(profile.role) && profile.status === 'active') {
    // All staff roles land on the same dashboard today — sub_admin and
    // collection_agent don't have separate dashboard UIs yet (see
    // ADMIN_MIGRATION_MAP.md). Each page's own RLS-scoped queries
    // already show only what that role is allowed to see.
    return '/admin/dashboard.html';
  }
  return patientRedirect || '/pages/my-bookings.html';
}
