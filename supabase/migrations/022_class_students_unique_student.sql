-- ════════════════════════════════════════════════════════════════════════════
-- A student belongs to exactly one class at a time — enforced here so the
-- new "edit a student's class" feature (student_records_screen.dart) can
-- safely assume `class_students` has at most one row per student and use
-- .maybeSingle() without risking a "multiple rows returned" error.
-- ════════════════════════════════════════════════════════════════════════════

alter table class_students add constraint class_students_student_id_key unique (student_id);
