// ============================================================
// Supabase client — shared by every page.
// ============================================================
// SUPABASE_URL + the publishable key below are PUBLIC values, safe in
// browser code by design (see .env.example and SECURITY.md). Real data
// protection comes from Row Level Security policies on every table,
// not from hiding these two values — exactly the same trust model the
// existing app already uses for its Firebase client config.
//
// Loaded as a native ES module, no bundler — same CDN-script pattern
// index-1.html already uses for Firebase.
import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';

const SUPABASE_URL = 'https://woedykgrzczgogtymfxg.supabase.co';
const SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_TN-SovfsBqnVV3laPT9HJw_SKzMryrU';

export const supabase = createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
  },
});

// Exposed for non-module inline scripts during the transition period
// (mirrors how index-1.html exposes window._firebaseAuth etc.).
window._supabase = supabase;
