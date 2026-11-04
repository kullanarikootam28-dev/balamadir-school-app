-- ════════════════════════════════════════════════════════════════════════════
-- Half-day attendance status, requested by real school staff (Bugs1.docx:
-- "Students/teachers halfday leave update"). Shared by both `attendance`
-- (students) and `teacher_attendance` since both columns use this same enum.
--
-- Note: a value added to a Postgres enum can't be referenced in the same
-- transaction/migration that adds it, so this migration only adds the value —
-- nothing here uses 'half_day' yet.
-- ════════════════════════════════════════════════════════════════════════════

alter type attendance_status add value if not exists 'half_day';
