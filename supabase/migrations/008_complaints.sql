-- Anonymous complaint box: no author is recorded at all (by design — the
-- student picked "anonymous, simple list, no status workflow"), so there's
-- nothing here to link back to a submitter even for admins.
create table complaints (
  id uuid primary key default gen_random_uuid(),
  message text not null,
  created_at timestamptz not null default now()
);

alter table complaints enable row level security;

create policy "Authenticated users can submit complaints"
  on complaints for insert
  to authenticated
  with check (true);

create policy "Admins can view complaints"
  on complaints for select
  using (is_admin());
