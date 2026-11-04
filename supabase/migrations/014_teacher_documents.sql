-- ════════════════════════════════════════════════════════════════════════════
-- Teacher Records module: address (grounded in the real contact-info sheet)
-- + document upload columns, mirroring student_documents (010) exactly.
-- ════════════════════════════════════════════════════════════════════════════

alter table teacher_details add column if not exists address text;
alter table teacher_details add column if not exists resume_url text;
alter table teacher_details add column if not exists certificate_url text;
alter table teacher_details add column if not exists id_proof_url text;

insert into storage.buckets (id, name, public)
values ('teacher_documents', 'teacher_documents', false)
on conflict (id) do nothing;

create policy "Admins manage teacher_documents"
  on storage.objects for all
  using (bucket_id = 'teacher_documents' and is_admin());

create policy "Teachers can read own documents"
  on storage.objects for select
  using (
    bucket_id = 'teacher_documents'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
