// ============================================================
// Shared nav + footer — single source of truth, injected into every
// page's <div id="site-header"></div> / <div id="site-footer"></div>.
// No build step: this is the plain-JS equivalent of a shared layout
// component (see ARCHITECTURE_PLAN.md §5).
// ============================================================
import { supabase } from './supabase-client.js';

const NAV_ITEMS = [
  { href: '/index.html', label: 'Home', key: 'home' },
  { href: '/pages/tests.html', label: 'Tests', key: 'tests' },
  { href: '/pages/packages.html', label: 'Packages', key: 'packages' },
  { href: '/pages/about.html', label: 'About Us', key: 'about' },
  { href: '/pages/contact.html', label: 'Contact', key: 'contact' },
  { href: '/pages/track-booking.html', label: 'Track Booking', key: 'track-booking' },
];

function navLinkHTML(item, currentKey) {
  const current = item.key === currentKey ? ' aria-current="page"' : '';
  return `<a href="${item.href}"${current}>${item.label}</a>`;
}

function renderHeader(currentKey) {
  const el = document.getElementById('site-header');
  if (!el) return;
  el.innerHTML = `
    <a href="#main" class="skip-link">Skip to content</a>
    <nav class="site-nav" aria-label="Primary">
      <div class="site-nav-inner">
        <a class="logo" href="/index.html">
          <img src="/assets/img/logo.jpg" alt="My Prime Diagnostic" width="38" height="38">
          <span class="logo-name">My Prime Diagnostic</span>
        </a>
        <ul class="nav-links">
          ${NAV_ITEMS.map(i => `<li>${navLinkHTML(i, currentKey)}</li>`).join('')}
        </ul>
        <div class="nav-actions" id="navActionsSlot">
          <a href="/pages/login.html" class="btn btn-ghost" id="navLoginBtn">Login</a>
          <a href="/pages/packages.html" class="btn btn-orange">Book a Test</a>
        </div>
        <button class="nav-hamburger" id="navHamburger" aria-label="Open menu" aria-expanded="false">
          <span></span>
        </button>
      </div>
    </nav>
    <div class="nav-drawer-backdrop" id="navDrawerBackdrop"></div>
    <aside class="nav-drawer" id="navDrawer" aria-label="Mobile menu">
      <button class="nav-drawer-close" id="navDrawerClose" aria-label="Close menu">&times;</button>
      <ul>
        ${NAV_ITEMS.map(i => `<li>${navLinkHTML(i, currentKey)}</li>`).join('')}
        <li><a href="/pages/login.html">Login</a></li>
      </ul>
      <a href="/pages/packages.html" class="btn btn-orange btn-block">Book a Test</a>
    </aside>
  `;

  const hamburger = document.getElementById('navHamburger');
  const drawer = document.getElementById('navDrawer');
  const backdrop = document.getElementById('navDrawerBackdrop');
  const closeBtn = document.getElementById('navDrawerClose');
  const openDrawer = () => { drawer.classList.add('open'); backdrop.classList.add('open'); hamburger.setAttribute('aria-expanded', 'true'); document.body.style.overflow = 'hidden'; };
  const closeDrawer = () => { drawer.classList.remove('open'); backdrop.classList.remove('open'); hamburger.setAttribute('aria-expanded', 'false'); document.body.style.overflow = ''; };
  hamburger.addEventListener('click', openDrawer);
  closeBtn.addEventListener('click', closeDrawer);
  backdrop.addEventListener('click', closeDrawer);

  // Real auth-state check (not a fake logged-out placeholder) — swaps
  // Login for a simple account menu when a session exists.
  supabase.auth.getSession().then(({ data }) => {
    if (data.session) {
      const name = data.session.user.user_metadata?.full_name || data.session.user.email;
      const slot = document.getElementById('navActionsSlot');
      const loginBtn = document.getElementById('navLoginBtn');
      if (loginBtn) {
        loginBtn.outerHTML = `
          <div class="nav-user-menu">
            <a href="/pages/my-bookings.html" class="btn btn-ghost">👤 ${name.split('@')[0]}</a>
          </div>`;
      }
    }
  });
}

function renderFooter() {
  const el = document.getElementById('site-footer');
  if (!el) return;
  const year = new Date().getFullYear();
  // Renders immediately with the known-good hardcoded number (never a
  // blank/broken footer while the network request below is pending),
  // then quietly upgrades to app_settings.support_phone/lab_name if
  // that loads successfully — see admin/settings.html.
  el.innerHTML = `
    <footer class="site-footer">
      <div class="container footer-grid">
        <div class="footer-col">
          <h4 style="display:flex;align-items:center;gap:8px;"><img src="/assets/img/logo.jpg" alt="" width="24" height="24" style="border-radius:4px;"> <span id="footerLabName">My Prime Diagnostic</span></h4>
          <p>NABL-certified pathology lab in Noida — accurate blood tests and free home sample collection.</p>
          <p>📞 <a href="tel:+917428456590" id="footerPhoneLink">+91 74284 56590</a></p>
        </div>
        <div class="footer-col">
          <h4>Explore</h4>
          <a href="/pages/tests.html">Tests</a>
          <a href="/pages/packages.html">Packages</a>
          <a href="/pages/about.html">About Us</a>
          <a href="/pages/contact.html">Contact</a>
        </div>
        <div class="footer-col">
          <h4>Account</h4>
          <a href="/pages/track-booking.html">Track Booking</a>
          <a href="/pages/login.html">Login</a>
          <a href="/pages/my-bookings.html">My Bookings</a>
          <a href="/pages/my-reports.html">My Reports</a>
        </div>
        <div class="footer-col">
          <h4>Visit</h4>
          <p>Noida, Uttar Pradesh</p>
          <p>Mon–Sun, 7:00 AM – 9:00 PM</p>
        </div>
      </div>
      <div class="footer-bottom container">© ${year} <span id="footerLabNameBottom">My Prime Diagnostic</span>. All rights reserved.</div>
    </footer>
  `;

  supabase.from('app_settings').select('key, value').in('key', ['lab_name', 'support_phone']).then(({ data }) => {
    if (!data) return;
    const map = Object.fromEntries(data.map(r => [r.key, r.value]));
    if (map.lab_name) {
      document.getElementById('footerLabName').textContent = map.lab_name;
      document.getElementById('footerLabNameBottom').textContent = map.lab_name;
    }
    if (map.support_phone) {
      const link = document.getElementById('footerPhoneLink');
      link.href = 'tel:' + map.support_phone;
      link.textContent = map.support_phone;
    }
  }).catch(() => { /* keep the hardcoded default shown above — never a broken footer */ });
}

export function mountChrome(currentKey) {
  renderHeader(currentKey);
  renderFooter();
}
