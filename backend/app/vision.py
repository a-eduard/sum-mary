"""Фото доски и слайдов: распознаём текст, формулы и графики мультимодальной моделью в Yandex AI Studio (данные в РФ).
Результат сохраняется в marks (поле text), чтобы «Сменить тип записи» не распознавал фото заново."""
import base64
import logging
import os
import tempfile
from concurrent.futures import ThreadPoolExecutor

import requests

from . import config, storage

log = logging.getLogger("vision")
PHOTO_BUCKET = "photos"

PROMPT = ("Это фото доски, слайда или тетради с урока/лекции. Перепиши всё содержимое по-русски:\n"
          "1) весь текст и формулы — формулы одной строкой обычными символами (√, ², ⁻¹, λ, θ, ∫, ≈), без LaTeX;\n"
          "2) каждый график и схему: что по осям, какие кривые/элементы, подписи, какую зависимость или вывод показывает;\n"
          "3) таблицы — построчно.\n"
          "Не выдумывай то, чего не видно; неразборчивое помечай [неразборчиво]. Если на фото не учебный материал — "
          "одно предложение, что на нём. Ответ — только содержимое, без вступлений.")


def _describe(path: str) -> str:
    with open(path, "rb") as f:
        b64 = base64.b64encode(f.read()).decode()

    def ask(extra: dict, max_tokens: int) -> str:
        body = {"model": f"gpt://{config.YC_FOLDER_ID}/{config.YC_VISION_MODEL}", "temperature": 0.1,
                "max_tokens": max_tokens,
                "messages": [{"role": "user", "content": [
                    {"type": "text", "text": PROMPT},
                    {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{b64}"}}]}], **extra}
        r = requests.post("https://ai.api.cloud.yandex.net/v1/chat/completions",
                          headers={"Authorization": f"Api-Key {config.YC_LLM_API_KEY}", "OpenAI-Project": config.YC_FOLDER_ID},
                          json=body, timeout=180)
        r.raise_for_status()
        return (r.json()["choices"][0]["message"].get("content") or "").strip()

    # Без «размышлений»: ~2 с на фото, и модель не тратит весь лимит токенов на рассуждения (тогда ответ пустой).
    text = ask({"reasoning_effort": "none"}, 2500)
    if not text:
        text = ask({}, 8000)
    return clean_latex(text)


_TEX = {r"\lambda": "λ", r"\theta": "θ", r"\alpha": "α", r"\beta": "β", r"\gamma": "γ", r"\delta": "δ", r"\Delta": "Δ",
        r"\varphi": "φ", r"\phi": "φ", r"\omega": "ω", r"\Omega": "Ω", r"\pi": "π", r"\mu": "μ", r"\nu": "ν",
        r"\sigma": "σ", r"\epsilon": "ε", r"\varepsilon": "ε", r"\rho": "ρ", r"\tau": "τ", r"\infty": "∞",
        r"\ll": "≪", r"\gg": "≫", r"\le": "≤", r"\leq": "≤", r"\ge": "≥", r"\geq": "≥", r"\approx": "≈", r"\neq": "≠",
        r"\cdot": "·", r"\times": "×", r"\to": "→", r"\rightarrow": "→", r"\int": "∫", r"\sum": "Σ", r"\sqrt": "√",
        r"\partial": "∂", r"\nabla": "∇", r"\pm": "±", r"\sim": "~", r"\hbar": "ħ"}


def clean_latex(s: str) -> str:
    """Модель иногда пишет формулы в LaTeX — переводим в обычные символы."""
    import re
    for k in sorted(_TEX, key=len, reverse=True):
        s = re.sub(re.escape(k) + r"(?![A-Za-z])", _TEX[k], s)
    s = re.sub(r"\\frac\{([^{}]*)\}\{([^{}]*)\}", r"(\1)/(\2)", s)
    s = re.sub(r"\\(?:text|mathrm|mathbf)\{([^{}]*)\}", r"\1", s)
    return s.replace("$", "").replace("\\,", " ")


def read_photos(marks: list[dict]) -> tuple[list[dict], bool]:
    """Возвращает (photos для промпта, изменились ли marks). photos: [{n, t, key, text}]."""
    items = [m for m in marks if m.get("type") == "photo" and m.get("key")]
    if not items or not (config.YC_LLM_API_KEY and config.YC_FOLDER_ID):
        return [{"n": i + 1, "t": m.get("t"), "key": m.get("key"), "text": m.get("text", "")}
                for i, m in enumerate(items)], False

    def work(m):
        if m.get("text"):
            return False
        with tempfile.TemporaryDirectory() as td:
            p = os.path.join(td, "photo.jpg")
            try:
                storage.download(m["key"], p, bucket=PHOTO_BUCKET)
                m["text"] = _describe(p)
            except Exception:
                log.exception("photo %s failed", m.get("key"))
                m["text"] = ""
        return True

    with ThreadPoolExecutor(max_workers=4) as ex:
        changed = any(list(ex.map(work, items)))
    photos = [{"n": i + 1, "t": m.get("t"), "key": m["key"], "text": m.get("text", "")} for i, m in enumerate(items)]
    log.info("photos: %d, recognized: %d", len(photos), sum(1 for p in photos if p["text"]))
    return photos, changed
