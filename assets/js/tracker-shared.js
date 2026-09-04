// ============================================================
// Shared stage vocabulary — the exact TRACKER_STATUSES/TRACKER_FLOW
// keys from index-1.html (AUDIT.md §9), unrenamed, with a customer-
// facing label layered on top per BOOKING_FLOW.md §6.1. Used by both
// the public tracker and (in the admin migration phase) the admin
// tracker, so the two can never drift out of sync on wording.
// ============================================================

export const STAGE_FLOW = ['booked', 'dispatched', 'collected', 'processing', 'report_ready', 'completed'];

export const STAGE_META = {
  booked:        { customerLabel: 'Booking Confirmed',            adminLabel: 'Booked',            icon: '📅', color: '#04378A' },
  dispatched:    { customerLabel: 'Agent Assigned',                adminLabel: 'Agent Dispatched',  icon: '🚗', color: '#7C3AED' },
  collected:     { customerLabel: 'Sample Collection',             adminLabel: 'Sample Collected',  icon: '🧪', color: '#16a34a' },
  processing:    { customerLabel: 'Sample Received / Processing',  adminLabel: 'Processing',        icon: '🔬', color: '#d97706' },
  report_ready:  { customerLabel: 'Report Ready',                  adminLabel: 'Report Ready',      icon: '📄', color: '#0891b2' },
  completed:     { customerLabel: 'Completed',                     adminLabel: 'Completed',         icon: '✅', color: '#15803d' },
  no_show:       { customerLabel: 'Missed Appointment',            adminLabel: 'No Show',           icon: '❌', color: '#dc2626' },
  cancelled:     { customerLabel: 'Booking Cancelled',             adminLabel: 'Cancelled',         icon: '🚫', color: '#94A3B8' },
};

export function stageIndex(stage) {
  return STAGE_FLOW.indexOf(stage);
}

export function isTerminalException(stage) {
  return stage === 'cancelled' || stage === 'no_show';
}
