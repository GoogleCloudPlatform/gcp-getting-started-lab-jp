FROM python:3.9-slim

WORKDIR /app

COPY . /app

RUN pip3 install -r requirements.txt

CMD ["fastapi", "run", "main.py", "--port", "8080"]
