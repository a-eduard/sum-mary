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
    recording_id: str
    question: str
    history: list[dict] = []


@app.get("/health")
def health():
    return {"ok": True}


@app.post("/chat")
def chat(body: ChatIn, user_id: str = Depends(current_user)):
    if not body.question.strip():
        raise HTTPException(400, "Пустой вопрос")
    rec, data = db.get_transcript_for_chat(body.recording_id, user_id)
    if not rec:
        raise HTTPException(404, "Запись не найдена")
    if not data["segments"]:
        raise HTTPException(409, "Запись ещё обрабатывается")
    transcript = llm.format_transcript(data["segments"], rec.get("speaker_names") or {})
    profile = db.get_profile(user_id)
    answer = llm.chat(body.question, body.history, transcript, data["summary"], profile["llm_provider"])
    return {"answer": answer}


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
    result, model = llm.summarize(
        llm.format_transcript(data["segments"], rec.get("speaker_names") or {}), db.get_vocabulary(user_id),
        profile["llm_provider"], mode=body.mode, marks=rec.get("marks") or [],
        recorded_at=rec["recorded_at"].astimezone(tz).replace(tzinfo=None),
        folders=[f["name"] for f in db.get_folders(user_id)])
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
