// ============================================================
// app_settings reader/writer. Every key here is genuinely consumed by
// real pages — see README.md's documentation-index table for which
// page reads which key. Public read (RLS: `using (true)`) since every
// seeded value is already public-facing info; writes are main_admin
// only, enforced by RLS regardless of what this module lets you call.
// ============================================================
import { supabase } from '../supabase-client.js';

let _cache = null;

/** Returns { key: value, ... }. Cached for the page's lifetime — call
 * clearSettingsCache() after a write if the same page needs to react
 * immediately (admin/settings.html does). */
export async function fetchSettings() {
  if (_cache) return _cache;
  const { data, error } = await supabase.from('app_settings').select('key, value');
  if (error) throw error;
  const map = {};
  (data || []).forEach(row => { map[row.key] = row.value; });
  _cache = map;
  return map;
}

export function clearSettingsCache() { _cache = null; }

export async function updateSetting(key, value) {
  const { error } = await supabase.from('app_settings').update({ value }).eq('key', key);
  if (error) throw error;
  clearSettingsCache();
}
