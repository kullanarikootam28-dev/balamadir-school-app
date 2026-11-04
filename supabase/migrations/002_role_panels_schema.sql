-- ════════════════════════════════════════════════════════════════════════════
-- School Management App — Phase 3 Schema: role panels (admin/teacher/student)
-- ════════════════════════════════════════════════════════════════════════════

-- Needed so the Gradebook Input screen can upsert (re-saving the same
-- student/class/subject/exam updates the existing row instead of duplicating).
alter table grades
  add constraint grades_student_class_subject_exam_key
  unique (student_id, class_id, subject_name, exam_type);

-- ── TABLE: subjects ────────────────────────────────────────────────────────
create table if not exists subjects (
  id          uuid        primary key default uuid_generate_v4(),
  name        text        not null unique,
  created_at  timestamptz not null default now()
);

-- ── TABLE: class_subject_teachers ─────────────────────────────────────────
-- Assigns a teacher to teach a specific subject to a specific class.
create table if not exists class_subject_teachers (
  id          uuid        primary key default uuid_generate_v4(),
  class_id    uuid        not null references classes(id) on delete cascade,
  subject_id  uuid        not null references subjects(id) on delete cascade,
  teacher_id  uuid        not null references profiles(id) on delete cascade,
  created_at  timestamptz not null default now(),
  unique (class_id, subject_id)
);

-- ── TABLE: class_students ──────────────────────────────────────────────────
-- Enrollment roster — which students belong to which class, with roll number.
create table if not exists class_students (
  id           uuid        primary key default uuid_generate_v4(),
  class_id     uuid        not null references classes(id) on delete cascade,
  student_id   uuid        not null references profiles(id) on delete cascade,
  roll_number  text,
  created_at   timestamptz not null default now(),
  unique (class_id, student_id)
);

-- ── TABLE: timetable_slots ─────────────────────────────────────────────────
create table if not exists timetable_slots (
  id             uuid        primary key default uuid_generate_v4(),
  class_id       uuid        not null references classes(id) on delete cascade,
  day_of_week    smallint    not null check (day_of_week between 1 and 7), -- 1=Mon..7=Sun
  period_number  smallint    not null check (period_number > 0),
  subject_id     uuid        references subjects(id) on delete set null,
  teacher_id     uuid        references profiles(id) on delete set null,
  start_time     time        not null,
  end_time       time        not null,
  created_at     timestamptz not null default now(),
  unique (class_id, day_of_week, period_number)
);

-- ── TABLE: announcements ───────────────────────────────────────────────────
-- class_id null = school-wide broadcast; set = class-scoped noticeboard post.
create table if not exists announcements (
  id          uuid        primary key default uuid_generate_v4(),
  author_id   uuid        not null references profiles(id) on delete cascade,
  class_id    uuid        references classes(id) on delete cascade,
  title       text        not null,
  body        text        not null,
  created_at  timestamptz not null default now()
);

create index if not exists idx_announcements_class_id on announcements(class_id);

-- ── TABLE: messages ─────────────────────────────────────────────────────────
-- Direct chat between a teacher and a student's account (shared parent/student login).
create table if not exists messages (
  id            uuid        primary key default uuid_generate_v4(),
  sender_id     uuid        not null references profiles(id) on delete cascade,
  recipient_id  uuid        not null references profiles(id) on delete cascade,
  body          text        not null,
  created_at    timestamptz not null default now(),
  read_at       timestamptz
);

create index if not exists idx_messages_sender_recipient on messages(sender_id, recipient_id);
create index if not exists idx_messages_recipient_sender on messages(recipient_id, sender_id);

-- ════════════════════════════════════════════════════════════════════════════
-- Row Level Security
-- ════════════════════════════════════════════════════════════════════════════

alter table subjects enable row level security;
alter table class_subject_teachers enable row level security;
alter table class_students enable row level security;
alter table timetable_slots enable row level security;
alter table announcements enable row level security;
alter table messages enable row level security;

-- Helper predicate used inline below: is the current user an admin?
-- (kept inline per-policy to match the style already used in 001_initial_schema.sql)

-- subjects ─────────────────────────────────────────────────────────────────
create policy "Authenticated users can read subjects"
  on subjects for select
  to authenticated
  using (true);

create policy "Admins manage subjects"
  on subjects for all
  using (
    exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'admin')
  );

-- class_subject_teachers ────────────────────────────────────────────────────
create policy "Admins manage class_subject_teachers"
  on class_subject_teachers for all
  using (
    exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'admin')
  );

