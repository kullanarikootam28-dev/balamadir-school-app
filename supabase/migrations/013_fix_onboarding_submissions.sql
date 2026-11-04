-- ════════════════════════════════════════════════════════════════════════════
-- Fix: teacher_detail_submissions / staff_detail_submissions assumed an
-- existing profiles/non_teaching_staff row to attach to, but unlike
-- students, no real teacher or staff roster exists yet — only students
-- came with a source spreadsheet. These become self-registration intake
-- forms instead: the admin creates the real account/staff row from what's
-- submitted (User Management / Staff Management), rather than the
-- submission updating a pre-existing record.
-- ════════════════════════════════════════════════════════════════════════════

alter table teacher_detail_submissions drop constraint if exists teacher_detail_submissions_teacher_id_fkey;
alter table teacher_detail_submissions alter column teacher_id drop not null;
alter table teacher_detail_submissions add column if not exists full_name text;
alter table teacher_detail_submissions add column if not exists email text;

alter table staff_detail_submissions drop constraint if exists staff_detail_submissions_staff_id_fkey;
alter table staff_detail_submissions alter column staff_id drop not null;
alter table staff_detail_submissions add column if not exists full_name text;
alter table staff_detail_submissions add column if not exists designation text;
alter table staff_detail_submissions add column if not exists department text;
alter table staff_detail_submissions add column if not exists joining_date date;
