alter table private.meta_credentials enable row level security;
alter table private.page_credentials enable row level security;
alter table private.webhook_events enable row level security;

alter table public.customers
  add column if not exists picture_storage_path text;

create or replace function public.service_get_user_credential(target_user_id uuid)
returns table(encrypted_user_token text, encryption_iv text)
language sql security definer set search_path = ''
as $$
  select encrypted_user_token, encryption_iv
  from private.meta_credentials
  where user_id = target_user_id;
$$;

create or replace function public.service_clear_meta_credentials(target_user_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  delete from private.page_credentials pc
  using public.facebook_pages fp
  where pc.page_id = fp.id and fp.owner_id = target_user_id;
  delete from private.meta_credentials where user_id = target_user_id;
end;
$$;

revoke all on function public.service_get_user_credential(uuid) from public, anon, authenticated;
revoke all on function public.service_clear_meta_credentials(uuid) from public, anon, authenticated;
grant execute on function public.service_get_user_credential(uuid) to service_role;
grant execute on function public.service_clear_meta_credentials(uuid) to service_role;

insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values ('customer-media', 'customer-media', false, 10485760, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

create policy customer_media_owner on storage.objects for all to authenticated
using (bucket_id='customer-media' and (storage.foldername(name))[1]=(select auth.uid())::text)
with check (bucket_id='customer-media' and (storage.foldername(name))[1]=(select auth.uid())::text);

create index if not exists publication_items_upload_idx
on public.publication_items(publication_id, upload_status, position);
