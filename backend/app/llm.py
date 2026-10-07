"""ИИ Мари: резюме/задачи и чат. Провайдер: DeepSeek напрямую или DeepSeek в Yandex AI Studio (данные в РФ)."""
import json
import re

import requests

from . import config

SUMMARY_PROMPT = """Ты — Мари, ИИ-ассистент приложения СамМари. Тебе дают расшифровку записи.
Расшифровка сделана автоматически: возможны ошибки распознавания, спикеры размечены автоматически и могут быть перепутаны.
Тип записи: {mode_name}. {mode_rules}
Запись сделана: {recorded} ({weekday}). Относительные даты («завтра», «в четверг», «через неделю») считай от этой даты.
{vocab}
{marks}
{folders}
{user}
Верни СТРОГО JSON без пояснений, такого вида:
{{
  "title": "название записи, до 8 слов",
  "folder": "точное название подходящей полки из списка или null",
  "summary": "краткое резюме, 3–7 предложений, по фактам",
  "key_points": [{{"text": "главная мысль / определение / формула / пример", "kind": "definition|formula|example|important|mistake|note", "t": "мм:сс"}}],
  "sections": [{{"title": "название блока", "items": ["пункт", ...]}}],
  "decisions": ["ключевое решение", ...],
  "tasks": [{{"text": "что сделать", "assignee": "кто или null", "due": "срок как сказали или null", "due_date": "ГГГГ-ММ-ДД или null", "for_me": true, "t": "мм:сс"}}],
  "events": [{{"title": "что за событие", "date": "ГГГГ-ММ-ДД", "time": "ЧЧ:ММ или null", "kind": "test|meeting|deadline|homework|other", "t": "мм:сс"}}],
  "explanations": [{{"t": "мм:сс", "topic": "что было непонятно", "answer": "объяснение простыми словами"}}],
  "responsibilities": [{{"person": "имя", "area": "за что отвечает"}}],
  "open_questions": ["вопрос", ...],
  "term_fixes": [{{"from": "как распознано", "to": "как правильно"}}]
}}
Правила:
- Только факты из расшифровки, ничего не выдумывай. Нет данных — пустой список или null.
- "t" — таймкод из расшифровки, где это прозвучало (формат мм:сс или ч:мм:сс). Обязательно для key_points, tasks, events.
- key_points: 3–12 самых важных пунктов. kind: definition — определение термина; formula — формула (пиши в одну строку обычными символами: ∫, √, ², ≤); example — разобранный пример; important — то, что подчеркнули как важное («будет на контрольной», «обратите внимание»); mistake — типичная ошибка; note — прочее.
- tasks — только реальные договорённости, поручения, домашние задания. for_me = true, если задачу поручили пользователю приложения (обратились к нему по имени) или он сам пообещал её сделать; домашнее задание на уроке/лекции — тоже for_me = true; иначе false.
- events — только конкретные даты событий (контрольная, экзамен, встреча, созвон, дедлайн, сдача ДЗ). Без даты — не включай.
- explanations — только для моментов, отмеченных пользователем как «Не понял». Объясни простыми словами, опираясь на расшифровку; если используешь общие знания — это допустимо, но не противоречь сказанному.
- term_fixes — только явные ошибки распознавания названий, брендов, IT-терминов и англоязычных слов. "from" должен дословно встречаться в тексте.
- Пиши по-русски (термины — в оригинальном написании)."""

MODES = {
    "lesson": ("школьный урок", "Это урок в школе. sections: «Домашнее задание», «Что будет на контрольной» (если прозвучало), «Новые термины». В key_points — определения, формулы, разобранные примеры, важное от учителя. Спикер, который объясняет, — учитель."),
    "lecture": ("лекция", "Это лекция в вузе. sections: «План лекции» (темы по порядку), «Литература» (если называли), «Вопросы к экзамену» (если прозвучали). В key_points — определения, формулы, теоремы, примеры, акценты преподавателя."),
    "seminar": ("семинар", "Это семинар. sections: «Разобранные задачи», «Кто что отвечал», «Задано». decisions обычно пустые."),
    "meeting": ("рабочая встреча", "sections: «Ключевые темы», «Риски» (если были). Основное — решения, задачи с ответственными и сроками."),
    "call": ("телефонный звонок", "sections: «О чём договорились», «Следующий шаг». Будь краток."),
    "interview": ("собеседование", "Это собеседование с кандидатом. sections: «Опыт кандидата», «Сильные стороны», «Слабые стороны и риски», «Ответы на ключевые вопросы», «Вопросы кандидата». В summary — общее впечатление без оценочных суждений о личности, только по фактам из разговора."),
    "sales": ("переговоры / продажи", "Это разговор с клиентом. sections: «Потребности клиента», «Возражения», «Бюджет и сроки», «Следующий шаг». tasks — что обещали сделать."),
    "tutor": ("занятие с репетитором", "Это занятие с репетитором. sections: «Что прошли», «Где были ошибки», «Домашнее задание». В key_points — правила, формулы, примеры, типичные ошибки ученика."),
}

WEEKDAYS = ["понедельник", "вторник", "среда", "четверг", "пятница", "суббота", "воскресенье"]

