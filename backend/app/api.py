"""HTTP API (api.sum-mary.ru): чат с Мари по записи. Запуск: uvicorn app.api:app"""
import jwt
from fastapi import Depends, FastAPI, Header, HTTPException
from pydantic import BaseModel

from . import config, db, llm

app = FastAPI(title="СамМари API")


def current_user(authorization: str = Header(...)) -> str:
    if not authorization.lower().startswith("bearer "):
        raise HTTPException(401, "Нет токена")
    try:
        claims = jwt.decode(authorization[7:], config.SUPABASE_JWT_SECRET, algorithms=["HS256"],
                            audience="authenticated")
    except jwt.PyJWTError:
        raise HTTPException(401, "Неверный токен")
    return claims["sub"]


class ChatIn(BaseModel):
    recording_id: str | None = None   # чат по одной записи
    folder_id: str | None = None      # по полке; без обоих — по всем записям
    question: str
    history: list[dict] = []


@app.get("/health")
def health():
    return {"ok": True}


# ---------- поддержка ----------
class SupportIn(BaseModel):
    text: str
    app_version: str | None = None
    device: str | None = None


@app.post("/support")
def support_send(body: SupportIn, user_id: str = Depends(current_user)):
    from . import support
    text = body.text.strip()
    if not text:
        raise HTTPException(400, "Пустое сообщение")
    with db.conn() as c:
        n = c.execute("select count(*) as n from public.support_messages where user_id=%s and direction='in' "
                      "and created_at > now() - interval '1 hour'", (user_id,)).fetchone()["n"]
    if n >= 20:
        raise HTTPException(429, "Слишком много сообщений. Мы уже читаем предыдущие — ответим скоро.")
    return support.submit(user_id, text, {"app_version": body.app_version, "device": body.device})


@app.post("/tg/{secret}")
def tg_webhook(secret: str, update: dict,
               x_telegram_bot_api_secret_token: str | None = Header(None)):
    from . import support
    ok = config.TG_WEBHOOK_SECRET and secret == config.TG_WEBHOOK_SECRET \
        and x_telegram_bot_api_secret_token == config.TG_WEBHOOK_SECRET
    if not ok:
        raise HTTPException(404)
    try:
        support.handle_update(update)
    except Exception:
        import logging
        logging.getLogger("support").exception("tg update failed")
    return {"ok": True}  # всегда 200, иначе Telegram будет слать повторно


@app.post("/chat")
def chat(body: ChatIn, user_id: str = Depends(current_user)):
    if not body.question.strip():
        raise HTTPException(400, "Пустой вопрос")
    if not body.recording_id:
        return {"answer": _chat_library(body, user_id)}
    rec, data = db.get_transcript_for_chat(body.recording_id, user_id)
    if not rec:
        raise HTTPException(404, "Запись не найдена")
    if not data["segments"]:
        raise HTTPException(409, "Запись ещё обрабатывается")
    transcript = llm.format_transcript(data["segments"], rec.get("speaker_names") or {})
    profile = db.get_profile(user_id)
    answer = llm.chat(body.question, body.history, transcript, data["summary"], profile["llm_provider"])
    return {"answer": answer}


def _chat_library(body: ChatIn, user_id: str) -> str:
    recs, trans = db.library_for_chat(user_id, body.question, body.folder_id)
    if not recs:
        return "Пока нет готовых записей — запишите урок или встречу, и я смогу отвечать по ним."
    lines = []
    for r in recs:
        kp = "; ".join(k.get("text", "") for k in (r.get("key_points") or [])[:8] if isinstance(k, dict))
        ev = "; ".join(f'{e.get("title")} {e.get("date")}' for e in (r.get("events") or []) if isinstance(e, dict))
        lines.append(f'• «{r["title"]}» ({r["recorded_at"]:%d.%m.%Y}, {r["mode"]}): {r.get("summary") or ""}'
                     + (f" Главное: {kp}." if kp else "") + (f" Даты: {ev}." if ev else ""))
    library = "\n".join(lines)[:60000]
    transcripts = "\n\n".join(f'=== «{r["title"]}» ({r["recorded_at"]:%d.%m.%Y}) ===\n'
                               + llm.format_transcript(segs, r.get("speaker_names") or {}) for r, segs in trans)[:60000]
    scope = " с полки" if body.folder_id else ""
    profile = db.get_profile(user_id)
    return llm.chat_library(body.question, body.history, library, transcripts, scope, profile["llm_provider"])


class PrepareIn(BaseModel):
    kind: str                       # quiz | cards | tickets
    recording_id: str | None = None
    folder_id: str | None = None
    tickets: str = ""
    count: int = 10


