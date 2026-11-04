-- ════════════════════════════════════════════════════════════════════════════
-- Daily QR-based teacher attendance. Admin's Flutter Web session overwrites
-- the single live_qr_gate row every 20 seconds; a teacher's scan calls
-- mark_attendance_via_qr(token), which does the actual server-side
-- verification (token match + 20s freshness) inside a security-definer
-- function the caller cannot bypass, then marks them present. Confirmed
-- decisions: multiple simultaneous scans allowed (code is not consumed on
-- first use), online-only (no offline queue), no GPS check.
-- ════════════════════════════════════════════════════════════════════════════

create table if not exists live_qr_gate (
  id            text        primary key default 'default',
  token         text,
  generated_at  timestamptz,
  generated_by  uuid        references profiles(id) on delete set null
);

insert into live_qr_gate (id) values ('default') on conflict (id) do nothing;

create table if not exists qr_scan_log (
  id           uuid        primary key default gen_random_uuid(),
  teacher_id   uuid        references profiles(id) on delete set null,
  token_used   text,
  success      boolean     not null,
  reason       text,
  scanned_at   timestamptz not null default now()
);

create index idx_qr_scan_log_teacher on qr_scan_log (teacher_id);
create index idx_qr_scan_log_scanned_at on qr_scan_log (scanned_at);

alter table live_qr_gate enable row level security;
alter table qr_scan_log  enable row level security;

create policy "Authenticated users can read the live gate"
  on live_qr_gate for select
  to authenticated
  using (true);

create policy "Admins manage the live gate"
  on live_qr_gate for all
  using (is_admin());

create policy "Admins read qr_scan_log"
  on qr_scan_log for select
  using (is_admin());

create policy "Teachers read own scan log"
  on qr_scan_log for select
  using (teacher_id = auth.uid());

-- No insert policy for qr_scan_log — only mark_attendance_via_qr (security
-- definer, below) writes to it, regardless of the caller's own grants.

create or replace function mark_attendance_via_qr(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_gate      record;
  v_teacher   uuid := auth.uid();
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

  if now() - v_gate.generated_at > interval '20 seconds' then
    insert into qr_scan_log (teacher_id, token_used, success, reason)
    values (v_teacher, p_token, false, 'expired');
    return jsonb_build_object('success', false, 'reason', 'expired');
  end if;

  insert into teacher_attendance (teacher_id, date, status, marked_by, remarks)
  values (v_teacher, current_date, 'present', v_teacher, 'QR self check-in')
  on conflict (teacher_id, date)
  do update set status = 'present', marked_by = v_teacher, remarks = 'QR self check-in';

  insert into qr_scan_log (teacher_id, token_used, success, reason)
  values (v_teacher, p_token, true, 'success');

  return jsonb_build_object('success', true);
end;
$$;

grant execute on function mark_attendance_via_qr(text) to authenticated;
