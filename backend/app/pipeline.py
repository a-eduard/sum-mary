"""Полная обработка записи: аудио → текст → спикеры → резюме."""
import logging
import os
import tempfile

from . import asr, audio, diarize, llm

log = logging.getLogger("pipeline")


def process_file(path: str, vocabulary: list[str] | None = None, provider: str = "deepseek",
                 on_stage=lambda s: None, mode: str = "meeting", marks: list[dict] | None = None,
                 recorded_at=None, folders: list[str] | None = None, user_names: list[str] | None = None,
                 photos: list[dict] | None = None) -> dict:
    """Обрабатывает локальный аудиофайл. Используется и worker'ом, и локальным тестом."""
    with tempfile.TemporaryDirectory() as td:
        wav_path = os.path.join(td, "a.wav")
        audio.to_wav16k(path, wav_path)
        dur = audio.duration_sec(wav_path)
        wav = audio.load(wav_path)

        on_stage("transcribing")
        segs = asr.transcribe(wav, on_progress=lambda i, n: log.info("asr %d/%d", i, n))
        log.info("asr done: %d segments", len(segs))

        on_stage("diarizing")
        if segs:
            segs = diarize.assign(segs, diarize.turns(wav))
        log.info("speakers: %d", len({s["speaker"] for s in segs}))

    on_stage("summarizing")
    if segs and mode == "auto":
        mode = llm.detect_mode(llm.format_transcript(segs), provider)
    if segs:
        result, model = llm.summarize(llm.format_transcript(segs), vocabulary or [], provider,
                                      mode=mode, marks=marks, recorded_at=recorded_at, folders=folders,
                                      user_names=user_names, photos=photos, duration_sec=dur)
        segs = llm.apply_term_fixes(segs, result.get("term_fixes", []))
    else:
        result, model = {"title": "Речи не слышно",
                          "summary": "Мари не услышала в записи речи. Проверьте, что микрофон не закрыт, "
                                     "и положите телефон ближе к говорящему. Эту запись можно удалить.",
                          "tasks": []}, "-"
    return {"duration_sec": dur, "segments": segs, "result": result, "model": model,
            "mode": mode if mode != "auto" else "meeting"}
