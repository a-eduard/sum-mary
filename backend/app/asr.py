"""Распознавание речи: silero VAD режет на фразы ≤22 с, GigaAM-v3 распознаёт каждую."""
import os
import tempfile
import threading

import soundfile as sf
import torch

from . import config
from .audio import SR

_lock = threading.Lock()
_vad = None
_model = None


def _load():
    global _vad, _model
    with _lock:
        if _model is None:
            import gigaam
            from silero_vad import load_silero_vad
            torch.set_num_threads(config.NUM_THREADS)
            _vad = load_silero_vad()
            _model = gigaam.load_model(config.GIGAAM_MODEL, download_root=os.path.join(config.MODELS_DIR, "gigaam"))
    return _vad, _model


def speech_chunks(wav):
    from silero_vad import get_speech_timestamps
    vad, _ = _load()
    return get_speech_timestamps(torch.from_numpy(wav), vad, sampling_rate=SR,
                                 max_speech_duration_s=22, min_silence_duration_ms=300)


def transcribe(wav, on_progress=None) -> list[dict]:
    """Возвращает [{start_ms, end_ms, text}]."""
    _, model = _load()
    chunks = speech_chunks(wav)
    out = []
    fd, tmp = tempfile.mkstemp(suffix=".wav", dir="/dev/shm" if os.path.isdir("/dev/shm") else None)
    os.close(fd)
    try:
        for i, st in enumerate(chunks):
            sf.write(tmp, wav[st["start"]:st["end"]], SR)
            res = model.transcribe(tmp)
            text = (res if isinstance(res, str) else getattr(res, "text", str(res))).strip()
            if text:
                out.append({"start_ms": st["start"] * 1000 // SR, "end_ms": st["end"] * 1000 // SR, "text": text})
            if on_progress and i % 50 == 0:
                on_progress(i, len(chunks))
    finally:
        os.remove(tmp)
    return out
