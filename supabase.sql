-- BARBER PRO · Ejecuta TODO este archivo en Supabase > SQL Editor.
-- No borres las políticas ni publiques una service_role key.
create extension if not exists btree_gist;

create table if not exists public.admin_users (
 user_id uuid primary key references auth.users(id) on delete cascade
);
create table if not exists public.shop_settings (
 id integer primary key default 1 check(id=1),
 name text not null default 'BARBER PRO', phone text not null default '',
 address text not null default '', slot_interval integer not null default 30 check(slot_interval in (15,30,60))
);
create table if not exists public.services (
 id uuid primary key default gen_random_uuid(),
 name text not null check(length(name) between 2 and 80),
 description text not null default '',duration integer not null check(duration between 15 and 240 and duration%15=0),
 price numeric(12,2) not null check(price>=0),active boolean not null default true
);
create table if not exists public.barbers (
 id uuid primary key default gen_random_uuid(),name text not null check(length(name) between 2 and 80),
 description text not null default '',work_days integer[] not null default '{1,2,3,4,5,6}',
 start_time time not null default '09:00',end_time time not null default '18:00',
 active boolean not null default true,check(end_time>start_time)
);
create table if not exists public.clients (
 id uuid primary key default gen_random_uuid(),name text not null,
 phone text unique not null,email text not null default '',created_at timestamptz not null default now()
);
create table if not exists public.appointments (
 id uuid primary key default gen_random_uuid(),client_id uuid not null references public.clients(id),
 service_id uuid not null references public.services(id),barber_id uuid not null references public.barbers(id),
 start_at timestamp without time zone not null,end_at timestamp without time zone not null,
 status text not null default 'confirmed' check(status in ('confirmed','completed','cancelled')),
 notes text not null default '', price numeric(12,2) not null default 0,
 created_at timestamptz not null default now(),check(end_at>start_at),
 constraint no_overlapping_confirmed_appointments exclude using gist
  (barber_id with =, tsrange(start_at,end_at,'[)') with &&)
  where (status='confirmed')
);
create index if not exists appointments_start_idx on public.appointments(start_at);
create index if not exists appointments_client_idx on public.appointments(client_id);
insert into public.shop_settings(id,name,phone,address,slot_interval) values(1,'BARBER PRO','','',30) on conflict(id) do nothing;
insert into public.services(name,description,duration,price) select 'Corte clásico','Corte a tu estilo y acabado perfecto.',30,25000 where not exists(select 1 from public.services);
insert into public.services(name,description,duration,price) select 'Barba premium','Diseño, perfilado y arreglo de barba.',30,20000 where not exists(select 1 from public.services where name='Barba premium');
insert into public.services(name,description,duration,price) select 'Corte + barba','El combo completo para verte impecable.',60,40000 where not exists(select 1 from public.services where name='Corte + barba');
insert into public.services(name,description,duration,price) select 'Corte infantil','Estilo para los más pequeños.',30,22000 where not exists(select 1 from public.services where name='Corte infantil');
insert into public.barbers(name,description) select 'Andrés','Especialista en degradados' where not exists(select 1 from public.barbers);
insert into public.barbers(name,description) select 'Mateo','Cortes clásicos y barba' where not exists(select 1 from public.barbers where name='Mateo');

create or replace function public.is_barber_admin() returns boolean language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.admin_users where user_id=(select auth.uid()))
$$;
revoke all on function public.is_barber_admin() from public;
grant execute on function public.is_barber_admin() to authenticated;

alter table public.admin_users enable row level security;
alter table public.shop_settings enable row level security;
alter table public.services enable row level security;
alter table public.barbers enable row level security;
alter table public.clients enable row level security;
alter table public.appointments enable row level security;

create policy "settings publicly readable" on public.shop_settings for select to anon,authenticated using(true);
create policy "settings only admins write" on public.shop_settings for all to authenticated using(public.is_barber_admin()) with check(public.is_barber_admin());
create policy "active services visible to public" on public.services for select to anon,authenticated using(active or public.is_barber_admin());
create policy "admins manage services" on public.services for all to authenticated using(public.is_barber_admin()) with check(public.is_barber_admin());
create policy "active barbers visible to public" on public.barbers for select to anon,authenticated using(active or public.is_barber_admin());
create policy "admins manage barbers" on public.barbers for all to authenticated using(public.is_barber_admin()) with check(public.is_barber_admin());
create policy "admins manage clients" on public.clients for all to authenticated using(public.is_barber_admin()) with check(public.is_barber_admin());
create policy "admins manage appointments" on public.appointments for all to authenticated using(public.is_barber_admin()) with check(public.is_barber_admin());
-- No se conceden SELECT públicos sobre clientes ni reservas. Las RPC exponen solo la disponibilidad.

create or replace function public.get_busy_slots(p_barber_id uuid,p_day date)
returns table(start_time text,end_time text)
language sql security definer set search_path = '' as $$
 select to_char(a.start_at,'HH24:MI'),to_char(a.end_at,'HH24:MI')
 from public.appointments a
 where a.barber_id=p_barber_id and a.status='confirmed'
 and a.start_at>=p_day::timestamp and a.start_at<(p_day+1)::timestamp
$$;
revoke all on function public.get_busy_slots(uuid,date) from public;
grant execute on function public.get_busy_slots(uuid,date) to anon,authenticated;

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
 if coalesce(p_email,'')<>'' and p_email !~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
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

-- PASO MANUAL IMPORTANTE, DESPUÉS DE CREAR EL USUARIO ADMIN EN AUTH:
-- Reemplaza el correo y ejecuta esta instrucción por separado:
-- insert into public.admin_users(user_id)
-- select id from auth.users where email = 'admin@tubarberia.com';
