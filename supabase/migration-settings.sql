-- إعدادات ساعات العمل ومكان شريط التنقل لصالون جود
create table if not exists public.salon_settings (
  id boolean primary key default true check (id = true),
  open_time time not null default time '09:00',
  close_time time not null default time '02:00',
  nav_position text not null default 'bottom' check (nav_position in ('bottom','top')),
  updated_at timestamptz not null default now()
);

insert into public.salon_settings (id, open_time, close_time, nav_position)
values (true, time '09:00', time '02:00', 'bottom')
on conflict (id) do nothing;

alter table public.salon_settings enable row level security;

drop policy if exists "public can read salon settings" on public.salon_settings;
create policy "public can read salon settings" on public.salon_settings
for select to anon, authenticated using (true);

drop policy if exists "owner manages salon settings" on public.salon_settings;
create policy "owner manages salon settings" on public.salon_settings
for all to authenticated using (public.is_owner()) with check (public.is_owner());

-- إزالة القيد القديم الذي كان يحصر المواعيد بين 15:00 و22:00.
alter table public.bookings drop constraint if exists within_opening_hours;

alter table public.bookings drop constraint if exists not_friday;
