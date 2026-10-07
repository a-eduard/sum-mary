-- Удаления и изменения доходят до приложения в реальном времени (фильтр по user_id работает и для delete)
alter table public.tasks replica identity full;
alter table public.recordings replica identity full;
alter table public.folders replica identity full;
do $$ begin
  begin alter publication supabase_realtime add table public.folders; exception when duplicate_object then null; end;
end $$;
grant update (events) on public.summaries to authenticated;
drop policy if exists summaries_update on public.summaries;
create policy summaries_update on public.summaries for update using (user_id = auth.uid()) with check (user_id = auth.uid());
update storage.buckets set file_size_limit = 1073741824 where id = 'audio';
-- Вне SQL: в supabase/docker-compose.yml FILE_SIZE_LIMIT=1073741824; в envoy lds.template маршрут /storage/v1/ timeout 900s.
