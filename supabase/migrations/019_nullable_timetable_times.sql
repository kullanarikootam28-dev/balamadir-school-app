-- ════════════════════════════════════════════════════════════════════════════
-- The real school timetable (ALL CLASS TIMETABLE FOR BMS.xlsx) has no clock
-- times, only period numbers — start_time/end_time were previously required,
-- which would have forced inventing times not present in the source data.
-- Made nullable so bulk-imported slots can carry just day/period/subject/
-- teacher; the admin's manual per-slot editor still lets a real time be set.
-- ════════════════════════════════════════════════════════════════════════════

alter table timetable_slots alter column start_time drop not null;
alter table timetable_slots alter column end_time drop not null;
