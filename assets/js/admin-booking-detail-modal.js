// ============================================================
// Shared booking-detail modal (view + stage update) — used by both
// admin/bookings.html and admin/tracker.html so there's one place
// that renders a booking's detail, not two copies to keep in sync.
// Requires the host page to have:
//   <div class="admin-modal-backdrop" id="detailModalBackdrop">
//     <div class="admin-modal"><button class="admin-modal-close" id="detailModalClose">&times;</button>
//       <div id="detailModalBody"></div></div></div>
// ============================================================
import { fetchBookingDetail, updateBookingStage } from './services/admin-bookings.js';
import { STAGE_META } from './tracker-shared.js';

function fmtDate(d) { return new Date(d).toLocaleDateString('en-IN', { day: 'numeric', month: 'short', year: 'numeric' }); }

export function initBookingDetailModal(onChanged) {
  const backdrop = document.getElementById('detailModalBackdrop');
  document.getElementById('detailModalClose').addEventListener('click', () => backdrop.classList.remove('open'));
  backdrop.addEventListener('click', (e) => { if (e.target === backdrop) backdrop.classList.remove('open'); });

  async function openBookingDetailModal(id) {
    const body = document.getElementById('detailModalBody');
    body.innerHTML = `<div class="state-block"><div class="state-icon">⏳</div></div>`;
    backdrop.classList.add('open');
    try {
      const b = await fetchBookingDetail(id);
      if (!b) { body.innerHTML = `<div class="state-block">Not found (outside your access scope, or deleted).</div>`; return; }
      renderDetail(b);
    } catch (e) {
      body.innerHTML = `<div class="state-block"><div class="state-icon">⚠️</div><div class="state-desc">${e.message}</div></div>`;
    }
  }

  function renderDetail(b) {
    const body = document.getElementById('detailModalBody');
    const addr = b.collection_addresses?.[0];
    const meta = STAGE_META[b.stage] || STAGE_META.booked;
    body.innerHTML = `
      <h3 style="margin-bottom:2px;">${b.booking_code}</h3>
      <p style="font-size:12px;margin-bottom:16px;">Created ${new Date(b.created_at).toLocaleString('en-IN')}</p>
      <div class="review-section"><div class="review-row"><span>Patient</span><span>${b.patient_name}</span></div>
        <div class="review-row"><span>Phone</span><span>${b.patient_phone}</span></div>
        ${b.patient_email ? `<div class="review-row"><span>Email</span><span>${b.patient_email}</span></div>` : ''}
      </div>
      <div class="review-section"><div class="review-row"><span>Item</span><span>${b.booking_items?.[0]?.name_snapshot}</span></div>
        <div class="review-row"><span>Amount</span><span>₹${Number(b.final_amount).toLocaleString('en-IN')}</span></div>
        ${b.coupon_code ? `<div class="review-row"><span>Coupon</span><span>${b.coupon_code} (−₹${b.discount_amount})</span></div>` : ''}
      </div>
      <div class="review-section"><div class="review-row"><span>Schedule</span><span>${fmtDate(b.scheduled_date)}, ${b.appointment_slots?.label}</span></div>
        <div class="review-row"><span>Collection</span><span>${b.collection_type === 'home' ? '🏠 Home Collection' : '🏥 Walk-in at Lab'}</span></div>
        ${addr ? `<div class="review-row" style="color:var(--text-muted);">${addr.address_line}, ${addr.city} — ${addr.pincode}</div>` : ''}
      </div>
      <div class="review-section">
        <div class="review-row"><span>Status</span><span class="badge badge-blue">${b.status}</span></div>
        <div class="review-row"><span>Stage</span><span class="badge" style="background:${meta.color}22;color:${meta.color};">${meta.icon} ${meta.adminLabel}</span></div>
        <div class="review-row"><span>Payment</span><span>${b.payment_mode} · ${b.payment_status}</span></div>
      </div>
      <div class="review-section">
        <div class="review-section-title" style="margin-bottom:8px;">Move to Stage</div>
        <div style="display:flex;gap:6px;flex-wrap:wrap;" id="stageButtons">
          ${['booked','dispatched','collected','processing','report_ready','completed','no_show','cancelled'].map(s => {
            const m = STAGE_META[s];
            return `<button type="button" class="btn btn-ghost" style="font-size:11.5px;padding:6px 10px;${s === b.stage ? `border-color:${m.color};color:${m.color};` : ''}" data-stage="${s}">${m.icon} ${m.adminLabel}</button>`;
          }).join('')}
        </div>
        <div id="stageMsg" style="font-size:12px;margin-top:8px;"></div>
      </div>
      <div class="review-section">
        <div class="review-section-title" style="margin-bottom:8px;">Status History</div>
        ${b.history.length ? b.history.map(h => `<div style="font-size:12px;padding:4px 0;border-bottom:1px dashed var(--gray-200);">${STAGE_META[h.new_status]?.icon || ''} ${STAGE_META[h.new_status]?.adminLabel || h.new_status} — <span style="color:var(--text-muted);">${new Date(h.created_at).toLocaleString('en-IN')} by ${h.changed_by_name || '—'}</span>${h.note ? `<div style="color:var(--text-muted);">"${h.note}"</div>` : ''}</div>`).join('') : '<p style="font-size:12px;color:var(--text-muted);">No history yet.</p>'}
      </div>`;

    body.querySelectorAll('#stageButtons button').forEach(btn => {
      btn.addEventListener('click', async () => {
        const msgEl = document.getElementById('stageMsg');
        btn.disabled = true;
        try {
          await updateBookingStage(b.id, btn.dataset.stage);
          msgEl.textContent = '✅ Stage updated.';
          msgEl.style.color = 'var(--success)';
          const fresh = await fetchBookingDetail(b.id);
          renderDetail(fresh);
          if (onChanged) onChanged();
        } catch (e) {
          msgEl.textContent = '❌ ' + e.message;
          msgEl.style.color = 'var(--danger)';
          btn.disabled = false;
        }
      });
    });
  }

  return openBookingDetailModal;
}
