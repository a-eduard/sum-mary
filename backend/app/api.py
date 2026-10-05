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


class PurchaseIn(BaseModel):
    purchase_id: str
    product_id: str


@app.post("/billing/rustore")
def billing_rustore(body: PurchaseIn, user_id: str = Depends(current_user)):
    """Включает Pro после покупки в RuStore.
    TODO до публичного запуска: проверять покупку через RuStore Public API (getSubscription по purchase_id)
    и продлевать/отключать по вебхукам RuStore. Сейчас доверяем приложению — подходит только для теста."""
    import json as _json
    days = {"sammari_pro_month": 31, "sammari_pro_year": 366}.get(body.product_id)
    if not days:
        raise HTTPException(400, "Неизвестная подписка")
    with db.conn() as c:
        c.execute(
            "insert into public.purchases (user_id, product_id, purchase_id, status, expires_at, raw) "
            "values (%s,%s,%s,'active', now() + make_interval(days => %s), %s) "
            "on conflict (purchase_id) do update set status='active', expires_at=excluded.expires_at",
            (user_id, body.product_id, body.purchase_id, days, _json.dumps(body.model_dump())),
        )
        c.execute("update public.profiles set plan='pro', plan_expires_at = now() + make_interval(days => %s) where id=%s",
                  (days, user_id))
        c.commit()
    return {"ok": True}
