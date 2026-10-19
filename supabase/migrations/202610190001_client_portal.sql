-- Shubham Production client portal schema. Apply in Supabase SQL Editor or via Supabase CLI.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text unique,
  full_name text,
  role text not null default 'client' check (role in ('admin','photographer','editor','album_designer','assistant','client')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.projects (
  id uuid primary key default gen_random_uuid(),
  title text not null check (length(trim(title)) between 1 and 120),
  client_email text not null,
  event_date date,
  selection_limit integer not null default 80 check (selection_limit between 1 and 2000),
  package_amount numeric(12,2) not null default 0 check (package_amount >= 0),
  delivery_status text not null default 'In Progress' check (delivery_status in ('In Progress','Editing','Awaiting Client Selection','Album Selection Submitted','Awaiting Approval','Ready for Delivery','Delivered')),
  archived boolean not null default false,
  gallery_expires_at timestamptz,
  downloads_enabled boolean not null default false,
  created_by uuid not null default auth.uid() references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists projects_status_idx on public.projects(delivery_status) where archived=false;
create index if not exists projects_updated_idx on public.projects(updated_at desc);

create table if not exists public.project_members (
  project_id uuid not null references public.projects(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  email text not null,
  role text not null default 'client' check (role in ('client','photographer','editor','album_designer','assistant')),
  invited_at timestamptz not null default now(),
  primary key(project_id,user_id)
);
create index if not exists project_members_user_idx on public.project_members(user_id,project_id);

create table if not exists public.events (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  name text not null check(length(trim(name)) between 1 and 80),
  sort_order integer not null default 0,
  event_date date,
  created_at timestamptz not null default now(),
  unique(project_id,name)
);

create table if not exists public.photos (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  event_id uuid not null references public.events(id) on delete cascade,
  original_filename text not null,
  storage_key text not null unique,
  thumbnail_key text,
  mime_type text not null check(mime_type in ('image/jpeg','image/png','image/webp')),
  file_size bigint not null check(file_size between 1 and 20971520),
  width integer,
  height integer,
  captured_at timestamptz,
  upload_status text not null default 'ready' check(upload_status in ('pending','ready','failed')),
  created_by uuid not null default auth.uid() references public.profiles(id),
  created_at timestamptz not null default now(),
  check (width is null or width > 0), check (height is null or height > 0)
);
create index if not exists photos_project_event_idx on public.photos(project_id,event_id,created_at desc);

create table if not exists public.favorites (
  project_id uuid not null references public.projects(id) on delete cascade,
  photo_id uuid not null references public.photos(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(photo_id,user_id)
);

create table if not exists public.album_selections (
  project_id uuid not null references public.projects(id) on delete cascade,
  photo_id uuid not null references public.photos(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'draft' check(status in ('draft','submitted')),
  selected_at timestamptz not null default now(),
  submitted_at timestamptz,
  primary key(project_id,photo_id,user_id)
);
create index if not exists selections_project_user_idx on public.album_selections(project_id,user_id,status);

create table if not exists public.payments (
  project_id uuid primary key references public.projects(id) on delete cascade,
  package_amount numeric(12,2) not null default 0 check(package_amount >= 0),
  amount_received numeric(12,2) not null default 0 check(amount_received >= 0),
  status text not null default 'Pending' check(status in ('Pending','Partially Paid','Paid','Refunded')),
  due_date date,
  transaction_reference text,
  updated_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check(amount_received <= package_amount or status='Refunded')
);

create table if not exists public.project_activity (
  id bigint generated always as identity primary key,
  project_id uuid not null references public.projects(id) on delete cascade,
  actor_id uuid references public.profiles(id) on delete set null,
  action text not null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists project_activity_idx on public.project_activity(project_id,created_at desc);

create table if not exists public.delivery_items (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  label text not null,
  storage_key text not null,
  mime_type text,
  delivered_at timestamptz,
  created_at timestamptz not null default now()
);

create or replace function public.touch_updated_at() returns trigger language plpgsql as $$
begin new.updated_at=now(); return new; end; $$;
drop trigger if exists profiles_touch on public.profiles;
create trigger profiles_touch before update on public.profiles for each row execute function public.touch_updated_at();
drop trigger if exists projects_touch on public.projects;
create trigger projects_touch before update on public.projects for each row execute function public.touch_updated_at();
drop trigger if exists payments_touch on public.payments;
create trigger payments_touch before update on public.payments for each row execute function public.touch_updated_at();

create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into public.profiles(id,email,full_name) values(new.id,lower(new.email),coalesce(new.raw_user_meta_data->>'full_name',''))
  on conflict(id) do update set email=excluded.email;
  return new;
end; $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

create or replace function public.is_portal_admin() returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.profiles where id=auth.uid() and role in ('admin','photographer'));
$$;
create or replace function public.can_access_project(p_project_id uuid) returns boolean language sql stable security definer set search_path=public as $$
 select public.is_portal_admin() or exists(select 1 from public.project_members pm where pm.project_id=p_project_id and pm.user_id=auth.uid());
$$;

-- Client link helper only links an already registered account. It never grants admin rights or sends email.
create or replace function public.invite_project_client(p_project_id uuid,p_email text) returns void language plpgsql security definer set search_path=public as $$
declare target_id uuid;
begin
 if not public.is_portal_admin() then raise exception 'Admin access required'; end if;
 select id into target_id from public.profiles where lower(email)=lower(trim(p_email));
 if target_id is null then raise exception 'Client account not found. Invite them through Supabase Authentication first, then retry.'; end if;
 insert into public.project_members(project_id,user_id,email,role) values(p_project_id,target_id,lower(trim(p_email)),'client') on conflict(project_id,user_id) do update set email=excluded.email,role='client';
 insert into public.project_activity(project_id,actor_id,action,details) values(p_project_id,auth.uid(),'client_linked',jsonb_build_object('email',lower(trim(p_email))));
end; $$;

create or replace function public.enforce_album_selection_limit() returns trigger language plpgsql security definer set search_path=public as $$
declare lim integer; current_count integer; locked boolean;
begin
 if tg_op='DELETE' then
   if old.status='submitted' and not public.is_portal_admin() then raise exception 'Submitted selections are locked'; end if;
   return old;
 end if;
 if tg_op='UPDATE' then
   if old.status='submitted' and not public.is_portal_admin() then raise exception 'Submitted selections are locked'; end if;
   return new;
 end if;
 if not public.can_access_project(new.project_id) then raise exception 'Project access denied'; end if;
 if not exists(select 1 from public.photos where id=new.photo_id and project_id=new.project_id and upload_status='ready') then raise exception 'Photo does not belong to this project'; end if;
 select selection_limit into lim from public.projects where id=new.project_id;
 select count(*) into current_count from public.album_selections where project_id=new.project_id and user_id=new.user_id;
 if current_count >= lim then raise exception 'Album selection limit reached (%)',lim; end if;
 if exists(select 1 from public.album_selections where project_id=new.project_id and user_id=new.user_id and status='submitted') then raise exception 'Selection is submitted and locked'; end if;
 return new;
end; $$;
drop trigger if exists album_selection_guard on public.album_selections;
create trigger album_selection_guard before insert or update or delete on public.album_selections for each row execute function public.enforce_album_selection_limit();

create or replace function public.submit_album_selection(p_project_id uuid) returns integer language plpgsql security definer set search_path=public as $$
declare n integer; lim integer;
begin
 if not public.can_access_project(p_project_id) then raise exception 'Project access denied'; end if;
 select selection_limit into lim from public.projects where id=p_project_id;
 select count(*) into n from public.album_selections where project_id=p_project_id and user_id=auth.uid();
 if n<1 then raise exception 'Select at least one photo before submitting'; end if;
 if n>lim then raise exception 'Selection limit exceeded'; end if;
 update public.album_selections set status='submitted',submitted_at=now() where project_id=p_project_id and user_id=auth.uid();
 update public.projects set delivery_status='Album Selection Submitted' where id=p_project_id and not public.is_portal_admin();
 insert into public.project_activity(project_id,actor_id,action,details) values(p_project_id,auth.uid(),'album_selection_submitted',jsonb_build_object('count',n));
 return n;
end; $$;
create or replace function public.reopen_album_selection(p_project_id uuid,p_user_id uuid) returns void language plpgsql security definer set search_path=public as $$
begin
 if not public.is_portal_admin() then raise exception 'Admin access required'; end if;
 update public.album_selections set status='draft',submitted_at=null where project_id=p_project_id and user_id=p_user_id;
 insert into public.project_activity(project_id,actor_id,action,details) values(p_project_id,auth.uid(),'album_selection_reopened',jsonb_build_object('client_user_id',p_user_id));
end; $$;

-- Row Level Security
alter table public.profiles enable row level security;
alter table public.projects enable row level security;
alter table public.project_members enable row level security;
alter table public.events enable row level security;
alter table public.photos enable row level security;
alter table public.favorites enable row level security;
alter table public.album_selections enable row level security;
alter table public.payments enable row level security;
alter table public.project_activity enable row level security;
alter table public.delivery_items enable row level security;

-- Makes this script safe to re-run: drop old policies first.
do $$ declare r record; begin
  for r in select schemaname,tablename,policyname from pg_policies
    where (schemaname='public' and tablename in ('profiles','projects','project_members','events','photos','favorites','album_selections','payments','project_activity','delivery_items'))
       or (schemaname='storage' and tablename='objects' and policyname in ('project members read gallery objects','admin uploads gallery objects','admin updates gallery objects','admin deletes gallery objects'))
  loop execute format('drop policy if exists %I on %I.%I',r.policyname,r.schemaname,r.tablename); end loop;
end $$;

-- Backfill profiles for users that signed up before this script ran.
insert into public.profiles(id,email,full_name)
select id,lower(email),coalesce(raw_user_meta_data->>'full_name','') from auth.users
on conflict(id) do nothing;

create policy "profile self or admin read" on public.profiles for select to authenticated using(id=auth.uid() or public.is_portal_admin());
create policy "profile self update limited" on public.profiles for update to authenticated using(id=auth.uid()) with check(id=auth.uid() and role not in ('admin','photographer','editor','album_designer','assistant'));
create policy "admin manages profiles" on public.profiles for all to authenticated using(public.is_portal_admin()) with check(public.is_portal_admin());
create policy "project access read" on public.projects for select to authenticated using(public.can_access_project(id));
create policy "admin creates projects" on public.projects for insert to authenticated with check(public.is_portal_admin());
create policy "admin updates projects" on public.projects for update to authenticated using(public.is_portal_admin()) with check(public.is_portal_admin());
create policy "admin archives projects" on public.projects for delete to authenticated using(public.is_portal_admin());
create policy "members read own membership" on public.project_members for select to authenticated using(user_id=auth.uid() or public.is_portal_admin());
create policy "admin manages members" on public.project_members for all to authenticated using(public.is_portal_admin()) with check(public.is_portal_admin());
create policy "project events read" on public.events for select to authenticated using(public.can_access_project(project_id));
create policy "admin manages events" on public.events for all to authenticated using(public.is_portal_admin()) with check(public.is_portal_admin());
create policy "project photos read" on public.photos for select to authenticated using(public.can_access_project(project_id));
create policy "admin manages photos" on public.photos for all to authenticated using(public.is_portal_admin()) with check(public.is_portal_admin());
create policy "own favorites read" on public.favorites for select to authenticated using(user_id=auth.uid() and public.can_access_project(project_id));
create policy "own favorites insert" on public.favorites for insert to authenticated with check(user_id=auth.uid() and public.can_access_project(project_id));
create policy "own favorites delete" on public.favorites for delete to authenticated using(user_id=auth.uid() and public.can_access_project(project_id));
create policy "selection read own or admin" on public.album_selections for select to authenticated using((user_id=auth.uid() and public.can_access_project(project_id)) or public.is_portal_admin());
create policy "selection draft insert" on public.album_selections for insert to authenticated with check(user_id=auth.uid() and public.can_access_project(project_id) and status='draft');
create policy "selection draft delete" on public.album_selections for delete to authenticated using(user_id=auth.uid() and public.can_access_project(project_id) and status='draft');
create policy "admin manages selections" on public.album_selections for all to authenticated using(public.is_portal_admin()) with check(public.is_portal_admin());
create policy "payment read project" on public.payments for select to authenticated using(public.can_access_project(project_id));
create policy "admin manages payments" on public.payments for all to authenticated using(public.is_portal_admin()) with check(public.is_portal_admin());
create policy "activity read project" on public.project_activity for select to authenticated using(public.can_access_project(project_id));
create policy "activity admin inserts" on public.project_activity for insert to authenticated with check(public.is_portal_admin() or actor_id=auth.uid() and public.can_access_project(project_id));
create policy "delivery items read project" on public.delivery_items for select to authenticated using(public.can_access_project(project_id));
create policy "admin manages delivery" on public.delivery_items for all to authenticated using(public.is_portal_admin()) with check(public.is_portal_admin());

grant usage on schema public to authenticated;
grant select,update on public.profiles to authenticated;
grant select,insert,update,delete on public.projects,public.project_members,public.events,public.photos,public.favorites,public.album_selections,public.payments,public.project_activity,public.delivery_items to authenticated;
grant execute on function public.invite_project_client(uuid,text) to authenticated;
grant execute on function public.submit_album_selection(uuid) to authenticated;
grant execute on function public.reopen_album_selection(uuid,uuid) to authenticated;

-- Private object bucket: the first path segment must be the project UUID.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('private-gallery','private-gallery',false,20971520,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=false,file_size_limit=20971520,allowed_mime_types=array['image/jpeg','image/png','image/webp'];
create policy "project members read gallery objects" on storage.objects for select to authenticated using(bucket_id='private-gallery' and public.can_access_project((storage.foldername(name))[1]::uuid));
create policy "admin uploads gallery objects" on storage.objects for insert to authenticated with check(bucket_id='private-gallery' and public.is_portal_admin() and public.can_access_project((storage.foldername(name))[1]::uuid));
create policy "admin updates gallery objects" on storage.objects for update to authenticated using(bucket_id='private-gallery' and public.is_portal_admin() and public.can_access_project((storage.foldername(name))[1]::uuid)) with check(bucket_id='private-gallery' and public.is_portal_admin() and public.can_access_project((storage.foldername(name))[1]::uuid));
create policy "admin deletes gallery objects" on storage.objects for delete to authenticated using(bucket_id='private-gallery' and public.is_portal_admin() and public.can_access_project((storage.foldername(name))[1]::uuid));



-- new
-- Self-signup support: when a user registers, link them to every project whose client_email matches.
-- Run this once in the Supabase SQL Editor (after 202610190001_client_portal.sql).

create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into public.profiles(id,email,full_name)
  values(new.id,lower(new.email),coalesce(new.raw_user_meta_data->>'full_name',''))
  on conflict(id) do update set email=excluded.email;

  insert into public.project_members(project_id,user_id,email,role)
  select p.id,new.id,lower(new.email),'client'
  from public.projects p
  where lower(trim(p.client_email))=lower(trim(new.email))
  on conflict(project_id,user_id) do nothing;

  return new;
end; $$;

-- Link existing accounts to matching projects too (one-time backfill).
insert into public.project_members(project_id,user_id,email,role)
select p.id,pr.id,pr.email,'client'
from public.projects p
join public.profiles pr on lower(trim(pr.email))=lower(trim(p.client_email))
where pr.role='client'
on conflict(project_id,user_id) do nothing;