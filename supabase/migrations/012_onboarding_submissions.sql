-- ════════════════════════════════════════════════════════════════════════════
-- Public onboarding forms (no login — teachers/staff/transport coordinators
-- fill these from a shared link, same trust model as
-- parent_contact_submissions in 011): submissions land in staging tables the
-- admin reviews, plus two small real gaps in the schema (module 3 of the
-- client spec calls for teacher "Status & Remarks", which nothing modeled
-- until now).
-- ════════════════════════════════════════════════════════════════════════════

-- ── TABLE: teacher_details (real gap-fill, mirrors student_details/
-- non_teaching_staff's shape) ────────────────────────────────────────────────
create table if not exists teacher_details (
  teacher_id       uuid        primary key references profiles(id) on delete cascade,
  qualification    text,
  specialization   text,
  experience_years integer     check (experience_years >= 0),
  joining_date     date,
  status           text        not null default 'active'
                     check (status in ('active', 'on_leave', 'resigned')),
  remarks          text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create trigger trg_teacher_details_updated_at
  before update on teacher_details
  for each row execute function update_updated_at();

alter table teacher_details enable row level security;

create policy "Admins manage teacher_details"
  on teacher_details for all
  using (is_admin());

create policy "Teachers read and update own details"
  on teacher_details for select
  using (teacher_id = auth.uid());

create policy "Teachers can upsert their own details"
  on teacher_details for insert
  with check (teacher_id = auth.uid());

create policy "Teachers can edit their own details"
  on teacher_details for update
  using (teacher_id = auth.uid());

-- ── TABLE: teacher_detail_submissions (public form staging) ─────────────────
create table if not exists teacher_detail_submissions (
  id               uuid        primary key default gen_random_uuid(),
  teacher_id       uuid        not null references profiles(id) on delete cascade,
  mobile_number    text,
  qualification    text,
  specialization   text,
  experience_years integer,
  joining_date     date,
  remarks          text,
  submitted_at     timestamptz not null default now()
);

create index idx_teacher_detail_submissions_teacher on teacher_detail_submissions (teacher_id);

alter table teacher_detail_submissions enable row level security;

create policy "Anyone can submit teacher details"
  on teacher_detail_submissions for insert
  to anon, authenticated
  with check (true);

create policy "Admins can view teacher detail submissions"
  on teacher_detail_submissions for select
  using (is_admin());

-- ── TABLE: staff_detail_submissions (public form staging) ───────────────────
create table if not exists staff_detail_submissions (
  id             uuid        primary key default gen_random_uuid(),
  staff_id       uuid        not null references non_teaching_staff(id) on delete cascade,
  mobile_number  text,
  remarks        text,
  submitted_at   timestamptz not null default now()
);

create index idx_staff_detail_submissions_staff on staff_detail_submissions (staff_id);

alter table staff_detail_submissions enable row level security;

create policy "Anyone can submit staff details"
  on staff_detail_submissions for insert
  to anon, authenticated
  with check (true);

create policy "Admins can view staff detail submissions"
  on staff_detail_submissions for select
  using (is_admin());

-- ── TABLE: bus_detail_submissions (public form staging — new-bus
-- registration by a transport coordinator, no existing directory to pick
-- from) ──────────────────────────────────────────────────────────────────────
create table if not exists bus_detail_submissions (
  id              uuid        primary key default gen_random_uuid(),
  bus_number      text        not null,
  route           text,
  driver_name     text,
  driver_contact  text,
  capacity        integer,
  notes           text,
  submitted_at    timestamptz not null default now()
);

alter table bus_detail_submissions enable row level security;

create policy "Anyone can submit bus details"
  on bus_detail_submissions for insert
  to anon, authenticated
  with check (true);

create policy "Admins can view bus detail submissions"
  on bus_detail_submissions for select
  using (is_admin());
