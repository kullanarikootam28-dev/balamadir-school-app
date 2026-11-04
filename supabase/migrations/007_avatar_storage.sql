-- Profile photos ("ID card" images) bucket.
-- Public read (so <Image.network> works without an auth header everywhere
-- avatars are shown), but only admins can upload/replace/delete — matches
-- the "admin manages account data" model already used for user creation.
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

create policy "Public can view avatars"
  on storage.objects for select
  using (bucket_id = 'avatars');

create policy "Admins can upload avatars"
  on storage.objects for insert
  with check (bucket_id = 'avatars' and is_admin());

create policy "Admins can update avatars"
  on storage.objects for update
  using (bucket_id = 'avatars' and is_admin());

create policy "Admins can delete avatars"
  on storage.objects for delete
  using (bucket_id = 'avatars' and is_admin());
