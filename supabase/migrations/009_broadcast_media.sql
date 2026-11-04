-- Optional photo/video attachment on a broadcast/notice, instead of a
-- separate Events feature — extends the existing announcements table.
alter table announcements add column if not exists media_url text;

insert into storage.buckets (id, name, public)
values ('broadcast_media', 'broadcast_media', true)
on conflict (id) do nothing;

create policy "Public can view broadcast media"
  on storage.objects for select
  using (bucket_id = 'broadcast_media');

create policy "Staff can upload broadcast media"
  on storage.objects for insert
  with check (
    bucket_id = 'broadcast_media' and
    exists (select 1 from profiles where id = auth.uid() and role in ('admin', 'teacher'))
  );
