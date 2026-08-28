# CareCart backend image
FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# curl: compose healthcheck. tesseract-ocr: the OCR engine pytesseract shells out
# to (medication label scan). No build toolchain needed otherwise
# (psycopg[binary] and grpcio ship manylinux wheels).
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl tesseract-ocr \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt ./
RUN pip install -r requirements.txt

COPY . .

EXPOSE 8000

# entrypoint runs `alembic upgrade head` (unless AUTO_MIGRATE=0), then the CMD.
ENTRYPOINT ["sh", "entrypoint.sh"]

# Dev default. Compose overrides this with --reload.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
