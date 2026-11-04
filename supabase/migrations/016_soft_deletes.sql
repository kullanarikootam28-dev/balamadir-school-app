-- ════════════════════════════════════════════════════════════════════════════
-- Soft delete across complaints, messages, and broadcasts (announcements).
-- Rows are hidden (deleted_at set) rather than removed, so audit_log entries
-- referencing them stay meaningful and nothing is unrecoverable by mistake.
-- ════════════════════════════════════════════════════════════════════════════

alter table complaints    add column if not exists deleted_at timestamptz;
alter table complaints    add column if not exists deleted_by uuid references profiles(id) on delete set null;

alter table messages      add column if not exists deleted_at timestamptz;
alter table messages      add column if not exists deleted_by uuid references profiles(id) on delete set null;

alter table announcements add column if not exists deleted_at timestamptz;
alter table announcements add column if not exists deleted_by uuid references profiles(id) on delete set null;

-- messages: a sender may soft-delete their own message (shown to both sides
-- as a placeholder — the confirmed "notify" behaviour for the one place a
-- single other participant actually exists).
create policy "Senders can soft-delete their own messages"
  on messages for update
  using (sender_id = auth.uid())
  with check (sender_id = auth.uid());

-- announcements: author or any admin may soft-delete a broadcast/notice.
create policy "Authors and admins can soft-delete announcements"
  on announcements for update
  using (author_id = auth.uid() or is_admin())
  with check (author_id = auth.uid() or is_admin());

-- complaints: admin-only (already the only role that can read them at all).
create policy "Admins can soft-delete complaints"
  on complaints for update
  using (is_admin())
  with check (is_admin());
