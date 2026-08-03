ARG PYTHON_IMAGE=python:3.12-slim@sha256:57cd7c3a7a273101a6485ba99423ee568157882804b1124b4dd04266317710de
FROM ${PYTHON_IMAGE}

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DEFAULT_TIMEOUT=300 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_RETRIES=5

WORKDIR /app
COPY requirements.prod.txt ./
RUN pip install --no-cache-dir --require-hashes --only-binary=:all: -r requirements.prod.txt
COPY pyproject.toml ./
RUN pip install --no-cache-dir --no-deps --no-build-isolation .
COPY alembic.ini ./
COPY alembic ./alembic
COPY app ./app

USER nobody
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
