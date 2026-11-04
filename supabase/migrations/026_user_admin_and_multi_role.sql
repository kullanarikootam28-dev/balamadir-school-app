-- ════════════════════════════════════════════════════════════════════════════
-- 026 — Admin user management, teacher+admin dual role, and closing two
-- privilege-escalation holes on `profiles`.
--
-- Before this migration:
--   * "Users can update their own profile" had no column restriction, so any
--     signed-in user (a student included) could PATCH their own `role` to
--     'admin' through the REST API.
--   * "Users can insert their own profile" let anyone who signed up through
--     the public API (the anon key ships inside the app) insert a profile
--     with role 'admin'. Accounts were created that way on purpose — the app
--     signed the new user up from a throwaway client — so sign-ups had to
--     stay enabled.
--   * There was no admin UPDATE or DELETE policy on `profiles`, so User
--     Management's Edit and Delete silently changed nothing (RLS filters the
--     row out instead of raising an error).
--
-- After it:
--   * Only admins can change role / admin access / email (trigger below).
--   * Accounts are created, edited, re-passworded and deleted only through
--     the admin_* functions, which check is_admin() themselves. Public
--     sign-ups are switched off in the Auth settings alongside this.
--   * `admin_access` lets a teacher also open the Admin panel; is_admin()
--     honours it, so every existing RLS policy that calls is_admin() works
--     for them unchanged.
-- ════════════════════════════════════════════════════════════════════════════

alter table public.profiles
  add column if not exists admin_access boolean not null default false;

comment on column public.profiles.admin_access is
  'Teacher who can also open the Admin panel (they choose Admin or Teacher at sign-in). Always false for other roles.';

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from profiles
    where id = auth.uid() and (role = 'admin' or admin_access)
  );
$$;

-- ── Guard: who may change privileges ────────────────────────────────────────
-- SECURITY INVOKER on purpose: current_user is then the API role
-- ('authenticated') for app requests, but 'postgres' inside the admin_*
-- functions below, which do their own is_admin() check first.
create or replace function public.guard_profile_privileges()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_was_admin boolean;
  v_now_admin boolean;
begin
  -- Admin access only means something for teachers: admins already have it,
  -- and students must never get it.
  if new.role <> 'teacher' then
    new.admin_access := false;
  end if;

  if tg_op = 'INSERT' then
    return new;
  end if;

  if current_user in ('authenticated', 'anon') and not public.is_admin() then
    if new.role is distinct from old.role
       or new.admin_access is distinct from old.admin_access
       or new.email is distinct from old.email
       or new.id is distinct from old.id then
      raise exception 'Only an admin can change a user''s role, admin access or email'
        using errcode = '42501';
    end if;
  end if;

  v_was_admin := old.role = 'admin' or old.admin_access;
  v_now_admin := new.role = 'admin' or new.admin_access;
  if v_was_admin and not v_now_admin then
    if new.id = auth.uid() then
      raise exception 'You can''t remove your own admin access. Ask another admin to do it.'
        using errcode = '42501';
    end if;
    if not exists (
      select 1 from profiles p
      where p.id <> new.id and (p.role = 'admin' or p.admin_access)
    ) then
      raise exception 'This is the only admin account. Make someone else an admin first.'
        using errcode = '42501';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_profile_privileges on public.profiles;
create trigger trg_guard_profile_privileges
  before insert or update on public.profiles
  for each row execute function public.guard_profile_privileges();

-- ── Policies ────────────────────────────────────────────────────────────────
drop policy if exists "Users can insert their own profile" on public.profiles;

drop policy if exists "Users can update their own profile" on public.profiles;
create policy "Users can update their own profile" on public.profiles
  for update to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);

drop policy if exists "Admins can update any profile" on public.profiles;
create policy "Admins can update any profile" on public.profiles
  for update to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- ── admin_create_user ───────────────────────────────────────────────────────
-- Writes the same auth.users / auth.identities shape Supabase Auth creates
-- for an email sign-up (confirmed, bcrypt password), then the profile.
create or replace function public.admin_create_user(
  p_email text,
  p_password text,
  p_full_name text,
  p_role public.user_role,
  p_phone text default null,
  p_admin_access boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid := gen_random_uuid();
  v_email text := lower(trim(p_email));
  v_identity jsonb;
begin
  if not public.is_admin() then
    raise exception 'Only an admin can create accounts' using errcode = '42501';
  end if;
  if v_email is null or v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Enter a valid email address' using errcode = '22023';
  end if;
  if coalesce(length(p_password), 0) < 6 then
    raise exception 'Password must be at least 6 characters' using errcode = '22023';
  end if;
  if coalesce(trim(p_full_name), '') = '' then
    raise exception 'Full name is required' using errcode = '22023';
  end if;
  if exists (select 1 from auth.users where lower(email) = v_email) then
    raise exception 'An account with this email already exists' using errcode = '23505';
  end if;

  v_identity := jsonb_build_object(
    'sub', v_id::text, 'email', v_email, 'email_verified', true, 'phone_verified', false);

  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change
  ) values (
    '00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated',
    v_email, extensions.crypt(p_password, extensions.gen_salt('bf', 10)), now(),
    '{"provider":"email","providers":["email"]}'::jsonb, v_identity, now(), now(),
    '', '', '', ''
  );

  insert into auth.identities (provider_id, user_id, identity_data, provider, created_at, updated_at)
  values (v_id::text, v_id, v_identity, 'email', now(), now());

  insert into public.profiles (id, full_name, email, role, phone, admin_access)
  values (v_id, trim(p_full_name), v_email, p_role,
          nullif(trim(coalesce(p_phone, '')), ''), coalesce(p_admin_access, false));

  insert into public.audit_log (actor_id, actor_role, module, action, new_value)
  values (auth.uid(), 'admin', 'users', 'create',
          jsonb_build_object('user_id', v_id, 'email', v_email, 'role', p_role,
                             'admin_access', p_role = 'teacher' and coalesce(p_admin_access, false)));
  return v_id;
