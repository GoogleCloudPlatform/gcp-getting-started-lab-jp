FROM python:3.12-slim

WORKDIR /srv

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY policyapi/ policyapi/

ENV PORT=8080
EXPOSE 8080

CMD ["sh", "-c", "uvicorn policyapi.api:app --host 0.0.0.0 --port ${PORT}"]
