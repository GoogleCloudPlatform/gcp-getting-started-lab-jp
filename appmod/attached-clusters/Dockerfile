# Use golang image as a builder
FROM golang:1.16.5-alpine3.13 as builder

# Create and set workdir
WORKDIR /work

# Copy `go.mod` for definitions and `go.sum` to invalidate the next layer
# in case of a change in the dependencies
COPY go.* ./

# Install git to be used "go mod download"
RUN apk add --no-cache git

# Download dependencies
RUN go mod download

# Copy all files and build an executable
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -v -o /app

# Use a Docker multi-stage build to create a lean production image
FROM alpine:3.13
RUN apk add --no-cache ca-certificates
COPY --from=builder /app /app
ENTRYPOINT ["/app"]
