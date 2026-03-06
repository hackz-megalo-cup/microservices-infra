FROM golang:1.26-alpine AS builder

RUN go install go.opentelemetry.io/collector/cmd/builder@v0.147.0

WORKDIR /build
COPY builder-config.yaml .

RUN builder --config=builder-config.yaml

RUN CGO_ENABLED=0 go build -C output -ldflags="-s -w" -o /otel-collector .

FROM gcr.io/distroless/static-debian12:nonroot

COPY --from=builder /otel-collector /otel-collector

ENTRYPOINT ["/otel-collector"]
