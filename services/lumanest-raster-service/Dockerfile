FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends libexpat1 \
    && rm -rf /var/lib/apt/lists/*

COPY pyproject.toml ./
COPY app ./app
RUN pip install --default-timeout=300 --retries=5 --no-cache-dir .

EXPOSE 8792

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8792"]
