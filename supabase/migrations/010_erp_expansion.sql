-- ════════════════════════════════════════════════════════════════════════════
-- School Management App — Phase 4 Schema: 22-module ERP gap-fill
-- Parent/guardian data, staff, academic years, formal exams, attendance
-- lock/unlock, teacher attendance, transport, calendar, promotion, audit
-- log, notification log, fee types, document storage.
-- ════════════════════════════════════════════════════════════════════════════

create type staff_status as enum ('active', 'on_leave', 'resigned');
create type calendar_event_type as enum ('holiday', 'event', 'exam', 'sports_day', 'annual_day');
create type notification_trigger as enum ('fee_reminder', 'fee_payment', 'attendance', 'marks_published', 'event');

-- ────────────────────────────────────────────────────────────────────────────
-- TABLE: student_details
-- 1:1 extension of profiles for role='student'. Field names/shapes are
-- grounded in the client's real EMIS export (EMIS Id, Admission Number,
-- Father/Mother/Guardian Name+Occupation+Education, Aadhaar, Address, Pin
-- code, Blood Group, Religion, Medium of Instruction, Community, Mother
-- Tongue) — not invented placeholders.
-- ────────────────────────────────────────────────────────────────────────────
create table if not exists student_details (
  student_id                uuid        primary key references profiles(id) on delete cascade,
  emis_id                   text,
  admission_number          text,
  father_name               text,
  father_occupation         text,
  father_education          text,
  mother_name               text,
  mother_occupation         text,
  mother_education          text,
  guardian_name             text,
  guardian_occupation       text,
  aadhaar_number            text,
  date_of_birth             date,
  gender                    text,
  date_of_joining           date,
  address                   text,
  pin_code                  text,
  blood_group               text,
  religion                  text,
  medium_of_instruction     text,
  community                 text,
  mother_tongue             text,
  emergency_contact_name    text,
  emergency_contact_phone   text,
  status                    text        not null default 'active'
                              check (status in ('active', 'transferred', 'archived')),
  photo_url                 text,
  birth_certificate_url     text,
  aadhaar_doc_url           text,
  tc_url                    text,
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now()
);

create trigger trg_student_details_updated_at
  before update on student_details
  for each row execute function update_updated_at();

-- ────────────────────────────────────────────────────────────────────────────
-- TABLE: non_teaching_staff
-- ────────────────────────────────────────────────────────────────────────────
create table if not exists non_teaching_staff (
  id            uuid          primary key default gen_random_uuid(),
  full_name     text          not null,
  designation   text          not null,
  department    text,
  phone         text,
  salary_paise  integer       check (salary_paise >= 0),
  joining_date  date,
  status        staff_status  not null default 'active',
  remarks       text,
  created_at    timestamptz   not null default now(),
  updated_at    timestamptz   not null default now()
);

create trigger trg_non_teaching_staff_updated_at
  before update on non_teaching_staff
  for each row execute function update_updated_at();

-- ────────────────────────────────────────────────────────────────────────────
-- TABLE: academic_years
-- ────────────────────────────────────────────────────────────────────────────
create table if not exists academic_years (
  id          uuid        primary key default gen_random_uuid(),
  year_label  text        not null unique,
  start_date  date,
  end_date    date,
  is_current  boolean     not null default false,
  archived    boolean     not null default false,
  created_at  timestamptz not null default now()
);

-- Only one academic year may be current at a time.
create unique index idx_academic_years_one_current
  on academic_years (is_current)
  where is_current;

-- ────────────────────────────────────────────────────────────────────────────
-- TABLE: fee_types (Admission, Tuition, Transport, Exam, Special)
-- ────────────────────────────────────────────────────────────────────────────
create table if not exists fee_types (
  id          uuid        primary key default gen_random_uuid(),
  name        text        not null unique,
  created_at  timestamptz not null default now()
);

insert into fee_types (name) values
  ('Admission'), ('Tuition'), ('Transport'), ('Exam'), ('Special')
on conflict (name) do nothing;

alter table fee_payments add column if not exists fee_type_id uuid references fee_types(id) on delete set null;
alter table fee_payments add column if not exists payment_mode text;
alter table fee_payments add column if not exists receipt_number text;

-- ────────────────────────────────────────────────────────────────────────────
-- TABLE: exams / exam_subjects
-- ────────────────────────────────────────────────────────────────────────────
create table if not exists exams (
  id            uuid        primary key default gen_random_uuid(),
  name          text        not null,          -- 'Test 1', 'Quarterly', 'Annual', ...
  academic_year text        not null default to_char(now(), 'YYYY'),
  exam_date     date,
  created_by    uuid        references profiles(id) on delete set null,
  created_at    timestamptz not null default now()
);

