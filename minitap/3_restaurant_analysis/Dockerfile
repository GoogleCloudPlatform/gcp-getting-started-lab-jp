FROM python:3.10

EXPOSE 8080
WORKDIR /

COPY . ./

RUN pip install -r requirements.txt
ENTRYPOINT ["python", "app.py", "golf-demo-abr", "golf-demo-abr_cloudbuild"]