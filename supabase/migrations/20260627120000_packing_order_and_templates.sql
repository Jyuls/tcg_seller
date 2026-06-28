alter table public.orders
  add column if not exists packing_position integer,
  add column if not exists packed_at timestamptz;

create index if not exists orders_packing_idx
on public.orders(owner_id, delivery_status, packing_position nulls last, created_at);

update public.message_templates
set body = 'Esta subasta termina a las {horaCierre}. Puja mas alta: {pujaActual}.',
    updated_at = now()
where kind = 'auction_reminder';

update public.message_templates
set body = 'Esta subasta termina a las {horaCierre}. Aún sin pujas.',
    updated_at = now()
where kind = 'auction_reminder_no_bids';

update public.message_templates
set body = 'Ganaste esta subasta. Enviame mensaje para confirmar tu pedido.',
    updated_at = now()
where kind = 'winner_unlinked';
