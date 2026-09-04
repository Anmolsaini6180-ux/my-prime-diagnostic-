// ============================================================
// Catalog service — the only place that knows how to query
// packages/tests from Supabase. Pages call these, never the raw
// Supabase client directly, so the query shape lives in one place.
// ============================================================
import { supabase } from '../supabase-client.js';

/** All active packages, each with its features + included tests, ordered for display. */
export async function fetchPackages() {
  const { data, error } = await supabase
    .from('packages')
    .select(`
      id, slug, name, description, price, original_price, badge, emoji, featured,
      sample_type, report_time, preparation_required,
      package_features ( feature, sort_order ),
      package_tests ( label, code, count, sort_order )
    `)
    .eq('is_active', true)
    .order('sort_order', { ascending: true });

  if (error) throw error;
  return (data || []).map(normalizePackage);
}

export async function fetchPackageBySlug(slug) {
  const { data, error } = await supabase
    .from('packages')
    .select(`
      id, slug, name, description, price, original_price, badge, emoji, featured,
      sample_type, report_time, preparation_required,
      package_features ( feature, sort_order ),
      package_tests ( label, code, count, sort_order )
    `)
    .eq('slug', slug)
    .eq('is_active', true)
    .maybeSingle();

  if (error) throw error;
  return data ? normalizePackage(data) : null;
}

function normalizePackage(p) {
  return {
    ...p,
    features: (p.package_features || []).sort((a, b) => a.sort_order - b.sort_order).map(f => f.feature),
    tests: (p.package_tests || []).sort((a, b) => a.sort_order - b.sort_order),
  };
}

/** All active individual tests, ordered for display. */
export async function fetchTests() {
  const { data, error } = await supabase
    .from('tests')
    .select('id, slug, name, category, price, price_note, icon, description, preparation, sample_type')
    .eq('is_active', true)
    .order('sort_order', { ascending: true });

  if (error) throw error;
  return data || [];
}

export async function fetchTestBySlug(slug) {
  const { data, error } = await supabase
    .from('tests')
    .select('id, slug, name, category, price, price_note, icon, description, preparation, sample_type')
    .eq('slug', slug)
    .eq('is_active', true)
    .maybeSingle();

  if (error) throw error;
  return data;
}

/** Distinct categories present in the active test catalog, for filter chips. */
export function distinctCategories(tests) {
  return [...new Set(tests.map(t => t.category).filter(Boolean))];
}
