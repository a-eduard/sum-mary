#!/bin/sh
# Настраивает /opt/sammari/supabase/.env под СамМари (запускать на сервере).
set -e
cd /opt/sammari/supabase
cp /opt/sammari/deploy/supabase.override.yml docker-compose.sammari.yml
set_env() { grep -q "^$1=" .env && sed -i "s|^$1=.*|$1=$2|" .env || echo "$1=$2" >> .env; }
set_env COMPOSE_FILE docker-compose.yml:docker-compose.sammari.yml
set_env SUPABASE_PUBLIC_URL https://db.sum-mary.ru
set_env API_EXTERNAL_URL https://db.sum-mary.ru
set_env SITE_URL https://sum-mary.ru
set_env ADDITIONAL_REDIRECT_URLS ""
set_env DASHBOARD_USERNAME eduard
set_env ENABLE_EMAIL_SIGNUP true
set_env ENABLE_EMAIL_AUTOCONFIRM false
set_env ENABLE_ANONYMOUS_USERS false
set_env ENABLE_PHONE_SIGNUP false
set_env DISABLE_SIGNUP false
set_env STUDIO_DEFAULT_ORGANIZATION "СамМари"
set_env STUDIO_DEFAULT_PROJECT "sammari"
# SMTP (почта noreply@sum-mary.ru на Beget) — заполняется отдельно
[ -n "$SMTP_PASS" ] && {
  set_env SMTP_HOST smtp.beget.com
  set_env SMTP_PORT 465
  set_env SMTP_USER noreply@sum-mary.ru
  set_env SMTP_PASS "$SMTP_PASS"
  set_env SMTP_ADMIN_EMAIL noreply@sum-mary.ru
  set_env SMTP_SENDER_NAME "СамМари"
}
echo "supabase .env configured"
