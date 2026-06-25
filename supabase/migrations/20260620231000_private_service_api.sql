create or replace function public.service_store_user_credential(target_user_id uuid, encrypted_token text, token_iv text)
returns void language sql security definer set search_path = ''
as $$
  insert into private.meta_credentials(user_id, encrypted_user_token, encryption_iv, updated_at)
  values (target_user_id, encrypted_token, token_iv, now())
  on conflict (user_id) do update set encrypted_user_token=excluded.encrypted_user_token, encryption_iv=excluded.encryption_iv, updated_at=now();
$$;

create or replace function public.service_store_page_credential(target_page_id uuid, encrypted_token text, token_iv text)
returns void language sql security definer set search_path = ''
as $$
  insert into private.page_credentials(page_id, encrypted_page_token, encryption_iv, updated_at)
  values (target_page_id, encrypted_token, token_iv, now())
  on conflict (page_id) do update set encrypted_page_token=excluded.encrypted_page_token, encryption_iv=excluded.encryption_iv, updated_at=now();
$$;

create or replace function public.service_get_page_credential(target_page_id uuid)
returns table(encrypted_page_token text, encryption_iv text)
language sql security definer set search_path = ''
as $$ select encrypted_page_token, encryption_iv from private.page_credentials where page_id=target_page_id $$;

create or replace function public.service_get_cron_secret()
returns text language sql security definer set search_path = ''
as $$ select value from private.internal_secrets where name='cron_secret' $$;

create or replace function public.service_record_webhook_event(event_id text, target_event_type text, target_payload jsonb)
returns boolean language plpgsql security definer set search_path = ''
as $$
begin
  insert into private.webhook_events(id,event_type,payload) values(event_id,target_event_type,target_payload);
  return true;
exception when unique_violation then return false;
end;
$$;

create or replace function public.service_complete_webhook_event(event_id text, target_error text default null)
returns void language sql security definer set search_path = ''
as $$ update private.webhook_events set processed_at=case when target_error is null then now() else processed_at end,error=target_error where id=event_id $$;

revoke all on function public.handle_new_user() from public, anon, authenticated;
revoke all on function public.recalculate_order_total(uuid) from public, anon, authenticated;
revoke all on function public.sync_order_total() from public, anon, authenticated;
revoke all on function public.service_store_user_credential(uuid,text,text) from public, anon, authenticated;
revoke all on function public.service_store_page_credential(uuid,text,text) from public, anon, authenticated;
revoke all on function public.service_get_page_credential(uuid) from public, anon, authenticated;
revoke all on function public.service_get_cron_secret() from public, anon, authenticated;
revoke all on function public.service_record_webhook_event(text,text,jsonb) from public, anon, authenticated;
revoke all on function public.service_complete_webhook_event(text,text) from public, anon, authenticated;

grant execute on function public.service_store_user_credential(uuid,text,text) to service_role;
grant execute on function public.service_store_page_credential(uuid,text,text) to service_role;
grant execute on function public.service_get_page_credential(uuid) to service_role;
grant execute on function public.service_get_cron_secret() to service_role;
grant execute on function public.service_record_webhook_event(text,text,jsonb) to service_role;
grant execute on function public.service_complete_webhook_event(text,text) to service_role;

create index if not exists alerts_owner_idx on public.alerts(owner_id);
create index if not exists jobs_owner_idx on public.automation_jobs(owner_id);
create index if not exists conversations_owner_customer_idx on public.conversations(owner_id,customer_id);
create index if not exists identities_customer_idx on public.customer_meta_identities(customer_id);
create index if not exists customers_owner_page_idx on public.customers(owner_id,page_id);
create index if not exists messages_conversation_idx on public.messages(conversation_id,created_at);
create index if not exists order_items_order_idx on public.order_items(order_id);
