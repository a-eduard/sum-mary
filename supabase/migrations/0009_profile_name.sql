-- Имя пользователя больше не берём из e-mail: «a.eduardmail» — не имя.
-- Имя спрашиваем в приложении (онбординг / карточка на «Сегодня»).
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, nullif(trim(coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', '')), ''))
  on conflict (id) do nothing;
  return new;
end $$;

update public.profiles p set display_name = null
  from auth.users u
 where u.id = p.id and p.display_name = split_part(u.email, '@', 1);

-- В задачах исполнитель «a.eduardmail» → «я» помечено флагом for_me, имя убираем.
update public.tasks t set assignee = null, for_me = true
  from public.recordings r join auth.users u on u.id = r.user_id
 where t.recording_id = r.id and t.assignee = split_part(u.email, '@', 1);
