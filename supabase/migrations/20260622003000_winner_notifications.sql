alter table public.message_templates
  drop constraint if exists message_templates_kind_check;

alter table public.message_templates
  add constraint message_templates_kind_check check (
    kind in (
      'winner_linked',
      'winner_unlinked',
      'winner_window_closed',
      'order_confirmation',
      'delivery_reminder',
      'arrival_notice',
      'payment_confirmation'
    )
  );

alter table public.publication_items
  add column if not exists winner_reply_meta_id text,
  add column if not exists winner_reply_kind text,
  add column if not exists winner_replied_at timestamptz;

create table if not exists public.winner_notification_batches (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  publication_id uuid not null references public.publications(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  conversation_id uuid references public.conversations(id) on delete set null,
  order_id uuid not null references public.orders(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','sending','sent','failed','skipped')),
  item_count integer not null default 0 check (item_count >= 0),
  subtotal integer not null default 0 check (subtotal >= 0),
  summary_meta_message_id text,
  attempts integer not null default 0 check (attempts >= 0),
  last_error text,
  sent_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(publication_id, customer_id)
);

create table if not exists public.winner_notification_media (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references public.winner_notification_batches(id) on delete cascade,
  order_item_id uuid not null references public.order_items(id) on delete cascade,
  position integer not null check (position >= 0),
  status text not null default 'pending' check (status in ('pending','sending','sent','failed')),
  image_meta_message_id text,
  caption_meta_message_id text,
  attempts integer not null default 0 check (attempts >= 0),
  last_error text,
  sent_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(batch_id, order_item_id)
);

create index if not exists winner_batches_status_idx
  on public.winner_notification_batches(status, updated_at);
create index if not exists winner_media_batch_idx
  on public.winner_notification_media(batch_id, position);

alter table public.winner_notification_batches enable row level security;
alter table public.winner_notification_media enable row level security;

create policy winner_batches_owner_select
on public.winner_notification_batches for select to authenticated
using (owner_id = (select auth.uid()));

create policy winner_media_owner_select
on public.winner_notification_media for select to authenticated
using (
  exists (
    select 1 from public.winner_notification_batches batch
    where batch.id = batch_id and batch.owner_id = (select auth.uid())
  )
);

grant select on public.winner_notification_batches to authenticated;
grant select on public.winner_notification_media to authenticated;
