# Use golang image as a builder
FROM golang:1.16.3-buster as builder

# Create and set workdir
WORKDIR /app

# Copy `go.mod` for definitions and `go.sum` to invalidate the next layer
# in case of a change in the dependencies
COPY go.mod go.sum ./

# Download dependencies
RUN go mod download

# Copy all files and build an executable
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -v -o gig02_app

# Use a Docker multi-stage build to create a lean production image
FROM gcr.io/distroless/static-debian10
COPY --from=builder /app/gig02_app ./
EXPOSE 8080
ENTRYPOINT ["/gig02_app"]
