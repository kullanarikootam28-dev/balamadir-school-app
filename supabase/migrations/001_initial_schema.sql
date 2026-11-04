-- ════════════════════════════════════════════════════════════════════════════
-- School Management App — Phase 2 PostgreSQL Schema Migration
-- Run this in: Supabase Dashboard → SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════════════════

-- ── Extensions ───────────────────────────────────────────────────────────────
create extension if not exists "uuid-ossp";
create extension if not exists pgcrypto;

-- ── Enums ─────────────────────────────────────────────────────────────────────
create type user_role         as enum ('student', 'teacher', 'admin');
create type attendance_status as enum ('present', 'absent', 'late', 'excused');
create type payment_status    as enum ('pending', 'paid', 'overdue', 'waived');

-- ────────────────────────────────────────────────────────────────────────────
-- TABLE: profiles
-- Linked to Supabase Auth UUIDs via id = auth.users.id (FK enforced).
-- ────────────────────────────────────────────────────────────────────────────
create table if not exists profiles (
  id          uuid         primary key references auth.users(id) on delete cascade,
  full_name   text         not null,
  email       text         not null unique,
  role        user_role    not null default 'student',
  avatar_url  text,
  phone       text,
  created_at  timestamptz  not null default now(),
  updated_at  timestamptz  not null default now()
);

-- Auto-sync updated_at
create or replace function update_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger trg_profiles_updated_at
  before update on profiles
  for each row execute function update_updated_at();

-- ────────────────────────────────────────────────────────────────────────────
-- TABLE: classes
-- Grade/section identification. teacher_id links to a 'teacher' profile.
-- ────────────────────────────────────────────────────────────────────────────
create table if not exists classes (
  id            uuid        primary key default uuid_generate_v4(),
  grade         text        not null,          -- e.g. '10'
  section       text        not null,          -- e.g. 'A'
  teacher_id    uuid        references profiles(id) on delete set null,
  academic_year text        not null default to_char(now(), 'YYYY'),
  created_at    timestamptz not null default now(),
  unique (grade, section, academic_year)
);

-- ────────────────────────────────────────────────────────────────────────────
-- TABLE: attendance
-- Daily per-student log, marked by the assigned teacher.
-- ────────────────────────────────────────────────────────────────────────────
create table if not exists attendance (
  id                    uuid              primary key default uuid_generate_v4(),
  student_id            uuid              not null references profiles(id) on delete cascade,
  class_id              uuid              not null references classes(id)  on delete cascade,
  date                  date              not null default current_date,
  status                attendance_status not null default 'present',
  marked_by_teacher_id  uuid              references profiles(id) on delete set null,
  remarks               text,
  created_at            timestamptz       not null default now(),
  unique (student_id, class_id, date)     -- one record per student per day
);

create index idx_attendance_date      on attendance (date);
create index idx_attendance_student   on attendance (student_id);
create index idx_attendance_class     on attendance (class_id);

-- ────────────────────────────────────────────────────────────────────────────
-- TABLE: grades
-- Relational ledger: student × class × subject × score.
-- ────────────────────────────────────────────────────────────────────────────
create table if not exists grades (
  id            uuid        primary key default uuid_generate_v4(),
  student_id    uuid        not null references profiles(id) on delete cascade,
  class_id      uuid        not null references classes(id)  on delete cascade,
  subject_name  text        not null,
  score         numeric(6,2) not null check (score >= 0),
  max_score     numeric(6,2) not null check (max_score > 0),
  exam_type     text,                          -- 'Midterm' | 'Final' | 'Quiz'
  graded_at     timestamptz not null default now(),
  created_at    timestamptz not null default now(),
  constraint    chk_score_range check (score <= max_score)
);

create index idx_grades_student  on grades (student_id);
create index idx_grades_class    on grades (class_id);
create index idx_grades_subject  on grades (subject_name);

-- ────────────────────────────────────────────────────────────────────────────
-- TABLE: fee_payments
-- Transactional log: Invoice → Student → Amount (₹100 scale = paise) → Status.
-- ────────────────────────────────────────────────────────────────────────────
create table if not exists fee_payments (
  id              uuid           primary key default uuid_generate_v4(),
  invoice_id      text           not null unique,   -- human-readable INV-YYYY-NNNN
  student_id      uuid           not null references profiles(id) on delete cascade,
  amount_paise    integer        not null check (amount_paise > 0),
  -- amount_paise uses ₹100 scale:
  --   ₹1       = 100 paise
  --   ₹500     = 50000 paise
  --   ₹10,000  = 1000000 paise
  status          payment_status not null default 'pending',
  due_date        date,
  paid_at         timestamptz,
  description     text,
  transaction_ref text,
  created_at      timestamptz    not null default now(),
  updated_at      timestamptz    not null default now()
);

create trigger trg_fee_payments_updated_at
  before update on fee_payments
  for each row execute function update_updated_at();

create index idx_fee_payments_student on fee_payments (student_id);
create index idx_fee_payments_status  on fee_payments (status);
create index idx_fee_payments_due     on fee_payments (due_date);

-- ────────────────────────────────────────────────────────────────────────────
-- ROW LEVEL SECURITY (RLS)
-- ────────────────────────────────────────────────────────────────────────────

-- profiles ─────────────────────────────────────────────────────────────────
alter table profiles enable row level security;

create policy "Users can read their own profile"
  on profiles for select
  using (auth.uid() = id);

create policy "Admins can read all profiles"
  on profiles for select
  using (
    exists (
      select 1 from profiles p
      where p.id = auth.uid() and p.role = 'admin'
    )
  );

create policy "Users can update their own profile"
  on profiles for update
  using (auth.uid() = id);

-- attendance ────────────────────────────────────────────────────────────────
alter table attendance enable row level security;

create policy "Students see own attendance"
  on attendance for select
  using (student_id = auth.uid());

create policy "Teachers see class attendance"
  on attendance for select
  using (
    exists (
      select 1 from classes c
      where c.id = attendance.class_id and c.teacher_id = auth.uid()
    )
  );

create policy "Teachers can insert attendance"
  on attendance for insert
  with check (marked_by_teacher_id = auth.uid());

create policy "Teachers can update attendance"
  on attendance for update
  using (marked_by_teacher_id = auth.uid());

-- grades ────────────────────────────────────────────────────────────────────
alter table grades enable row level security;

create policy "Students see own grades"
  on grades for select
  using (student_id = auth.uid());

create policy "Teachers see all grades for their class"
  on grades for select
  using (
    exists (
      select 1 from classes c
      where c.id = grades.class_id and c.teacher_id = auth.uid()
    )
  );

-- fee_payments ──────────────────────────────────────────────────────────────
alter table fee_payments enable row level security;

create policy "Students see own fee payments"
  on fee_payments for select
  using (student_id = auth.uid());

create policy "Admins manage all fee payments"
  on fee_payments for all
  using (
    exists (
      select 1 from profiles p
      where p.id = auth.uid() and p.role = 'admin'
    )
  );

-- ── Done ─────────────────────────────────────────────────────────────────────
-- Next: paste your Supabase project URL + anon key into
-- lib/config/supabase_config.dart and run `flutter pub get`.
