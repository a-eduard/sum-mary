"""Локальная проверка пайплайна без базы: python test_local.py путь_к_аудио
Нужны: DEEPSEEK_API_KEY и MODELS_DIR в окружении. Результат — рядом с аудио, *.sammari.json"""
import json
import os
import sys
import time

for k in ("DATABASE_URL", "SUPABASE_URL", "SUPABASE_SERVICE_KEY", "SUPABASE_JWT_SECRET"):
    os.environ.setdefault(k, "local-test")

from app import llm, pipeline  # noqa: E402

t = time.time()
out = pipeline.process_file(sys.argv[1], on_stage=lambda s: print(f"[{time.time() - t:.0f}s] {s}", flush=True))
dst = os.path.splitext(sys.argv[1])[0] + ".sammari.json"
with open(dst, "w", encoding="utf-8") as f:
    json.dump(out, f, ensure_ascii=False, indent=1)
with open(os.path.splitext(sys.argv[1])[0] + ".sammari.txt", "w", encoding="utf-8") as f:
    f.write(llm.format_transcript(out["segments"]))
print(f"done in {time.time() - t:.0f}s, speakers={len({s['speaker'] for s in out['segments']})}, -> {dst}")
