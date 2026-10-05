FROM python:3.12-slim
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg git curl ca-certificates && rm -rf /var/lib/apt/lists/*
# корневой сертификат Минцифры (нужен для новых доменов RuStore API)
RUN curl -fsSL https://gu-st.ru/content/lending/russian_trusted_root_ca_pem.crt -o /usr/local/share/ca-certificates/russian_trusted_root_ca.crt \
    && update-ca-certificates
ENV REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
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
