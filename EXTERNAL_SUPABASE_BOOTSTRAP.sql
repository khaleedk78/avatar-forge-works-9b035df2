-- =============================================================================
-- FULL SCHEMA BOOTSTRAP for the EXTERNAL Supabase project
-- (the one pinned in src/integrations/supabase/client.ts:7 — ref ixkzdnowlbjeiwqzfctu)
--
-- Your external project only has user_roles + the settings tables. The core
-- application tables (characters, images, videos, review_queue, schedules,
-- scene/prompt/intensity templates, ...) were never created there. This script
-- creates the entire schema the app expects.
--
-- Every statement is idempotent — safe to run (and re-run). Run the whole file
-- once in the SQL Editor, then sign out and back in of the app.
-- =============================================================================

-- ----------------------------------------------------------------------------
-- 0) Helpers (no-ops if the settings migration already created them)
-- ----------------------------------------------------------------------------
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

do $$ begin
  create type public.app_role as enum ('admin', 'user');
exception when duplicate_object then null; end $$;

create or replace function public.has_role(_user_id uuid, _role public.app_role)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.user_roles
    where user_id = _user_id and role = _role
  );
$$;

-- ----------------------------------------------------------------------------
-- 1) Enums (final value sets; guarded)
-- ----------------------------------------------------------------------------
do $$ begin
  create type public.content_status as enum
    ('pending','approved','rejected','draft','pending_review','scheduled','published','failed');
exception when duplicate_object then
  -- already exists: make sure the publishing lifecycle values are present
  begin alter type public.content_status add value if not exists 'draft'; exception when others then null; end;
  begin alter type public.content_status add value if not exists 'pending_review'; exception when others then null; end;
  begin alter type public.content_status add value if not exists 'scheduled'; exception when others then null; end;
  begin alter type public.content_status add value if not exists 'published'; exception when others then null; end;
  begin alter type public.content_status add value if not exists 'failed'; exception when others then null; end;
end $$;

do $$ begin create type public.job_type as enum ('image','video'); exception when duplicate_object then null; end $$;
do $$ begin create type public.job_status as enum ('queued','processing','completed','failed'); exception when duplicate_object then null; end $$;
do $$ begin create type public.content_type as enum ('image','video'); exception when duplicate_object then null; end $$;
do $$ begin create type public.schedule_status as enum ('scheduled','published','failed','cancelled'); exception when duplicate_object then null; end $$;
do $$ begin create type public.publishing_platform as enum ('fanvue'); exception when duplicate_object then null; end $$;
do $$ begin create type public.connection_status as enum ('connected','disconnected','error','pending'); exception when duplicate_object then null; end $$;
do $$ begin create type public.publish_status as enum ('draft','pending_review','approved','scheduled','published','failed'); exception when duplicate_object then null; end $$;

-- ----------------------------------------------------------------------------
-- 2) PROFILES
-- ----------------------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  display_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
grant select, insert, update, delete on public.profiles to authenticated;
grant all on public.profiles to service_role;
alter table public.profiles enable row level security;

drop policy if exists "Users can view their own profile" on public.profiles;
create policy "Users can view their own profile"
  on public.profiles for select to authenticated using (auth.uid() = id);
drop policy if exists "Admins can view all profiles" on public.profiles;
create policy "Admins can view all profiles"
  on public.profiles for select to authenticated using (public.has_role(auth.uid(), 'admin'));
drop policy if exists "Users can update their own profile" on public.profiles;
create policy "Users can update their own profile"
  on public.profiles for update to authenticated using (auth.uid() = id);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, display_name)
  values (new.id, new.email, coalesce(new.raw_user_meta_data->>'display_name', new.email))
  on conflict (id) do nothing;
  return new;
end;
$$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users for each row execute function public.handle_new_user();

drop trigger if exists profiles_updated_at on public.profiles;
create trigger profiles_updated_at before update on public.profiles
  for each row execute function public.touch_updated_at();

-- Backfill profiles for any users that already exist
insert into public.profiles (id, email, display_name)
select id, email, coalesce(raw_user_meta_data->>'display_name', email) from auth.users
on conflict (id) do nothing;

