// ============================================================
// Admin booking queries — every query here relies on RLS to scope
// results to whatever the signed-in staff member is allowed to see
// (main_admin: all, sub_admin: their team, collection_agent: their
// own bookings). No role-based filtering is duplicated client-side;
// the database is the only place that decides visibility.
// ============================================================
import { supabase } from '../supabase-client.js';

const LIST_SELECT = `
  id, booking_code, patient_name, patient_phone, scheduled_date, collection_type,
  final_amount, payment_mode, payment_status, status, stage, source, created_at,
  assigned_collection_agent_id,
  booking_items ( name_snapshot ),
  appointment_slots ( label )
`;

/** Single RLS-respecting RPC (migration 0010) replaces the old 8
 * separate count queries — one round trip, and a role's numbers are
 * automatically scoped to whatever bookings that role's own RLS
 * policies let it see (main_admin: everything; sub_admin: their team;
 * collection_agent: their own bookings). */
export async function fetchDashboardCounts() {
  const { data, error } = await supabase.rpc('admin_dashboard_stats');
  if (error) throw error;
  const r = data && data[0];
  if (!r) return {};
  return {
    total: r.total_bookings, today: r.today_bookings, pending: r.pending_count, confirmed: r.confirmed_count,
    sampleCollected: r.sample_collected_count, processing: r.processing_count,
    completed: r.completed_count, cancelled: r.cancelled_count,
    home: r.home_count, walkIn: r.walkin_count,
    unassigned: r.unassigned_count, assigned: r.assigned_count,
    revenue: r.total_revenue,
  };
}

export async function fetchRecentBookings(limit = 8) {
  const { data, error } = await supabase
    .from('bookings')
    .select(LIST_SELECT)
    .order('created_at', { ascending: false })
    .limit(limit);
  if (error) throw error;
  return data || [];
}

export async function fetchBookings({ search, status, collectionType } = {}) {
  let q = supabase.from('bookings').select(LIST_SELECT).order('created_at', { ascending: false }).limit(200);
  if (status && status !== 'all') q = q.eq('status', status);
  if (collectionType && collectionType !== 'all') q = q.eq('collection_type', collectionType);
  if (search) q = q.or(`patient_name.ilike.%${search}%,patient_phone.ilike.%${search}%,booking_code.ilike.%${search}%`);
  const { data, error } = await q;
  if (error) throw error;
  return data || [];
}

export async function fetchBookingDetail(id) {
  const { data, error } = await supabase
    .from('bookings')
    .select(`
      *, booking_items ( item_type, name_snapshot, price_snapshot ),
      collection_addresses ( address_line, city, state, pincode, landmark ),
      appointment_slots ( label )
    `)
    .eq('id', id)
    .maybeSingle();
  if (error) throw error;
  if (!data) return null;

  const { data: history } = await supabase
    .from('booking_status_history')
    .select('old_status, new_status, changed_by_name, note, created_at')
    .eq('booking_id', id)
    .order('created_at', { ascending: true });

  return { ...data, history: history || [] };
}

/** All bookings in the caller's RLS scope, for the tracker's client-side grouping — mirrors the original app's _getTrackerBookings pattern (fetch once, filter/group in the UI). */
export async function fetchTrackerBookings() {
  const { data, error } = await supabase
    .from('bookings')
    .select(LIST_SELECT)
    .not('status', 'in', '(cancelled,failed)')
    .order('scheduled_date', { ascending: true });
  if (error) throw error;
  return data || [];
}

export async function updateBookingStage(bookingId, newStage, note) {
  const { error } = await supabase.rpc('update_booking_stage', {
    p_booking_id: bookingId, p_new_stage: newStage, p_note: note || null,
  });
  if (error) throw error;
}

/** Active collection agents visible to the caller (RLS: main_admin sees
 * all, sub_admin sees their own team via profiles_sub_admin_select_team). */
export async function fetchCollectionAgents() {
  const { data, error } = await supabase
    .from('profiles')
    .select('id, full_name, email')
    .eq('role', 'collection_agent')
    .eq('status', 'active')
    .order('full_name');
  if (error) throw error;
  return data || [];
}

export async function assignCollectionAgent(bookingId, agentId) {
  const { error } = await supabase.rpc('assign_collection_agent', { p_booking_id: bookingId, p_agent_id: agentId });
  if (error) throw error;
}

/** Partial update — any field omitted (undefined) is left out of the
 * call entirely so admin_update_booking's own coalesce(param, current)
 * logic keeps the existing value; never sends a field as null unless
 * the caller explicitly means "no change needed for this one". */
export async function adminUpdateBooking(bookingId, fields) {
  const payload = { p_booking_id: bookingId };
  const map = {
    patientName: 'p_patient_name', patientPhone: 'p_patient_phone', patientEmail: 'p_patient_email',
    patientDob: 'p_patient_dob', patientGender: 'p_patient_gender', collectionType: 'p_collection_type',
    address: 'p_address', scheduledDate: 'p_scheduled_date', slotId: 'p_slot_id',
    specialNotes: 'p_special_notes', status: 'p_status', assignedAgentId: 'p_assigned_agent_id', note: 'p_note',
    // Migration 0011 — records money actually collected. Does NOT
    // change final_amount at all (still fixed forever at creation); the
    // RPC auto-promotes payment_status to 'paid' once this reaches it.
    amountReceived: 'p_amount_received',
  };
  Object.entries(fields).forEach(([k, v]) => {
    if (v !== undefined && map[k]) payload[map[k]] = v;
  });
  const { error } = await supabase.rpc('admin_update_booking', payload);
  if (error) throw error;
}
