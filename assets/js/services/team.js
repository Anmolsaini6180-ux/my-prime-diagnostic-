// ============================================================
// Team/staff service. Reads rely entirely on existing profiles RLS
// (main_admin: everyone; sub_admin: their own team only, via
// profiles_sub_admin_select_team). Writes to role/status are
// main_admin-only at the RLS level (profiles_main_admin_update_all) —
// this module doesn't attempt to work around that for sub_admin;
// admin/team.html hides those controls for anyone else, matching
// what the database actually allows.
// ============================================================
import { supabase } from '../supabase-client.js';

export async function fetchStaff() {
  const { data, error } = await supabase
    .from('profiles')
    .select('id, full_name, email, phone, role, status, parent_sub_admin_id, created_at, last_login')
    .in('role', ['main_admin', 'sub_admin', 'collection_agent'])
    .order('role')
    .order('full_name');
  if (error) throw error;
  return data || [];
}

export async function fetchProtectedUids() {
  const { data, error } = await supabase.from('main_admin_locks').select('uid');
  if (error) throw error; // main_admin-only read policy — sub_admin gets a clean RLS-empty array, not an error
  return new Set((data || []).map(r => r.uid));
}

export async function fetchWorkload() {
  const { data, error } = await supabase.rpc('team_workload');
  if (error) throw error;
  return data || [];
}

export async function updateStaffStatus(uid, status) {
  const { error } = await supabase.from('profiles').update({ status }).eq('id', uid);
  if (error) throw error;
}

export async function updateStaffRole(uid, role, parentSubAdminId) {
  const payload = { role };
  if (role === 'collection_agent') payload.parent_sub_admin_id = parentSubAdminId || null;
  const { error } = await supabase.from('profiles').update(payload).eq('id', uid);
  if (error) throw error;
}

/** The only way a new staff account is ever created — see
 * supabase/functions/admin-create-staff. Never creates a password; the
 * invited person sets their own via Supabase's real invite email. */
export async function inviteStaff({ email, fullName, phone, role, parentSubAdminId }) {
  const { data, error } = await supabase.functions.invoke('admin-create-staff', {
    body: { email, full_name: fullName, phone, role, parent_sub_admin_id: parentSubAdminId || null },
  });
  if (error) {
    // supabase-js wraps a non-2xx Edge Function response in a generic
    // FunctionsHttpError — surface the function's own JSON message
    // when available instead of a bare "Edge Function returned a
    // non-2xx status code".
    const detail = await error.context?.json?.().catch(() => null);
    throw new Error(detail?.error || error.message);
  }
  if (data?.error) throw new Error(data.error);
  return data;
}