-- ----------------------------------------------------------------------------
-- 3) CHARACTERS (full column set the app reads/writes)
-- ----------------------------------------------------------------------------
create table if not exists public.characters (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  biography text,
  personality_traits text[] not null default '{}',
  brand_hashtags text[] not null default '{}',
  reference_images text[] not null default '{}',
  reference_image_url text,
  persona jsonb not null default '{}'::jsonb,
  generation_defaults jsonb not null default '{}'::jsonb,
  memory jsonb not null default '{}'::jsonb,
  consistency jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
-- If the table already existed in a partial form, make sure every column is present:
alter table public.characters
  add column if not exists biography           text,
  add column if not exists brand_hashtags      text[] not null default '{}',
  add column if not exists reference_images    text[] not null default '{}',
  add column if not exists reference_image_url text,
  add column if not exists persona             jsonb not null default '{}'::jsonb,
  add column if not exists generation_defaults jsonb not null default '{}'::jsonb,
  add column if not exists memory              jsonb not null default '{}'::jsonb,
  add column if not exists consistency         jsonb not null default '{}'::jsonb;

grant select, insert, update, delete on public.characters to authenticated;
grant all on public.characters to service_role;
alter table public.characters enable row level security;
drop policy if exists "Admins manage characters" on public.characters;
create policy "Admins manage characters" on public.characters for all to authenticated
  using (public.has_role(auth.uid(), 'admin')) with check (public.has_role(auth.uid(), 'admin'));
drop trigger if exists characters_updated_at on public.characters;
create trigger characters_updated_at before update on public.characters
  for each row execute function public.touch_updated_at();

-- ----------------------------------------------------------------------------
-- 4) CONNECTED ACCOUNTS (referenced by images/videos)
-- ----------------------------------------------------------------------------
create table if not exists public.connected_accounts (
  id uuid primary key default gen_random_uuid(),
  platform public.publishing_platform not null,
  account_name text not null,
  account_identifier text not null,
  connection_status public.connection_status not null default 'pending',
  access_token text,
  last_sync_at timestamptz,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (platform, account_identifier)
);
grant select, insert, update, delete on public.connected_accounts to authenticated;
grant all on public.connected_accounts to service_role;
alter table public.connected_accounts enable row level security;
drop policy if exists "Users can view connected accounts" on public.connected_accounts;
create policy "Users can view connected accounts"
  on public.connected_accounts for select to authenticated using (true);
drop policy if exists "Users can insert their own connected accounts" on public.connected_accounts;
create policy "Users can insert their own connected accounts"
  on public.connected_accounts for insert to authenticated with check (auth.uid() = created_by);
drop policy if exists "Users can update their own connected accounts" on public.connected_accounts;
create policy "Users can update their own connected accounts"
  on public.connected_accounts for update to authenticated using (auth.uid() = created_by);
drop policy if exists "Users can delete their own connected accounts" on public.connected_accounts;
create policy "Users can delete their own connected accounts"
  on public.connected_accounts for delete to authenticated using (auth.uid() = created_by);
drop trigger if exists connected_accounts_updated_at on public.connected_accounts;
create trigger connected_accounts_updated_at before update on public.connected_accounts
  for each row execute function public.touch_updated_at();

