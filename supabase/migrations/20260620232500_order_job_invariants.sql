create policy automation_jobs_owner_insert on public.automation_jobs
for insert to authenticated
with check (owner_id = (select auth.uid()) and kind in ('publish_auction','close_auction'));

create unique index orders_one_unpaid_pending_per_customer
on public.orders(customer_id)
where payment_status='pending' and delivery_status='pending';
