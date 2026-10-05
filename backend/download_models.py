"""Скачивает модели в MODELS_DIR (выполняется при сборке Docker-образа)."""
import os
import tarfile
import urllib.request

M = os.environ.get("MODELS_DIR", "/models")
os.makedirs(M, exist_ok=True)
REL = "https://github.com/k2-fsa/sherpa-onnx/releases/download"


def get(url, dst):
    if not os.path.exists(dst):
        print("download", url, flush=True)
        urllib.request.urlretrieve(url, dst)


seg_tar = os.path.join(M, "seg.tar.bz2")
get(f"{REL}/speaker-segmentation-models/sherpa-onnx-pyannote-segmentation-3-0.tar.bz2", seg_tar)
with tarfile.open(seg_tar) as t:
    t.extractall(M)
get(f"{REL}/speaker-recongition-models/wespeaker_en_voxceleb_resnet34_LM.onnx",
    os.path.join(M, "wespeaker_en_voxceleb_resnet34_LM.onnx"))

import gigaam  # noqa: E402
from silero_vad import load_silero_vad  # noqa: E402

gigaam.load_model(os.environ.get("GIGAAM_MODEL", "v3_e2e_rnnt"), download_root=os.path.join(M, "gigaam"))
load_silero_vad()
print("models ready")
