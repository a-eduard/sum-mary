-- Поддержка: переписка пользователя с командой.
-- direction: 'in' — от пользователя, 'out' — ответ поддержки (приходит из Telegram-бота).
create table if not exists public.support_messages (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  direction     text not null check (direction in ('in', 'out')),
  text          text not null check (length(text) between 1 and 4000),
  meta          jsonb not null default '{}'::jsonb,   -- версия приложения, устройство
  tg_message_id bigint,                               -- id сообщения в чате админа (для ответа реплаем)
  read_at       timestamptz,                          -- когда пользователь прочитал ответ
  created_at    timestamptz not null default now()
);
create index if not exists support_messages_user_idx on public.support_messages (user_id, created_at);
create index if not exists support_messages_tg_idx on public.support_messages (tg_message_id);

alter table public.support_messages enable row level security;
alter table public.support_messages replica identity full;

-- Пользователь видит только свою переписку. Пишет — только через API (сервисная роль),
-- чтобы каждое сообщение гарантированно ушло в Telegram.
drop policy if exists support_select on public.support_messages;
create policy support_select on public.support_messages for select using (user_id = auth.uid());
drop policy if exists support_read on public.support_messages;
create policy support_read on public.support_messages for update using (user_id = auth.uid()) with check (user_id = auth.uid());

revoke all on public.support_messages from anon, authenticated;
grant select on public.support_messages to authenticated;
grant update (read_at) on public.support_messages to authenticated;

do $$ begin
  alter publication supabase_realtime add table public.support_messages;
exception when duplicate_object then null; end $$;
