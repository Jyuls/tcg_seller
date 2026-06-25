create table if not exists private.internal_secrets (
  name text primary key,
  value text not null,
  created_at timestamptz not null default now()
);
alter table private.internal_secrets enable row level security;
insert into private.internal_secrets(name, value)
values ('cron_secret', encode(gen_random_bytes(32), 'hex'))
on conflict (name) do nothing;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'tcg-seller-automation-worker') then
    perform cron.unschedule('tcg-seller-automation-worker');
  end if;
  perform cron.schedule(
    'tcg-seller-automation-worker',
    '* * * * *',
    $job$
      select net.http_post(
        url := 'https://jmoacqfkefpcwxjfvrqc.supabase.co/functions/v1/automation-worker',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'x-cron-secret', (select value from private.internal_secrets where name = 'cron_secret')
        ),
        body := '{"action":"due"}'::jsonb,
        timeout_milliseconds := 55000
      );
    $job$
  );
end $$;
