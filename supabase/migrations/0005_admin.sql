-- Режим тестировщика (админ): без лимита минут, быстрые переключатели ролей в приложении.
-- Меняется только сервером/вручную: колонка не входит в grant update для authenticated.
alter table public.profiles add column if not exists is_admin boolean not null default false;
notify pgrst, 'reload schema';
