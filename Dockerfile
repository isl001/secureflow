FROM python:3.12-slim

# Security fix: the base image still ships a vulnerable zlib1g (CVE-2026-85091, CVE-2026-76844).
# Debian already has the fix (1:1.3.dfsg+really1.3.1-1+deb13u1). Remove this when the base image includes it.
RUN apt-get update \
 && apt-get install -y --no-install-recommends --only-upgrade zlib1g \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app/ ./app/
RUN useradd --uid 10001 --no-create-home appuser
USER appuser

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]