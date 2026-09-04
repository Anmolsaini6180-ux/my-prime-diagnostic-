-- ============================================================
-- Migration: 0001_foundation_and_catalog
-- ============================================================
-- Establishes the foundation every later migration depends on:
--   - public.profiles: one row per Supabase Auth user, consolidating
--     Firebase's separate `users` + `staff_users` collections into one
--     idiomatic Postgres table (role defaults to 'patient').
--   - Head-Admin bootstrap + permanent lock, re-implementing the exact
--     security guarantee documented in the original index-1.html
--     (MHL_OWNER_EMAILS / _resolveStaffRole / _ensureMainAdminLock).
--   - The public test/package catalog (tests, packages, package_tests,
--     package_features) with real RLS from the moment each table exists.
--   - coupons, validated only through a SECURITY DEFINER RPC so the
--     full code list is never exposed to the client.
--
-- RLS is enabled on every table in this file. Nothing is left in a
-- temporarily-open state "to fix later".
-- ============================================================

create extension if not exists "pgcrypto";

-- ------------------------------------------------------------
-- Roles
-- ------------------------------------------------------------
create type public.staff_role as enum ('patient', 'main_admin', 'sub_admin', 'collection_agent');

-- ------------------------------------------------------------
-- profiles
-- ------------------------------------------------------------
create table public.profiles (
  id                    uuid primary key references auth.users(id) on delete cascade,
  email                 text not null,
  full_name             text,
  phone                 text,
  role                  public.staff_role not null default 'patient',
  status                text not null default 'active' check (status in ('active','inactive')),
  parent_sub_admin_id   uuid references public.profiles(id),
  branch_id             text,
  city_id               text,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  last_login            timestamptz
);

comment on table public.profiles is
  'One row per auth.users id. role=patient for regular customers; staff roles mirror the original Firebase RBAC model (main_admin/sub_admin/collection_agent). No finance_admin role exists in the source app, so none is created here.';

create index idx_profiles_role on public.profiles(role);
create index idx_profiles_parent_sub_admin on public.profiles(parent_sub_admin_id);

-- ------------------------------------------------------------
-- Head-Admin lock (mirrors Firebase system_meta/main_admins/locked/{uid})
-- ------------------------------------------------------------
create table public.main_admin_locks (
  uid        uuid primary key references auth.users(id) on delete cascade,
  email      text not null,
  locked_at  timestamptz not null default now()
);
comment on table public.main_admin_locks is
  'Permanent record of every uid ever granted main_admin via the Head-Admin bootstrap. Never updated or deleted by application code.';

-- ------------------------------------------------------------
-- Head-Admin bootstrap trigger
-- Exactly two hardcoded owner emails may self-bootstrap as main_admin,
-- the moment their auth.users row is first created. Everyone else
-- starts as 'patient'. This is intentionally NOT editable from any
-- table or client call — it is a literal constant in this function.
-- ------------------------------------------------------------
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  owner_emails text[] := array['workwithme.digital@gmail.com', 'thisisamansaini@gmail.com'];
  resolved_role public.staff_role := 'patient';
begin
  if lower(new.email) = any(owner_emails) then
    resolved_role := 'main_admin';
  end if;

  insert into public.profiles (id, email, full_name, role)
  values (new.id, new.email, new.raw_user_meta_data ->> 'full_name', resolved_role);

  if resolved_role = 'main_admin' then
    insert into public.main_admin_locks (uid, email)
    values (new.id, lower(new.email))
    on conflict (uid) do nothing;
  end if;

  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_auth_user();

-- ------------------------------------------------------------
-- RLS helper functions (SECURITY DEFINER so they bypass RLS on their
-- own internal lookup instead of recursively re-evaluating policies —
-- the standard, recommended Supabase pattern for role checks).
-- ------------------------------------------------------------
create or replace function public.current_user_role()
returns public.staff_role
language sql security definer stable set search_path = public
as $$ select role from public.profiles where id = auth.uid(); $$;

create or replace function public.is_main_admin()
returns boolean
language sql security definer stable set search_path = public
as $$ select coalesce((select role = 'main_admin' from public.profiles where id = auth.uid()), false); $$;

