// ============================================================
// Admin route guard — every admin/*.html page calls this first.
// Real check: a live Supabase session AND a staff role read fresh
// from `profiles` (never trusted from a cached/local value). Not a
// cosmetic redirect — pages that need role-specific behavior get the
// resolved role back to condition on.
// ============================================================
import { supabase } from './supabase-client.js';

const STAFF_ROLES = ['main_admin', 'sub_admin', 'collection_agent'];

/**
 * Resolves to { user, role, profile } or redirects to admin/login.html
 * and resolves to null. Call this before rendering any admin page body.
 */
export async function requireStaffSession() {
  const { data: sessionData } = await supabase.auth.getSession();
  if (!sessionData.session) {
    location.href = '/admin/login.html';
    return null;
  }

  const { data: profile, error } = await supabase
    .from('profiles')
    .select('id, email, full_name, role, status')
    .eq('id', sessionData.session.user.id)
    .single();

  if (error || !profile || !STAFF_ROLES.includes(profile.role) || profile.status !== 'active') {
    // A real patient account, a deactivated staff account, or a lookup
    // failure — none of these get into the admin area, silently or not.
    await supabase.auth.signOut();
    location.href = '/admin/login.html?denied=1';
    return null;
  }

  return { user: sessionData.session.user, role: profile.role, profile };
}

export function roleLabel(role) {
  return { main_admin: 'Main Admin', sub_admin: 'Sub Admin', collection_agent: 'Collection Agent' }[role] || role;
}
