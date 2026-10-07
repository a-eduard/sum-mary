-- v2: роли пользователя, полки (папки) с цветом, подсказка папки от Мари
alter table public.profiles add column if not exists roles text[] not null default '{}';
alter table public.profiles add column if not exists grade int;
alter table public.profiles add column if not exists onboarded boolean not null default false;
alter table public.profiles add column if not exists default_mode text not null default 'meeting';
grant update (display_name, roles, grade, onboarded, default_mode) on public.profiles to authenticated;

alter table public.folders add column if not exists color text not null default '#8B7CFF';
alter table public.folders add column if not exists kind text not null default 'other';
alter table public.folders add column if not exists sort int not null default 0;
alter table public.folders add column if not exists default_mode text;

alter table public.recordings add column if not exists suggested_folder_id uuid references public.folders(id) on delete set null;
notify pgrst, 'reload schema';
