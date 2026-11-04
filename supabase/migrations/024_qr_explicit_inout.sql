-- ════════════════════════════════════════════════════════════════════════════
-- Client feedback (Bug3.pdf): after scanning, the teacher should be shown a
-- choice of "In" or "Out" and pick it themselves, rather than the app
-- silently deciding based on scan count (021_qr_checkin_inout.sql). Same
-- token freshness/validity checks as before; only the in/out decision
-- changes from automatic to explicit.
-- ════════════════════════════════════════════════════════════════════════════

-- Postgres treats a different parameter list as a distinct overload, not a
-- replacement — drop the old single-argument version explicitly so it
-- doesn't linger unused alongside the new one.
drop function if exists mark_attendance_via_qr(text);

create or replace function mark_attendance_via_qr(p_token text, p_action text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_gate      record;
  v_teacher   uuid := auth.uid();
  v_now       timestamptz := now();
begin
  if v_teacher is null then
    return jsonb_build_object('success', false, 'reason', 'not_authenticated');
  end if;

  if p_action not in ('check_in', 'check_out') then
    return jsonb_build_object('success', false, 'reason', 'invalid_action');
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

  if p_action = 'check_in' then
    insert into teacher_attendance (teacher_id, date, status, marked_by, remarks, check_in_time)
    values (v_teacher, current_date, 'present', v_teacher, 'QR self check-in', v_now)
    on conflict (teacher_id, date)
    do update set status = 'present', marked_by = v_teacher, remarks = 'QR self check-in', check_in_time = v_now;
  else
    insert into teacher_attendance (teacher_id, date, status, marked_by, remarks, check_out_time)
    values (v_teacher, current_date, 'present', v_teacher, 'QR self check-out', v_now)
    on conflict (teacher_id, date)
    do update set check_out_time = v_now;
  end if;

  insert into qr_scan_log (teacher_id, token_used, success, reason)
  values (v_teacher, p_token, true, p_action);

  return jsonb_build_object('success', true, 'action', p_action, 'time', v_now);
end;
$$;

grant execute on function mark_attendance_via_qr(text, text) to authenticated;
