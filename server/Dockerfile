FROM golang:1.25-alpine AS builder

WORKDIR /build
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN go mod tidy
ENV GOTOOLCHAIN=auto
ENV CGO_ENABLED=0
RUN go build -o beamlet .

FROM alpine:3.21

RUN apk add --no-cache ca-certificates imagemagick ffmpeg libheif-tools
RUN adduser -D -u 1001 beamlet

WORKDIR /app
COPY --from=builder /build/beamlet .
COPY --from=builder /build/migrations ./migrations

RUN mkdir -p /data/files && chown -R beamlet:beamlet /data

EXPOSE 8080

USER beamlet

ENTRYPOINT ["/app/beamlet"]
CMD ["serve"]
