-- ============================================================
-- Seed: 001_catalog_seed
-- ============================================================
-- Ports the REAL package/test catalog currently live in index-1.html
-- (the `adminPackages` fallback array and `testDB` array) into
-- Supabase. This is real production content being migrated, not
-- synthetic test fixtures — see AUDIT.md and BACKEND_DEPENDENCIES.md
-- for where each value was sourced.
--
-- Safe to re-run: every insert is idempotent via ON CONFLICT.
-- ============================================================

-- ---- Packages (fixed ids so package_features below can reference them) ----
insert into public.packages (id, slug, name, description, price, badge, featured, is_active, sort_order)
values
  ('10000000-0000-4000-8000-000000000001', 'basic-health',     'Basic Health',      'Essential screening for young adults',        599,  null,             false, true, 1),
  ('10000000-0000-4000-8000-000000000002', 'advanced-health',  'Advanced Health',   'Comprehensive 75-parameter panel',           1299,  'Most Popular',   true,  true, 2),
  ('10000000-0000-4000-8000-000000000003', 'senior-citizen',   'Senior Citizen',    'Tailored for 60+ age group',                 1799,  null,             false, true, 3),
  ('10000000-0000-4000-8000-000000000004', 'women-wellness',   'Women Wellness',    'Designed specifically for women''s health',  1499,  null,             false, true, 4),
  ('10000000-0000-4000-8000-000000000005', 'corporate-health', 'Corporate Health',  'Bulk employee wellness programs',             799,  null,             false, true, 5)
on conflict (id) do update set
  name = excluded.name, description = excluded.description, price = excluded.price,
  badge = excluded.badge, featured = excluded.featured, is_active = excluded.is_active,
  sort_order = excluded.sort_order, updated_at = now();

-- ---- package_features (legacy plain-string schema — matches the source exactly) ----
delete from public.package_features where package_id in (
  '10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002',
  '10000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000004',
  '10000000-0000-4000-8000-000000000005'
);

insert into public.package_features (package_id, feature, sort_order) values
  ('10000000-0000-4000-8000-000000000001', 'Complete Blood Count (CBC)', 1),
  ('10000000-0000-4000-8000-000000000001', 'Blood Sugar (Fasting)', 2),
  ('10000000-0000-4000-8000-000000000001', 'Lipid Profile', 3),
  ('10000000-0000-4000-8000-000000000001', 'Urine Routine', 4),
  ('10000000-0000-4000-8000-000000000001', 'Kidney Function (KFT)', 5),
  ('10000000-0000-4000-8000-000000000001', 'Digital Report in 6 hrs', 6),

  ('10000000-0000-4000-8000-000000000002', 'All Basic Tests Included', 1),
  ('10000000-0000-4000-8000-000000000002', 'Thyroid Profile (TSH, T3, T4)', 2),
  ('10000000-0000-4000-8000-000000000002', 'Vitamin D & B12', 3),
  ('10000000-0000-4000-8000-000000000002', 'Liver Function (LFT)', 4),
  ('10000000-0000-4000-8000-000000000002', 'HbA1c (3-month avg sugar)', 5),
  ('10000000-0000-4000-8000-000000000002', 'Free Home Collection', 6),
  ('10000000-0000-4000-8000-000000000002', 'Report in 4 hrs', 7),

  ('10000000-0000-4000-8000-000000000003', 'All Advanced Tests', 1),
  ('10000000-0000-4000-8000-000000000003', 'Calcium & Phosphorus', 2),
  ('10000000-0000-4000-8000-000000000003', 'PSA (for men)', 3),
  ('10000000-0000-4000-8000-000000000003', 'ECG', 4),
  ('10000000-0000-4000-8000-000000000003', 'Joint & Bone Markers', 5),
  ('10000000-0000-4000-8000-000000000003', 'Priority Home Collection', 6),

  ('10000000-0000-4000-8000-000000000004', 'Complete Hormone Panel', 1),
  ('10000000-0000-4000-8000-000000000004', 'PCOS Screening', 2),
  ('10000000-0000-4000-8000-000000000004', 'Thyroid & Vitamin D', 3),
  ('10000000-0000-4000-8000-000000000004', 'Iron & Ferritin', 4),
  ('10000000-0000-4000-8000-000000000004', 'Cervical Screening (PAP)', 5),
  ('10000000-0000-4000-8000-000000000004', 'Female Pathologist Review', 6),

  ('10000000-0000-4000-8000-000000000005', 'Minimum 25 employees', 1),
  ('10000000-0000-4000-8000-000000000005', 'On-site sample collection', 2),
  ('10000000-0000-4000-8000-000000000005', 'Custom Test Panels', 3),
  ('10000000-0000-4000-8000-000000000005', 'HR Dashboard Access', 4),
  ('10000000-0000-4000-8000-000000000005', 'Individual Digital Reports', 5),
  ('10000000-0000-4000-8000-000000000005', 'Group Health Analytics', 6);

-- ---- Individual tests (from testDB — excludes the 6 rows that were just
-- search-index shims pointing back to the packages above, and the
-- "Home Sample Collection" service marker, which isn't a sellable test) ----
insert into public.tests (slug, name, category, price, icon, is_active, sort_order) values
  ('cbc',                  'Complete Blood Count (CBC)',      'Blood Tests',  199, '🩸', true, 1),
  ('thyroid-profile',      'Thyroid Profile (TSH, T3, T4)',   'Thyroid Tests',349, '🦋', true, 2),
  ('hba1c-test',           'HbA1c Test',                      'Diabetes',     299, '🍬', true, 3),
  ('fasting-blood-sugar',  'Fasting Blood Sugar',             'Diabetes',      99, '🍬', true, 4),
  ('lipid-profile',        'Lipid Profile',                   'Heart Health', 399, '❤️', true, 5),
  ('vitamin-d-test',       'Vitamin D Test',                  'Vitamins',     399, '☀️', true, 6),
  ('vitamin-b12-test',     'Vitamin B12 Test',                'Vitamins',     299, '💊', true, 7),
  ('liver-function-test',  'Liver Function Test (LFT)',       'Blood Tests',  499, '🩺', true, 8),
  ('kidney-function-test', 'Kidney Function Test (KFT)',      'Blood Tests',  449, '🫀', true, 9),
  ('iron-ferritin-panel',  'Iron & Ferritin Panel',           'Blood Tests',  599, '🩸', true, 10),
  ('pcos-screening',       'PCOS Screening',                  'Women Health', 899, '🌸', true, 11),
  ('cardiac-risk-panel',   'Cardiac Risk Panel',              'Heart Health', 899, '❤️', true, 12),
  ('urine-routine-exam',   'Urine Routine Exam',              'Routine',      149, '🧪', true, 13),
  ('psa-test',             'PSA Test',                        'Men Health',   499, '🔬', true, 14),
  ('ecg',                  'ECG',                             'Heart Health', 299, '❤️', true, 15)
on conflict (slug) do update set
  name = excluded.name, category = excluded.category, price = excluded.price,
  icon = excluded.icon, is_active = excluded.is_active, sort_order = excluded.sort_order,
  updated_at = now();

-- No coupons are seeded: the source app has no hardcoded default coupons
-- (they are admin-created only), so an empty table here is the accurate
-- real state, not a gap.
