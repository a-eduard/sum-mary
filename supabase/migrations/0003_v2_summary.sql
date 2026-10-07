-- v2: расширенный итог (ключевые пункты с таймкодами, блоки по режиму, даты событий, разборы «Не понял»)
alter table public.summaries add column if not exists key_points jsonb not null default '[]'::jsonb;
alter table public.summaries add column if not exists sections jsonb not null default '[]'::jsonb;
alter table public.summaries add column if not exists events jsonb not null default '[]'::jsonb;
alter table public.summaries add column if not exists explanations jsonb not null default '[]'::jsonb;
alter table public.tasks add column if not exists due_date date;
alter table public.tasks add column if not exists t_sec integer;
alter table public.recordings add column if not exists tz_offset_min integer;
notify pgrst, 'reload schema';
