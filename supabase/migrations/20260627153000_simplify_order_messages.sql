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
    'manual_order_confirmation',
    'bulk_delivery_reminder',
    'bulk_arrival_notice',
    'order_delivered'
  ]::text[]));

update public.delivery_locations
set
  default_delivery_mode = 'fixed_booth',
  default_fixed_booth_name = 'Tokyo Morningstore',
  location_help_text = 'Este puesto NO TIENE NUMERO, se encuentra enfrente del puesto #138, Zona 1. Al entrar también puedes preguntar por mí.',
  requires_booth = false,
  position = 1
where name = 'Mundo Divertido';

update public.message_templates
set body = case kind
  when 'manual_order_confirmation' then 'Confirmo tu pedido para este Domingo en Mundo Divertido, el total serian {precio}.'
  when 'bulk_delivery_reminder' then 'Hola {cliente}, te recuerdo que este domingo te entrego tu pedido en Mundo Divertido, en el puesto Tokyo Morningstore. Total: {total}.'
  when 'bulk_arrival_notice' then 'Ya estoy en el puesto Tokyo Morningstore, este puesto NO TIENE NUMERO, se encuentra enfrente del puesto #138, Zona 1.

Me encuentras sentado en una mesa, al entrar tambien puedes preguntar por mi.

Voy vestido asi: {descripcion}. Estare hasta {horaLimite}.'
  when 'auction_reminder' then 'Esta subasta termina a las {horaCierre}. Puja mas alta: {pujaActual}.'
  when 'auction_reminder_no_bids' then 'Esta subasta termina a las {horaCierre}. Aún sin pujas.'
  when 'winner_unlinked' then 'Ganaste esta subasta. Enviame mensaje para confirmar tu pedido.'
  else body
end
where kind in (
  'manual_order_confirmation',
  'bulk_delivery_reminder',
  'bulk_arrival_notice',
  'auction_reminder',
  'auction_reminder_no_bids',
  'winner_unlinked'
);

insert into public.message_templates (owner_id, kind, body)
select distinct owner_id, 'order_delivered', 'Pedido Entregado'
from public.facebook_pages
on conflict (owner_id, kind) do update set body = excluded.body;

delete from public.message_templates
where kind in (
  'order_confirmation',
  'delivery_reminder',
  'arrival_notice',
  'payment_confirmation'
);

update public.delivery_locations
set position = case name
  when 'Mundo Divertido' then 1
  when 'Game Hunters' then 2
  when 'Entrega a puesto' then 3
  else position
end
where name in ('Mundo Divertido','Game Hunters','Entrega a puesto');
