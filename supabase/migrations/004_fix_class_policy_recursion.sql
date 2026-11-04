-- ════════════════════════════════════════════════════════════════════════════
-- Fix: "infinite recursion detected in policy for relation class_subject_teachers"
--
-- class_subject_teachers' "Students can read assignments for their class"
-- policy queries class_students. class_students' "Teachers can read roster
-- for their classes" policy queries class_subject_teachers back. Each side
-- re-triggers the other's RLS, recursing indefinitely. Same fix as 003:
-- SECURITY DEFINER helper functions break the cycle by bypassing RLS
-- re-entrancy on the inner lookup.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function is_teacher_of_class(check_class_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select
    exists (
      select 1 from class_subject_teachers
      where class_id = check_class_id and teacher_id = auth.uid()
    )
    or exists (
      select 1 from classes
      where id = check_class_id and teacher_id = auth.uid()
    );
$$;

grant execute on function is_teacher_of_class(uuid) to authenticated;

create or replace function is_student_of_class(check_class_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from class_students
    where class_id = check_class_id and student_id = auth.uid()
  );
$$;

grant execute on function is_student_of_class(uuid) to authenticated;

-- class_subject_teachers ─────────────────────────────────────────────────────
drop policy if exists "Students can read assignments for their class" on class_subject_teachers;
create policy "Students can read assignments for their class"
  on class_subject_teachers for select
  using (is_student_of_class(class_id));

-- class_students ─────────────────────────────────────────────────────────────
drop policy if exists "Teachers can read roster for their classes" on class_students;
create policy "Teachers can read roster for their classes"
  on class_students for select
  using (is_teacher_of_class(class_id));

-- timetable_slots ────────────────────────────────────────────────────────────
drop policy if exists "Students can read their class timetable" on timetable_slots;
create policy "Students can read their class timetable"
  on timetable_slots for select
  using (is_student_of_class(class_id));

-- announcements ───────────────────────────────────────────────────────────────
drop policy if exists "Students can read announcements for their class" on announcements;
create policy "Students can read announcements for their class"
  on announcements for select
  using (is_student_of_class(class_id));

drop policy if exists "Teachers can read and post to their class noticeboard" on announcements;
create policy "Teachers can read and post to their class noticeboard"
  on announcements for select
  using (is_teacher_of_class(class_id));

drop policy if exists "Teachers can insert announcements for their class" on announcements;
create policy "Teachers can insert announcements for their class"
  on announcements for insert
  with check (author_id = auth.uid() and is_teacher_of_class(class_id));

-- grades ──────────────────────────────────────────────────────────────────────
-- Also broadened from "classes.teacher_id only" to include subject-teachers,
-- so a teacher assigned to a class for one subject (not just the homeroom
-- teacher) can record grades for it.
drop policy if exists "Teachers can insert grades for their class" on grades;
create policy "Teachers can insert grades for their class"
  on grades for insert
  with check (is_teacher_of_class(class_id));

drop policy if exists "Teachers can update grades for their class" on grades;
create policy "Teachers can update grades for their class"
  on grades for update
  using (is_teacher_of_class(class_id));

-- attendance (from 001_initial_schema.sql) — same broadening for consistency.
drop policy if exists "Teachers see class attendance" on attendance;
create policy "Teachers see class attendance"
  on attendance for select
  using (is_teacher_of_class(class_id));

drop policy if exists "Teachers can insert attendance" on attendance;
create policy "Teachers can insert attendance"
  on attendance for insert
  with check (marked_by_teacher_id = auth.uid() and is_teacher_of_class(class_id));

drop policy if exists "Teachers can update attendance" on attendance;
create policy "Teachers can update attendance"
  on attendance for update
  using (is_teacher_of_class(class_id));

-- grades (from 001_initial_schema.sql) — same broadening for read access.
drop policy if exists "Teachers see all grades for their class" on grades;
create policy "Teachers see all grades for their class"
  on grades for select
  using (is_teacher_of_class(class_id));
