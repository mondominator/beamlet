FROM golang:1.25-alpine AS builder

WORKDIR /build
COPY go.mod go.sum ./
RUN go mod download
COPY . .
ENV GOTOOLCHAIN=auto
ENV CGO_ENABLED=0
RUN go build -o beamlet .

FROM alpine:3.19

RUN apk add --no-cache ca-certificates imagemagick ffmpeg

WORKDIR /app
COPY --from=builder /build/beamlet .
COPY --from=builder /build/migrations ./migrations

RUN mkdir -p /data/files

EXPOSE 8080

ENTRYPOINT ["/app/beamlet"]
CMD ["serve"]
