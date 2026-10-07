"""Работа с Postgres напрямую (сервисная роль, RLS не применяется)."""
import json
from contextlib import contextmanager

import psycopg
from psycopg.rows import dict_row

from . import config


@contextmanager
def conn():
    with psycopg.connect(config.DATABASE_URL, row_factory=dict_row, autocommit=False) as c:
        yield c


def claim_job(max_sec: int = 0):
    """Берёт одну запись из очереди (короткие — первыми). Несколько worker'ов не возьмут одну и ту же.
    max_sec > 0 — только записи с известной длительностью не больше max_sec (быстрая полоса)."""
    with conn() as c:
        row = c.execute(
            """
            update public.recordings set status = 'processing', stage = 'transcribing', error = null
            where id = (
              select id from public.recordings
              where status = 'queued' and deleted_at is null
                and (%(max)s = 0 or (duration_sec is not null and duration_sec <= %(max)s))
              order by coalesce(duration_sec, 1000000), created_at
              for update skip locked
              limit 1)
            returning *
            """, {"max": max_sec}
        ).fetchone()
        c.commit()
        return row


def requeue_stale(hours: int = 2):
    with conn() as c:
        c.execute(
            "update public.recordings set status='queued', stage=null "
            "where status='processing' and created_at < now() - make_interval(hours => %s)",
            (hours,),
        )
        c.commit()


def set_stage(rec_id, stage: str):
    with conn() as c:
        c.execute("update public.recordings set stage=%s where id=%s", (stage, rec_id))
        c.commit()


def set_status(rec_id, status: str, error: str | None = None):
    with conn() as c:
        c.execute(
            "update public.recordings set status=%s, error=%s, stage=null, "
            "processed_at = case when %s='ready' then now() else processed_at end where id=%s",
            (status, error, status, rec_id),
        )
        c.commit()


def get_profile(user_id):
    """Профиль с автосбросом месячного лимита."""
    with conn() as c:
        c.execute(
            "update public.profiles set seconds_used = 0, period_start = date_trunc('month', now())::date "
            "where id = %s and period_start < date_trunc('month', now())::date",
            (user_id,),
        )
        p = c.execute("select * from public.profiles where id=%s", (user_id,)).fetchone()
        c.commit()
        return p


def get_vocabulary(user_id) -> list[str]:
    with conn() as c:
        return [r["term"] for r in c.execute(
            "select term from public.vocabulary where user_id=%s order by created_at", (user_id,))]


def get_folders(user_id) -> list[dict]:
    with conn() as c:
        return c.execute("select id, name from public.folders where user_id=%s order by sort", (user_id,)).fetchall()


def _j(result: dict, key: str) -> str:
    return json.dumps(result.get(key) or [], ensure_ascii=False)


def _date(v):
    """«ГГГГ-ММ-ДД» → date или None (ИИ иногда пишет мусор)."""
    from datetime import date
    try:
        return date.fromisoformat(str(v)[:10]) if v else None
    except ValueError:
        return None


def _write_summary(c, rec, result: dict, model: str):
    """Итог, задачи и подсказка полки (без транскрипта и без учёта минут)."""
    rid, uid = rec["id"], rec["user_id"]
    c.execute(
        """
        insert into public.summaries (recording_id, user_id, summary, decisions, open_questions,
                                      responsibilities, term_fixes, model, key_points, sections, events, explanations)
        values (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
        on conflict (recording_id) do update set summary=excluded.summary, decisions=excluded.decisions,
          open_questions=excluded.open_questions, responsibilities=excluded.responsibilities,
          term_fixes=excluded.term_fixes, model=excluded.model, key_points=excluded.key_points,
          sections=excluded.sections, events=excluded.events, explanations=excluded.explanations, created_at=now()
        """,
        (rid, uid, result.get("summary", ""), _j(result, "decisions"), _j(result, "open_questions"),
         _j(result, "responsibilities"), _j(result, "term_fixes"), model,
         _j(result, "key_points"), _j(result, "sections"), _j(result, "events"), _j(result, "explanations")),
    )
    c.execute("delete from public.tasks where recording_id=%s", (rid,))
    for t in result.get("tasks", []):
        if not t.get("text"):
            continue
        c.execute(
            "insert into public.tasks (user_id, recording_id, text, assignee, due_text, due_date, t_sec, for_me) "
            "values (%s,%s,%s,%s,%s,%s,%s,%s)",
            (uid, rid, t["text"], t.get("assignee"), t.get("due"), _date(t.get("due_date")), t.get("t_sec"),
             bool(t.get("for_me"))),
        )
    if not rec.get("folder_id") and result.get("folder"):
        f = c.execute("select id from public.folders where user_id=%s and lower(name)=lower(%s) limit 1",
                      (uid, str(result["folder"]).strip())).fetchone()
        if f:
            c.execute("update public.recordings set suggested_folder_id=%s where id=%s", (f["id"], rid))


