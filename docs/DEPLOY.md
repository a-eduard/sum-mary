# Развёртывание на VPS Beget

## 1. Сервер и домен
1. Beget → VPS: Ubuntu 24.04, **4 vCPU / 8 ГБ RAM / 80 ГБ NVMe** (минимум).
2. DNS домена sum-mary.ru (A-записи на IP VPS): `@`, `www`, `api`, `db`.
3. На сервере:
```bash
curl -fsSL https://get.docker.com | sh
ufw allow 22,80,443/tcp && ufw enable      # наружу только SSH и HTTPS
```

## 2. Supabase (self-hosted)
```bash
git clone --depth 1 https://github.com/supabase/supabase
mkdir -p ~/sammari && cp -r supabase/docker ~/sammari/supabase && cd ~/sammari/supabase
cp .env.example .env
```
В `.env` обязательно поменять:
- `POSTGRES_PASSWORD`, `JWT_SECRET` (≥32 символа), `ANON_KEY`, `SERVICE_ROLE_KEY` — сгенерировать по инструкции https://supabase.com/docs/guides/self-hosting/docker#generate-api-keys
- `DASHBOARD_USERNAME` / `DASHBOARD_PASSWORD` — вход в Studio
- `SITE_URL=https://sum-mary.ru`, `API_EXTERNAL_URL=https://db.sum-mary.ru`, `SUPABASE_PUBLIC_URL=https://db.sum-mary.ru`
- Почта для кодов входа: `SMTP_HOST/PORT/USER/PASS/SENDER_NAME/ADMIN_EMAIL` (почта Beget на домене, например `noreply@sum-mary.ru`)
- `ENABLE_EMAIL_SIGNUP=true`, `ENABLE_EMAIL_AUTOCONFIRM=false`

Письмо с 6-значным кодом: в `docker-compose.yml` в сервис `auth` → `environment` добавить:
```yaml
GOTRUE_MAILER_TEMPLATES_MAGIC_LINK: https://api.sum-mary.ru/email/code.html
GOTRUE_MAILER_TEMPLATES_CONFIRMATION: https://api.sum-mary.ru/email/code.html
GOTRUE_MAILER_SUBJECTS_MAGIC_LINK: "Код входа в СамМари"
GOTRUE_MAILER_SUBJECTS_CONFIRMATION: "Код входа в СамМари"
GOTRUE_MAILER_OTP_EXP: 600
```
Порты Kong (8000/8443) наружу не открываем — к ним ходит Caddy по внутренней сети.
```bash
docker compose pull && docker compose up -d
```

## 3. Схема базы
Открыть https://db.sum-mary.ru (логин/пароль Dashboard) → SQL Editor → выполнить `supabase/migrations/0001_init.sql`.

## 4. Сервер обработки + сайт
```bash
cd ~/sammari && git clone <ваш GitHub-репозиторий> app && cd app/backend
cp .env.example .env   # заполнить: пароль Postgres, SERVICE_ROLE_KEY, JWT_SECRET, DEEPSEEK_API_KEY
docker compose up -d --build     # первая сборка ~15 мин: скачиваются модели
docker compose logs -f worker
```
Проверка: https://api.sum-mary.ru/health → `{"ok":true}`.

## 5. Приложение
В `app/lib/config.dart` указать `supabaseUrl = https://db.sum-mary.ru` и `anonKey` из `.env` Supabase.

## Обновление
```bash
cd ~/sammari/app && git pull && cd backend && docker compose up -d --build
```
