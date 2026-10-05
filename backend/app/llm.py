"""ИИ Мари: резюме/задачи и чат. Провайдер: DeepSeek напрямую или DeepSeek в Yandex AI Studio (данные в РФ)."""
import json
import re

import requests

from . import config

SUMMARY_PROMPT = """Ты — Мари, ИИ-ассистент приложения СамМари. Тебе дают расшифровку записи (встреча, звонок, лекция или урок).
Расшифровка сделана автоматически: возможны ошибки распознавания, спикеры размечены автоматически и могут быть перепутаны.
{vocab}
Верни СТРОГО JSON без пояснений, такого вида:
{{
  "title": "название записи, до 8 слов",
  "summary": "краткое резюме, 3–7 предложений, по фактам",
  "decisions": ["ключевое решение", ...],
  "tasks": [{{"text": "что сделать", "assignee": "кто или null", "due": "срок как сказали или null"}}],
  "responsibilities": [{{"person": "имя", "area": "за что отвечает"}}],
  "open_questions": ["вопрос", ...],
  "term_fixes": [{{"from": "как распознано", "to": "как правильно"}}]
}}
Правила:
- Только факты из расшифровки, ничего не выдумывай. Нет данных — пустой список или null.
- tasks — только реальные договорённости и поручения.
- responsibilities — кто за какое направление/сервис/тему отвечает, если это прозвучало.
- term_fixes — только явные ошибки распознавания названий, брендов, IT-терминов и англоязычных слов (например «доку сил» → «DocuSeal»). "from" должен дословно встречаться в тексте.
- Пиши по-русски (термины — в оригинальном написании)."""

CHAT_PROMPT = """Ты — Мари, дружелюбный ИИ-ассистент приложения СамМари. Отвечай на вопросы пользователя по расшифровке записи ниже.
Отвечай кратко и по делу, по-русски. Если ответа в расшифровке нет — так и скажи. Указывай таймкоды [мм:сс], где это уместно.

Резюме: {summary}

Расшифровка:
{transcript}"""


def _call(messages, provider: str, json_mode: bool = False, max_tokens: int = 4000) -> tuple[str, str]:
    if provider == "yandex" and config.YC_LLM_API_KEY:
        model = f"gpt://{config.YC_FOLDER_ID}/{config.YC_LLM_MODEL}"
        r = requests.post("https://llm.api.cloud.yandex.net/v1/chat/completions",
                          headers={"Authorization": f"Api-Key {config.YC_LLM_API_KEY}",
                                   "x-folder-id": config.YC_FOLDER_ID},
                          json={"model": model, "messages": messages, "temperature": 0.2,
                                "max_tokens": max(max_tokens, 12000)}, timeout=600)
    else:
        model = config.DEEPSEEK_MODEL
        body = {"model": model, "messages": messages, "temperature": 0.2, "max_tokens": max_tokens}
        if json_mode:
            body["response_format"] = {"type": "json_object"}
        r = requests.post("https://api.deepseek.com/chat/completions",
                          headers={"Authorization": f"Bearer {config.DEEPSEEK_API_KEY}"}, json=body, timeout=600)
    r.raise_for_status()
    return r.json()["choices"][0]["message"]["content"], model


def format_transcript(segments: list[dict], names: dict | None = None) -> str:
    """Склеивает подряд идущие фразы одного спикера: «[мм:сс] Спикер 1: текст»."""
    names = names or {}
    lines, last = [], None
    for s in segments:
        who = names.get(str(s["speaker"])) or f"Спикер {s['speaker']}"
        if last is not None and s["speaker"] == last:
            lines[-1] += " " + s["text"]
        else:
            t = s["start_ms"] // 1000
            lines.append(f"[{t // 60:02d}:{t % 60:02d}] {who}: {s['text']}")
        last = s["speaker"]
    return "\n".join(lines)


def _parse_json(text: str) -> dict:
    text = text.strip()
    m = re.search(r"\{.*\}", text, re.S)
    return json.loads(m.group(0) if m else text)


def summarize(transcript: str, vocabulary: list[str], provider: str = "deepseek") -> tuple[dict, str]:
    vocab = ""
    if vocabulary:
        vocab = "Словарь пользователя (правильное написание терминов, имён и названий): " + ", ".join(vocabulary)
    msgs = [{"role": "system", "content": SUMMARY_PROMPT.format(vocab=vocab)},
            {"role": "user", "content": "Расшифровка:\n\n" + transcript}]
    text, model = _call(msgs, provider, json_mode=True)
    try:
        data = _parse_json(text)
    except Exception:
        data = {"summary": text}
    for k in ("decisions", "tasks", "responsibilities", "open_questions", "term_fixes"):
        if not isinstance(data.get(k), list):
            data[k] = []
    return data, model


def apply_term_fixes(segments: list[dict], fixes: list[dict]) -> list[dict]:
    """Исправляет термины в транскрипте (без учёта регистра, только целые слова)."""
    pairs = [(f["from"], f["to"]) for f in fixes
             if isinstance(f, dict) and f.get("from") and f.get("to") and len(f["from"]) >= 3]
    if not pairs:
        return segments
    for s in segments:
        for a, b in pairs:
            s["text"] = re.sub(rf"(?<!\w){re.escape(a)}(?!\w)", b, s["text"], flags=re.I)
    return segments


def chat(question: str, history: list[dict], transcript: str, summary: str | None, provider: str = "deepseek") -> str:
    msgs = [{"role": "system", "content": CHAT_PROMPT.format(summary=summary or "—", transcript=transcript)}]
    for h in history[-10:]:
        if h.get("role") in ("user", "assistant") and h.get("content"):
            msgs.append({"role": h["role"], "content": h["content"]})
    msgs.append({"role": "user", "content": question})
    text, _ = _call(msgs, provider, max_tokens=1500)
    return text