create policy "Teachers can read their own assignments"
  on class_subject_teachers for select
  using (teacher_id = auth.uid());

create policy "Students can read assignments for their class"
  on class_subject_teachers for select
  using (
    exists (
      select 1 from class_students cs
      where cs.class_id = class_subject_teachers.class_id
        and cs.student_id = auth.uid()
    )
  );

-- class_students ────────────────────────────────────────────────────────────
create policy "Admins manage class_students"
  on class_students for all
  using (
    exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'admin')
  );

create policy "Students can read their own enrollment"
  on class_students for select
  using (student_id = auth.uid());

create policy "Teachers can read roster for their classes"
  on class_students for select
  using (
    exists (
      select 1 from class_subject_teachers cst
      where cst.class_id = class_students.class_id
        and cst.teacher_id = auth.uid()
    )
    or exists (
      select 1 from classes c
      where c.id = class_students.class_id
        and c.teacher_id = auth.uid()
    )
  );

-- timetable_slots ────────────────────────────────────────────────────────────
create policy "Admins manage timetable_slots"
  on timetable_slots for all
  using (
    exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'admin')
  );

create policy "Teachers can read their own timetable"
  on timetable_slots for select
  using (teacher_id = auth.uid());

create policy "Students can read their class timetable"
  on timetable_slots for select
  using (
    exists (
      select 1 from class_students cs
      where cs.class_id = timetable_slots.class_id
        and cs.student_id = auth.uid()
    )
  );

-- announcements ───────────────────────────────────────────────────────────────
create policy "Admins manage announcements"
  on announcements for all
  using (
    exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'admin')
  );

create policy "Everyone can read global announcements"
  on announcements for select
  using (class_id is null);

create policy "Students can read announcements for their class"
  on announcements for select
  using (
    exists (
      select 1 from class_students cs
      where cs.class_id = announcements.class_id
        and cs.student_id = auth.uid()
    )
  );

create policy "Teachers can read and post to their class noticeboard"
  on announcements for select
  using (
    exists (
      select 1 from class_subject_teachers cst
      where cst.class_id = announcements.class_id
        and cst.teacher_id = auth.uid()
    )
    or exists (
      select 1 from classes c
      where c.id = announcements.class_id
        and c.teacher_id = auth.uid()
    )
  );

create policy "Teachers can insert announcements for their class"
  on announcements for insert
  with check (
    author_id = auth.uid()
    and (
      exists (
        select 1 from class_subject_teachers cst
        where cst.class_id = announcements.class_id
          and cst.teacher_id = auth.uid()
      )
      or exists (
        select 1 from classes c
        where c.id = announcements.class_id
          and c.teacher_id = auth.uid()
      )
    )
  );

-- messages ────────────────────────────────────────────────────────────────────
create policy "Users can read their own conversations"
  on messages for select
  using (sender_id = auth.uid() or recipient_id = auth.uid());

create policy "Users can send messages as themselves"
  on messages for insert
  with check (sender_id = auth.uid());

create policy "Recipients can mark messages read"
  on messages for update
  using (recipient_id = auth.uid())
  with check (recipient_id = auth.uid());

-- ════════════════════════════════════════════════════════════════════════════
-- Fixes for RLS gaps found in 001_initial_schema.sql
-- ════════════════════════════════════════════════════════════════════════════

-- profiles: allow a newly-registered user to insert their own row
-- (needed by the admin "register account" flow, which signs the new user up
-- via a throwaway client and then inserts their own profile row).
create policy "Users can insert their own profile"
  on profiles for insert
  with check (auth.uid() = id);

-- attendance: admins previously had no read/write access at all.
create policy "Admins manage all attendance"
  on attendance for all
  using (
    exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'admin')
  );

-- grades: no one but admins could ever write grades under RLS as originally written.
create policy "Teachers can insert grades for their class"
  on grades for insert
  with check (
    exists (
      select 1 from class_subject_teachers cst
      where cst.class_id = grades.class_id
        and cst.teacher_id = auth.uid()
    )
    or exists (
      select 1 from classes c
      where c.id = grades.class_id
        and c.teacher_id = auth.uid()
    )
  );

create policy "Teachers can update grades for their class"
  on grades for update
  using (
    exists (
      select 1 from class_subject_teachers cst
      where cst.class_id = grades.class_id
        and cst.teacher_id = auth.uid()
    )
    or exists (
      select 1 from classes c
      where c.id = grades.class_id
        and c.teacher_id = auth.uid()
    )
  );

create policy "Admins manage all grades"
  on grades for all
  using (
    exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'admin')
  );
