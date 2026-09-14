// ============================================================
// Shared booking-detail modal (view + edit + assign agent + stage
// update) — used by both admin/bookings.html and admin/tracker.html
// so there's one place that renders a booking's detail, not two
// copies to keep in sync.
// Requires the host page to have:
//   <div class="admin-modal-backdrop" id="detailModalBackdrop">
//     <div class="admin-modal"><button class="admin-modal-close" id="detailModalClose">&times;</button>
//       <div id="detailModalBody"></div></div></div>
// ============================================================
import { fetchBookingDetail, updateBookingStage, fetchCollectionAgents, assignCollectionAgent, adminUpdateBooking } from './services/admin-bookings.js';
import { fetchSlotAvailability } from './services/bookings.js';
import { STAGE_META } from './tracker-shared.js';
import { showToast, confirmDialog } from './admin-ui.js';

function fmtDate(d) { return new Date(d).toLocaleDateString('en-IN', { day: 'numeric', month: 'short', year: 'numeric' }); }

/** @param {() => void} onChanged  @param {string} role — the signed-in
 * staff member's role, so Edit/Assign controls only render for
 * main_admin/sub_admin (collection_agent gets the read-only view +
 * stage buttons only, matching what update_booking_stage's own RPC
 * already restricts them to server-side). */
