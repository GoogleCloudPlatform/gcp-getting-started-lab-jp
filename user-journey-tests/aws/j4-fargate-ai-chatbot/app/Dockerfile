# syntax=docker/dockerfile:1
# fac-api — multi-stage build, non-root runtime.
# Base image: python:3.12-slim (current stable slim tag, verified 2026-07).

FROM python:3.12-slim AS builder
WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM python:3.12-slim
RUN useradd --create-home --uid 10001 fac
WORKDIR /app
COPY --from=builder /install /usr/local
COPY *.py ./
USER fac
ENV PORT=8000
EXPOSE 8000
# $PORT is honored so the same image runs anywhere the platform injects PORT.
CMD ["sh", "-c", "exec uvicorn main:app --host 0.0.0.0 --port ${PORT:-8000}"]