CHAT_PROMPT = """Ты — Мари, дружелюбный ИИ-ассистент приложения СамМари. Отвечай на вопросы пользователя по расшифровке записи ниже.
Отвечай кратко и по делу, по-русски. Если ответа в расшифровке нет — так и скажи. Указывай таймкоды [мм:сс], где это уместно.

Резюме: {summary}

Расшифровка:
{transcript}"""


LIBRARY_PROMPT = """Ты — Мари, ИИ-ассистент приложения СамМари. У пользователя много записей (уроки, лекции, встречи, звонки).
Ниже — краткие итоги его записей{scope} и полные расшифровки самых подходящих к вопросу.
Отвечай по-русски, кратко и по делу, только по этим данным. Если ответа нет — так и скажи.
Всегда указывай, из какой записи факт: «название записи (дата)», а для расшифровок — ещё таймкод [мм:сс].
Если просят подготовиться (тест, вопросы, конспект) — делай это по материалам записей.

ИТОГИ ЗАПИСЕЙ:
{library}

РАСШИФРОВКИ:
{transcripts}"""


def chat_library(question: str, history: list[dict], library: str, transcripts: str, scope: str,
                 provider: str = "deepseek") -> str:
    msgs = [{"role": "system", "content": LIBRARY_PROMPT.format(library=library or "—", transcripts=transcripts or "—",
                                                                 scope=scope)}]
    for h in history[-10:]:
        if h.get("role") in ("user", "assistant") and h.get("content"):
            msgs.append({"role": h["role"], "content": h["content"]})
    msgs.append({"role": "user", "content": question})
    text, _ = _call(msgs, provider, max_tokens=2000)
    return text


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


def _fmt_t(sec: int) -> str:
    return f"{sec // 60:02d}:{sec % 60:02d}"


def parse_t(v) -> int | None:
    """«мм:сс» или «ч:мм:сс» → секунды."""
    if not isinstance(v, str):
        return None
    try:
        parts = [int(x) for x in v.strip().strip("[]").split(":")]
    except ValueError:
        return None
    sec = 0
    for p in parts:
        sec = sec * 60 + p
    return sec


def summarize(transcript: str, vocabulary: list[str], provider: str = "deepseek", mode: str = "meeting",
              marks: list[dict] | None = None, recorded_at=None, folders: list[str] | None = None,
              user_names: list[str] | None = None) -> tuple[dict, str]:
    from datetime import datetime
    vocab = ""
    if vocabulary:
        vocab = "Словарь пользователя (правильное написание терминов, имён и названий): " + ", ".join(vocabulary)
    mode_name, mode_rules = MODES.get(mode, MODES["meeting"])
    rec = recorded_at or datetime.now()
    marks_text = ""
    imp = [m for m in (marks or []) if m.get("type") == "important"]
    unc = [m for m in (marks or []) if m.get("type") == "unclear"]
    if imp:
        marks_text += ("Пользователь во время записи отметил как ВАЖНОЕ моменты около: "
                       + ", ".join(_fmt_t(int(m.get("t", 0))) for m in imp)
                       + ". Обязательно включи сказанное в эти моменты (±30 секунд) в key_points с kind=important.\n")
    if unc:
        marks_text += ("Пользователь отметил «НЕ ПОНЯЛ» в моменты около: "
                       + ", ".join(_fmt_t(int(m.get("t", 0))) for m in unc)
                       + ". Для каждого такого момента добавь пункт в explanations.\n")
    folders_text = ""
    if folders:
        folders_text = ("Полки пользователя (предметы, проекты, клиенты): " + "; ".join(folders)
                        + ". В поле folder верни название той полки, к которой явно относится запись, иначе null.")
    user_text = ""
    names = [n for n in (user_names or []) if n and n.strip()]
    if names:
        user_text = (f"Пользователь приложения (тот, кто записывает): {names[0]}. К нему могут обращаться так: "
                     + ", ".join(names) + ". Если в записи кто-то из спикеров явно он — подпиши в задачах его имя.")
    prompt = SUMMARY_PROMPT.format(mode_name=mode_name, mode_rules=mode_rules, vocab=vocab, marks=marks_text, folders=folders_text,
                                   user=user_text, recorded=rec.strftime("%Y-%m-%d %H:%M"), weekday=WEEKDAYS[rec.weekday()])
    msgs = [{"role": "system", "content": prompt},
            {"role": "user", "content": "Расшифровка:\n\n" + transcript}]
    text, model = _call(msgs, provider, json_mode=True, max_tokens=6000)
    try:
        data = _parse_json(text)
    except Exception:
        data = {"summary": text}
    for k in ("key_points", "sections", "decisions", "tasks", "events", "explanations",
              "responsibilities", "open_questions", "term_fixes"):
        if not isinstance(data.get(k), list):
            data[k] = []
    for k in ("key_points", "tasks", "events", "explanations"):
        for it in data[k]:
            if isinstance(it, dict):
                it["t_sec"] = parse_t(it.get("t"))
    data["events"] = [e for e in data["events"] if isinstance(e, dict) and e.get("date") and e.get("title")]
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
