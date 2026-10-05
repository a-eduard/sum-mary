"""Проверка подписок через RuStore Public API (ключ API из консоли RuStore → Компания → API RuStore)."""
import base64
import time
from datetime import datetime, timezone

import requests
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding

from . import config

# Новый домен RuStore (сертификат Минцифры установлен в образе), старый — запасной.
HOSTS = ["https://public-api-m.rustore.ru", "https://public-api.rustore.ru"]
_token: tuple[str, float] | None = None


def enabled() -> bool:
    return bool(config.RUSTORE_KEY_ID and config.RUSTORE_PRIVATE_KEY)


def _private_key():
    raw = config.RUSTORE_PRIVATE_KEY.strip()
    if "BEGIN" not in raw:
        raw = "-----BEGIN PRIVATE KEY-----\n" + raw + "\n-----END PRIVATE KEY-----"
    return serialization.load_pem_private_key(raw.encode(), password=None)


def _get(path: str, headers: dict) -> requests.Response:
    last = None
    for h in HOSTS:
        try:
            return requests.get(h + path, headers=headers, timeout=30)
        except requests.RequestException as e:
            last = e
    raise last


def _auth() -> str:
    global _token
    if _token and _token[1] > time.time() + 60:
        return _token[0]
    ts = datetime.now(timezone.utc).astimezone().isoformat(timespec="milliseconds")
    sig = _private_key().sign((config.RUSTORE_KEY_ID + ts).encode(), padding.PKCS1v15(), hashes.SHA512())
    body = {"keyId": config.RUSTORE_KEY_ID, "timestamp": ts, "signature": base64.b64encode(sig).decode()}
    last = None
    for h in HOSTS:
        try:
            r = requests.post(h + "/public/auth", json=body, timeout=30)
            j = r.json()
            if j.get("code") == "OK":
                b = j["body"]
                _token = (b["jwe"], time.time() + int(b.get("ttl", 900)))
                return _token[0]
            last = RuntimeError(f"RuStore auth: {j.get('message')}")
        except requests.RequestException as e:
            last = e
    raise last


def subscription(product_id: str, purchase_id: str, sandbox: bool = False) -> dict:
    """Возвращает {'active': bool, 'expires_at': datetime|None, 'raw': dict}."""
    prefix = "/public/sandbox/v4" if sandbox else "/public/v4"
    path = f"{prefix}/subscription/{config.PACKAGE_NAME}/{product_id}/{purchase_id}"
    j = _get(path, {"Public-Token": _auth()}).json()
    body = j.get("body", j)
    exp = body.get("expiryTimeMillis")
    expires = datetime.fromtimestamp(int(exp) / 1000, tz=timezone.utc) if exp else None
    active = j.get("code", "OK") == "OK" and body.get("paymentState") in (1, 2) \
        and expires is not None and expires > datetime.now(timezone.utc)
    return {"active": bool(active), "expires_at": expires, "raw": j}