-- ----------------------------------------------------------------------------
-- 5) IMAGES / VIDEOS / GENERATION JOBS / REVIEW QUEUE / SCHEDULES
-- ----------------------------------------------------------------------------
create table if not exists public.images (
  id uuid primary key default gen_random_uuid(),
  character_id uuid references public.characters(id) on delete cascade,
  image_url text not null,
  prompt text,
  status public.content_status not null default 'pending',
  connected_account_id uuid references public.connected_accounts(id) on delete set null,
  publish_status public.publish_status not null default 'draft',
  published_at timestamptz,
  external_post_id text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
grant select, insert, update, delete on public.images to authenticated;
grant all on public.images to service_role;
alter table public.images enable row level security;
drop policy if exists "Admins manage images" on public.images;
create policy "Admins manage images" on public.images for all to authenticated
  using (public.has_role(auth.uid(), 'admin')) with check (public.has_role(auth.uid(), 'admin'));
drop trigger if exists images_updated_at on public.images;
create trigger images_updated_at before update on public.images
  for each row execute function public.touch_updated_at();

create table if not exists public.videos (
  id uuid primary key default gen_random_uuid(),
  character_id uuid references public.characters(id) on delete cascade,
  video_url text not null,
  prompt text,
  scene_prompts jsonb not null default '[]'::jsonb,
  status public.content_status not null default 'pending',
  connected_account_id uuid references public.connected_accounts(id) on delete set null,
  publish_status public.publish_status not null default 'draft',
  published_at timestamptz,
  external_post_id text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
grant select, insert, update, delete on public.videos to authenticated;
grant all on public.videos to service_role;
alter table public.videos enable row level security;
drop policy if exists "Admins manage videos" on public.videos;
create policy "Admins manage videos" on public.videos for all to authenticated
  using (public.has_role(auth.uid(), 'admin')) with check (public.has_role(auth.uid(), 'admin'));
drop trigger if exists videos_updated_at on public.videos;
create trigger videos_updated_at before update on public.videos
  for each row execute function public.touch_updated_at();

create table if not exists public.generation_jobs (
  id uuid primary key default gen_random_uuid(),
  type public.job_type not null,
  character_id uuid references public.characters(id) on delete set null,
  input_payload jsonb not null default '{}'::jsonb,
  status public.job_status not null default 'queued',
  output_url text,
  error_message text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
grant select, insert, update, delete on public.generation_jobs to authenticated;
grant all on public.generation_jobs to service_role;
alter table public.generation_jobs enable row level security;
drop policy if exists "Admins manage generation_jobs" on public.generation_jobs;
create policy "Admins manage generation_jobs" on public.generation_jobs for all to authenticated
  using (public.has_role(auth.uid(), 'admin')) with check (public.has_role(auth.uid(), 'admin'));
drop trigger if exists generation_jobs_updated_at on public.generation_jobs;
create trigger generation_jobs_updated_at before update on public.generation_jobs
  for each row execute function public.touch_updated_at();

create table if not exists public.review_queue (
  id uuid primary key default gen_random_uuid(),
  content_type public.content_type not null,
  content_id uuid not null,
  status public.content_status not null default 'pending',
  reviewer_id uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
grant select, insert, update, delete on public.review_queue to authenticated;
grant all on public.review_queue to service_role;
alter table public.review_queue enable row level security;
drop policy if exists "Admins manage review_queue" on public.review_queue;
create policy "Admins manage review_queue" on public.review_queue for all to authenticated
  using (public.has_role(auth.uid(), 'admin')) with check (public.has_role(auth.uid(), 'admin'));
drop trigger if exists review_queue_updated_at on public.review_queue;
create trigger review_queue_updated_at before update on public.review_queue
  for each row execute function public.touch_updated_at();

create table if not exists public.schedules (
  id uuid primary key default gen_random_uuid(),
  content_type public.content_type not null,
  content_id uuid not null,
  publish_time timestamptz not null,
  platform text not null default 'Fanvue',
  status public.schedule_status not null default 'scheduled',
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
grant select, insert, update, delete on public.schedules to authenticated;
grant all on public.schedules to service_role;
alter table public.schedules enable row level security;
drop policy if exists "Admins manage schedules" on public.schedules;
create policy "Admins manage schedules" on public.schedules for all to authenticated
  using (public.has_role(auth.uid(), 'admin')) with check (public.has_role(auth.uid(), 'admin'));
drop trigger if exists schedules_updated_at on public.schedules;
create trigger schedules_updated_at before update on public.schedules
  for each row execute function public.touch_updated_at();

-- ----------------------------------------------------------------------------
-- 6) SCENE / PROMPT / INTENSITY TEMPLATE TABLES (Character Manager)
-- ----------------------------------------------------------------------------
create table if not exists public.scene_templates (
  id uuid primary key default gen_random_uuid(),
  character_id uuid not null references public.characters(id) on delete cascade,
  category text not null,
  label text not null,
  description text,
  intensity text not null default 'SFW',
  prompt text not null default '',
  enabled boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
grant select, insert, update, delete on public.scene_templates to authenticated;
grant all on public.scene_templates to service_role;
alter table public.scene_templates enable row level security;
drop policy if exists "Admins manage scene_templates" on public.scene_templates;
create policy "Admins manage scene_templates" on public.scene_templates for all to authenticated
  using (public.has_role(auth.uid(), 'admin')) with check (public.has_role(auth.uid(), 'admin'));
drop trigger if exists trg_scene_templates_updated on public.scene_templates;
create trigger trg_scene_templates_updated before update on public.scene_templates
  for each row execute function public.touch_updated_at();

create table if not exists public.prompt_templates (
  id uuid primary key default gen_random_uuid(),
  character_id uuid not null references public.characters(id) on delete cascade,
  name text not null,
  prompt text not null default '',
  caption_direction text,
  category text,
  intensity text,
  enabled boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
grant select, insert, update, delete on public.prompt_templates to authenticated;
grant all on public.prompt_templates to service_role;
alter table public.prompt_templates enable row level security;
drop policy if exists "Admins manage prompt_templates" on public.prompt_templates;
create policy "Admins manage prompt_templates" on public.prompt_templates for all to authenticated
  using (public.has_role(auth.uid(), 'admin')) with check (public.has_role(auth.uid(), 'admin'));
drop trigger if exists trg_prompt_templates_updated on public.prompt_templates;
create trigger trg_prompt_templates_updated before update on public.prompt_templates
  for each row execute function public.touch_updated_at();

create table if not exists public.intensity_presets (
  id uuid primary key default gen_random_uuid(),
  character_id uuid not null references public.characters(id) on delete cascade,
  key text not null,
  label text not null,
  prompt_style text,
  caption_style text,
  negative_prompt text,
  description text,
  enabled boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
grant select, insert, update, delete on public.intensity_presets to authenticated;
grant all on public.intensity_presets to service_role;
alter table public.intensity_presets enable row level security;
drop policy if exists "Admins manage intensity_presets" on public.intensity_presets;
create policy "Admins manage intensity_presets" on public.intensity_presets for all to authenticated
  using (public.has_role(auth.uid(), 'admin')) with check (public.has_role(auth.uid(), 'admin'));
drop trigger if exists trg_intensity_presets_updated on public.intensity_presets;
create trigger trg_intensity_presets_updated before update on public.intensity_presets
  for each row execute function public.touch_updated_at();

-- ----------------------------------------------------------------------------
-- 7) INDEXES
-- ----------------------------------------------------------------------------
create index if not exists idx_images_character on public.images(character_id);
create index if not exists idx_images_status on public.images(status);
create index if not exists idx_images_connected_account on public.images(connected_account_id);
create index if not exists idx_images_publish_status on public.images(publish_status);
create index if not exists idx_videos_character on public.videos(character_id);
create index if not exists idx_videos_status on public.videos(status);
create index if not exists idx_videos_connected_account on public.videos(connected_account_id);
create index if not exists idx_videos_publish_status on public.videos(publish_status);
create index if not exists idx_jobs_status on public.generation_jobs(status);
create index if not exists idx_review_status on public.review_queue(status);
create index if not exists idx_schedules_publish_time on public.schedules(publish_time);
create index if not exists scene_templates_character_id_idx on public.scene_templates(character_id);
create index if not exists prompt_templates_character_id_idx on public.prompt_templates(character_id);
create index if not exists intensity_presets_character_id_idx on public.intensity_presets(character_id);

-- ----------------------------------------------------------------------------
-- 8) Make sure your admin user has the 'admin' role
-- ----------------------------------------------------------------------------
insert into public.user_roles (user_id, role)
select id, 'admin'::public.app_role from auth.users where email = 'admin@lilastudio.ai'
on conflict (user_id, role) do nothing;

-- ----------------------------------------------------------------------------
-- 9) Reload PostgREST schema cache
-- ----------------------------------------------------------------------------
notify pgrst, 'reload schema';
