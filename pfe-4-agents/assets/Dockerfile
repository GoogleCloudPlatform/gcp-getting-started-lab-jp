FROM python:3.11-slim

WORKDIR /app

ENV PYTHONUNBUFFERED=1

COPY requirements.txt .
RUN python -m pip install --upgrade pip setuptools wheel \
  && python -m pip install --no-cache-dir --retries 10 --default-timeout 120 -r requirements.txt

COPY . .

EXPOSE 8080

CMD ["python", "server.py"]
