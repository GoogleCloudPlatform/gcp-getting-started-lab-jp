FROM golang:1.16.3-alpine3.13 AS build
WORKDIR /src
COPY . .
RUN go build -o /out/player .

FROM alpine:3.13 AS bin
COPY --from=build /out/player /player
CMD ["/player"]