def save_summary(rec, result: dict, model: str, mode: str):
    """Пересборка итога в другом режиме по уже готовой расшифровке."""
    with conn() as c:
        _write_summary(c, rec, result, model)
        c.execute("update public.recordings set mode=%s where id=%s", (mode, rec["id"]))
        c.commit()


def get_segments(rec_id) -> list[dict]:
    with conn() as c:
        return c.execute("select speaker, start_ms, end_ms, text from public.segments where recording_id=%s order by idx",
                         (rec_id,)).fetchall()


def save_results(rec, duration_sec: int, segments: list[dict], result: dict, model: str, mode: str | None = None):
    """Сохраняет транскрипт, резюме и задачи одной транзакцией."""
    rid, uid = rec["id"], rec["user_id"]
    with conn() as c:
        c.execute("delete from public.segments where recording_id=%s", (rid,))
        with c.cursor() as cur:
            cur.executemany(
                "insert into public.segments (recording_id, user_id, idx, speaker, start_ms, end_ms, text) "
                "values (%s,%s,%s,%s,%s,%s,%s)",
                [(rid, uid, i, s["speaker"], s["start_ms"], s["end_ms"], s["text"]) for i, s in enumerate(segments)],
            )
        _write_summary(c, rec, result, model)
        title = result.get("title")
        keep_title = rec.get("title") and rec["title"] != "Новая запись"
        c.execute(
            "update public.recordings set duration_sec=%s, audio_path=null, status='ready', stage=null, "
            "processed_at=now(), title=%s, mode=coalesce(%s, mode) where id=%s",
            (duration_sec, rec["title"] if keep_title or not title else title, mode, rid),
        )
        c.execute("update public.profiles set seconds_used = seconds_used + %s where id=%s", (duration_sec, uid))
        c.commit()


def library_for_chat(user_id, question: str, folder_id=None, limit: int = 40):
    """Итоги последних записей (по полке или всех) + полные расшифровки 2 самых подходящих к вопросу."""
    import re
    with conn() as c:
        where = "r.user_id=%(u)s and r.deleted_at is null and r.status='ready'"
        if folder_id:
            where += " and r.folder_id=%(f)s"
        recs = c.execute(
            f"""select r.id, r.title, r.mode, r.recorded_at, r.speaker_names, s.summary, s.key_points, s.events
                from public.recordings r left join public.summaries s on s.recording_id = r.id
                where {where} order by r.recorded_at desc limit %(n)s""",
            {"u": user_id, "f": folder_id, "n": limit}).fetchall()
        ids = [r["id"] for r in recs]
        words = [w for w in re.findall(r"[\wё]{4,}", question.lower())][:6]
        best = []
        if ids and words:
            best = c.execute(
                """select recording_id, count(*) n from public.segments
                   where recording_id = any(%(ids)s) and text ilike any(%(pats)s)
                   group by recording_id order by n desc limit 2""",
                {"ids": ids, "pats": [f"%{w[:max(4, len(w) - 2)]}%" for w in words]}).fetchall()
        trans = []
        for b in best:
            segs = c.execute("select speaker, start_ms, text from public.segments where recording_id=%s order by idx",
                             (b["recording_id"],)).fetchall()
            rec = next(r for r in recs if r["id"] == b["recording_id"])
            trans.append((rec, segs))
        return recs, trans


def get_transcript_for_chat(rec_id, user_id):
    with conn() as c:
        rec = c.execute(
            "select * from public.recordings where id=%s and user_id=%s and deleted_at is null", (rec_id, user_id)
        ).fetchone()
        if not rec:
            return None, None
        segs = c.execute(
            "select speaker, start_ms, text from public.segments where recording_id=%s order by idx", (rec_id,)
        ).fetchall()
        summ = c.execute("select summary from public.summaries where recording_id=%s", (rec_id,)).fetchone()
        return rec, {"segments": segs, "summary": (summ or {}).get("summary")}
