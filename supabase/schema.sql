-- صالون جود: Supabase schema
-- نفّذ الملف كاملاً في Supabase SQL Editor بعد إنشاء مشروع جديد.
create extension if not exists pgcrypto;
create extension if not exists btree_gist;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  role text not null check (role in ('owner','reception')) default 'reception',
  created_at timestamptz not null default now()
);

create table if not exists public.services (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  duration_minutes integer not null check (duration_minutes between 5 and 240),
  price numeric(12,2),
  active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.bookings (
  id uuid primary key default gen_random_uuid(),
  customer_name text not null,
  customer_phone text not null,
  service_id uuid not null references public.services(id),
  booking_date date not null,
  start_time time not null,
  end_time time not null,
  status text not null default 'pending' check (status in ('pending','confirmed','rejected','cancelled','completed')),
  created_at timestamptz not null default now(),
  constraint valid_booking_time check (end_time > start_time),
  constraint within_opening_hours check (start_time >= time '15:00' and end_time <= time '22:00'),
  constraint not_friday check (extract(dow from booking_date) <> 5)
);

create table if not exists public.queue_entries (
  id uuid primary key default gen_random_uuid(),
  ticket_number bigint generated always as identity unique,
  customer_name text not null,
  customer_phone text not null,
  service_id uuid not null references public.services(id),
  status text not null default 'waiting' check (status in ('waiting','called','serving','completed','skipped','cancelled')),
  created_at timestamptz not null default now()
);

create index if not exists bookings_date_status_idx on public.bookings(booking_date,status);
create index if not exists queue_status_created_idx on public.queue_entries(status,created_at);

-- Prevent overlapping pending/confirmed appointments, including simultaneous submissions.
do $$ begin
  alter table public.bookings add constraint no_overlapping_active_bookings
  exclude using gist (
    booking_date with =,
    tsrange(booking_date + start_time, booking_date + end_time, '[)') with &&
  ) where (status in ('pending','confirmed'));
exception when duplicate_object then null;
end $$;

-- Role lookup used by RLS. A profile must exist before admin access is granted.
create or replace function public.is_staff()
returns boolean language sql stable security definer set search_path = public
as $$ select exists(select 1 from public.profiles p where p.id = auth.uid() and p.role in ('owner','reception')); $$;

create or replace function public.is_owner()
returns boolean language sql stable security definer set search_path = public
as $$ select exists(select 1 from public.profiles p where p.id = auth.uid() and p.role = 'owner'); $$;

create or replace function public.join_queue(p_customer_name text, p_customer_phone text, p_service_id uuid)
returns bigint language plpgsql security definer set search_path = public
as $$
declare v_ticket bigint;
begin
  if length(trim(p_customer_name)) < 2 or length(trim(p_customer_phone)) < 6 then
    raise exception 'يرجى إدخال اسم ورقم هاتف صحيحين';
  end if;
  if not exists(select 1 from public.services where id=p_service_id and active=true) then
    raise exception 'الخدمة غير متاحة';
  end if;
  insert into public.queue_entries(customer_name,customer_phone,service_id)
  values(trim(p_customer_name),trim(p_customer_phone),p_service_id)
  returning ticket_number into v_ticket;
  return v_ticket;
end;
$$;
grant execute on function public.join_queue(text,text,uuid) to anon, authenticated;

alter table public.profiles enable row level security;
alter table public.services enable row level security;
alter table public.bookings enable row level security;
alter table public.queue_entries enable row level security;

drop policy if exists "public can view active services" on public.services;
create policy "public can view active services" on public.services for select to anon, authenticated using (active = true or public.is_staff());
drop policy if exists "staff manage services" on public.services;
create policy "staff manage services" on public.services for all to authenticated using (public.is_staff()) with check (public.is_staff());

drop policy if exists "staff read profiles" on public.profiles;
create policy "staff read profiles" on public.profiles for select to authenticated using (public.is_staff());
drop policy if exists "owner manage profiles" on public.profiles;
create policy "owner manage profiles" on public.profiles for all to authenticated using (public.is_owner()) with check (public.is_owner());

drop policy if exists "public create booking requests" on public.bookings;
create policy "public create booking requests" on public.bookings for insert to anon, authenticated with check (
  status = 'pending'
  and exists(select 1 from public.services s where s.id=service_id and s.active=true)
);
drop policy if exists "staff manage bookings" on public.bookings;
create policy "staff manage bookings" on public.bookings for all to authenticated using (public.is_staff()) with check (public.is_staff());

drop policy if exists "public join queue" on public.queue_entries;
drop policy if exists "staff manage queue" on public.queue_entries;
create policy "staff manage queue" on public.queue_entries for all to authenticated using (public.is_staff()) with check (public.is_staff());

-- Initial services. The manager can edit prices and skin-cleaning duration in the dashboard.
insert into public.services(name,duration_minutes,price,sort_order)
select 'قص شعر',30,null,1 where not exists(select 1 from public.services where name='قص شعر');
insert into public.services(name,duration_minutes,price,sort_order)
select 'قص ذقن',25,null,2 where not exists(select 1 from public.services where name='قص ذقن');
insert into public.services(name,duration_minutes,price,sort_order)
select 'قص شعر وذقن',45,null,3 where not exists(select 1 from public.services where name='قص شعر وذقن');
insert into public.services(name,duration_minutes,price,sort_order)
select 'تنظيف البشرة',30,null,4 where not exists(select 1 from public.services where name='تنظيف البشرة');

-- IMPORTANT: Create the first auth user in Supabase Authentication, then run:
-- insert into public.profiles(id,full_name,role)
-- values ('AUTH_USER_UUID_HERE','مدير صالون جود','owner');
-- Create reception users in Authentication, then add their profile with role='reception'.
