"""Разделение спикеров на CPU: sherpa-onnx (pyannote segmentation 3.0 + wespeaker), без токенов HuggingFace."""
import os
import threading
from collections import Counter

from . import config

_lock = threading.Lock()
_sd = None

SEG_MODEL = "sherpa-onnx-pyannote-segmentation-3-0/model.onnx"
EMB_MODEL = "wespeaker_en_voxceleb_resnet34_LM.onnx"


def _load():
    global _sd
    with _lock:
        if _sd is None:
            import sherpa_onnx
            m = config.MODELS_DIR
            cfg = sherpa_onnx.OfflineSpeakerDiarizationConfig(
                segmentation=sherpa_onnx.OfflineSpeakerSegmentationModelConfig(
                    pyannote=sherpa_onnx.OfflineSpeakerSegmentationPyannoteModelConfig(
                        model=os.path.join(m, SEG_MODEL)),
                    num_threads=config.NUM_THREADS),
                embedding=sherpa_onnx.SpeakerEmbeddingExtractorConfig(
                    model=os.path.join(m, EMB_MODEL), num_threads=config.NUM_THREADS),
                clustering=sherpa_onnx.FastClusteringConfig(num_clusters=-1, threshold=config.DIARIZATION_THRESHOLD),
                min_duration_on=0.3, min_duration_off=0.5)
            _sd = sherpa_onnx.OfflineSpeakerDiarization(cfg)
    return _sd


def turns(wav) -> list[tuple[float, float, int]]:
    sd = _load()
    return [(r.start, r.end, r.speaker) for r in sd.process(wav).sort_by_start_time()]


def assign(segments: list[dict], turns_: list[tuple[float, float, int]], min_talk_sec: float = 5.0) -> list[dict]:
    """Каждой фразе — спикер с наибольшим перекрытием. Мелкие «спикеры» (<5 с речи) сливаются с соседями.
    Номера перенумеровываются по порядку появления: 1, 2, 3…"""
    talk = Counter()
    for s, e, k in turns_:
        talk[k] += e - s
    small = {k for k, v in talk.items() if v < min_talk_sec}
    prev = None
    for seg in segments:
        a, b = seg["start_ms"] / 1000, seg["end_ms"] / 1000
        ov = Counter()
        for s, e, k in turns_:
            o = min(b, e) - max(a, s)
            if o > 0 and k not in small:
                ov[k] += o
        k = ov.most_common(1)[0][0] if ov else prev
        seg["_spk"] = k if k is not None else 0
        prev = seg["_spk"]
    order = {}
    for seg in segments:
        order.setdefault(seg["_spk"], len(order) + 1)
        seg["speaker"] = order[seg.pop("_spk")]
    return segments
