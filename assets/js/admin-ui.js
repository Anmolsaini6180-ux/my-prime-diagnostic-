// ============================================================
// Shared admin UI primitives — toast notifications and a confirm
// dialog, used by every admin page that performs a real write, so a
// user never sees a bare "Success" unless the database operation
// actually succeeded, and never triggers something irreversible
// (delete/deactivate/role change) without an explicit confirm step
// (Sections 33/43).
// ============================================================

function ensureToastStack() {
  let stack = document.querySelector('.admin-toast-stack');
  if (!stack) {
    stack = document.createElement('div');
    stack.className = 'admin-toast-stack';
    document.body.appendChild(stack);
  }
  return stack;
}

/** type: 'success' | 'error' | 'info' (default). Auto-dismisses. */
export function showToast(message, type = 'info', ms = 3500) {
  const stack = ensureToastStack();
  const el = document.createElement('div');
  el.className = `admin-toast ${type}`;
  const icon = type === 'success' ? '✅' : type === 'error' ? '⚠️' : 'ℹ️';
  el.innerHTML = `<span>${icon}</span><span>${message}</span>`;
  stack.appendChild(el);
  setTimeout(() => el.remove(), ms);
}

/** Resolves true/false. Use before anything destructive or hard to reverse. */
export function confirmDialog(message, { confirmLabel = 'Confirm', danger = true } = {}) {
  return new Promise((resolve) => {
    const backdrop = document.createElement('div');
    backdrop.className = 'admin-confirm-backdrop';
    backdrop.innerHTML = `
      <div class="admin-confirm-box">
        <div style="font-size:28px;">${danger ? '⚠️' : '❓'}</div>
        <p>${message}</p>
        <div class="admin-confirm-actions">
          <button type="button" class="btn btn-ghost" data-a="cancel">Cancel</button>
          <button type="button" class="btn ${danger ? 'btn-primary' : 'btn-primary'}" style="${danger ? 'background:var(--danger);border-color:var(--danger);' : ''}" data-a="ok">${confirmLabel}</button>
        </div>
      </div>`;
    document.body.appendChild(backdrop);
    backdrop.addEventListener('click', (e) => {
      if (e.target === backdrop || e.target.dataset.a === 'cancel') { backdrop.remove(); resolve(false); }
      else if (e.target.dataset.a === 'ok') { backdrop.remove(); resolve(true); }
    });
  });
}
