-- ════════════════════════════════════════════════════════════════════════════
-- 027 — One login for a parent with several children.
--
-- 48 families at this school have 2+ children enrolled (108 students). Each
-- child has their own login, so a parent had to sign out of one child to see
-- the other. This links siblings into a family: any login in that family can
-- switch between the children inside the student portal, exactly like the
-- child switcher in other school apps.
--
-- How it works: `profiles.family_id` groups siblings. family_student_ids()
-- returns the caller plus every student sharing their family_id, and the
-- student-facing policies below now allow that whole set instead of only
-- auth.uid(). Nothing changes for a student with no siblings linked — the
-- set is just themselves.
--
-- Only an admin can set family_id (enforced in guard_profile_privileges),
-- so nobody can link themselves into another family to read its data.
-- ════════════════════════════════════════════════════════════════════════════

alter table public.profiles
  add column if not exists family_id uuid;

create index if not exists idx_profiles_family_id on public.profiles (family_id)
  where family_id is not null;

comment on column public.profiles.family_id is
  'Siblings share this id. Any login in the family can switch between those children in the student portal. Admin-only field.';

-- ── Who this login may act for ──────────────────────────────────────────────
-- Wrapped in "(select ...)" at every call site so Postgres evaluates it once
-- per query instead of once per row.
create or replace function public.family_student_ids()
returns uuid[]
language sql
stable
security definer
set search_path = public
as $$
  select array(
    select auth.uid()
    union
    select p.id
      from profiles p
      join profiles me on me.id = auth.uid()
     where me.family_id is not null
       and p.family_id = me.family_id
       and p.role = 'student'
  );
$$;

