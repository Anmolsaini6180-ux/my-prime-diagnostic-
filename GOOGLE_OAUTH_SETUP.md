# GOOGLE_OAUTH_SETUP.md

**Status: code is complete and verified reaching Supabase correctly. The OAuth flow itself is not yet functional and has not been tested, because two pieces of external configuration only you can do remain outstanding.** This document is exactly those two pieces, nothing more.

Verified this session: clicking "Continue with Google" on both `pages/login.html` and `admin/login.html` correctly redirects to Supabase's real endpoint (`https://woedykgrzczgogtymfxg.supabase.co/auth/v1/authorize?provider=google&redirect_to=...`) with the correct dynamic redirect URL for whatever origin the app is running on. Supabase's own server responded with `{"error_code":"validation_failed","msg":"Unsupported provider: provider is not enabled"}` — confirming the client code is wired correctly and the *only* gap is that the Google provider isn't turned on yet.

---

## Step 1 — Google Cloud Console: create an OAuth Client

1. Go to [Google Cloud Console](https://console.cloud.google.com/) → APIs & Services → Credentials (create/select a project first if you don't have one for this app yet).
2. **Create Credentials → OAuth client ID** → Application type: **Web application**.
3. **Authorized redirect URIs** — add exactly this one URL (Supabase's fixed callback, not your site):
   ```
   https://woedykgrzczgogtymfxg.supabase.co/auth/v1/callback
   ```
4. Save. Copy the **Client ID** and **Client Secret** it gives you — you'll paste both into Supabase in Step 2. Don't paste them anywhere else (not into this repo, not into chat, not into any file I can see).

If this project doesn't have an OAuth consent screen configured yet, Google will prompt you to set one up first (app name "My Prime Diagnostic", your support email, and the `myprimediagnostics.co.in` domain if you want to verify it — verification isn't required just to test with your own Google account).

## Step 2 — Supabase Dashboard: enable the provider

1. Open your project → **Authentication → Providers → Google**.
2. Toggle it **on**.
3. Paste the **Client ID** and **Client Secret** from Step 1.
4. Save.

## Step 3 — Supabase Dashboard: allow the redirect URLs

Still in Authentication, under **URL Configuration**:

1. **Site URL**: set to your production domain, `https://myprimediagnostics.co.in`.
2. **Redirect URLs** — add every origin the app will actually run from, since the code sends `redirectTo` as `window.location.origin + '/pages/login.html'` (or `/admin/login.html`) dynamically rather than a hardcoded domain, so it works in every environment without code changes:
   ```
   https://myprimediagnostics.co.in/pages/login.html
   https://myprimediagnostics.co.in/admin/login.html
   http://localhost:5500/pages/login.html
   http://localhost:5500/admin/login.html
   ```
   (Keep the `localhost:5500` ones — that's how this project is tested locally today, via `npx http-server -p 5500`. Remove them later if you want to lock this down once the app is fully deployed.)

## Step 4 — Also worth enabling while you're there (unrelated to Google, flagged by the security advisor)

**Authentication → Policies → Password**: "Leaked password protection" is currently **off**. Turning it on checks new passwords against HaveIBeenPwned.org — a one-click hardening step, unrelated to Google OAuth, that I can't do from here since it's a project-level Auth setting.

## Step 5 — Test it yourself

Once Steps 1-3 are done:
1. Go to `/pages/login.html`, click **Continue with Google**, sign in with **any** Google account.
2. A brand-new Google account (not one of the 3 approved owner emails) should land on **My Bookings** with role `patient`.
3. Sign in with **`anmolsaini6180@gmail.com`** specifically — since that email's profile is already promoted to `main_admin` (done this session, see [ADMIN_MIGRATION_MAP.md](ADMIN_MIGRATION_MAP.md)/session notes), it should land straight on **`/admin/dashboard.html`**.

I could not perform this step myself — it requires a real Google consent screen and a real account, which I don't have access to and shouldn't attempt to simulate. Please let me know the result, especially if anything doesn't match what's described above.
