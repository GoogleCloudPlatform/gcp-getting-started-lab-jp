# Use the official lightweight Python image.
# https://hub.docker.com/_/python
FROM python:3.11-slim

# Allow statements and log messages to immediately appear in the Knative logs
ENV PYTHONUNBUFFERED True

# Copy local code to the container image.
WORKDIR /app
COPY . .

# Install production dependencies.
RUN pip install -r requirements.txt 

# PORT is overwritten in Cloud Run
ENV PORT 8080
CMD gunicorn --bind 0.0.0.0:$PORT -k uvicorn.workers.UvicornWorker main:app
