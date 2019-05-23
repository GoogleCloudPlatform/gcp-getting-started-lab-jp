FROM amd64/debian:9.8 as builder
RUN apt-get update && apt-get -y upgrade && apt-get -y install git curl wget gcc
RUN git clone https://github.com/syndbg/goenv.git ~/.goenv
ENV GOENV_ROOT=/root/.goenv
ENV PATH /root/.goenv/bin:/root/.goenv/shims:$PATH
RUN goenv install 1.11.2
RUN goenv global 1.11.2
RUN go get -u cloud.google.com/go/cmd/go-cloud-debug-agent github.com/astaxie/beego github.com/astaxie/beego/context github.com/beego/bee go.opencensus.io/trace contrib.go.opencensus.io/exporter/stackdriver cloud.google.com/go/profiler github.com/sirupsen/logrus
COPY . /root/go/1.11.2/src/devops
RUN cd /root/go/1.11.2/src/devops && go build -gcflags=all='-N -l' -ldflags=-compressdwarf=false ./main.go

FROM amd64/debian:9.8 as production
RUN apt-get update && apt-get -y upgrade && apt-get -y install ca-certificates
COPY --from=builder /root/go/1.11.2/src/devops /root/devops
EXPOSE 8080
CMD cd /root/devops && GOOGLE_APPLICATION_CREDENTIALS=./gcp-credentials/auth.json ./main
