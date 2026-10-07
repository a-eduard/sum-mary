-- v2: режим записи и метки во время записи (Важно / Не понял / фото доски)
alter table public.recordings add column if not exists mode text not null default 'meeting';
alter table public.recordings add column if not exists marks jsonb not null default '[]'::jsonb;
update public.recordings set mode = 'call' where source = 'call' and mode = 'meeting';
notify pgrst, 'reload schema';