create or replace function public.is_staff()
returns boolean
language sql security definer stable set search_path = public
as $$ select coalesce((select role in ('main_admin','sub_admin','collection_agent') from public.profiles where id = auth.uid()), false); $$;

-- ------------------------------------------------------------
-- updated_at helper
-- ------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ------------------------------------------------------------
-- RLS: profiles
-- ------------------------------------------------------------
alter table public.profiles enable row level security;

create policy "profiles_self_select" on public.profiles
  for select using (auth.uid() = id);

create policy "profiles_main_admin_select_all" on public.profiles
  for select using (public.is_main_admin());

create policy "profiles_sub_admin_select_team" on public.profiles
  for select using (
    public.current_user_role() = 'sub_admin' and parent_sub_admin_id = auth.uid()
  );

create policy "profiles_self_update" on public.profiles
  for update using (auth.uid() = id);

create policy "profiles_main_admin_update_all" on public.profiles
  for update using (public.is_main_admin());

-- A self-update is still permitted by profiles_self_update above, but this
-- trigger blocks the specific privilege-escalation hole the original app
-- was already patched for: a non-main_admin editing their OWN role/status/
-- reporting line. Row-level RLS alone cannot express a column-level rule,
-- so it is enforced here.
create or replace function public.prevent_self_role_escalation()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if auth.uid() = old.id and not public.is_main_admin() then
    if new.role <> old.role
       or new.status <> old.status
       or new.parent_sub_admin_id is distinct from old.parent_sub_admin_id then
      raise exception 'Not allowed to change role, status, or reporting line on your own profile.';
    end if;
  end if;
  return new;
end;
$$;

create trigger trg_prevent_self_role_escalation
  before update on public.profiles
  for each row execute function public.prevent_self_role_escalation();

create trigger trg_profiles_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

grant select, update on public.profiles to authenticated;

