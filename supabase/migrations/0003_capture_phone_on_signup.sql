-- ============================================================
-- Migration: 0003_capture_phone_on_signup
-- ============================================================
-- pages/login.html's registration form sends `phone` in
-- auth signUp()'s options.data, but handle_new_auth_user() (0001)
-- never copied it into profiles — it would have been silently
-- dropped. Fixes the trigger to store it like full_name already is.
-- ============================================================

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

  insert into public.profiles (id, email, full_name, phone, role)
  values (
    new.id,
    new.email,
    new.raw_user_meta_data ->> 'full_name',
    new.raw_user_meta_data ->> 'phone',
    resolved_role
  );

  if resolved_role = 'main_admin' then
    insert into public.main_admin_locks (uid, email)
    values (new.id, lower(new.email))
    on conflict (uid) do nothing;
  end if;

  return new;
end;
$$;
