"""Поддержка: сообщения из приложения → Telegram-бот владельцу; ответ реплаем → пользователю
в приложение (таблица support_messages, realtime) и на почту."""
import html
import logging
import smtplib
from email.message import EmailMessage
from email.utils import formataddr

import requests
from psycopg.types.json import Jsonb

from . import config, db

log = logging.getLogger("support")
TG = "https://api.telegram.org/bot{token}/{method}"


def tg(method: str, **params):
    if not config.TG_BOT_TOKEN:
        raise RuntimeError("TG_BOT_TOKEN не задан")
    r = requests.post(TG.format(token=config.TG_BOT_TOKEN, method=method), json=params, timeout=15)
    data = r.json()
    if not data.get("ok"):
        raise RuntimeError(f"Telegram {method}: {data.get('description')}")
    return data["result"]


def _user_info(c, user_id: str) -> dict:
    return c.execute(
        """
        select u.email, p.display_name, p.is_admin, p.plan, p.seconds_used,
               (select count(*) from public.recordings r where r.user_id = u.id and r.deleted_at is null) as recs
        from auth.users u left join public.profiles p on p.id = u.id where u.id = %s
        """, (user_id,)).fetchone() or {}


def _plan(u: dict) -> str:
    if u.get("is_admin"):
        return "тестировщик"
    return "Pro" if u.get("plan") == "pro" else "бесплатный"


def submit(user_id: str, text: str, meta: dict) -> dict:
    """Сохраняет сообщение пользователя и пересылает его владельцу в Telegram."""
    text = text.strip()[:4000]
    with db.conn() as c:
        u = _user_info(c, user_id)
        row = c.execute(
            "insert into public.support_messages (user_id, direction, text, meta) values (%s, 'in', %s, %s) "
            "returning id, created_at", (user_id, text, Jsonb(meta))).fetchone()
        c.commit()
    who = html.escape(u.get("display_name") or "без имени")
    head = (f"💬 <b>{who}</b> · {html.escape(u.get('email') or '?')}\n"
            f"Тариф: {_plan(u)} · записей: {u.get('recs', 0)} · минут в месяце: {int((u.get('seconds_used') or 0) // 60)}\n"
            f"Приложение {html.escape(str(meta.get('app_version', '?')))} · {html.escape(str(meta.get('device', '?')))}")
    try:
        sent = tg("sendMessage", chat_id=config.TG_ADMIN_CHAT_ID, parse_mode="HTML",
                  text=f"{head}\n\n{html.escape(text)}\n\n<i>Ответьте реплаем — ответ придёт пользователю в приложение и на почту.</i>")
        with db.conn() as c:
            c.execute("update public.support_messages set tg_message_id=%s where id=%s", (sent["message_id"], row["id"]))
            c.commit()
    except Exception:  # сообщение сохранено в базе — не теряем, даже если Telegram недоступен
        log.exception("telegram send failed")
    return {"id": str(row["id"])}


def _send_email(to: str, name: str | None, question: str, answer: str):
    if not (config.SMTP_HOST and config.SMTP_PASS and to):
        return
    m = EmailMessage()
    m["Subject"] = "Ответ поддержки СамМари"
    m["From"] = formataddr(("СамМари", config.SMTP_USER))
    m["To"] = to
    m["Reply-To"] = config.SUPPORT_EMAIL
    hello = f"Здравствуйте, {name}!" if name else "Здравствуйте!"
    m.set_content(f"{hello}\n\n{answer}\n\n— Команда СамМари\n\nВаш вопрос:\n> " + question.replace("\n", "\n> ")
                  + "\n\nОтветить можно прямо в приложении: Профиль → Написать в поддержку.")
    with smtplib.SMTP_SSL(config.SMTP_HOST, config.SMTP_PORT, timeout=20) as s:
        s.login(config.SMTP_USER, config.SMTP_PASS)
        s.send_message(m)


def handle_update(upd: dict):
    """Вебхук Telegram: реплай владельца на сообщение пользователя → ответ пользователю."""
    msg = upd.get("message") or {}
    chat_id = (msg.get("chat") or {}).get("id")
    if str(chat_id) != str(config.TG_ADMIN_CHAT_ID):
        return  # бот отвечает только владельцу; чужие сообщения игнорируем
    text = (msg.get("text") or "").strip()
    reply_to = (msg.get("reply_to_message") or {}).get("message_id")
    if not reply_to:
        if text:
            tg("sendMessage", chat_id=chat_id,
               text="Чтобы ответить пользователю, нажмите на его сообщение → «Ответить» и напишите текст.")
        return
    if not text:
        tg("sendMessage", chat_id=chat_id, reply_to_message_id=msg["message_id"],
           text="Пока можно отвечать только текстом.")
        return
    with db.conn() as c:
        orig = c.execute(
            "select s.user_id, s.text, u.email, p.display_name from public.support_messages s "
            "join auth.users u on u.id = s.user_id left join public.profiles p on p.id = s.user_id "
            "where s.tg_message_id = %s order by s.created_at limit 1", (reply_to,)).fetchone()
        if not orig:
            tg("sendMessage", chat_id=chat_id, reply_to_message_id=msg["message_id"],
               text="Не нашёл, к какому пользователю это относится. Ответьте реплаем на исходное сообщение.")
            return
        c.execute("insert into public.support_messages (user_id, direction, text, tg_message_id) "
                  "values (%s, 'out', %s, %s)", (orig["user_id"], text[:4000], msg["message_id"]))
        c.commit()
    mailed = "и на почту"
    try:
        _send_email(orig["email"], orig["display_name"], orig["text"], text)
    except Exception:
        log.exception("support email failed")
        mailed = "(письмо не ушло — только в приложение)"
    tg("sendMessage", chat_id=chat_id, reply_to_message_id=msg["message_id"],
       text=f"✓ Ответ отправлен в приложение {mailed}.")
