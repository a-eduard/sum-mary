"""Worker: берёт записи из очереди и обрабатывает. Запуск: python -m app.worker"""
import logging
import os
import tempfile
import time
import traceback
from datetime import timedelta, timezone
from zoneinfo import ZoneInfo

from . import config, db, pipeline, storage

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
log = logging.getLogger("worker")


PRO_MINUTES = 3000  # Pro: 50 часов в месяц


def quota_ok(profile, duration_sec: int) -> bool:
    from datetime import datetime, timezone
    if profile.get("is_admin"):
        return True  # тестировщик: без лимита
    pro = profile["plan"] == "pro" and (profile["plan_expires_at"] is None
                                        or profile["plan_expires_at"] > datetime.now(timezone.utc))
    limit = PRO_MINUTES if pro else profile["minutes_limit"]
    return profile["seconds_used"] + duration_sec <= limit * 60


def user_names(profile) -> list[str]:
    return [n for n in [profile.get("display_name"), *(profile.get("name_aliases") or [])] if n]


def handle(rec):
    rid = rec["id"]
    log.info("job %s (%s)", rid, rec["audio_path"])
    with tempfile.TemporaryDirectory() as td:
        src = os.path.join(td, "src")
        storage.download(rec["audio_path"], src)
        from .audio import duration_sec
        dur = duration_sec(src)
        profile = db.get_profile(rec["user_id"])
        if not quota_ok(profile, dur):
            storage.delete(rec["audio_path"])
            db.set_status(rid, "limit_exceeded", "Закончились минуты в этом месяце")
            return
        off = rec.get("tz_offset_min")
        tz = timezone(timedelta(minutes=off)) if off is not None else ZoneInfo("Europe/Moscow")
        tz_rec = rec["recorded_at"].astimezone(tz).replace(tzinfo=None)
        out = pipeline.process_file(src, db.get_vocabulary(rec["user_id"]), profile["llm_provider"],
                                    on_stage=lambda s: db.set_stage(rid, s), mode=rec.get("mode") or "meeting",
                                    marks=rec.get("marks") or [], recorded_at=tz_rec,
                                    folders=[f["name"] for f in db.get_folders(rec["user_id"])],
                                    user_names=user_names(profile))
    db.save_results(rec, out["duration_sec"], out["segments"], out["result"], out["model"])
    try:
        storage.delete(rec["audio_path"])
    except Exception:
        log.warning("не удалось удалить аудио %s", rec["audio_path"])
    log.info("job %s ready", rid)


def main():
    if not config.WORKER_MAX_SEC:
        db.requeue_stale()
    log.info("worker started, threads=%s, max_sec=%s", config.NUM_THREADS, config.WORKER_MAX_SEC or "∞")
    while True:
        rec = None
        try:
            rec = db.claim_job(config.WORKER_MAX_SEC)
            if not rec:
                time.sleep(config.POLL_SECONDS)
                continue
            handle(rec)
        except Exception as e:
            log.error("job failed: %s", traceback.format_exc())
            if rec:
                db.set_status(rec["id"], "error", str(e)[:500])
            time.sleep(1)


if __name__ == "__main__":
    main()
