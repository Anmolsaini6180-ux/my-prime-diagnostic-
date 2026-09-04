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

export async function fetchDashboardCounts() {
  const today = new Date().toISOString().split('T')[0];
  const [{ count: total }, { count: todayCount }, { count: pending }, { count: confirmed }, { count: home }, { count: walkIn }, { count: completed }, { count: cancelled }] = await Promise.all([
    supabase.from('bookings').select('id', { count: 'exact', head: true }),
    supabase.from('bookings').select('id', { count: 'exact', head: true }).eq('scheduled_date', today),
    supabase.from('bookings').select('id', { count: 'exact', head: true }).eq('status', 'pending'),
    supabase.from('bookings').select('id', { count: 'exact', head: true }).eq('status', 'confirmed'),
    supabase.from('bookings').select('id', { count: 'exact', head: true }).eq('collection_type', 'home'),
    supabase.from('bookings').select('id', { count: 'exact', head: true }).eq('collection_type', 'lab_visit'),
    supabase.from('bookings').select('id', { count: 'exact', head: true }).eq('status', 'completed'),
    supabase.from('bookings').select('id', { count: 'exact', head: true }).eq('status', 'cancelled'),
  ]);
  return { total, today: todayCount, pending, confirmed, home, walkIn, completed, cancelled };
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
