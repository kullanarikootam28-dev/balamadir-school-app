-- ════════════════════════════════════════════════════════════════════════════
-- Expense & Maintenance Management: admin-only expense ledger + repair
-- request tracker, requested as a full new module (nothing existed for this
-- before). Mirrors patterns already used elsewhere in this schema:
-- non_teaching_staff's admin-only RLS one-liner, fee_payments' paise-based
-- amounts, 016_soft_deletes.sql's deleted_at/deleted_by, and
-- 014_teacher_documents.sql's private-bucket upload shape.
-- ════════════════════════════════════════════════════════════════════════════

-- ── TABLE: app_settings (small key/value config store) ──────────────────────
create table if not exists app_settings (
  key         text        primary key,
  value       text        not null,
  updated_at  timestamptz not null default now()
);

create trigger trg_app_settings_updated_at
  before update on app_settings
  for each row execute function update_updated_at();

alter table app_settings enable row level security;

create policy "Admins manage app_settings"
  on app_settings for all
  using (is_admin());

insert into app_settings (key, value) values
  ('expense_approval_threshold_paise', '500000')
on conflict (key) do nothing;

-- ── TABLE: expense_categories ────────────────────────────────────────────────
create table if not exists expense_categories (
  id          uuid        primary key default gen_random_uuid(),
  name        text        not null unique,
  created_at  timestamptz not null default now()
);

alter table expense_categories enable row level security;

create policy "Admins manage expense_categories"
  on expense_categories for all
  using (is_admin());

insert into expense_categories (name) values
  ('Daily'), ('Maintenance'), ('Repair'), ('Emergency'), ('Other')
on conflict (name) do nothing;

-- ── TABLE: repair_requests ───────────────────────────────────────────────────
create table if not exists repair_requests (
  id                  uuid        primary key default gen_random_uuid(),
  location            text        not null,
  category            text        not null,
  description         text        not null,
  reported_date       date        not null default current_date,
  responsible_person  text,
  estimated_cost_paise integer    check (estimated_cost_paise is null or estimated_cost_paise >= 0),
  actual_cost_paise    integer    check (actual_cost_paise is null or actual_cost_paise >= 0),
  advance_paid_paise   integer    check (advance_paid_paise is null or advance_paid_paise >= 0),
  quotation_url       text,
  bill_url            text,
  before_photo_url    text,
  after_photo_url     text,
  status              text        not null default 'reported'
                        check (status in ('reported', 'approved', 'in_progress', 'completed', 'cancelled')),
  completion_date     date,
  remarks             text,
  created_by          uuid        references profiles(id) on delete set null,
  deleted_at          timestamptz,
  deleted_by          uuid        references profiles(id) on delete set null,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create trigger trg_repair_requests_updated_at
  before update on repair_requests
  for each row execute function update_updated_at();

alter table repair_requests enable row level security;

create policy "Admins manage repair_requests"
  on repair_requests for all
  using (is_admin());

-- ── TABLE: expenses ───────────────────────────────────────────────────────────
create table if not exists expenses (
  id            uuid        primary key default gen_random_uuid(),
  category_id   uuid        references expense_categories(id) on delete set null,
  description   text        not null,
  amount_paise  integer     not null check (amount_paise > 0),
  expense_date  date        not null default current_date,
  vendor_name   text,
  payment_mode  text        not null check (payment_mode in ('Cash', 'UPI', 'Bank', 'Cheque')),
  bill_number   text,
  receipt_url   text,
  remarks       text,
  status        text        not null default 'pending'
                  check (status in ('pending', 'approved', 'paid')),
  repair_id     uuid        references repair_requests(id) on delete set null,
  created_by    uuid        references profiles(id) on delete set null,
  approved_by   uuid        references profiles(id) on delete set null,
  approved_at   timestamptz,
  deleted_at    timestamptz,
  deleted_by    uuid        references profiles(id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create trigger trg_expenses_updated_at
  before update on expenses
  for each row execute function update_updated_at();

-- Prevents entering the same bill twice, per the "prevent duplicate bills"
-- control. Partial: only applies to real bill numbers on live (non-deleted)
-- rows, since a cancelled expense's bill number shouldn't block a re-entry.
create unique index if not exists expenses_bill_number_unique
  on expenses (bill_number)
  where bill_number is not null and deleted_at is null;

alter table expenses enable row level security;

create policy "Admins manage expenses"
  on expenses for all
  using (is_admin());

-- ── Storage: expense_documents (receipts, quotations, before/after photos) ──
insert into storage.buckets (id, name, public)
values ('expense_documents', 'expense_documents', false)
on conflict (id) do nothing;

create policy "Admins manage expense_documents"
  on storage.objects for all
  using (bucket_id = 'expense_documents' and is_admin());
