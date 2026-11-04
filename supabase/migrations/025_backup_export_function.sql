-- ════════════════════════════════════════════════════════════════════════════
-- The backup Worker (cloudflare-worker/index.js) read each table with
-- `?limit=10000`, but this project's PostgREST caps every response at 1000
-- rows (max_rows = 1000) and ignores larger limits — so backups of
-- attendance/audit_log would silently stop at 1000 rows. Paging instead
-- would cost one Worker subrequest per 1000 rows and blow the free plan's
-- 50-subrequest limit.
--
-- This returns a whole table as ONE json value (json_agg), so the row cap
-- doesn't apply and each table stays a single request. Security definer
-- bypasses RLS, so execution is restricted to service_role (which already
-- bypasses RLS) and the table name is checked against a fixed whitelist
-- before being used in dynamic SQL.
-- ════════════════════════════════════════════════════════════════════════════

create or replace function export_table_json(p_table text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_allowed constant text[] := array[
    'profiles', 'student_details', 'teacher_details', 'non_teaching_staff',
    'academic_years', 'classes', 'subjects', 'class_subject_teachers', 'class_students',
    'timetable_slots', 'attendance', 'teacher_attendance', 'grades', 'exams',
    'exam_subjects', 'report_card_remarks', 'promotions', 'attendance_unlocks',
    'fee_types', 'fee_payments', 'app_settings', 'expense_categories', 'expenses',
    'repair_requests', 'announcements', 'messages', 'complaints', 'buses',
    'bus_stops', 'student_transport', 'calendar_events', 'teacher_leaves', 'audit_log'
  ];
  v_result json;
begin
  if not (p_table = any (v_allowed)) then
    raise exception 'Table % is not exportable', p_table;
  end if;

  execute format('select coalesce(json_agg(t), ''[]''::json) from %I t', p_table)
    into v_result;
  return v_result;
end;
$$;

revoke all on function export_table_json(text) from public;
revoke all on function export_table_json(text) from anon, authenticated;
grant execute on function export_table_json(text) to service_role;
