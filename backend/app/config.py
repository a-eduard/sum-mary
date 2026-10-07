"""Настройки сервера из переменных окружения (.env)."""
import os


def _env(name: str, default: str | None = None, required: bool = False) -> str:
    v = os.environ.get(name, default)
    if required and not v:
        raise RuntimeError(f"Не задана переменная окружения {name}")
    return v or ""


DATABASE_URL = _env("DATABASE_URL", required=True)          # postgres://postgres:...@db:5432/postgres
SUPABASE_URL = _env("SUPABASE_URL", required=True).rstrip("/")  # https://db.sum-mary.ru
SUPABASE_SERVICE_KEY = _env("SUPABASE_SERVICE_KEY", required=True)
SUPABASE_JWT_SECRET = _env("SUPABASE_JWT_SECRET", required=True)

DEEPSEEK_API_KEY = _env("DEEPSEEK_API_KEY")
DEEPSEEK_MODEL = _env("DEEPSEEK_MODEL", "deepseek-chat")
YC_FOLDER_ID = _env("YC_FOLDER_ID")
YC_LLM_API_KEY = _env("YC_LLM_API_KEY")
YC_LLM_MODEL = _env("YC_LLM_MODEL", "deepseek-v4.1-flash")

MODELS_DIR = _env("MODELS_DIR", "/models")
GIGAAM_MODEL = _env("GIGAAM_MODEL", "v3_e2e_rnnt")
DIARIZATION_THRESHOLD = float(_env("DIARIZATION_THRESHOLD", "0.6"))
NUM_THREADS = int(_env("NUM_THREADS", str(os.cpu_count() or 4)))
POLL_SECONDS = float(_env("POLL_SECONDS", "3"))
# Если задано — worker берёт только записи не длиннее стольких секунд (быстрая полоса).
WORKER_MAX_SEC = int(_env("WORKER_MAX_SEC", "0"))
AUDIO_BUCKET = _env("AUDIO_BUCKET", "audio")

# RuStore Public API — проверка подписок
PACKAGE_NAME = _env("PACKAGE_NAME", "ru.summary.app")
RUSTORE_KEY_ID = _env("RUSTORE_KEY_ID")
RUSTORE_PRIVATE_KEY = _env("RUSTORE_PRIVATE_KEY")