@app.post("/prepare")
def prepare(body: PrepareIn, user_id: str = Depends(current_user)):
    """Подготовка: тест, карточки или ответы на билеты — по записи, по полке или по всем записям."""
    if body.kind not in llm.PREP_PROMPTS:
        raise HTTPException(400, "Неизвестный вид подготовки")
    if body.kind == "tickets" and not body.tickets.strip():
        raise HTTPException(400, "Добавьте список билетов")
    if body.recording_id:
        rec, data = db.get_transcript_for_chat(body.recording_id, user_id)
        if not rec or not data["segments"]:
            raise HTTPException(404, "Запись не найдена или ещё обрабатывается")
        materials = (f'=== «{rec["title"]}» ({rec["recorded_at"]:%d.%m.%Y}) ===\nИтог: {data["summary"] or ""}\n'
                     + llm.format_transcript(data["segments"], rec.get("speaker_names") or {}))[:120000]
    else:
        recs, _ = db.library_for_chat(user_id, "", body.folder_id, limit=60)
        if not recs:
            raise HTTPException(404, "Нет готовых записей")
        parts = []
        for r in recs:
            kp = "\n".join(f'- [{k.get("t") or ""}] {k.get("text", "")}' for k in (r.get("key_points") or []) if isinstance(k, dict))
            parts.append(f'=== «{r["title"]}» ({r["recorded_at"]:%d.%m.%Y}) ===\n{r.get("summary") or ""}\n{kp}')
        materials = "\n\n".join(parts)
        if body.kind == "tickets":
            # для билетов добавляем полные тексты, пока помещаются
            for r in recs:
                if len(materials) > 110000:
                    break
                segs = db.get_segments(r["id"])
                materials += f'\n\n=== Расшифровка «{r["title"]}» ({r["recorded_at"]:%d.%m.%Y}) ===\n' + llm.format_transcript(
                    segs, r.get("speaker_names") or {})
        materials = materials[:120000]
    profile = db.get_profile(user_id)
    items = llm.prepare(body.kind, materials, max(3, min(body.count, 20)), body.tickets, profile["llm_provider"])
    if not items:
        raise HTTPException(502, "Мари не смогла подготовить материалы — попробуйте ещё раз")
    return {"items": items}


class ResummarizeIn(BaseModel):
    recording_id: str
    mode: str


@app.post("/resummarize")
def resummarize(body: ResummarizeIn, user_id: str = Depends(current_user)):
    """Пересобрать итог в другом режиме (урок → лекция и т. п.) без повторной расшифровки."""
    from datetime import timedelta, timezone
    from zoneinfo import ZoneInfo
    if body.mode not in llm.MODES:
        raise HTTPException(400, "Неизвестный режим")
    rec, data = db.get_transcript_for_chat(body.recording_id, user_id)
    if not rec:
        raise HTTPException(404, "Запись не найдена")
    if not data["segments"]:
        raise HTTPException(409, "Запись ещё обрабатывается")
    off = rec.get("tz_offset_min")
    tz = timezone(timedelta(minutes=off)) if off is not None else ZoneInfo("Europe/Moscow")
    profile = db.get_profile(user_id)
    from . import vision
    marks = rec.get("marks") or []
    photos, changed = vision.read_photos(marks)  # уже распознанные фото берутся из marks
    if changed:
        db.set_marks(rec["id"], marks)
    result, model = llm.summarize(
        llm.format_transcript(data["segments"], rec.get("speaker_names") or {}), db.get_vocabulary(user_id),
        profile["llm_provider"], mode=body.mode, marks=marks,
        recorded_at=rec["recorded_at"].astimezone(tz).replace(tzinfo=None),
        folders=[f["name"] for f in db.get_folders(user_id)],
        user_names=[n for n in [profile.get("display_name"), *(profile.get("name_aliases") or [])] if n],
        photos=photos, duration_sec=rec.get("duration_sec"))
    db.save_summary(rec, result, model, body.mode)
    return {"ok": True}


class PurchaseIn(BaseModel):
    purchase_id: str
    product_id: str
    sandbox: bool = False


PRODUCTS = {"sammari_pro_month": 31, "sammari_pro_year": 366}


@app.post("/billing/rustore")
def billing_rustore(body: PurchaseIn, user_id: str = Depends(current_user)):
    """Включает/продлевает Pro после покупки в RuStore.
    Если задан ключ RuStore API — срок берём из RuStore (проверенная покупка).
    Без ключа (только для теста) — доверяем приложению и даём срок по продукту."""
    import json as _json
    from datetime import datetime, timedelta, timezone

    from . import rustore
    if body.product_id not in PRODUCTS:
        raise HTTPException(400, "Неизвестная подписка")
    if rustore.enabled():
        try:
            info = rustore.subscription(body.product_id, body.purchase_id, body.sandbox)
        except Exception as e:
            raise HTTPException(502, f"RuStore недоступен: {e}")
        if not info["active"]:
            raise HTTPException(402, "Подписка не оплачена или истекла")
        expires, raw, verified = info["expires_at"], info["raw"], True
    else:
        expires = datetime.now(timezone.utc) + timedelta(days=PRODUCTS[body.product_id])
        raw, verified = body.model_dump(), False
    with db.conn() as c:
        owner = c.execute("select user_id from public.purchases where purchase_id=%s", (body.purchase_id,)).fetchone()
        if owner and str(owner["user_id"]) != user_id:
            raise HTTPException(409, "Покупка привязана к другому аккаунту")
        c.execute(
            "insert into public.purchases (user_id, product_id, purchase_id, status, expires_at, raw) "
            "values (%s,%s,%s,'active',%s,%s) "
            "on conflict (purchase_id) do update set status='active', expires_at=excluded.expires_at, raw=excluded.raw",
            (user_id, body.product_id, body.purchase_id, expires,
             _json.dumps({"verified": verified, "data": raw}, ensure_ascii=False, default=str)),
        )
        c.execute("update public.profiles set plan='pro', plan_expires_at=greatest(coalesce(plan_expires_at, now()), %s) "
                  "where id=%s", (expires, user_id))
        c.commit()
    return {"ok": True, "expires_at": expires.isoformat(), "verified": verified}
