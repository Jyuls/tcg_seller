create policy automation_jobs_owner_update
on public.automation_jobs
for update
to authenticated
using (owner_id = (select auth.uid()))
with check (
  owner_id = (select auth.uid())
  and kind in ('publish_auction', 'close_auction')
);