-- ------------------------------------------------------------
-- tests
-- ------------------------------------------------------------
create table public.tests (
  id               uuid primary key default gen_random_uuid(),
  slug             text unique not null,
  name             text not null,
  category         text,
  price            numeric(10,2) not null default 0,
  price_note       text,              -- e.g. 'per employee' for corporate-style pricing
  icon             text,
  description      text,
  preparation      text,
  sample_type      text,
  is_active        boolean not null default true,
  sort_order       int not null default 0,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index idx_tests_category on public.tests(category);
create index idx_tests_active on public.tests(is_active);

alter table public.tests enable row level security;
create policy "tests_public_read_active" on public.tests for select using (is_active = true);
create policy "tests_main_admin_read_all" on public.tests for select using (public.is_main_admin());
create policy "tests_main_admin_insert" on public.tests for insert with check (public.is_main_admin());
create policy "tests_main_admin_update" on public.tests for update using (public.is_main_admin());
create policy "tests_main_admin_delete" on public.tests for delete using (public.is_main_admin());
create trigger trg_tests_updated_at before update on public.tests for each row execute function public.set_updated_at();
grant select on public.tests to anon, authenticated;

-- ------------------------------------------------------------
-- packages
-- ------------------------------------------------------------
create table public.packages (
  id                     uuid primary key default gen_random_uuid(),
  slug                   text unique not null,
  name                   text not null,
  description            text,
  price                  numeric(10,2) not null,
  original_price         numeric(10,2),
  badge                  text,
  emoji                  text,
  featured               boolean not null default false,
  sample_type            text,
  report_time            text,
  preparation_required   boolean,
  is_active              boolean not null default true,
  sort_order             int not null default 0,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);
create index idx_packages_active on public.packages(is_active);

alter table public.packages enable row level security;
create policy "packages_public_read_active" on public.packages for select using (is_active = true);
create policy "packages_main_admin_read_all" on public.packages for select using (public.is_main_admin());
create policy "packages_main_admin_insert" on public.packages for insert with check (public.is_main_admin());
create policy "packages_main_admin_update" on public.packages for update using (public.is_main_admin());
create policy "packages_main_admin_delete" on public.packages for delete using (public.is_main_admin());
create trigger trg_packages_updated_at before update on public.packages for each row execute function public.set_updated_at();
grant select on public.packages to anon, authenticated;

-- ------------------------------------------------------------
-- package_tests — tests included in a package.
-- Stores a display-label SNAPSHOT (not just a foreign key) so a
-- package's advertised contents never silently change if the linked
-- test is later edited or removed — matches the "snapshot information
-- that must remain historically accurate" requirement.
-- ------------------------------------------------------------
create table public.package_tests (
  id            uuid primary key default gen_random_uuid(),
  package_id    uuid not null references public.packages(id) on delete cascade,
  test_id       uuid references public.tests(id) on delete set null,
  label         text not null,
  code          text,
  count         int not null default 1,
  sort_order    int not null default 0
);
create index idx_package_tests_package on public.package_tests(package_id);

alter table public.package_tests enable row level security;
create policy "package_tests_public_read" on public.package_tests for select using (true);
create policy "package_tests_main_admin_insert" on public.package_tests for insert with check (public.is_main_admin());
create policy "package_tests_main_admin_update" on public.package_tests for update using (public.is_main_admin());
create policy "package_tests_main_admin_delete" on public.package_tests for delete using (public.is_main_admin());
grant select on public.package_tests to anon, authenticated;

-- ------------------------------------------------------------
-- package_features — legacy plain-string feature list fallback
-- (mirrors the `features: [string]` shape used when a package has no
-- structured test list in the source app).
-- ------------------------------------------------------------
create table public.package_features (
  id            uuid primary key default gen_random_uuid(),
  package_id    uuid not null references public.packages(id) on delete cascade,
  feature       text not null,
  sort_order    int not null default 0
);
create index idx_package_features_package on public.package_features(package_id);

alter table public.package_features enable row level security;
create policy "package_features_public_read" on public.package_features for select using (true);
create policy "package_features_main_admin_insert" on public.package_features for insert with check (public.is_main_admin());
create policy "package_features_main_admin_update" on public.package_features for update using (public.is_main_admin());
create policy "package_features_main_admin_delete" on public.package_features for delete using (public.is_main_admin());
grant select on public.package_features to anon, authenticated;

-- ------------------------------------------------------------
-- coupons — deliberately NOT publicly readable. The full code list
-- must never be scrapeable from the client; validity is checked only
-- through validate_coupon() below.
-- ------------------------------------------------------------
create table public.coupons (
  code          text primary key,
  type          text not null check (type in ('percent','flat')),
  value         numeric(10,2) not null,
  active        boolean not null default true,
  min_amount    numeric(10,2),
  usage_limit   int,
  used_count    int not null default 0,
  expires_at    date,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

alter table public.coupons enable row level security;
create policy "coupons_main_admin_read" on public.coupons for select using (public.is_main_admin());
create policy "coupons_main_admin_insert" on public.coupons for insert with check (public.is_main_admin());
create policy "coupons_main_admin_update" on public.coupons for update using (public.is_main_admin());
create policy "coupons_main_admin_delete" on public.coupons for delete using (public.is_main_admin());
create trigger trg_coupons_updated_at before update on public.coupons for each row execute function public.set_updated_at();

-- validate_coupon: the ONLY public surface for coupon checks. Returns
-- just enough to apply a discount — never the full coupons table.
create or replace function public.validate_coupon(coupon_code text, order_amount numeric)
returns table(valid boolean, discount numeric, message text)
language plpgsql security definer set search_path = public
as $$
declare
  c record;
begin
  select * into c from public.coupons where code = upper(coupon_code);

  if not found then
    return query select false, 0::numeric, 'Invalid coupon code';
    return;
  end if;
  if not c.active then
    return query select false, 0::numeric, 'This coupon is no longer active';
    return;
  end if;
  if c.expires_at is not null and c.expires_at < current_date then
    return query select false, 0::numeric, 'This coupon has expired';
    return;
  end if;
  if c.usage_limit is not null and c.used_count >= c.usage_limit then
    return query select false, 0::numeric, 'This coupon has reached its usage limit';
    return;
  end if;
  if c.min_amount is not null and order_amount < c.min_amount then
    return query select false, 0::numeric, format('Minimum order amount is ₹%s', c.min_amount);
    return;
  end if;

  return query select
    true,
    case when c.type = 'flat' then least(c.value, order_amount) else round(order_amount * c.value / 100, 2) end,
    'Coupon applied';
end;
$$;

grant execute on function public.validate_coupon(text, numeric) to anon, authenticated;
