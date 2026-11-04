-- ════════════════════════════════════════════════════════════════════════════
-- Fix: "infinite recursion detected in policy for relation profiles"
--
-- Every "Admins can ..." policy checked admin status with an inline
-- `exists (select 1 from profiles p where p.id = auth.uid() and p.role =
-- 'admin')` subquery. Because that subquery reads from `profiles` itself,
-- Postgres must re-apply profiles' own RLS policies to evaluate it — and the
-- planner is not guaranteed to short-circuit via the simpler "own row"
-- policy first, so this can recurse. The standard fix is a SECURITY DEFINER
-- helper function, which runs with privileges that bypass RLS re-entrancy.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function is_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from profiles where id = auth.uid() and role = 'admin'
  );
$$;

grant execute on function is_admin() to authenticated;

-- profiles (from 001_initial_schema.sql) ────────────────────────────────────
drop policy if exists "Admins can read all profiles" on profiles;
create policy "Admins can read all profiles"
  on profiles for select
  using (is_admin());

-- attendance / grades (from 002_role_panels_schema.sql) ─────────────────────
drop policy if exists "Admins manage all attendance" on attendance;
create policy "Admins manage all attendance"
  on attendance for all
  using (is_admin());

drop policy if exists "Admins manage all grades" on grades;
create policy "Admins manage all grades"
  on grades for all
  using (is_admin());

-- new tables (from 002_role_panels_schema.sql) ───────────────────────────────
drop policy if exists "Admins manage subjects" on subjects;
create policy "Admins manage subjects"
  on subjects for all
  using (is_admin());

drop policy if exists "Admins manage class_subject_teachers" on class_subject_teachers;
create policy "Admins manage class_subject_teachers"
  on class_subject_teachers for all
  using (is_admin());

drop policy if exists "Admins manage class_students" on class_students;
create policy "Admins manage class_students"
  on class_students for all
  using (is_admin());

drop policy if exists "Admins manage timetable_slots" on timetable_slots;
create policy "Admins manage timetable_slots"
  on timetable_slots for all
  using (is_admin());

drop policy if exists "Admins manage announcements" on announcements;
create policy "Admins manage announcements"
  on announcements for all
  using (is_admin());
