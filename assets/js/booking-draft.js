// ============================================================
// Booking draft — the cross-page state for the wizard.
// sessionStorage (not localStorage): per-tab, self-clears when the
// browser tab closes — a booking draft has no business lingering
// across unrelated future visits the way mhl_appointments-style
// caches might. Cleared explicitly on successful submit either way.
// See ARCHITECTURE_PLAN.md §6.
// ============================================================
const DRAFT_KEY = 'mpd_booking_draft';

export function getDraft() {
  try {
    return JSON.parse(sessionStorage.getItem(DRAFT_KEY) || 'null');
  } catch (e) {
    return null;
  }
}

export function saveDraft(partial) {
  const current = getDraft() || {};
  const merged = { ...current, ...partial };
  sessionStorage.setItem(DRAFT_KEY, JSON.stringify(merged));
  return merged;
}

export function clearDraft() {
  sessionStorage.removeItem(DRAFT_KEY);
}

/** Call when a package/test's "Book Now" is clicked — starts a fresh draft. */
export function startDraft({ itemType, itemId, itemName, itemPrice }) {
  clearDraft();
  return saveDraft({
    itemType, itemId, itemName, itemPrice,
    idempotencyKey: crypto.randomUUID(),
  });
}

/**
 * Every wizard step page calls this first. If there's no item selected
 * yet (direct URL visit, expired tab, etc.) it sends the visitor back
 * to Packages instead of showing a broken/empty wizard step.
 */
export function requireDraftOrRedirect() {
  const draft = getDraft();
  if (!draft || !draft.itemId) {
    location.href = '/pages/packages.html';
    return null;
  }
  return draft;
}

/** The compact package/test summary that stays visible through the whole flow. */
export function renderSummaryRail(container, draft) {
  if (!container || !draft) return;
  container.innerHTML = `
    <div class="booking-summary-rail">
      <div class="booking-summary-icon">${draft.itemType === 'package' ? '📦' : '🔬'}</div>
      <div class="booking-summary-info">
        <div class="booking-summary-name">${draft.itemName}</div>
        <div class="booking-summary-price">₹${Number(draft.itemPrice).toLocaleString('en-IN')}</div>
      </div>
      <a href="/pages/packages.html" class="booking-summary-change">Change</a>
    </div>`;
}

/** Step progress indicator — shared markup across all 5 wizard pages. */
const STEPS = [
  { key: 'patient', num: '01', label: 'Patient' },
  { key: 'collection', num: '02', label: 'Collection' },
  { key: 'schedule', num: '03', label: 'Schedule' },
  { key: 'review', num: '04', label: 'Review' },
  { key: 'confirmed', num: '05', label: 'Confirmed' },
];

export function renderStepper(container, currentKey) {
  if (!container) return;
  const currentIdx = STEPS.findIndex(s => s.key === currentKey);
  container.innerHTML = `
    <div class="booking-stepper">
      ${STEPS.map((s, i) => `
        <div class="booking-step ${i < currentIdx ? 'done' : ''} ${i === currentIdx ? 'active' : ''}">
          <div class="booking-step-dot">${i < currentIdx ? '✓' : s.num}</div>
          <div class="booking-step-label">${s.label}</div>
        </div>
      `).join('<div class="booking-step-line"></div>')}
    </div>`;
}
