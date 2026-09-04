// ============================================================
// Admin shell — sidebar + topbar, shared across every admin page.
// Only links to pages that actually exist (see ADMIN_MIGRATION_MAP.md)
// — no nav items pointing at not-yet-built modules.
// ============================================================
import { supabase } from './supabase-client.js';
import { roleLabel } from './admin-guard.js';

const NAV_ITEMS = [
  { href: '/admin/dashboard.html', label: 'Dashboard', icon: 'fa-gauge-high', key: 'dashboard' },
  { href: '/admin/bookings.html', label: 'Bookings', icon: 'fa-calendar-check', key: 'bookings' },
  { href: '/admin/tracker.html', label: 'Booking Tracker', icon: 'fa-route', key: 'tracker' },
];

export function mountAdminShell({ currentKey, title, profile }) {
  const topbarSlot = document.getElementById('admin-topbar');
  const sidebarSlot = document.getElementById('admin-sidebar');

  sidebarSlot.innerHTML = `
    <div class="admin-sidebar-backdrop" id="adminSidebarBackdrop"></div>
    <aside class="admin-sidebar" id="adminSidebar">
      <div class="admin-sidebar-brand">
        <span style="font-size:20px;">🏥</span>
        <div>
          <div class="admin-sidebar-brand-name">My Prime Diagnostic</div>
          <div class="admin-sidebar-brand-sub">Admin Panel</div>
        </div>
      </div>
      <nav class="admin-nav">
        <div class="admin-nav-divider">Operations</div>
        ${NAV_ITEMS.map(i => `<a href="${i.href}" ${i.key === currentKey ? 'aria-current="page"' : ''}><i class="fas ${i.icon}"></i> ${i.label}</a>`).join('')}
        <div class="admin-nav-divider">More modules</div>
        <div style="padding:8px 14px;font-size:11.5px;color:rgba(255,255,255,0.45);">Tests, Packages, Coupons, Staff, Reports, Cash Flow, Settings — see ADMIN_MIGRATION_MAP.md</div>
      </nav>
      <div class="admin-sidebar-footer">
        <div class="admin-user-name">${profile?.full_name || profile?.email || ''}</div>
        <div class="admin-user-role">${roleLabel(profile?.role)}</div>
        <button class="btn btn-ghost btn-block" id="adminLogoutBtn" style="color:#fff;border-color:rgba(255,255,255,0.3);font-size:12px;padding:8px;">Logout</button>
      </div>
    </aside>`;

  topbarSlot.innerHTML = `
    <button class="admin-hamburger" id="adminHamburger" aria-label="Open menu"><i class="fas fa-bars"></i></button>
    <div class="admin-topbar-title">${title}</div>
    <a href="/index.html" class="btn btn-ghost" style="font-size:12px;padding:8px 14px;" target="_blank" rel="noopener"><i class="fas fa-external-link-alt"></i> View Site</a>`;

  const sidebar = document.getElementById('adminSidebar');
  const backdrop = document.getElementById('adminSidebarBackdrop');
  document.getElementById('adminHamburger').addEventListener('click', () => {
    sidebar.classList.add('open'); backdrop.classList.add('open');
  });
  backdrop.addEventListener('click', () => {
    sidebar.classList.remove('open'); backdrop.classList.remove('open');
  });
  document.getElementById('adminLogoutBtn').addEventListener('click', async () => {
    await supabase.auth.signOut();
    location.href = '/admin/login.html';
  });
}
