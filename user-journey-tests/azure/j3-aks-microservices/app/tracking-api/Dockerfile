# tracking-api — two-stage build: compile in golang:1.25-alpine, run from a
# distroless static image (no shell, no libc; the binary is fully static).
#
# 1.25 is the floor, not a preference: azcore, azidentity and azcosmos all
# declare `go 1.25.0`, so an older builder refuses the module graph.
#
# Modules are downloaded against the committed go.sum, so the build is
# reproducible and fails rather than drifting if a checksum changes.
FROM golang:1.25-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY main.go ./
COPY internal ./internal
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/tracking-api .

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/tracking-api /tracking-api
ENV PORT=8080
EXPOSE 8080
USER nonroot
ENTRYPOINT ["/tracking-api"]
