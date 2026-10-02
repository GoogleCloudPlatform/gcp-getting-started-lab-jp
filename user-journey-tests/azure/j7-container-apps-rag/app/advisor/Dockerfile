# Portfolio explainer image.
#
# Multi-stage so pip's build cache and the wheel directory never reach the
# runtime layer — the image ships the installed packages and nothing else. The
# app runs as a non-root user and listens on $PORT, which the container app sets
# to match its ingress target port.

FROM python:3.12-slim AS build

WORKDIR /wheels
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip \
    && pip wheel --no-cache-dir --wheel-dir /wheels -r requirements.txt

FROM python:3.12-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8000

RUN useradd --create-home --shell /usr/sbin/nologin advisor

WORKDIR /app

COPY --from=build /wheels /wheels
COPY requirements.txt .
RUN pip install --no-cache-dir --no-index --find-links=/wheels -r requirements.txt \
    && rm -rf /wheels

COPY main.py rag.py azure_clients.py ./

USER advisor

EXPOSE 8000

CMD ["sh", "-c", "exec uvicorn main:app --host 0.0.0.0 --port ${PORT}"]
