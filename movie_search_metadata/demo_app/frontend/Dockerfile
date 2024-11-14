FROM python:3.9-slim

WORKDIR /app

COPY . /app

RUN pip3 install -r requirements.txt

EXPOSE 8080

HEALTHCHECK CMD curl --fail http://localhost:8080/_stcore/health

CMD ["streamlit", "run", "main.py", "--server.port=8080", "--server.address=0.0.0.0"]