export function initBookingDetailModal(onChanged, role) {
  const backdrop = document.getElementById('detailModalBackdrop');
  document.getElementById('detailModalClose').addEventListener('click', () => backdrop.classList.remove('open'));
  backdrop.addEventListener('click', (e) => { if (e.target === backdrop) backdrop.classList.remove('open'); });

  const canEdit = role === 'main_admin' || role === 'sub_admin';
  let agentsCache = null;

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
        <div class="review-row"><span>Received</span><span>₹${Number(b.amount_received || 0).toLocaleString('en-IN')}</span></div>
        <div class="review-row"><span>Balance Due</span><span style="${Number(b.final_amount) - Number(b.amount_received || 0) > 0 ? 'color:var(--danger);font-weight:700;' : 'color:var(--success);'}">₹${Math.max(Number(b.final_amount) - Number(b.amount_received || 0), 0).toLocaleString('en-IN')}</span></div>
      </div>
      <div class="review-section"><div class="review-row"><span>Schedule</span><span>${fmtDate(b.scheduled_date)}, ${b.appointment_slots?.label}</span></div>
        <div class="review-row"><span>Collection</span><span>${b.collection_type === 'home' ? '🏠 Home Collection' : '🏥 Walk-in at Lab'}</span></div>
        ${addr ? `<div class="review-row" style="color:var(--text-muted);">${addr.address_line}, ${addr.city} — ${addr.pincode}</div>` : ''}
      </div>
      <div class="review-section">
        <div class="review-row"><span>Status</span><span class="badge badge-blue">${b.status}</span></div>
        <div class="review-row"><span>Stage</span><span class="badge" style="background:${meta.color}22;color:${meta.color};">${meta.icon} ${meta.adminLabel}</span></div>
        <div class="review-row"><span>Payment</span><span>${b.payment_mode} · ${b.payment_status}</span></div>
        <div class="review-row"><span>Creator</span><span>${b.creator_role}${b.created_by_name ? ' — ' + b.created_by_name : ''}</span></div>
      </div>

      ${canEdit ? `
      <div class="review-section">
        <div class="review-section-title" style="margin-bottom:8px;">Assign Collection Agent</div>
        <div style="display:flex;gap:6px;">
          <select id="agentSelect" style="flex:1;padding:8px;border:1.5px solid var(--gray-200);border-radius:8px;font-size:12.5px;"><option>Loading agents…</option></select>
          <button type="button" class="btn btn-outline" id="assignBtn" style="font-size:12px;">Assign</button>
        </div>
        <div id="assignMsg" style="font-size:12px;margin-top:6px;"></div>
      </div>

      <div class="review-section">
        <button type="button" class="btn btn-ghost" id="editToggleBtn" style="font-size:12.5px;padding:6px 10px;"><i class="fas fa-pen"></i> Edit Booking Details</button>
        <div id="editForm" style="display:none;margin-top:12px;">
          <div class="field"><label style="font-size:12px;">Patient Name</label><input type="text" id="editName" value="${b.patient_name}" style="font-size:13px;padding:8px;"></div>
          <div class="field"><label style="font-size:12px;">Phone</label><input type="tel" id="editPhone" value="${b.patient_phone}" maxlength="10" style="font-size:13px;padding:8px;"></div>
          <div class="field"><label style="font-size:12px;">Email</label><input type="email" id="editEmail" value="${b.patient_email || ''}" style="font-size:13px;padding:8px;"></div>
          <div class="field"><label style="font-size:12px;">Collection Type</label>
            <select id="editCollectionType" style="font-size:13px;padding:8px;">
              <option value="home" ${b.collection_type === 'home' ? 'selected' : ''}>Home Collection</option>
              <option value="lab_visit" ${b.collection_type === 'lab_visit' ? 'selected' : ''}>Walk-in at Lab</option>
            </select>
          </div>
          <div id="editAddressWrap" style="${b.collection_type === 'home' ? '' : 'display:none;'}">
            <div class="field"><label style="font-size:12px;">Address Line</label><input type="text" id="editAddr" value="${addr?.address_line || ''}" style="font-size:13px;padding:8px;"></div>
            <div class="field"><label style="font-size:12px;">City</label><input type="text" id="editCity" value="${addr?.city || ''}" style="font-size:13px;padding:8px;"></div>
            <div class="field"><label style="font-size:12px;">Pincode</label><input type="text" id="editPin" value="${addr?.pincode || ''}" maxlength="6" style="font-size:13px;padding:8px;"></div>
          </div>
          <div class="field"><label style="font-size:12px;">Date</label><input type="date" id="editDate" value="${b.scheduled_date}" style="font-size:13px;padding:8px;"></div>
          <div class="field"><label style="font-size:12px;">Time Slot</label><select id="editSlot" style="font-size:13px;padding:8px;"><option value="${b.slot_id}">${b.appointment_slots?.label} (current)</option></select></div>
          <div class="field"><label style="font-size:12px;">Amount Received (₹) — of ₹${Number(b.final_amount).toLocaleString('en-IN')} total</label><input type="number" id="editAmountReceived" min="0" step="1" value="${Number(b.amount_received || 0)}" style="font-size:13px;padding:8px;"></div>
          <div class="field"><label style="font-size:12px;">Special Notes</label><textarea id="editNotes" style="font-size:13px;padding:8px;width:100%;box-sizing:border-box;">${b.special_notes || ''}</textarea></div>
          <div id="editMsg" style="font-size:12px;margin:6px 0;"></div>
          <button type="button" class="btn btn-primary btn-block" id="saveEditBtn" style="font-size:13px;">Save Changes</button>
        </div>
      </div>` : ''}

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
        ${b.history.length ? b.history.map(h => `<div style="font-size:12px;padding:4px 0;border-bottom:1px dashed var(--gray-200);">${STAGE_META[h.new_status]?.icon || '📝'} ${STAGE_META[h.new_status]?.adminLabel || h.new_status} — <span style="color:var(--text-muted);">${new Date(h.created_at).toLocaleString('en-IN')} by ${h.changed_by_name || '—'}</span>${h.note ? `<div style="color:var(--text-muted);">"${h.note}"</div>` : ''}</div>`).join('') : '<p style="font-size:12px;color:var(--text-muted);">No history yet.</p>'}
      </div>`;

    body.querySelectorAll('#stageButtons button').forEach(btn => {
      btn.addEventListener('click', async () => {
        const msgEl = document.getElementById('stageMsg');
        btn.disabled = true;
        try {
          await updateBookingStage(b.id, btn.dataset.stage);
          msgEl.textContent = '✅ Stage updated.'; msgEl.style.color = 'var(--success)';
          showToast('Stage updated to ' + (STAGE_META[btn.dataset.stage]?.adminLabel || btn.dataset.stage), 'success');
          const fresh = await fetchBookingDetail(b.id);
          renderDetail(fresh);
          if (onChanged) onChanged();
        } catch (e) {
          msgEl.textContent = '❌ ' + e.message; msgEl.style.color = 'var(--danger)';
          showToast(e.message, 'error');
          btn.disabled = false;
        }
      });
    });

    if (canEdit) {
      initAssignSection(b);
      initEditSection(b);
    }
  }

  async function initAssignSection(b) {
    const sel = document.getElementById('agentSelect');
    try {
      if (!agentsCache) agentsCache = await fetchCollectionAgents();
      sel.innerHTML = agentsCache.length
        ? agentsCache.map(a => `<option value="${a.id}" ${a.id === b.assigned_collection_agent_id ? 'selected' : ''}>${a.full_name || a.email}</option>`).join('')
        : '<option value="">No active collection agents yet</option>';
    } catch (e) {
      sel.innerHTML = '<option value="">Could not load agents</option>';
    }
    document.getElementById('assignBtn').addEventListener('click', async () => {
      const agentId = sel.value;
      const msgEl = document.getElementById('assignMsg');
      if (!agentId) { msgEl.textContent = 'Select an agent first.'; msgEl.style.color = 'var(--danger)'; return; }
      try {
        await assignCollectionAgent(b.id, agentId);
        msgEl.textContent = '✅ Assigned.'; msgEl.style.color = 'var(--success)';
        showToast('Collection agent assigned', 'success');
        const fresh = await fetchBookingDetail(b.id);
        renderDetail(fresh);
        if (onChanged) onChanged();
      } catch (e) {
        msgEl.textContent = '❌ ' + e.message; msgEl.style.color = 'var(--danger)';
        showToast(e.message, 'error');
      }
    });
  }

  function initEditSection(b) {
    const form = document.getElementById('editForm');
    document.getElementById('editToggleBtn').addEventListener('click', () => {
      form.style.display = form.style.display === 'none' ? 'block' : 'none';
    });
    document.getElementById('editCollectionType').addEventListener('change', (e) => {
      document.getElementById('editAddressWrap').style.display = e.target.value === 'home' ? 'block' : 'none';
    });

    let slotsLoadedForDate = b.scheduled_date;
    document.getElementById('editDate').addEventListener('change', async (e) => {
      const date = e.target.value;
      const slotSel = document.getElementById('editSlot');
      slotSel.innerHTML = '<option>Loading…</option>';
      try {
        const slots = await fetchSlotAvailability(date);
        slotSel.innerHTML = slots.map(s => `<option value="${s.slot_id}" ${!s.is_available ? 'disabled' : ''} ${s.slot_id === b.slot_id && date === slotsLoadedForDate ? 'selected' : ''}>${s.label}${!s.is_available ? ' — Full' : ''}</option>`).join('');
      } catch (err) { slotSel.innerHTML = '<option value="">Could not load slots</option>'; }
    });

    document.getElementById('saveEditBtn').addEventListener('click', async () => {
      const msgEl = document.getElementById('editMsg');
      const saveBtn = document.getElementById('saveEditBtn');
      const newCollectionType = document.getElementById('editCollectionType').value;
      const pin = document.getElementById('editPin').value.trim();
      if (newCollectionType === 'home' && (!document.getElementById('editAddr').value.trim() || !/^\d{6}$/.test(pin))) {
        msgEl.textContent = 'Home collection needs a complete address and a valid 6-digit pincode.';
        msgEl.style.color = 'var(--danger)';
        return;
      }
      const amountReceivedVal = document.getElementById('editAmountReceived').value.trim();
      if (amountReceivedVal !== '' && Number(amountReceivedVal) < 0) {
        msgEl.textContent = 'Amount received cannot be negative.';
        msgEl.style.color = 'var(--danger)';
        return;
      }
      const confirmed = await confirmDialog('Save these changes to the booking? This is recorded in the booking\'s history.', { confirmLabel: 'Save Changes', danger: false });
      if (!confirmed) return;

      saveBtn.disabled = true; saveBtn.textContent = 'Saving…';
      try {
        await adminUpdateBooking(b.id, {
          patientName: document.getElementById('editName').value.trim(),
          patientPhone: document.getElementById('editPhone').value.trim(),
          patientEmail: document.getElementById('editEmail').value.trim() || null,
          collectionType: newCollectionType,
          address: newCollectionType === 'home' ? {
            address_line: document.getElementById('editAddr').value.trim(),
            city: document.getElementById('editCity').value.trim(),
            pincode: pin,
          } : null,
          scheduledDate: document.getElementById('editDate').value,
          slotId: document.getElementById('editSlot').value || undefined,
          specialNotes: document.getElementById('editNotes').value.trim() || null,
          amountReceived: amountReceivedVal === '' ? undefined : Number(amountReceivedVal),
        });
        showToast('Booking updated', 'success');
        const fresh = await fetchBookingDetail(b.id);
        renderDetail(fresh);
        if (onChanged) onChanged();
      } catch (e) {
        msgEl.textContent = '❌ ' + e.message; msgEl.style.color = 'var(--danger)';
        showToast(e.message, 'error');
        saveBtn.disabled = false; saveBtn.textContent = 'Save Changes';
      }
    });
  }

  return openBookingDetailModal;
}