create or replace function public.is_family_student(p_student_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select p_student_id = any (public.family_student_ids());
$$;

-- Class-based reads (class notices, timetable, subject assignments) follow
-- whichever child the parent is viewing.
create or replace function public.is_student_of_class(check_class_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from class_students
    where class_id = check_class_id
      and student_id = any (public.family_student_ids())
  );
$$;

-- Seeing a sibling's name/photo in the switcher, and their profile page.
create or replace function public.can_view_profile(target_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    target_id = auth.uid()
    or is_admin()
    or public.is_family_student(target_id)
    -- Requester teaches a class the target is enrolled in as a student.
    or exists (
      select 1 from class_students cs
      where cs.student_id = target_id and is_teacher_of_class(cs.class_id)
    )
    -- Requester is enrolled in a class the target teaches (subject or homeroom).
    or exists (
      select 1 from class_students cs
      where cs.student_id = auth.uid()
        and (
          exists (
            select 1 from class_subject_teachers cst
            where cst.class_id = cs.class_id and cst.teacher_id = target_id
          )
          or exists (
            select 1 from classes c
            where c.id = cs.class_id and c.teacher_id = target_id
          )
        )
    );
$$;

-- ── Student-facing policies: own rows → the family's rows ───────────────────
drop policy if exists "Students see own attendance" on public.attendance;
create policy "Students see own attendance" on public.attendance
  for select using (student_id = any ((select public.family_student_ids())::uuid[]));

drop policy if exists "Students see own grades" on public.grades;
create policy "Students see own grades" on public.grades
  for select using (student_id = any ((select public.family_student_ids())::uuid[]));

drop policy if exists "Students see own fee payments" on public.fee_payments;
create policy "Students see own fee payments" on public.fee_payments
  for select using (student_id = any ((select public.family_student_ids())::uuid[]));

drop policy if exists "Students can read their own enrollment" on public.class_students;
create policy "Students can read their own enrollment" on public.class_students
  for select using (student_id = any ((select public.family_student_ids())::uuid[]));

drop policy if exists "Students read own details" on public.student_details;
create policy "Students read own details" on public.student_details
  for select using (student_id = any ((select public.family_student_ids())::uuid[]));

drop policy if exists "Students read own report_card_remarks" on public.report_card_remarks;
create policy "Students read own report_card_remarks" on public.report_card_remarks
  for select using (student_id = any ((select public.family_student_ids())::uuid[]));

drop policy if exists "Students read own transport" on public.student_transport;
create policy "Students read own transport" on public.student_transport
  for select using (student_id = any ((select public.family_student_ids())::uuid[]));

drop policy if exists "Students can read exam_subjects for their class" on public.exam_subjects;
create policy "Students can read exam_subjects for their class" on public.exam_subjects
  for select using (
    exists (
      select 1 from class_students cs
      where cs.class_id = exam_subjects.class_id
        and cs.student_id = any ((select public.family_student_ids())::uuid[])
    )
  );

-- Messages: a parent reads and replies to the conversation of whichever
-- child they're viewing, so a teacher's message about the younger child
-- isn't stranded in a login the family never opens.
drop policy if exists "Users can read their own conversations" on public.messages;
create policy "Users can read their own conversations" on public.messages
  for select using (
    sender_id = any ((select public.family_student_ids())::uuid[])
    or recipient_id = any ((select public.family_student_ids())::uuid[])
  );

drop policy if exists "Users can send messages as themselves" on public.messages;
create policy "Users can send messages as themselves" on public.messages
  for insert with check (sender_id = any ((select public.family_student_ids())::uuid[]));

drop policy if exists "Recipients can mark messages read" on public.messages;
create policy "Recipients can mark messages read" on public.messages
  for update using (recipient_id = any ((select public.family_student_ids())::uuid[]));

drop policy if exists "Senders can soft-delete their own messages" on public.messages;
create policy "Senders can soft-delete their own messages" on public.messages
  for update using (sender_id = any ((select public.family_student_ids())::uuid[]));

drop policy if exists "Users read their own notifications" on public.in_app_notifications;
create policy "Users read their own notifications" on public.in_app_notifications
  for select using (user_id = any ((select public.family_student_ids())::uuid[]) or is_admin());

drop policy if exists "Users mark their own notifications read" on public.in_app_notifications;
create policy "Users mark their own notifications read" on public.in_app_notifications
  for update using (user_id = any ((select public.family_student_ids())::uuid[]));

-- ── family_id is admin-only ─────────────────────────────────────────────────
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
       or new.id is distinct from old.id
       or new.family_id is distinct from old.family_id then
      raise exception 'Only an admin can change a user''s role, admin access, email or family link'
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

-- ── The children this login can switch between ──────────────────────────────
create or replace function public.my_family_students()
returns table (
  id uuid,
  full_name text,
  avatar_url text,
  grade text,
  section text,
  roll_number text,
  is_self boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, p.full_name, p.avatar_url, c.grade, c.section, cs.roll_number,
         p.id = auth.uid()
    from profiles p
    left join class_students cs on cs.student_id = p.id
    left join classes c on c.id = cs.class_id
   where p.id = any (public.family_student_ids())
     and (p.role = 'student' or p.id = auth.uid())
   order by c.grade nulls last, p.full_name;
$$;

-- ── Admin: link / unlink siblings ───────────────────────────────────────────
create or replace function public.admin_link_family(p_student_ids uuid[])
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_family uuid;
  v_count int;
begin
  if not public.is_admin() then
    raise exception 'Only an admin can link families' using errcode = '42501';
  end if;
  select count(*) into v_count
    from profiles where id = any (p_student_ids) and role = 'student';
  if v_count < 2 or v_count <> coalesce(array_length(p_student_ids, 1), 0) then
    raise exception 'Pick two or more student accounts to link' using errcode = '22023';
  end if;

  -- Join an existing family if any of them already has one (merging the rest).
  select family_id into v_family
    from profiles
   where id = any (p_student_ids) and family_id is not null
   limit 1;
  v_family := coalesce(v_family, gen_random_uuid());

  update profiles
     set family_id = v_family
   where family_id in (
           select family_id from profiles
            where id = any (p_student_ids) and family_id is not null
         )
      or id = any (p_student_ids);

  insert into public.audit_log (actor_id, actor_role, module, action, new_value)
  values (auth.uid(), 'admin', 'families', 'link',
          jsonb_build_object('family_id', v_family, 'student_ids', to_jsonb(p_student_ids)));
  return v_family;
end;
$$;

create or replace function public.admin_unlink_student(p_student_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_family uuid;
begin
  if not public.is_admin() then
    raise exception 'Only an admin can unlink families' using errcode = '42501';
  end if;
  select family_id into v_family from profiles where id = p_student_id;
  update profiles set family_id = null where id = p_student_id;

  -- A family of one is no family: clear the leftover member too.
  if v_family is not null then
    update profiles set family_id = null
     where family_id = v_family
       and (select count(*) from profiles where family_id = v_family) < 2;
  end if;

  insert into public.audit_log (actor_id, actor_role, module, action, old_value)
  values (auth.uid(), 'admin', 'families', 'unlink',
          jsonb_build_object('student_id', p_student_id, 'family_id', v_family));
end;
$$;

revoke all on function public.admin_link_family(uuid[]) from public, anon;
revoke all on function public.admin_unlink_student(uuid) from public, anon;
grant execute on function public.admin_link_family(uuid[]) to authenticated;
grant execute on function public.admin_unlink_student(uuid) to authenticated;
grant execute on function public.my_family_students() to authenticated;
grant execute on function public.family_student_ids() to authenticated;
grant execute on function public.is_family_student(uuid) to authenticated;
