"""Конвертация аудио в wav 16 кГц моно."""
import json
import subprocess

import numpy as np
import soundfile as sf

SR = 16000


def to_wav16k(src: str, dst: str):
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", src,
                    "-ac", "1", "-ar", str(SR), dst], check=True)


def duration_sec(path: str) -> int:
    if path.lower().endswith(".wav"):
        return int(sf.info(path).duration)
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "json", path],
                         check=True, capture_output=True, text=True).stdout
    return int(float(json.loads(out)["format"]["duration"]))


def load(path: str) -> np.ndarray:
    wav, sr = sf.read(path, dtype="float32")
    assert sr == SR, sr
    if wav.ndim > 1:
        wav = wav.mean(axis=1)
    return wav
