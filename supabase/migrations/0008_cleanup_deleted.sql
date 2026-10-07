-- При удалении записи (deleted_at) её задачи удаляются, чтобы не висели на главной и в «Задачах»
delete from public.tasks t using public.recordings r where t.recording_id = r.id and r.deleted_at is not null;
create or replace function public.cleanup_deleted_recording() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.deleted_at is not null and old.deleted_at is null then
    delete from public.tasks where recording_id = new.id;
  end if;
  return new;
end $$;
drop trigger if exists recordings_cleanup on public.recordings;
create trigger recordings_cleanup after update of deleted_at on public.recordings
  for each row execute function public.cleanup_deleted_recording();
