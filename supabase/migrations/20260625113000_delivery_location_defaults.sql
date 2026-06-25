alter table public.delivery_locations
  add column if not exists default_zone integer check (default_zone between 1 and 3),
  add column if not exists default_booth_number integer check (default_booth_number between 1 and 900);
