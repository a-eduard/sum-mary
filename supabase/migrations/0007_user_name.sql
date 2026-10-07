-- Имя пользователя и как к нему обращаются: Мари отмечает задачи, поручённые лично ему
alter table public.profiles add column if not exists name_aliases text[] not null default '{}';
grant update (display_name, roles, grade, onboarded, default_mode, name_aliases) on public.profiles to authenticated;
alter table public.tasks add column if not exists for_me boolean not null default false;
notify pgrst, 'reload schema';
