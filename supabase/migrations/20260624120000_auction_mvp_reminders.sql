alter table public.publication_items
  add column if not exists reminder_meta_comment_id text,
  add column if not exists reminder_sent_at timestamptz,
  add column if not exists reminder_count integer not null default 0,
  add column if not exists reminder_last_error text;

alter table public.publication_items
  add constraint publication_items_reminder_count_check
  check (reminder_count >= 0) not valid;

alter table public.winner_notification_batches
  add column if not exists commenter_id text,
  add column if not exists confirmation_code text,
  add column if not exists messenger_psid text;

create index if not exists publication_items_reminder_sent_at_idx
  on public.publication_items (publication_id, reminder_sent_at);

create index if not exists winner_notification_batches_confirmation_code_idx
  on public.winner_notification_batches (confirmation_code)
  where confirmation_code is not null;

alter table public.message_templates
  drop constraint if exists message_templates_kind_check;

alter table public.message_templates
  add constraint message_templates_kind_check
  check (kind = any (array[
    'auction_reminder',
    'auction_reminder_no_bids',
    'winner_linked',
    'winner_unlinked',
    'winner_window_closed',
    'winner_order_summary',
    'order_confirmation',
    'delivery_reminder',
    'arrival_notice',
    'payment_confirmation'
  ]::text[]));

insert into public.message_templates (owner_id, kind, body)
select p.owner_id, template.kind, template.body
from (
  select distinct owner_id from public.facebook_pages
) p
cross join (
  values
    ('auction_reminder', 'Recordatorio: esta subasta termina a las {horaCierre}. Puja actual: {pujaActual}.'),
    ('auction_reminder_no_bids', 'Recordatorio: esta subasta termina a las {horaCierre}. Aún sin pujas.'),
    ('winner_linked', 'Ganaste esta subasta. Te envié los detalles por inbox.'),
    ('winner_unlinked', 'Ganaste esta subasta. Mándanos inbox con el código {codigoConfirmacion} para confirmar tu pedido.'),
    ('winner_window_closed', 'Ganaste esta subasta. Mándanos un nuevo inbox con el código {codigoConfirmacion} para enviarte los detalles.'),
    ('winner_order_summary', 'Tu pedido de esta subasta: {cantidad} artículo(s), total {total}.')
) as template(kind, body)
on conflict (owner_id, kind) do nothing;
