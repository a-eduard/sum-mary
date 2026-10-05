FROM python:3.12-slim
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg git && rm -rf /var/lib/apt/lists/*
WORKDIR /srv
# torch только CPU-версия (без CUDA — образ меньше на ~5 ГБ)
RUN pip install --no-cache-dir torch torchaudio --index-url https://download.pytorch.org/whl/cpu
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
ENV MODELS_DIR=/models
COPY download_models.py .
RUN python download_models.py
COPY app ./app
# по умолчанию — worker; для API в docker-compose переопределяется command
CMD ["python", "-m", "app.worker"]
