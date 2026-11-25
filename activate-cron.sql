-- Primero configura en Vault los secretos barber_project_url y barber_cron_secret.
create extension if not exists pg_cron;
create extension if not exists pg_net;
select cron.schedule('barber-booking-email','* * * * *',$job$
 select net.http_post(
  url := rtrim((select decrypted_secret from vault.decrypted_secrets where name='barber_project_url'),'/') || '/functions/v1/send-booking-email',
  headers := jsonb_build_object('Content-Type','application/json','x-booking-secret',(select decrypted_secret from vault.decrypted_secrets where name='barber_cron_secret')),
  body := '{}'::jsonb, timeout_milliseconds := 120000
 ) where exists(select 1 from public.booking_email_queue where due_at<=now() and (state='pending' or (state='sending' and lease_until<now())));
$job$);
