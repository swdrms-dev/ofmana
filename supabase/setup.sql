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

-- Invitations admin : un email ajouté ici devient admin dès la création de son compte
create table if not exists public.admin_invites (
  email text primary key,
  invited_by uuid references auth.users on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.prospects (
  id text primary key,
  data jsonb not null default '{}'
);

create index if not exists content_model_idx on public.content (model_id);
create index if not exists tasks_model_idx on public.tasks (model_id);
create index if not exists models_user_idx on public.models (user_id);
create index if not exists admin_invites_invited_by_idx on public.admin_invites (invited_by);

-- ---------- Fonctions internes (schéma privé, non exposé par l'API) ----------
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

create or replace function private.is_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.profiles where id = (select auth.uid()) and role = 'admin');
$$;

create or replace function private.my_model_ids() returns setof text
language sql stable security definer set search_path = '' as $$
  select id from public.models where user_id = (select auth.uid());
$$;

revoke all on function private.is_admin() from public, anon;
revoke all on function private.my_model_ids() from public, anon;
grant execute on function private.is_admin() to authenticated;
grant execute on function private.my_model_ids() to authenticated;

-- Nouveau compte : le tout premier devient admin, ainsi que les emails invités comme admin.
-- Les autres sont des modèles ; si une fiche porte déjà cet email, le compte y est relié.
create or replace function private.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare r text;
begin
  r := case
         when not exists (select 1 from profiles where role = 'admin') then 'admin'
         when exists (select 1 from admin_invites where email = lower(new.email)) then 'admin'
         else 'model'
       end;
  insert into profiles (id, email, role) values (new.id, new.email, r) on conflict (id) do nothing;
  if r = 'admin' then
    delete from admin_invites where email = lower(new.email);
  else
    update models set user_id = new.id
     where user_id is null and email is not null and lower(email) = lower(new.email);
  end if;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

-- Quand l'admin saisit ou change l'email d'une fiche, on relie le compte correspondant.
create or replace function private.link_model_user() returns trigger
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
  for each row execute function private.link_model_user();

revoke all on function private.handle_new_user() from public, anon, authenticated;
revoke all on function private.link_model_user() from public, anon, authenticated;

-- Une modèle peut cocher / décocher les tâches partagées avec elle, et rien d'autre.
create or replace function public.set_task_done(task_id text, is_done boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  update tasks
     set data = jsonb_set(data, '{done}', to_jsonb(is_done))
   where id = task_id
     and (private.is_admin() or (shared and model_id in (select private.my_model_ids())));
  if not found then
    raise exception 'Tâche introuvable ou non autorisée';
  end if;
end $$;

revoke all on function public.set_task_done(text, boolean) from public, anon;
grant execute on function public.set_task_done(text, boolean) to authenticated;

-- ---------- Gestion de l'équipe (admins uniquement) ----------
create or replace function public.list_accounts()
returns table (id uuid, email text, role text, created_at timestamptz, model_name text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not private.is_admin() then raise exception 'Réservé aux admins'; end if;
  return query
    select p.id, p.email, p.role, p.created_at,
           (select m.data->>'name' from models m where m.user_id = p.id limit 1)
      from profiles p
     order by (p.role = 'admin') desc, p.created_at;
end $$;

-- Donne les droits admin à un email : immédiatement si le compte existe, sinon à sa création.
create or replace function public.grant_admin(target_email text) returns text
language plpgsql security definer set search_path = public as $$
declare e text := lower(btrim(coalesce(target_email, ''))); uid uuid;
begin
  if not private.is_admin() then raise exception 'Réservé aux admins'; end if;
  if e !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Adresse email invalide'; end if;
  select u.id into uid from auth.users u where lower(u.email) = e limit 1;
  if uid is not null then
    update profiles set role = 'admin' where id = uid;
    return 'promoted';
  end if;
  insert into admin_invites (email, invited_by) values (e, (select auth.uid())) on conflict (email) do nothing;
  return 'invited';
end $$;

-- Change le rôle d'un compte. On ne peut pas retirer ses propres droits, ni le dernier admin.
create or replace function public.set_role(target uuid, new_role text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not private.is_admin() then raise exception 'Réservé aux admins'; end if;
  if new_role not in ('admin', 'model') then raise exception 'Rôle inconnu'; end if;
  if target = (select auth.uid()) and new_role <> 'admin' then
    raise exception 'Tu ne peux pas retirer tes propres droits admin.';
  end if;
  if new_role = 'model'
     and exists (select 1 from profiles where id = target and role = 'admin')
     and (select count(*) from profiles where role = 'admin') <= 1 then
    raise exception 'Il doit rester au moins un admin.';
  end if;
  update profiles set role = new_role where id = target;
  if not found then raise exception 'Compte introuvable'; end if;
end $$;

revoke all on function public.list_accounts() from public, anon;
revoke all on function public.grant_admin(text) from public, anon;
revoke all on function public.set_role(uuid, text) from public, anon;
grant execute on function public.list_accounts() to authenticated;
grant execute on function public.grant_admin(text) to authenticated;
grant execute on function public.set_role(uuid, text) to authenticated;

-- ---------- Sécurité : Row Level Security ----------
alter table public.profiles      enable row level security;
alter table public.settings      enable row level security;
alter table public.models        enable row level security;
alter table public.model_private enable row level security;
alter table public.content       enable row level security;
alter table public.tasks         enable row level security;
alter table public.prospects     enable row level security;
alter table public.admin_invites enable row level security;

do $$
declare r record;
begin
  for r in select policyname, tablename from pg_policies
           where schemaname = 'public'
             and tablename in ('profiles','settings','models','model_private','content','tasks','prospects','admin_invites')
  loop
    execute format('drop policy if exists %I on public.%I', r.policyname, r.tablename);
  end loop;
end $$;

-- Profils : chacun lit le sien, l'admin lit tout. Les rôles ne changent que via set_role / grant_admin.
create policy profiles_select on public.profiles for select to authenticated
  using (id = (select auth.uid()) or private.is_admin());

-- Invitations admin : visibles et gérables par les admins
create policy admin_invites_admin on public.admin_invites for all to authenticated
  using (private.is_admin()) with check (private.is_admin());

-- Réglages (nom de l'agence) : lisibles par tout compte connecté, modifiables par l'admin
create policy settings_select on public.settings for select to authenticated using (true);
create policy settings_admin on public.settings for all to authenticated
  using (private.is_admin()) with check (private.is_admin());

-- Fiches modèles : l'admin gère tout, une modèle lit uniquement la sienne
create policy models_admin on public.models for all to authenticated
  using (private.is_admin()) with check (private.is_admin());
create policy models_self_select on public.models for select to authenticated
  using (user_id = (select auth.uid()));

-- Notes privées et prospection : admin uniquement
create policy model_private_admin on public.model_private for all to authenticated
  using (private.is_admin()) with check (private.is_admin());
create policy prospects_admin on public.prospects for all to authenticated
  using (private.is_admin()) with check (private.is_admin());

-- Planning : l'admin gère tout, une modèle lit uniquement ses contenus
create policy content_admin on public.content for all to authenticated
  using (private.is_admin()) with check (private.is_admin());
create policy content_self_select on public.content for select to authenticated
  using (model_id in (select private.my_model_ids()));

-- Tâches : l'admin gère tout, une modèle lit uniquement les tâches partagées avec elle
create policy tasks_admin on public.tasks for all to authenticated
  using (private.is_admin()) with check (private.is_admin());
create policy tasks_self_select on public.tasks for select to authenticated
  using (shared and model_id in (select private.my_model_ids()));

-- Accès anonyme : aucun
revoke all on public.profiles, public.settings, public.models, public.model_private,
              public.content, public.tasks, public.prospects, public.admin_invites from anon;
grant select, insert, update, delete on public.settings, public.models, public.model_private,
      public.content, public.tasks, public.prospects, public.admin_invites to authenticated;
revoke insert, update, delete on public.profiles from authenticated;
grant select on public.profiles to authenticated;

-- Nettoyage des anciennes versions de fonctions (si le script a déjà été lancé avant)
drop function if exists public.is_admin();
drop function if exists public.my_model_ids();
drop function if exists public.handle_new_user();
drop function if exists public.link_model_user();
-- ============================================================
--  ofmana v2 : paiements, dépôts de contenus, anti-fuite, IA, stockage de fichiers
-- ============================================================

create table if not exists public.payouts (
  id text primary key,
  model_id text not null references public.models on delete cascade,
  data jsonb not null default '{}',
  created_at timestamptz not null default now()
);

create table if not exists public.submissions (
  id text primary key,
  model_id text not null references public.models on delete cascade,
  data jsonb not null default '{}',
  created_by uuid default auth.uid() references auth.users on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.leaks (
  id text primary key,
  model_id text references public.models on delete cascade,
  data jsonb not null default '{}'
);

create table if not exists public.ai_usage (
  id bigint generated always as identity primary key,
  user_id uuid references auth.users on delete set null,
  kind text,
  tokens int not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists payouts_model_idx on public.payouts (model_id);
create index if not exists submissions_model_idx on public.submissions (model_id);
create index if not exists submissions_created_by_idx on public.submissions (created_by);
create index if not exists leaks_model_idx on public.leaks (model_id);
create index if not exists ai_usage_created_idx on public.ai_usage (created_at);
create index if not exists ai_usage_user_idx on public.ai_usage (user_id);

alter table public.payouts     enable row level security;
alter table public.submissions enable row level security;
alter table public.leaks       enable row level security;
alter table public.ai_usage    enable row level security;

do $$
declare r record;
begin
  for r in select policyname, tablename from pg_policies
           where schemaname = 'public' and tablename in ('payouts','submissions','leaks','ai_usage')
  loop
    execute format('drop policy if exists %I on public.%I', r.policyname, r.tablename);
  end loop;
end $$;

-- Paiements : l'admin gère, la modèle lit les siens
create policy payouts_admin on public.payouts for all to authenticated
  using (private.is_admin()) with check (private.is_admin());
create policy payouts_self_select on public.payouts for select to authenticated
  using (model_id in (select private.my_model_ids()));

-- Dépôts : l'admin gère ; la modèle lit les siens, en crée pour elle-même (statut « envoyé »)
-- et peut retirer un dépôt tant qu'il n'a pas été traité
create policy submissions_admin on public.submissions for all to authenticated
  using (private.is_admin()) with check (private.is_admin());
create policy submissions_self_select on public.submissions for select to authenticated
  using (model_id in (select private.my_model_ids()));
create policy submissions_self_insert on public.submissions for insert to authenticated
  with check (model_id in (select private.my_model_ids()) and data->>'status' = 'envoye'
              and created_by = (select auth.uid()));
create policy submissions_self_delete on public.submissions for delete to authenticated
  using (model_id in (select private.my_model_ids()) and data->>'status' = 'envoye');

-- Anti-fuite : admin uniquement
create policy leaks_admin on public.leaks for all to authenticated
  using (private.is_admin()) with check (private.is_admin());

-- Consommation IA : lecture admin (écriture par la fonction serveur uniquement)
create policy ai_usage_admin_select on public.ai_usage for select to authenticated
  using (private.is_admin());

revoke all on public.payouts, public.submissions, public.leaks, public.ai_usage from anon;
grant select, insert, update, delete on public.payouts, public.submissions, public.leaks to authenticated;
grant select on public.ai_usage to authenticated;

-- ---------- Stockage de fichiers ----------
-- uploads : contenus envoyés par les modèles (dossier = id de la fiche modèle)
-- documents : coffre de l'agence (contrats, pièces), admin uniquement
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('uploads', 'uploads', false, 52428800, array['image/*','video/*']),
       ('documents', 'documents', false, 20971520, null)
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit,
                               allowed_mime_types = excluded.allowed_mime_types;

do $$
declare r record;
begin
  for r in select policyname from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname like 'ofmana_%'
  loop
    execute format('drop policy if exists %I on storage.objects', r.policyname);
  end loop;
end $$;

create policy ofmana_uploads_select on storage.objects for select to authenticated
  using (bucket_id = 'uploads' and (private.is_admin() or (storage.foldername(name))[1] in (select private.my_model_ids())));
create policy ofmana_uploads_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'uploads' and (private.is_admin() or (storage.foldername(name))[1] in (select private.my_model_ids())));
create policy ofmana_uploads_delete on storage.objects for delete to authenticated
  using (bucket_id = 'uploads' and (private.is_admin() or (storage.foldername(name))[1] in (select private.my_model_ids())));
create policy ofmana_documents_admin on storage.objects for all to authenticated
  using (bucket_id = 'documents' and private.is_admin())
  with check (bucket_id = 'documents' and private.is_admin());

-- ---------- Clé OpenAI dans Vault (lecture réservée au serveur) ----------
create or replace function public.app_openai_key() returns text
language sql stable security definer set search_path = '' as $$
  select decrypted_secret from vault.decrypted_secrets
   where name = 'openai_api_key' order by created_at desc limit 1;
$$;
revoke all on function public.app_openai_key() from public, anon, authenticated;
grant execute on function public.app_openai_key() to service_role;
