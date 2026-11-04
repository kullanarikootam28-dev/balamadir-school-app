-- ════════════════════════════════════════════════════════════════════════════
-- QR check-in/check-out: a teacher's 1st scan of the day records check-in
-- time, the 2nd records check-out, matching a real physical in/out routine
-- rather than a single flat "present" mark. Also tightens the QR freshness
-- window from 20s to 10s (lib/screens/admin/daily_attendance_portal_screen.dart
-- rotates the code on the same schedule).
-- ════════════════════════════════════════════════════════════════════════════

alter table teacher_attendance add column if not exists check_in_time timestamptz;
alter table teacher_attendance add column if not exists check_out_time timestamptz;

create or replace function mark_attendance_via_qr(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_gate      record;
  v_teacher   uuid := auth.uid();
  v_existing  record;
  v_now       timestamptz := now();
begin
  if v_teacher is null then
    return jsonb_build_object('success', false, 'reason', 'not_authenticated');
  end if;

  select * into v_gate from live_qr_gate where id = 'default';

  if v_gate.token is null or v_gate.token != p_token then
    insert into qr_scan_log (teacher_id, token_used, success, reason)
    values (v_teacher, p_token, false, 'invalid_code');
    return jsonb_build_object('success', false, 'reason', 'invalid_code');
  end if;

  if v_now - v_gate.generated_at > interval '10 seconds' then
    insert into qr_scan_log (teacher_id, token_used, success, reason)
    values (v_teacher, p_token, false, 'expired');
    return jsonb_build_object('success', false, 'reason', 'expired');
  end if;

  select * into v_existing from teacher_attendance
    where teacher_id = v_teacher and date = current_date;

  if v_existing.id is null or v_existing.check_in_time is null then
    insert into teacher_attendance (teacher_id, date, status, marked_by, remarks, check_in_time)
    values (v_teacher, current_date, 'present', v_teacher, 'QR self check-in', v_now)
    on conflict (teacher_id, date)
    do update set status = 'present', marked_by = v_teacher, remarks = 'QR self check-in', check_in_time = v_now;

    insert into qr_scan_log (teacher_id, token_used, success, reason)
    values (v_teacher, p_token, true, 'check_in');
    return jsonb_build_object('success', true, 'action', 'check_in', 'time', v_now);
  elsif v_existing.check_out_time is null then
    update teacher_attendance set check_out_time = v_now
      where teacher_id = v_teacher and date = current_date;

    insert into qr_scan_log (teacher_id, token_used, success, reason)
    values (v_teacher, p_token, true, 'check_out');
    return jsonb_build_object('success', true, 'action', 'check_out', 'time', v_now);
  else
    insert into qr_scan_log (teacher_id, token_used, success, reason)
    values (v_teacher, p_token, true, 'already_complete');
    return jsonb_build_object('success', true, 'action', 'already_complete');
  end if;
end;
$$;

-- ════════════════════════════════════════════════════════════════════════════
-- In-app notification center (bell icon, all roles) — low attendance alerts
-- and noticeboard posts, computed opportunistically from existing screens
-- rather than a server cron job (none exists in this schema).
-- ════════════════════════════════════════════════════════════════════════════

create table if not exists in_app_notifications (
  id          uuid        primary key default gen_random_uuid(),
  user_id     uuid        not null references profiles(id) on delete cascade,
  title       text        not null,
  body        text        not null,
  type        text        not null check (type in ('low_attendance', 'noticeboard', 'general')),
  related_id  uuid,
  read_at     timestamptz,
  created_at  timestamptz not null default now()
);

create index idx_in_app_notifications_user on in_app_notifications (user_id, created_at desc);

alter table in_app_notifications enable row level security;

create policy "Users read their own notifications"
  on in_app_notifications for select
  using (user_id = auth.uid() or is_admin());

create policy "Users mark their own notifications read"
  on in_app_notifications for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Covers: a user generating their own notification (e.g. a student's
-- low-attendance check running in their own session) and an admin's
-- school-wide broadcast fan-out (one row per profile, inserted directly by
-- the admin's client since is_admin() doesn't care whose user_id the row
-- names).
create policy "Self-insert or admin insert"
  on in_app_notifications for insert
  with check (user_id = auth.uid() or is_admin());

create policy "Admins delete/manage all notifications"
  on in_app_notifications for delete
  using (is_admin());

-- A class-noticeboard post is made by a TEACHER, but needs to notify every
-- STUDENT in that class — no plain RLS check expresses "teacher of class X
-- may insert rows naming other users' ids", so this security-definer
-- function does the fan-out itself, gated by the same is_teacher_of_class()
-- helper 004_fix_class_policy_recursion.sql already uses for announcements.
create or replace function notify_class_students(
  p_class_id uuid,
  p_title text,
  p_body text,
  p_related_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (is_teacher_of_class(p_class_id) or is_admin()) then
    raise exception 'Not authorized to notify this class';
  end if;

  insert into in_app_notifications (user_id, title, body, type, related_id)
  select student_id, p_title, p_body, 'noticeboard', p_related_id
  from class_students
  where class_id = p_class_id;
end;
$$;

grant execute on function notify_class_students(uuid, text, text, uuid) to authenticated;
