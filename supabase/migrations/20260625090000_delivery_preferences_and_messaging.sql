alter table public.delivery_locations
  add column if not exists default_delivery_mode text not null default 'general',
  add column if not exists default_fixed_booth_name text,
  add column if not exists location_help_text text not null default '';

alter table public.delivery_locations
  drop constraint if exists delivery_locations_default_delivery_mode_check;

alter table public.delivery_locations
  add constraint delivery_locations_default_delivery_mode_check
  check (default_delivery_mode in ('general', 'fixed_booth', 'roaming'));

alter table public.customers
  add column if not exists preferred_delivery_location_id uuid references public.delivery_locations(id) on delete set null,
  add column if not exists preferred_delivery_mode text not null default 'general',
  add column if not exists preferred_fixed_booth_name text,
  add column if not exists preferred_delivery_zone integer check (preferred_delivery_zone between 1 and 3),
  add column if not exists preferred_booth_number integer check (preferred_booth_number between 1 and 900),
  add column if not exists preferred_delivery_notes text not null default '';

alter table public.customers
  drop constraint if exists customers_preferred_delivery_mode_check;

alter table public.customers
  add constraint customers_preferred_delivery_mode_check
  check (preferred_delivery_mode in ('general', 'fixed_booth', 'roaming'));

alter table public.orders
  add column if not exists delivery_mode text not null default 'general',
  add column if not exists fixed_booth_name text,
  add column if not exists location_help_text text not null default '';

alter table public.orders
  drop constraint if exists orders_delivery_mode_check;

alter table public.orders
  add constraint orders_delivery_mode_check
  check (delivery_mode in ('general', 'fixed_booth', 'roaming'));

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
    'manual_order_confirmation',
    'bulk_delivery_reminder',
    'bulk_arrival_notice',
    'delivery_reminder',
    'arrival_notice',
    'payment_confirmation'
  ]::text[]));

insert into public.delivery_locations (
  owner_id,
  name,
  requires_booth,
  booth_max,
  position,
  default_delivery_mode,
  default_fixed_booth_name,
  location_help_text
)
select distinct
  owner_id,
  'Mundo Divertido',
  false,
  900,
  1,
  'fixed_booth',
  'Tokyo Morningstore',
  'Puesto Tokyo Morningstore dentro de Mundo Divertido.'
from public.facebook_pages
on conflict (owner_id, name) do update
set
  default_delivery_mode = excluded.default_delivery_mode,
  default_fixed_booth_name = excluded.default_fixed_booth_name,
  location_help_text = case
    when public.delivery_locations.location_help_text = '' then excluded.location_help_text
    else public.delivery_locations.location_help_text
  end;

insert into public.message_templates (owner_id, kind, body)
select p.owner_id, template.kind, template.body
from (select distinct owner_id from public.facebook_pages) p
cross join (
  values
    ('manual_order_confirmation', 'Listo, te aparté este artículo por {precio}. Entrega: {detalleEntrega}. Te confirmo el domingo.'),
    ('bulk_delivery_reminder', 'Hola {cliente}, te recuerdo que este domingo te entrego tu pedido en {detalleEntrega}. Total: {total}.'),
    ('bulk_arrival_notice', 'Ya estoy en {detalleEntrega}. Voy vestido así: {descripcion}. Estaré hasta {horaLimite}.')
) as template(kind, body)
on conflict (owner_id, kind) do nothing;