create table if not exists exam_subjects (
  id          uuid        primary key default gen_random_uuid(),
  exam_id     uuid        not null references exams(id) on delete cascade,
  subject_id  uuid        not null references subjects(id) on delete cascade,
  class_id    uuid        not null references classes(id) on delete cascade,
  max_marks   numeric(6,2) not null check (max_marks > 0),
  pass_marks  numeric(6,2) not null check (pass_marks >= 0),
  created_at  timestamptz not null default now(),
  unique (exam_id, subject_id, class_id),
  constraint chk_pass_le_max check (pass_marks <= max_marks)
);

alter table grades add column if not exists exam_id uuid references exams(id) on delete set null;

-- ────────────────────────────────────────────────────────────────────────────
-- TABLE: report_card_remarks
-- ────────────────────────────────────────────────────────────────────────────
create table if not exists report_card_remarks (
  id          uuid        primary key default gen_random_uuid(),
  student_id  uuid        not null references profiles(id) on delete cascade,
  exam_id     uuid        not null references exams(id) on delete cascade,
  remarks     text,
  created_by  uuid        references profiles(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (student_id, exam_id)
);

create trigger trg_report_card_remarks_updated_at
  before update on report_card_remarks
  for each row execute function update_updated_at();

-- ────────────────────────────────────────────────────────────────────────────
-- TABLE: teacher_attendance
-- ────────────────────────────────────────────────────────────────────────────
create table if not exists teacher_attendance (
  id          uuid              primary key default gen_random_uuid(),
  teacher_id  uuid              not null references profiles(id) on delete cascade,
  date        date              not null default current_date,
  status      attendance_status not null default 'present',
  marked_by   uuid              references profiles(id) on delete set null,
  remarks     text,
  created_at  timestamptz       not null default now(),
  unique (teacher_id, date)
);

-- ────────────────────────────────────────────────────────────────────────────
-- TABLE: attendance_unlocks
-- Presence of a row = office staff re-opened that class's already-past
-- calendar week for editing.
-- ────────────────────────────────────────────────────────────────────────────
create table if not exists attendance_unlocks (
  id              uuid        primary key default gen_random_uuid(),
  class_id        uuid        not null references classes(id) on delete cascade,
  week_start_date date        not null,
  unlocked_by     uuid        references profiles(id) on delete set null,
  unlocked_at     timestamptz not null default now(),
  unique (class_id, week_start_date)
);

-- ────────────────────────────────────────────────────────────────────────────
-- TABLE: buses / bus_stops / student_transport
-- ────────────────────────────────────────────────────────────────────────────
create table if not exists buses (
  id              uuid        primary key default gen_random_uuid(),
  bus_number      text        not null unique,
  route           text,
  driver_name     text,
  driver_contact  text,
  capacity        integer     check (capacity > 0),
  created_at      timestamptz not null default now()
);

create table if not exists bus_stops (
  id          uuid        primary key default gen_random_uuid(),
  bus_id      uuid        not null references buses(id) on delete cascade,
  stop_name   text        not null,
  pickup_time time,
  drop_time   time,
  sequence    integer     not null default 0,
  created_at  timestamptz not null default now()
);

create table if not exists student_transport (
  id          uuid        primary key default gen_random_uuid(),
  student_id  uuid        not null unique references profiles(id) on delete cascade,
  bus_id      uuid        not null references buses(id) on delete cascade,
  stop_id     uuid        references bus_stops(id) on delete set null,
  created_at  timestamptz not null default now()
);

-- ────────────────────────────────────────────────────────────────────────────
-- TABLE: calendar_events
-- ────────────────────────────────────────────────────────────────────────────
create table if not exists calendar_events (
  id          uuid                 primary key default gen_random_uuid(),
  title       text                 not null,
  event_type  calendar_event_type  not null default 'event',
  event_date  date                 not null,
  end_date    date,
  description text,
  created_by  uuid                 references profiles(id) on delete set null,
  created_at  timestamptz          not null default now()
);

-- ────────────────────────────────────────────────────────────────────────────
-- TABLE: promotions (audit trail; the promotion itself just inserts new
-- class_students rows — old rows are untouched so history stays attached).
-- ────────────────────────────────────────────────────────────────────────────
create table if not exists promotions (
  id            uuid        primary key default gen_random_uuid(),
  student_id    uuid        not null references profiles(id) on delete cascade,
  from_class_id uuid        references classes(id) on delete set null,
  to_class_id   uuid        not null references classes(id) on delete cascade,
  academic_year text        not null,
  promoted_by   uuid        references profiles(id) on delete set null,
  promoted_at   timestamptz not null default now()
);

-- ────────────────────────────────────────────────────────────────────────────
-- TABLE: notification_log
-- ────────────────────────────────────────────────────────────────────────────
create table if not exists notification_log (
  id            uuid                  primary key default gen_random_uuid(),
  student_id    uuid                  references profiles(id) on delete cascade,
  trigger_type  notification_trigger  not null,
  channel       text                  not null default 'whatsapp',
  message       text                  not null,
  sent_by       uuid                  references profiles(id) on delete set null,
  sent_at       timestamptz           not null default now()
);

-- ────────────────────────────────────────────────────────────────────────────
-- TABLE: audit_log — general-purpose action trail.
-- ────────────────────────────────────────────────────────────────────────────
create table if not exists audit_log (
  id          uuid        primary key default gen_random_uuid(),
  actor_id    uuid        references profiles(id) on delete set null,
  actor_role  text,
  module      text        not null,
  action      text        not null,
  old_value   jsonb,
  new_value   jsonb,
  created_at  timestamptz not null default now()
);

create index idx_audit_log_module     on audit_log (module);
create index idx_audit_log_actor      on audit_log (actor_id);
create index idx_audit_log_created_at on audit_log (created_at);

-- ────────────────────────────────────────────────────────────────────────────
-- announcements: add category for the client's stated types.
-- ────────────────────────────────────────────────────────────────────────────
alter table announcements add column if not exists category text
  check (category in ('Holiday', 'Exam Schedule', 'Parent Meeting', 'Sports Day', 'Circular', 'General'));

-- ════════════════════════════════════════════════════════════════════════════
-- Row Level Security
-- ════════════════════════════════════════════════════════════════════════════

alter table student_details      enable row level security;
alter table non_teaching_staff   enable row level security;
alter table academic_years       enable row level security;
alter table fee_types            enable row level security;
alter table exams                enable row level security;
alter table exam_subjects        enable row level security;
alter table report_card_remarks  enable row level security;
alter table teacher_attendance   enable row level security;
alter table attendance_unlocks   enable row level security;
alter table buses                enable row level security;
alter table bus_stops            enable row level security;
alter table student_transport    enable row level security;
alter table calendar_events      enable row level security;
alter table promotions           enable row level security;
alter table notification_log     enable row level security;
alter table audit_log            enable row level security;

-- student_details ─────────────────────────────────────────────────────────
create policy "Admins manage student_details"
  on student_details for all
  using (is_admin());

create policy "Students read own details"
  on student_details for select
  using (student_id = auth.uid());

create policy "Teachers read details for their class students"
  on student_details for select
  using (
    exists (
      select 1 from class_students cs
      join class_subject_teachers cst on cst.class_id = cs.class_id
      where cs.student_id = student_details.student_id and cst.teacher_id = auth.uid()
    )
    or exists (
      select 1 from class_students cs
      join classes c on c.id = cs.class_id
      where cs.student_id = student_details.student_id and c.teacher_id = auth.uid()
    )
  );

-- non_teaching_staff ────────────────────────────────────────────────────────
create policy "Admins manage non_teaching_staff"
  on non_teaching_staff for all
  using (is_admin());

-- academic_years ────────────────────────────────────────────────────────────
create policy "Admins manage academic_years"
  on academic_years for all
  using (is_admin());

create policy "Authenticated users can read academic_years"
  on academic_years for select
  to authenticated
  using (true);

-- fee_types ─────────────────────────────────────────────────────────────────
create policy "Admins manage fee_types"
  on fee_types for all
  using (is_admin());

create policy "Authenticated users can read fee_types"
  on fee_types for select
  to authenticated
  using (true);

-- exams / exam_subjects ────────────────────────────────────────────────────
create policy "Admins manage exams"
  on exams for all
  using (is_admin());

create policy "Authenticated users can read exams"
  on exams for select
  to authenticated
  using (true);

create policy "Admins manage exam_subjects"
  on exam_subjects for all
  using (is_admin());

create policy "Teachers can read exam_subjects for their class"
  on exam_subjects for select
  using (
    exists (
      select 1 from class_subject_teachers cst
      where cst.class_id = exam_subjects.class_id and cst.teacher_id = auth.uid()
    )
    or exists (
      select 1 from classes c
      where c.id = exam_subjects.class_id and c.teacher_id = auth.uid()
    )
  );

create policy "Students can read exam_subjects for their class"
  on exam_subjects for select
  using (
    exists (
      select 1 from class_students cs
      where cs.class_id = exam_subjects.class_id and cs.student_id = auth.uid()
    )
  );

-- report_card_remarks ───────────────────────────────────────────────────────
create policy "Admins manage report_card_remarks"
  on report_card_remarks for all
  using (is_admin());

create policy "Students read own report_card_remarks"
  on report_card_remarks for select
  using (student_id = auth.uid());

create policy "Teachers manage report_card_remarks for their class students"
  on report_card_remarks for all
  using (
    exists (
      select 1 from class_students cs
      join class_subject_teachers cst on cst.class_id = cs.class_id
      where cs.student_id = report_card_remarks.student_id and cst.teacher_id = auth.uid()
    )
    or exists (
      select 1 from class_students cs
      join classes c on c.id = cs.class_id
      where cs.student_id = report_card_remarks.student_id and c.teacher_id = auth.uid()
    )
  );

-- teacher_attendance ────────────────────────────────────────────────────────
create policy "Admins manage teacher_attendance"
  on teacher_attendance for all
  using (is_admin());

create policy "Teachers read own attendance"
  on teacher_attendance for select
  using (teacher_id = auth.uid());

-- attendance_unlocks ────────────────────────────────────────────────────────
create policy "Admins manage attendance_unlocks"
  on attendance_unlocks for all
  using (is_admin());

create policy "Teachers can read unlocks for their class"
  on attendance_unlocks for select
  using (
    exists (
      select 1 from class_subject_teachers cst
      where cst.class_id = attendance_unlocks.class_id and cst.teacher_id = auth.uid()
    )
    or exists (
      select 1 from classes c
      where c.id = attendance_unlocks.class_id and c.teacher_id = auth.uid()
    )
  );

-- buses / bus_stops ─────────────────────────────────────────────────────────
create policy "Admins manage buses"
  on buses for all
  using (is_admin());

create policy "Authenticated users can read buses"
  on buses for select
  to authenticated
  using (true);

create policy "Admins manage bus_stops"
  on bus_stops for all
  using (is_admin());

create policy "Authenticated users can read bus_stops"
  on bus_stops for select
  to authenticated
  using (true);

-- student_transport ─────────────────────────────────────────────────────────
create policy "Admins manage student_transport"
  on student_transport for all
  using (is_admin());

create policy "Students read own transport"
  on student_transport for select
  using (student_id = auth.uid());

-- calendar_events ────────────────────────────────────────────────────────────
create policy "Admins manage calendar_events"
  on calendar_events for all
  using (is_admin());

create policy "Authenticated users can read calendar_events"
  on calendar_events for select
  to authenticated
  using (true);

-- promotions ────────────────────────────────────────────────────────────────
create policy "Admins manage promotions"
  on promotions for all
  using (is_admin());

create policy "Students read own promotions"
  on promotions for select
  using (student_id = auth.uid());

-- notification_log ──────────────────────────────────────────────────────────
create policy "Admins manage notification_log"
  on notification_log for all
  using (is_admin());

create policy "Staff can insert notification_log"
  on notification_log for insert
  with check (
    exists (select 1 from profiles p where p.id = auth.uid() and p.role in ('admin', 'teacher'))
  );

-- audit_log ─────────────────────────────────────────────────────────────────
create policy "Admins read audit_log"
  on audit_log for select
  using (is_admin());

create policy "Authenticated users can insert their own audit_log entries"
  on audit_log for insert
  to authenticated
  with check (actor_id = auth.uid());

-- ────────────────────────────────────────────────────────────────────────────
-- Storage: student_documents (private — admin full access, student reads
-- only their own folder, path convention <student_id>/<doc_type>.<ext>).
-- ────────────────────────────────────────────────────────────────────────────
insert into storage.buckets (id, name, public)
values ('student_documents', 'student_documents', false)
on conflict (id) do nothing;

create policy "Admins manage student_documents"
  on storage.objects for all
  using (bucket_id = 'student_documents' and is_admin());

create policy "Students can read own documents"
  on storage.objects for select
  using (
    bucket_id = 'student_documents'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
