-- Ejecutar después de supabase.sql (también válido para instalaciones existentes).
create table if not exists public.booking_email_queue (
 id uuid primary key default gen_random_uuid(),
 appointment_id uuid not null references public.appointments(id) on delete cascade,
 kind text not null check(kind in ('confirmed','cancelled','reminder','admin')),
 recipient text not null, payload jsonb not null,
 due_at timestamptz not null default now(), created_at timestamptz not null default now(),
 state text not null default 'pending' check(state in ('pending','sending','sent','failed','skipped')),
 attempts integer not null default 0, lease_until timestamptz, sent_at timestamptz, last_error text,
 unique(appointment_id,kind)
);
alter table public.booking_email_queue enable row level security;
revoke all on public.booking_email_queue from anon, authenticated;
grant select, update on public.booking_email_queue to service_role;
create index if not exists booking_email_due on public.booking_email_queue(state,due_at);
-- Guardar destinatario por cita: cambios posteriores en el directorio no lo alteran.
alter table public.appointments add column if not exists notification_email text;
create or replace function public.queue_booking_email() returns trigger
language plpgsql security definer set search_path='' as $$
declare c public.clients%rowtype; s public.services%rowtype; b public.barbers%rowtype; shop public.shop_settings%rowtype; p jsonb; dest text; start_utc timestamptz;
begin
 if TG_OP='UPDATE' then
  if new.status=old.status then return new; end if;
  if new.status<>'confirmed' then
   update public.booking_email_queue set state='skipped' where appointment_id=new.id and kind='reminder' and state='pending';
  end if;
  if new.status<>'cancelled' then return new; end if;
 elsif new.status<>'confirmed' then return new;
 end if;
 select * into c from public.clients where id=new.client_id;
 select * into s from public.services where id=new.service_id;
 select * into b from public.barbers where id=new.barber_id;
 select * into shop from public.shop_settings where id=1;
 dest:=coalesce(new.notification_email,c.email,'');
 if TG_OP='INSERT' then
  update public.appointments set notification_email=dest where id=new.id;
 end if;
 p:=jsonb_build_object('name',c.name,'service',s.name,'barber',b.name,'start',to_char(new.start_at,'YYYY-MM-DD"T"HH24:MI:SS'),'price',new.price,'shop',shop.name,'address',shop.address,'phone',shop.phone);
 start_utc:=new.start_at at time zone 'America/Bogota';
 if TG_OP='INSERT' then
  if dest<>'' then
   insert into public.booking_email_queue(appointment_id,kind,recipient,payload) values(new.id,'confirmed',dest,p) on conflict do nothing;
   if start_utc>now()+interval '24 hours' then
    insert into public.booking_email_queue(appointment_id,kind,recipient,payload,due_at) values(new.id,'reminder',dest,p,start_utc-interval '24 hours') on conflict do nothing;
   end if;
  end if;
  insert into public.booking_email_queue(appointment_id,kind,recipient,payload) values(new.id,'admin','',p) on conflict do nothing;
 elsif dest<>'' then
  insert into public.booking_email_queue(appointment_id,kind,recipient,payload) values(new.id,'cancelled',dest,p) on conflict do nothing;
 end if;
 return new;
end; $$;
revoke all on function public.queue_booking_email() from public;
drop trigger if exists booking_email_trigger on public.appointments;
create trigger booking_email_trigger after insert or update of status on public.appointments for each row execute function public.queue_booking_email();
create or replace function public.claim_booking_emails() returns setof public.booking_email_queue
language plpgsql security definer set search_path='' as $$
begin
 update public.booking_email_queue q set state='skipped' where q.kind='reminder' and q.state='pending' and not exists(select 1 from public.appointments a where a.id=q.appointment_id and a.status='confirmed' and a.start_at > now() at time zone 'America/Bogota');
 update public.booking_email_queue set state='failed',last_error='Límite de reintentos' where state='sending' and lease_until<now() and attempts>=5;
 return query with picked as (
  select id from public.booking_email_queue where due_at<=now() and attempts<5 and (state='pending' or (state='sending' and lease_until<now())) order by due_at limit 10 for update skip locked
 ) update public.booking_email_queue q set state='sending',attempts=q.attempts+1,lease_until=now()+interval '5 minutes' from picked where q.id=picked.id returning q.*;
end; $$;
revoke all on function public.claim_booking_emails() from public,anon,authenticated;
grant execute on function public.claim_booking_emails() to service_role;
-- Las reservas anteriores a la instalación no generan correos retroactivos.

-- Actualiza validación de reserva pública: el correo es obligatorio.
create or replace function public.create_public_booking(
 p_service_id uuid,p_barber_id uuid,p_day date,p_time text,
 p_name text,p_phone text,p_email text default null,p_notes text default null
) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_service public.services%rowtype;v_barber public.barbers%rowtype;
 v_client uuid;v_start timestamp;v_end timestamp;v_id uuid;
 v_interval integer;v_local_now timestamp;
begin
 if length(btrim(coalesce(p_name,'')))<2 or length(p_name)>90 or
    p_phone !~ '^\+?[0-9()\-]{7,20}$' or
    length(coalesce(p_email,''))>120 or length(coalesce(p_notes,''))>300 then
  raise exception 'Verifica los datos del cliente.';
 end if;
 if coalesce(p_email,'')='' or p_email !~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
  raise exception 'Correo electrónico inválido.';
 end if;
 if p_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then raise exception 'Hora inválida.';end if;
 select * into v_service from public.services where id=p_service_id and active=true;
 if not found then raise exception 'Este servicio no está disponible.';end if;
 select * into v_barber from public.barbers where id=p_barber_id and active=true;
 if not found then raise exception 'Este barbero no está disponible.';end if;
 select slot_interval into v_interval from public.shop_settings where id=1;
 v_start:=p_day::timestamp+p_time::time;
 v_end:=v_start+make_interval(mins=>v_service.duration);
 v_local_now:=now() at time zone 'America/Bogota';
 if v_start<v_local_now+interval '30 minutes' or p_day>(v_local_now::date+interval '120 days')::date then
  raise exception 'Elige una fecha y hora futura (máximo 120 días).';end if;
 if not (extract(dow from p_day)::integer=any(v_barber.work_days)) or
   v_start::time<v_barber.start_time or v_end::time>v_barber.end_time or
   (extract(hour from v_start)::integer*60+extract(minute from v_start)::integer
    -(extract(hour from v_barber.start_time)::integer*60+extract(minute from v_barber.start_time)::integer))%v_interval<>0 then
  raise exception 'El horario está fuera de la jornada disponible.';end if;
 insert into public.clients(name,phone,email) values(btrim(p_name),p_phone,coalesce(p_email,''))
 on conflict(phone) do update set name=excluded.name,email=excluded.email
 returning id into v_client;
 insert into public.appointments(client_id,service_id,barber_id,start_at,end_at,notes,price)
 values(v_client,p_service_id,p_barber_id,v_start,v_end,coalesce(p_notes,''),v_service.price)
 returning id into v_id;
 return v_id;
exception when exclusion_violation then
 raise exception 'Este horario ya está reservado. Selecciona otro.';
end;
$$;
revoke all on function public.create_public_booking(uuid,uuid,date,text,text,text,text,text) from public;
grant execute on function public.create_public_booking(uuid,uuid,date,text,text,text,text,text) to anon,authenticated;