end;
$$;

-- ── admin_update_user ───────────────────────────────────────────────────────
-- The trigger above still applies (no self-demotion, never zero admins).
create or replace function public.admin_update_user(
  p_user_id uuid,
  p_full_name text,
  p_phone text,
  p_role public.user_role,
  p_admin_access boolean default false
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old jsonb;
begin
  if not public.is_admin() then
    raise exception 'Only an admin can edit accounts' using errcode = '42501';
  end if;
  if coalesce(trim(p_full_name), '') = '' then
    raise exception 'Full name is required' using errcode = '22023';
  end if;

  select jsonb_build_object('full_name', full_name, 'phone', phone, 'role', role,
                            'admin_access', admin_access)
    into v_old
    from public.profiles where id = p_user_id;
  if v_old is null then
    raise exception 'User not found' using errcode = 'P0002';
  end if;

  update public.profiles
     set full_name = trim(p_full_name),
         phone = nullif(trim(coalesce(p_phone, '')), ''),
         role = p_role,
         admin_access = coalesce(p_admin_access, false)
   where id = p_user_id;

  insert into public.audit_log (actor_id, actor_role, module, action, old_value, new_value)
  values (auth.uid(), 'admin', 'users', 'update', v_old,
          jsonb_build_object('user_id', p_user_id, 'full_name', trim(p_full_name), 'role', p_role,
                             'admin_access', p_role = 'teacher' and coalesce(p_admin_access, false)));
end;
$$;

-- ── admin_set_password ──────────────────────────────────────────────────────
-- Also ends that user's existing sign-ins (unless it's the admin's own
-- account), so a password reset really locks out whoever had the old one.
create or replace function public.admin_set_password(p_user_id uuid, p_password text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Only an admin can set passwords' using errcode = '42501';
  end if;
  if coalesce(length(p_password), 0) < 6 then
    raise exception 'Password must be at least 6 characters' using errcode = '22023';
  end if;

  update auth.users
     set encrypted_password = extensions.crypt(p_password, extensions.gen_salt('bf', 10)),
         recovery_token = '',
         updated_at = now()
   where id = p_user_id;
  if not found then
    raise exception 'User not found' using errcode = 'P0002';
  end if;

  if p_user_id is distinct from auth.uid() then
    delete from auth.sessions where user_id = p_user_id;
  end if;

  insert into public.audit_log (actor_id, actor_role, module, action, new_value)
  values (auth.uid(), 'admin', 'users', 'set_password', jsonb_build_object('user_id', p_user_id));
end;
$$;

-- ── admin_delete_user ───────────────────────────────────────────────────────
-- Deleting the auth user cascades to the profile and, through the existing
-- foreign keys, to that person's own records (attendance, marks, fees,
-- enrollment...). Records they merely authored/marked keep existing with the
-- author cleared (those FKs are ON DELETE SET NULL).
create or replace function public.admin_delete_user(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile jsonb;
begin
  if not public.is_admin() then
    raise exception 'Only an admin can delete accounts' using errcode = '42501';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'You can''t delete your own account' using errcode = '42501';
  end if;

  select jsonb_build_object('user_id', id, 'email', email, 'full_name', full_name, 'role', role,
                            'admin_access', admin_access)
    into v_profile
    from public.profiles where id = p_user_id;

  if coalesce((v_profile ->> 'role') = 'admin' or (v_profile ->> 'admin_access')::boolean, false)
     and not exists (
       select 1 from public.profiles
       where id <> p_user_id and (role = 'admin' or admin_access)
     ) then
    raise exception 'This is the only admin account. Make someone else an admin first.'
      using errcode = '42501';
  end if;

  delete from auth.users where id = p_user_id;
  if not found then
    -- A profile left behind without a login: remove it directly.
    delete from public.profiles where id = p_user_id;
    if not found then
      raise exception 'User not found' using errcode = 'P0002';
    end if;
  end if;

  insert into public.audit_log (actor_id, actor_role, module, action, old_value)
  values (auth.uid(), 'admin', 'users', 'delete', v_profile);
end;
$$;

revoke all on function public.admin_create_user(text, text, text, public.user_role, text, boolean) from public, anon;
revoke all on function public.admin_update_user(uuid, text, text, public.user_role, boolean) from public, anon;
revoke all on function public.admin_set_password(uuid, text) from public, anon;
revoke all on function public.admin_delete_user(uuid) from public, anon;
grant execute on function public.admin_create_user(text, text, text, public.user_role, text, boolean) to authenticated;
grant execute on function public.admin_update_user(uuid, text, text, public.user_role, boolean) to authenticated;
grant execute on function public.admin_set_password(uuid, text) to authenticated;
grant execute on function public.admin_delete_user(uuid) to authenticated;
