# catalog-api — two-stage build: compile in golang:1.24-alpine, run from a
# distroless static image (no shell, no libc; the binary is fully static).
# Base images verified 2026-07. go.mod has zero requires, so the build makes
# no module downloads.
FROM golang:1.24-alpine AS build
WORKDIR /src
COPY go.mod main.go items.json ./
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/catalog-api .

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/catalog-api /catalog-api
ENV PORT=8080
EXPOSE 8080
USER nonroot
ENTRYPOINT ["/catalog-api"]
