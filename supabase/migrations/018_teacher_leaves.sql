-- ════════════════════════════════════════════════════════════════════════════
-- Teacher leave logging (Bugs1.docx: "Add and should be Update CL(1 DAY LEAVE
-- per MONTH-without any salary deduction)/LP(-₹500 from salary) for Leave for
-- teachers"). Per the client's decision, this is log-only — the ₹500 LP
-- figure is descriptive, not a computed deduction, since teacher salaries
-- aren't tracked anywhere in this schema. The one-CL-per-month rule is
-- enforced here at the database level via a partial unique index, not just
-- in the UI.
-- ════════════════════════════════════════════════════════════════════════════

create table if not exists teacher_leaves (
  id          uuid        primary key default gen_random_uuid(),
  teacher_id  uuid        not null references profiles(id) on delete cascade,
  leave_type  text        not null check (leave_type in ('CL', 'LP')),
  leave_date  date        not null,
  remarks     text,
  marked_by   uuid        references profiles(id) on delete set null,
  created_at  timestamptz not null default now()
);

create unique index if not exists teacher_leaves_one_cl_per_month
  on teacher_leaves (teacher_id, date_trunc('month', leave_date::timestamp))
  where leave_type = 'CL';

alter table teacher_leaves enable row level security;

create policy "Admins manage teacher_leaves"
  on teacher_leaves for all
  using (is_admin());

create policy "Teachers read their own leaves"
  on teacher_leaves for select
  using (teacher_id = auth.uid());
