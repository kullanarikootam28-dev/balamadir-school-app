-- Same recursion bug as 003, missed on the first pass: fee_payments' admin
-- policy (from 001_initial_schema.sql) still inlines the self-referencing
-- profiles subquery instead of using is_admin().
drop policy if exists "Admins manage all fee payments" on fee_payments;
create policy "Admins manage all fee payments"
  on fee_payments for all
  using (is_admin());
