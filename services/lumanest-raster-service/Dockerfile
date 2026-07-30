FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DEFAULT_TIMEOUT=300 \
    PIP_RETRIES=5

WORKDIR /app

RUN sed -i 's|http://deb.debian.org|https://deb.debian.org|g' /etc/apt/sources.list.d/debian.sources \
    && printf '%s\n' \
      'Acquire::Retries "5";' \
      'Acquire::ForceIPv4 "true";' \
      'Acquire::http::Timeout "60";' \
      'Acquire::https::Timeout "60";' \
      > /etc/apt/apt.conf.d/80-lumanest-network \
    && apt-get update \
    && apt-get install -y --no-install-recommends libexpat1 \
    && rm -rf /var/lib/apt/lists/*

COPY pyproject.toml ./
COPY app ./app
RUN pip install --no-cache-dir .

EXPOSE 8792

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8792"]
