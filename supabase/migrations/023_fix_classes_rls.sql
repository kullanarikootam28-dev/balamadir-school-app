-- ════════════════════════════════════════════════════════════════════════════
-- Critical fix: `classes` was created in 001_initial_schema.sql without RLS
-- ever being enabled on it — confirmed via Supabase's own Advisor and a
-- direct pg_class check (relrowsecurity = false), the only one of 40 public
-- tables in this state. With RLS off, PostgREST enforces no access control
-- at all on this table: any caller with just the public anon key could
-- read AND write every class, bypassing every admin check the app's UI
-- makes. Mirrors the exact pattern already used for the equally-public
-- `subjects` reference table (002_role_panels_schema.sql /
-- 003_fix_admin_policy_recursion.sql).
-- ════════════════════════════════════════════════════════════════════════════

alter table classes enable row level security;

create policy "Authenticated users can read classes"
  on classes for select
  to authenticated
  using (true);

create policy "Admins manage classes"
  on classes for all
  using (is_admin());
