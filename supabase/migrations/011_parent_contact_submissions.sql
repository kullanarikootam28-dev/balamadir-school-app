-- ════════════════════════════════════════════════════════════════════════════
-- Public parent-facing contact-details form (mobile, email, blood group)
-- submits here via the anon key — no login, since parents don't have
-- accounts. Insert-only for the public; only admins can read submissions,
-- same pattern as the complaints table (008_complaints.sql).
-- ════════════════════════════════════════════════════════════════════════════
create table if not exists parent_contact_submissions (
  id             uuid        primary key default gen_random_uuid(),
  student_id     uuid        not null references profiles(id) on delete cascade,
  mobile_number  text        not null,
  email          text        not null,
  blood_group    text,
  submitted_at   timestamptz not null default now()
);

create index idx_parent_contact_submissions_student on parent_contact_submissions (student_id);

alter table parent_contact_submissions enable row level security;

create policy "Anyone can submit parent contact details"
  on parent_contact_submissions for insert
  to anon, authenticated
  with check (true);

create policy "Admins can view parent contact submissions"
  on parent_contact_submissions for select
  using (is_admin());
