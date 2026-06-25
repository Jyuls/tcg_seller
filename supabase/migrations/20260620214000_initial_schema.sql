create extension if not exists pgcrypto;
create extension if not exists pg_cron;
create extension if not exists pg_net;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create type public.publication_status as enum ('draft', 'scheduled', 'publishing', 'active', 'ended', 'review', 'failed', 'archived');
create type public.payment_status as enum ('pending', 'paid');
create type public.delivery_status as enum ('pending', 'delivered', 'cancelled');
create type public.customer_category as enum ('unclassified', 'collector', 'player', 'both');
create type public.job_status as enum ('pending', 'running', 'completed', 'failed');
create type public.alert_severity as enum ('info', 'warning', 'error');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.meta_connections (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  meta_user_id text,
  connected_at timestamptz not null default now(),
  token_expires_at timestamptz,
  status text not null default 'connected' check (status in ('connected', 'expired', 'revoked', 'error')),
  last_error text,
  updated_at timestamptz not null default now()
);

create table private.meta_credentials (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  encrypted_user_token text not null,
  encryption_iv text not null,
  updated_at timestamptz not null default now()
);

create table public.facebook_pages (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  meta_page_id text not null,
  name text not null,
  picture_url text,
  category text,
  is_selected boolean not null default false,
  access_status text not null default 'active' check (access_status in ('active', 'expired', 'revoked', 'error')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(owner_id, meta_page_id)
);

create table private.page_credentials (
  page_id uuid primary key references public.facebook_pages(id) on delete cascade,
  encrypted_page_token text not null,
  encryption_iv text not null,
  updated_at timestamptz not null default now()
);

create table public.app_settings (
  owner_id uuid primary key references public.profiles(id) on delete cascade,
  timezone text not null default 'America/Tijuana',
  theme_mode text not null default 'dark' check (theme_mode in ('dark', 'light', 'system')),
  default_starting_bid integer not null default 5 check (default_starting_bid >= 0),
  default_bid_increment integer not null default 5 check (default_bid_increment > 0),
  default_duration_minutes integer not null default 1440 check (default_duration_minutes > 0),
  image_top_text text not null default 'SUBASTA',
  image_bottom_line_1 text not null default 'PUJA MÍNIMA',
  image_bottom_line_2 text not null default '$5 PESOS',
  updated_at timestamptz not null default now()
);

create table public.delivery_locations (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  requires_booth boolean not null default false,
  booth_max integer not null default 900 check (booth_max > 0),
  position integer not null default 0,
  is_active boolean not null default true,
  unique(owner_id, name)
);

create table public.publication_templates (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  body text not null,
  is_default boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(owner_id, name)
);

create table public.message_templates (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null check (kind in ('winner_linked', 'winner_unlinked', 'order_confirmation', 'delivery_reminder', 'arrival_notice', 'payment_confirmation')),
  body text not null,
  updated_at timestamptz not null default now(),
  unique(owner_id, kind)
);

create table public.publications (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  page_id uuid not null references public.facebook_pages(id) on delete cascade,
  template_id uuid references public.publication_templates(id) on delete set null,
  title text not null default 'Subasta',
  body text not null,
  status public.publication_status not null default 'draft',
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  scheduled_for timestamptz,
  published_at timestamptz,
  starting_bid integer not null check (starting_bid >= 0),
  bid_increment integer not null check (bid_increment > 0),
  meta_post_id text,
  meta_album_id text,
  cover_storage_path text,
  archived_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at > starts_at)
);

create index publications_due_idx on public.publications(status, scheduled_for, ends_at);
create index publications_page_idx on public.publications(page_id, created_at desc);

create table public.publication_items (
  id uuid primary key default gen_random_uuid(),
  publication_id uuid not null references public.publications(id) on delete cascade,
  position integer not null check (position >= 0),
  storage_path text not null,
  meta_photo_id text,
  upload_status text not null default 'pending' check (upload_status in ('pending', 'uploaded', 'failed')),
  winning_comment_id uuid,
  winning_amount integer,
  confirmation_code text,
  resolution_status text not null default 'open' check (resolution_status in ('open', 'winner', 'no_bids', 'review')),
  created_at timestamptz not null default now(),
  unique(publication_id, position)
);

create table public.meta_comments (
  id uuid primary key default gen_random_uuid(),
  publication_item_id uuid not null references public.publication_items(id) on delete cascade,
  meta_comment_id text not null unique,
  author_meta_id text,
  author_name text,
  message text not null,
  meta_created_at timestamptz not null,
  received_at timestamptz not null default now(),
  is_deleted boolean not null default false,
  raw_payload jsonb not null default '{}'::jsonb
);

