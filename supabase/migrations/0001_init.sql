-- СамМари: начальная схема. Выполнить в Supabase Studio → SQL Editor (или psql).

-- ============ Профили и тарифы ============
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  plan text not null default 'free' check (plan in ('free','pro')),
  plan_expires_at timestamptz,
  minutes_limit int not null default 30,          -- бесплатный лимит в месяц
  seconds_used int not null default 0,             -- использовано в текущем периоде
  period_start date not null default date_trunc('month', now())::date,
  llm_provider text not null default 'deepseek' check (llm_provider in ('deepseek','yandex')),
  created_at timestamptz not null default now()
);

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, split_part(new.email, '@', 1))
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ============ Папки ============
create table if not exists public.folders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now()
);

-- ============ Записи ============
create table if not exists public.recordings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  folder_id uuid references public.folders(id) on delete set null,
  title text not null default 'Новая запись',
  source text not null default 'mic' check (source in ('mic','call','import','desktop')),
  status text not null default 'uploading'
    check (status in ('uploading','queued','processing','ready','error','limit_exceeded')),
  stage text,                                   -- 'transcribing' | 'diarizing' | 'summarizing'
  error text,
  audio_path text,                              -- путь в bucket audio, очищается после обработки
  local_audio text,                             -- путь к файлу на устройстве (для плеера)
  duration_sec int,
  language text not null default 'ru',
  speaker_names jsonb not null default '{}'::jsonb,  -- {"1":"Сергей","2":"Олег"}
  favorite boolean not null default false,
  recorded_at timestamptz not null default now(),
  processed_at timestamptz,
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index if not exists recordings_user_idx on public.recordings(user_id, recorded_at desc);
create index if not exists recordings_queue_idx on public.recordings(created_at) where status = 'queued';

-- ============ Транскрипт ============
create table if not exists public.segments (
  id bigserial primary key,
  recording_id uuid not null references public.recordings(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  idx int not null,
  speaker int not null default 1,
  start_ms int not null,
  end_ms int not null,
  text text not null
);
create index if not exists segments_rec_idx on public.segments(recording_id, idx);

-- ============ Резюме ============
create table if not exists public.summaries (
  recording_id uuid primary key references public.recordings(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  summary text,
  decisions jsonb not null default '[]'::jsonb,
  open_questions jsonb not null default '[]'::jsonb,
  responsibilities jsonb not null default '[]'::jsonb,   -- [{"person":"Эдуард","area":"Order"}]
  term_fixes jsonb not null default '[]'::jsonb,         -- [{"from":"доку сил","to":"DocuSeal"}]
  model text,
  created_at timestamptz not null default now()
);

-- ============ Задачи ============
create table if not exists public.tasks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  recording_id uuid references public.recordings(id) on delete cascade,
  text text not null,
  assignee text,
  due_text text,
  due_date date,
  done boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists tasks_user_idx on public.tasks(user_id, done, created_at desc);

-- ============ Словарь терминов ============
create table if not exists public.vocabulary (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  term text not null,
  created_at timestamptz not null default now(),
  unique (user_id, term)
);

-- ============ Подписки (RuStore) ============
create table if not exists public.purchases (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  store text not null default 'rustore',
  product_id text not null,
  purchase_id text not null unique,
  status text not null default 'pending' check (status in ('pending','active','cancelled','expired')),
  expires_at timestamptz,
  raw jsonb,
  created_at timestamptz not null default now()
);

-- ============ RLS ============
alter table public.profiles   enable row level security;
alter table public.folders    enable row level security;
alter table public.recordings enable row level security;
alter table public.segments   enable row level security;
alter table public.summaries  enable row level security;
alter table public.tasks      enable row level security;
alter table public.vocabulary enable row level security;
alter table public.purchases  enable row level security;

-- профиль: читать свой; менять только имя (тариф и лимиты меняет сервер)
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select using (id = auth.uid());
drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles for update using (id = auth.uid()) with check (id = auth.uid());
revoke update on public.profiles from authenticated;
grant update (display_name) on public.profiles to authenticated;

do $$
declare t text;
begin
  foreach t in array array['folders','recordings','tasks','vocabulary'] loop
    execute format('drop policy if exists %1$s_all on public.%1$s', t);
    execute format('create policy %1$s_all on public.%1$s for all using (user_id = auth.uid()) with check (user_id = auth.uid())', t);
  end loop;
end $$;

-- транскрипт и резюме пишет сервер; пользователь читает и может править текст/спикера
drop policy if exists segments_select on public.segments;
create policy segments_select on public.segments for select using (user_id = auth.uid());
drop policy if exists segments_update on public.segments;
create policy segments_update on public.segments for update using (user_id = auth.uid()) with check (user_id = auth.uid());
revoke update on public.segments from authenticated;
grant update (text, speaker) on public.segments to authenticated;

drop policy if exists summaries_select on public.summaries;
create policy summaries_select on public.summaries for select using (user_id = auth.uid());

drop policy if exists purchases_select on public.purchases;
create policy purchases_select on public.purchases for select using (user_id = auth.uid());

-- пользователь не может сам поставить статус processing/ready
create or replace function public.guard_recording_status() returns trigger
language plpgsql as $$
begin
  if coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '') = 'authenticated'
     and new.status is distinct from old.status
     and new.status not in ('uploading','queued') then
    raise exception 'status % can be set only by server', new.status;
  end if;
  return new;
end $$;
drop trigger if exists recordings_status_guard on public.recordings;
create trigger recordings_status_guard before update on public.recordings
  for each row execute function public.guard_recording_status();

-- ============ Storage: временное аудио ============
insert into storage.buckets (id, name, public, file_size_limit)
values ('audio', 'audio', false, 524288000)   -- до 500 МБ
on conflict (id) do nothing;

drop policy if exists audio_insert on storage.objects;
create policy audio_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'audio' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists audio_select on storage.objects;
create policy audio_select on storage.objects for select to authenticated
  using (bucket_id = 'audio' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists audio_delete on storage.objects;
create policy audio_delete on storage.objects for delete to authenticated
  using (bucket_id = 'audio' and (storage.foldername(name))[1] = auth.uid()::text);

-- ============ Realtime ============
do $$ begin
  begin alter publication supabase_realtime add table public.recordings; exception when others then null; end;
  begin alter publication supabase_realtime add table public.tasks; exception when others then null; end;
end $$;

-- ============ Поиск по записям ============
create or replace function public.search_recordings(q text)
returns setof public.recordings language sql stable security invoker as $$
  select distinct r.* from public.recordings r
  left join public.segments s on s.recording_id = r.id
  left join public.summaries m on m.recording_id = r.id
  where r.user_id = auth.uid() and r.deleted_at is null
    and (r.title ilike '%'||q||'%' or s.text ilike '%'||q||'%' or m.summary ilike '%'||q||'%')
  order by r.recorded_at desc limit 50;
$$;
