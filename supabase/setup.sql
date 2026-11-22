-- ============================================================
--  ofmana : configuration de la base Supabase
--  À coller en entier dans Supabase > SQL Editor, puis « Run ».
--  Le script peut être relancé sans risque (il ne supprime aucune donnée).
-- ============================================================

-- ---------- Tables ----------
create table if not exists public.profiles (
  id uuid primary key references auth.users on delete cascade,
  email text,
  role text not null default 'model' check (role in ('admin','model')),
  created_at timestamptz not null default now()
);

create table if not exists public.settings (
  id int primary key default 1 check (id = 1),
  data jsonb not null default '{}'
);
insert into public.settings (id, data) values (1, '{"agency":"Mon Agence"}') on conflict (id) do nothing;

-- Fiche modèle : ce que la modèle peut voir d'elle-même
create table if not exists public.models (
  id text primary key,
  email text,
  user_id uuid references auth.users on delete set null,
  data jsonb not null default '{}',
  updated_at timestamptz not null default now()
);

-- Infos privées de l'agence sur une modèle (notes) : jamais visibles par elle
create table if not exists public.model_private (
  id text primary key references public.models on delete cascade,
  data jsonb not null default '{}'
);

create table if not exists public.content (
  id text primary key,
  model_id text references public.models on delete cascade,
  data jsonb not null default '{}'
);

create table if not exists public.tasks (
  id text primary key,
  model_id text references public.models on delete cascade,
  shared boolean not null default false,
  data jsonb not null default '{}'
);

create table if not exists public.prospects (
  id text primary key,
  data jsonb not null default '{}'
);

create index if not exists content_model_idx on public.content (model_id);
create index if not exists tasks_model_idx on public.tasks (model_id);
create index if not exists models_user_idx on public.models (user_id);

-- ---------- Fonctions d'aide ----------
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and role = 'admin');
$$;

create or replace function public.my_model_ids() returns setof text
language sql stable security definer set search_path = public as $$
  select id from models where user_id = auth.uid();
$$;

-- Nouveau compte : le tout premier devient admin, les suivants sont des modèles.
-- Si une fiche modèle porte déjà cet email, le compte y est relié automatiquement.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, email, role)
  values (new.id, new.email,
          case when exists (select 1 from profiles where role = 'admin') then 'model' else 'admin' end)
  on conflict (id) do nothing;
  update models set user_id = new.id
   where user_id is null and email is not null and lower(email) = lower(new.email);
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Quand l'admin saisit ou change l'email d'une fiche, on relie le compte correspondant.
create or replace function public.link_model_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.updated_at := now();
  if new.email is null or btrim(new.email) = '' then
    new.email := null;
    new.user_id := null;
  elsif tg_op = 'INSERT' or new.email is distinct from old.email then
    new.email := lower(btrim(new.email));
    select u.id into new.user_id
      from auth.users u
      left join profiles p on p.id = u.id
     where lower(u.email) = new.email and coalesce(p.role, 'model') <> 'admin'
     limit 1;
  end if;
  return new;
end $$;

drop trigger if exists models_link_user on public.models;
create trigger models_link_user
  before insert or update on public.models
  for each row execute function public.link_model_user();

-- Une modèle peut cocher / décocher les tâches partagées avec elle, et rien d'autre.
create or replace function public.set_task_done(task_id text, is_done boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  update tasks
     set data = jsonb_set(data, '{done}', to_jsonb(is_done))
   where id = task_id
     and (is_admin() or (shared and model_id in (select my_model_ids())));
  if not found then
    raise exception 'Tâche introuvable ou non autorisée';
  end if;
end $$;

revoke all on function public.set_task_done(text, boolean) from public, anon;
grant execute on function public.set_task_done(text, boolean) to authenticated;

-- ---------- Sécurité : Row Level Security ----------
alter table public.profiles      enable row level security;
alter table public.settings      enable row level security;
alter table public.models        enable row level security;
alter table public.model_private enable row level security;
alter table public.content       enable row level security;
alter table public.tasks         enable row level security;
alter table public.prospects     enable row level security;

do $$
declare r record;
begin
  for r in select policyname, tablename from pg_policies
           where schemaname = 'public'
             and tablename in ('profiles','settings','models','model_private','content','tasks','prospects')
  loop
    execute format('drop policy if exists %I on public.%I', r.policyname, r.tablename);
  end loop;
end $$;

-- Profils : chacun lit le sien, l'admin lit et modifie tout
create policy profiles_select on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_admin());
create policy profiles_admin_update on public.profiles for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Réglages (nom de l'agence) : lisibles par tout compte connecté, modifiables par l'admin
create policy settings_select on public.settings for select to authenticated using (true);
create policy settings_admin on public.settings for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Fiches modèles : l'admin gère tout, une modèle lit uniquement la sienne
create policy models_admin on public.models for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy models_self_select on public.models for select to authenticated
  using (user_id = auth.uid());

-- Notes privées et prospection : admin uniquement
create policy model_private_admin on public.model_private for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy prospects_admin on public.prospects for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Planning : l'admin gère tout, une modèle lit uniquement ses contenus
create policy content_admin on public.content for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy content_self_select on public.content for select to authenticated
  using (model_id in (select public.my_model_ids()));

-- Tâches : l'admin gère tout, une modèle lit uniquement les tâches partagées avec elle
create policy tasks_admin on public.tasks for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy tasks_self_select on public.tasks for select to authenticated
  using (shared and model_id in (select public.my_model_ids()));

-- Accès anonyme : aucun
revoke all on public.profiles, public.settings, public.models, public.model_private,
              public.content, public.tasks, public.prospects from anon;
grant select, insert, update, delete on public.profiles, public.settings, public.models,
      public.model_private, public.content, public.tasks, public.prospects to authenticated;
