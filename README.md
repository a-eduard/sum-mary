# СамМари (sum-mary.ru)

ИИ-ассистент Мари: записывает встречи, лекции и звонки, делает расшифровку со спикерами, резюме и задачи.

## Структура
- `app/` — Flutter-приложение (Android, Windows; позже iOS/macOS)
- `backend/` — сервер обработки: распознавание GigaAM-v3, разделение спикеров (sherpa-onnx), резюме DeepSeek, API чата с Мари
- `supabase/` — схема базы данных (Supabase self-hosted на VPS Beget)
- `landing/` — лендинг sum-mary.ru
- `docs/` — архитектура и инструкции по развёртыванию

Начать: `docs/ARCHITECTURE.md`, затем `docs/DEPLOY.md`.
