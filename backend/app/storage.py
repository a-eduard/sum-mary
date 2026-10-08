"""Supabase Storage: скачать и удалить временное аудио (ключ service_role)."""
import requests

from . import config

H = {"Authorization": f"Bearer {config.SUPABASE_SERVICE_KEY}", "apikey": config.SUPABASE_SERVICE_KEY}


def download(path: str, dest: str, bucket: str | None = None):
    url = f"{config.SUPABASE_URL}/storage/v1/object/{bucket or config.AUDIO_BUCKET}/{path}"
    with requests.get(url, headers=H, stream=True, timeout=600) as r:
        r.raise_for_status()
        with open(dest, "wb") as f:
            for chunk in r.iter_content(1 << 20):
                f.write(chunk)


def delete(path: str):
    url = f"{config.SUPABASE_URL}/storage/v1/object/{config.AUDIO_BUCKET}"
    r = requests.delete(url, headers=H, json={"prefixes": [path]}, timeout=60)
    r.raise_for_status()
