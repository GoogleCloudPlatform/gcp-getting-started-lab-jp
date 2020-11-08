# Use golang image as a builder
FROM golang:1.15.3-alpine3.12 as builder

# Create and set workdir
WORKDIR /app

# Copy `go.mod` for definitions and `go.sum` to invalidate the next layer
# in case of a change in the dependencies
COPY go.mod go.sum ./

# Install git to be used "go mod download"
RUN apk add --no-cache git

# Download dependencies
RUN go mod download

# Copy all files and build an executable
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -v -o devops_handson

# Use a Docker multi-stage build to create a lean production image
FROM alpine:3.12.1
RUN apk add --no-cache ca-certificates
COPY --from=builder /app/devops_handson ./
COPY --from=builder /app/static ./static
EXPOSE 8080
ENTRYPOINT ["/devops_handson"]
