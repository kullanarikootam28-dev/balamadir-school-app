-- ════════════════════════════════════════════════════════════════════════════
-- Fix: joined `profiles(full_name)` embeds silently return null for
-- teacher→student and student→teacher lookups (roster names, gradebook
-- names, timetable teacher names, messaging contact names, etc).
--
-- Root cause: `profiles` only had "read own row" and "admin reads all"
-- policies. A teacher reading a class roster CAN read the class_students
-- rows (roll numbers etc, via is_teacher_of_class), but the embedded
-- `profiles` row for each student fails RLS separately — there was no
-- policy letting a teacher read a *student's* profile, or a student read
-- a *teacher's* profile. PostgREST doesn't error on this; the embed is
-- just silently null, which is why names rendered as "—" instead of
-- erroring.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function can_view_profile(target_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select
    target_id = auth.uid()
    or is_admin()
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

grant execute on function can_view_profile(uuid) to authenticated;

drop policy if exists "Users can read their own profile" on profiles;
drop policy if exists "Admins can read all profiles" on profiles;

create policy "Users can view relevant profiles"
  on profiles for select
  using (can_view_profile(id));
