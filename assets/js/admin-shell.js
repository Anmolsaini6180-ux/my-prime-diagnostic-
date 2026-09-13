// ============================================================
// Admin shell — sidebar + topbar, shared across every admin page.
// Nav items are filtered by the signed-in profile's role BEFORE
// rendering — RBAC in the sidebar mirrors (never substitutes for) the
// real RLS/RPC enforcement in the database. A role seeing an item here
// is necessary-but-not-sufficient; the item existing at all is gated
// by what that role can actually do, per ADMIN_MIGRATION_MAP.md.
// ============================================================
import { supabase } from './supabase-client.js';
import { roleLabel } from './admin-guard.js';

// `roles: null` = every staff role sees it. Otherwise an explicit list.
const NAV_SECTIONS = [
  {
    label: 'Operations',
    items: [
      { href: '/admin/dashboard.html', label: 'Dashboard', icon: 'fa-gauge-high', key: 'dashboard', roles: null },
      { href: '/admin/bookings.html', label: 'Bookings', icon: 'fa-calendar-check', key: 'bookings', roles: null },
      { href: '/admin/tracker.html', label: 'Booking Tracker', icon: 'fa-route', key: 'tracker', roles: null },
      { href: '/admin/add-booking.html', label: 'Add Booking', icon: 'fa-square-plus', key: 'add-booking', roles: ['main_admin', 'sub_admin'] },
      { href: '/admin/whatsapp-booking.html', label: 'WhatsApp Booking', icon: 'fa-brands fa-whatsapp', key: 'whatsapp-booking', roles: ['main_admin', 'sub_admin'] },
    ],
  },
  {
    label: 'Catalogue',
    roles: ['main_admin', 'sub_admin'], // sub_admin gets read-only views — see each page
    items: [
      { href: '/admin/tests.html', label: 'Tests', icon: 'fa-vial', key: 'tests', roles: ['main_admin', 'sub_admin'] },
      { href: '/admin/packages.html', label: 'Packages', icon: 'fa-box-open', key: 'packages', roles: ['main_admin', 'sub_admin'] },
      { href: '/admin/coupons.html', label: 'Coupons', icon: 'fa-tag', key: 'coupons', roles: ['main_admin'] }, // coupons has zero sub_admin read RLS at all — see SECURITY.md §4
    ],
  },
  {
    label: 'People',
    roles: ['main_admin', 'sub_admin'],
    items: [
      { href: '/admin/users.html', label: 'Users', icon: 'fa-users', key: 'users', roles: ['main_admin'] },
      { href: '/admin/team.html', label: 'Team Management', icon: 'fa-user-shield', key: 'team', roles: ['main_admin', 'sub_admin'] },
    ],
  },
  {
    label: 'Insights',
    roles: ['main_admin', 'sub_admin'],
    items: [
      { href: '/admin/reports.html', label: 'Reports', icon: 'fa-file-lines', key: 'reports', roles: ['main_admin', 'sub_admin'] },
      { href: '/admin/analytics.html', label: 'Analytics', icon: 'fa-chart-line', key: 'analytics', roles: ['main_admin', 'sub_admin'] },
      { href: '/admin/activity.html', label: 'Activity Log', icon: 'fa-clock-rotate-left', key: 'activity', roles: ['main_admin', 'sub_admin'] },
    ],
  },
  {
    label: 'System',
    roles: ['main_admin'],
    items: [
      { href: '/admin/settings.html', label: 'Settings', icon: 'fa-gear', key: 'settings', roles: ['main_admin'] },
    ],
  },
];

export function mountAdminShell({ currentKey, title, profile }) {
  const topbarSlot = document.getElementById('admin-topbar');
  const sidebarSlot = document.getElementById('admin-sidebar');
  const role = profile?.role;

  const sectionsHtml = NAV_SECTIONS.map(section => {
    const items = section.items.filter(i => !i.roles || i.roles.includes(role));
    if (!items.length) return '';
    return `<div class="admin-nav-divider">${section.label}</div>` +
      items.map(i => `<a href="${i.href}" ${i.key === currentKey ? 'aria-current="page"' : ''}><i class="fas ${i.icon}"></i> ${i.label}</a>`).join('');
  }).join('');

  sidebarSlot.innerHTML = `
    <div class="admin-sidebar-backdrop" id="adminSidebarBackdrop"></div>
    <aside class="admin-sidebar" id="adminSidebar">
      <div class="admin-sidebar-brand">
        <img src="/assets/img/logo.jpg" alt="" width="32" height="32" style="border-radius:6px;">
        <div>
          <div class="admin-sidebar-brand-name">My Prime Diagnostic</div>
          <div class="admin-sidebar-brand-sub">Admin Panel</div>
        </div>
      </div>
      <nav class="admin-nav">
        ${sectionsHtml}
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
    // Destroys the real Supabase session (Section: logout must destroy
    // session) — every admin page's very next load re-runs
    // requireStaffSession(), which re-reads role fresh from the
    // database rather than trusting anything cached client-side.
    await supabase.auth.signOut();
    location.href = '/admin/login.html';
  });
}