create index meta_comments_item_time_idx on public.meta_comments(publication_item_id, meta_created_at);

create table public.bids (
  id uuid primary key default gen_random_uuid(),
  comment_id uuid not null unique references public.meta_comments(id) on delete cascade,
  publication_item_id uuid not null references public.publication_items(id) on delete cascade,
  amount integer not null check (amount >= 0),
  meta_created_at timestamptz not null,
  is_valid boolean not null,
  rejection_reason text,
  created_at timestamptz not null default now()
);

create index bids_winner_idx on public.bids(publication_item_id, is_valid, amount desc, meta_created_at asc);

alter table public.publication_items
  add constraint publication_items_winning_comment_fk
  foreign key (winning_comment_id) references public.meta_comments(id) on delete set null;

create table public.customers (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  page_id uuid not null references public.facebook_pages(id) on delete cascade,
  display_name text not null,
  picture_url text,
  category public.customer_category not null default 'unclassified',
  notes text not null default '',
  is_provisional boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.customer_meta_identities (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers(id) on delete cascade,
  page_id uuid not null references public.facebook_pages(id) on delete cascade,
  commenter_id text,
  messenger_psid text,
  confirmation_code text unique,
  messenger_eligible_until timestamptz,
  created_at timestamptz not null default now(),
  unique(page_id, commenter_id),
  unique(page_id, messenger_psid)
);

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  page_id uuid not null references public.facebook_pages(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete restrict,
  payment_status public.payment_status not null default 'pending',
  delivery_status public.delivery_status not null default 'pending',
  delivery_location_id uuid references public.delivery_locations(id) on delete set null,
  delivery_zone integer check (delivery_zone between 1 and 3),
  booth_number integer check (booth_number between 1 and 900),
  delivery_notes text not null default '',
  total integer not null default 0 check (total >= 0),
  paid_at timestamptz,
  delivered_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index orders_active_idx on public.orders(owner_id, delivery_status, payment_status, created_at desc);

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  publication_item_id uuid references public.publication_items(id) on delete restrict,
  photo_storage_path text not null,
  source_label text not null,
  price integer not null check (price >= 0),
  created_at timestamptz not null default now(),
  unique(publication_item_id)
);

create table public.conversations (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  page_id uuid not null references public.facebook_pages(id) on delete cascade,
  customer_id uuid references public.customers(id) on delete set null,
  messenger_psid text not null,
  last_message_at timestamptz,
  unread_count integer not null default 0,
  can_message_until timestamptz,
  unique(page_id, messenger_psid)
);

create table public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  meta_message_id text unique,
  direction text not null check (direction in ('incoming', 'outgoing')),
  body text,
  attachment_storage_path text,
  status text not null default 'received' check (status in ('queued', 'sent', 'delivered', 'failed', 'received')),
  meta_created_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.alerts (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  severity public.alert_severity not null default 'info',
  kind text not null,
  title text not null,
  body text not null,
  entity_type text,
  entity_id uuid,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.automation_jobs (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null,
  entity_id uuid,
  run_at timestamptz not null,
  status public.job_status not null default 'pending',
  attempts integer not null default 0,
  idempotency_key text not null unique,
  last_error text,
  locked_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now()
);

create index automation_jobs_due_idx on public.automation_jobs(status, run_at);

create table private.webhook_events (
  id text primary key,
  event_type text not null,
  payload jsonb not null,
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  error text
);

create or replace function public.parse_bid_amount(value text)
returns integer
language plpgsql
immutable
set search_path = ''
as $$
declare matched text[];
begin
  matched := regexp_match(value, '^\s*\$?\s*([0-9]+)\s*$');
  if matched is null then return null; end if;
  return matched[1]::integer;
exception when numeric_value_out_of_range then
  return null;
end;
$$;

create or replace function public.is_bid_before_close(comment_time timestamptz, close_time timestamptz)
returns boolean language sql immutable set search_path = ''
as $$ select comment_time < close_time $$;

create or replace function public.recalculate_order_total(target_order_id uuid)
returns void language sql security definer set search_path = ''
as $$
  update public.orders o
  set total = coalesce((select sum(oi.price) from public.order_items oi where oi.order_id = target_order_id), 0), updated_at = now()
  where o.id = target_order_id;
$$;

create or replace function public.sync_order_total()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  perform public.recalculate_order_total(coalesce(new.order_id, old.order_id));
  return coalesce(new, old);
end;
$$;

create trigger order_items_total_after_change
after insert or update or delete on public.order_items
for each row execute function public.sync_order_total();

create or replace function public.mark_order_delivered(target_order_id uuid)
returns public.orders language plpgsql security invoker set search_path = ''
as $$
declare result public.orders;
begin
  update public.orders
  set delivery_status = 'delivered', payment_status = 'paid', delivered_at = now(), paid_at = coalesce(paid_at, now()), updated_at = now()
  where id = target_order_id and owner_id = auth.uid()
  returning * into result;
  return result;
end;
$$;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.profiles(id, display_name, avatar_url)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name'), new.raw_user_meta_data ->> 'avatar_url')
  on conflict (id) do nothing;
  insert into public.app_settings(owner_id) values (new.id) on conflict do nothing;
  insert into public.delivery_locations(owner_id, name, position) values
    (new.id, 'Mundo Divertido', 0), (new.id, 'Game Hunters', 1), (new.id, 'Entrega a puesto', 2)
  on conflict do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created after insert on auth.users
for each row execute function public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.meta_connections enable row level security;
alter table public.facebook_pages enable row level security;
alter table public.app_settings enable row level security;
alter table public.delivery_locations enable row level security;
alter table public.publication_templates enable row level security;
alter table public.message_templates enable row level security;
alter table public.publications enable row level security;
alter table public.publication_items enable row level security;
alter table public.meta_comments enable row level security;
alter table public.bids enable row level security;
alter table public.customers enable row level security;
alter table public.customer_meta_identities enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.alerts enable row level security;
alter table public.automation_jobs enable row level security;

create policy profiles_owner on public.profiles for all using (id = auth.uid()) with check (id = auth.uid());
create policy meta_connections_owner on public.meta_connections for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy facebook_pages_owner on public.facebook_pages for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy app_settings_owner on public.app_settings for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy delivery_locations_owner on public.delivery_locations for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy publication_templates_owner on public.publication_templates for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy message_templates_owner on public.message_templates for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy publications_owner on public.publications for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy publication_items_owner on public.publication_items for all
  using (exists(select 1 from public.publications p where p.id = publication_id and p.owner_id = auth.uid()))
  with check (exists(select 1 from public.publications p where p.id = publication_id and p.owner_id = auth.uid()));
create policy meta_comments_owner on public.meta_comments for select
  using (exists(select 1 from public.publication_items i join public.publications p on p.id=i.publication_id where i.id=publication_item_id and p.owner_id=auth.uid()));
create policy bids_owner on public.bids for select
  using (exists(select 1 from public.publication_items i join public.publications p on p.id=i.publication_id where i.id=publication_item_id and p.owner_id=auth.uid()));
create policy customers_owner on public.customers for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy customer_identities_owner on public.customer_meta_identities for all
  using (exists(select 1 from public.customers c where c.id=customer_id and c.owner_id=auth.uid()))
  with check (exists(select 1 from public.customers c where c.id=customer_id and c.owner_id=auth.uid()));
create policy orders_owner on public.orders for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy order_items_owner on public.order_items for all
  using (exists(select 1 from public.orders o where o.id=order_id and o.owner_id=auth.uid()))
  with check (exists(select 1 from public.orders o where o.id=order_id and o.owner_id=auth.uid()));
create policy conversations_owner on public.conversations for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy messages_owner on public.messages for all
  using (exists(select 1 from public.conversations c where c.id=conversation_id and c.owner_id=auth.uid()))
  with check (exists(select 1 from public.conversations c where c.id=conversation_id and c.owner_id=auth.uid()));
create policy alerts_owner on public.alerts for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy automation_jobs_owner_select on public.automation_jobs for select using (owner_id = auth.uid());

insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values
  ('auction-media', 'auction-media', false, 15728640, array['image/jpeg','image/png','image/webp']),
  ('message-attachments', 'message-attachments', false, 15728640, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

create policy auction_media_owner on storage.objects for all to authenticated
using (bucket_id='auction-media' and (storage.foldername(name))[1]=auth.uid()::text)
with check (bucket_id='auction-media' and (storage.foldername(name))[1]=auth.uid()::text);
create policy message_attachments_owner on storage.objects for all to authenticated
using (bucket_id='message-attachments' and (storage.foldername(name))[1]=auth.uid()::text)
with check (bucket_id='message-attachments' and (storage.foldername(name))[1]=auth.uid()::text);

grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on function public.parse_bid_amount(text) to authenticated;
grant execute on function public.is_bid_before_close(timestamptz, timestamptz) to authenticated;
grant execute on function public.mark_order_delivered(uuid) to authenticated;
