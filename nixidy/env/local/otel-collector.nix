_:
let
  labels = {
    "app.kubernetes.io/name" = "otel-collector";
    "app.kubernetes.io/component" = "opentelemetry-collector";
  };

  collectorConfig = ''
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318

    processors:
      batch: {}

    exporters:
      prometheusremotewrite:
        endpoint: http://kube-prometheus-stack-prometheus.observability:9090/api/v1/write
      otlp:
        endpoint: tempo.observability:4317
        tls:
          insecure: true
      otlphttp:
        endpoint: http://loki.observability:3100/otlp

    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: [batch]
          exporters: [otlp]
        metrics:
          receivers: [otlp]
          processors: [batch]
          exporters: [prometheusremotewrite]
        logs:
          receivers: [otlp]
          processors: [batch]
          exporters: [otlphttp]
  '';
in
{
  applications.otel-collector = {
    namespace = "observability";
    createNamespace = false;

    resources = {
      configMaps.otel-collector-config = {
        data."config.yaml" = collectorConfig;
      };

      deployments.otel-collector.spec = {
        replicas = 1;
        selector.matchLabels = labels;
        template = {
          metadata.labels = labels;
          spec = {
            containers.otel-collector = {
              image = "otel-collector:latest";
              imagePullPolicy = "Never";
              args = [ "--config=/etc/otelcol/config.yaml" ];
              ports = {
                grpc.containerPort = 4317;
                http.containerPort = 4318;
              };
              volumeMounts = {
                "/etc/otelcol".name = "config";
              };
              resources = {
                requests = {
                  cpu = "100m";
                  memory = "128Mi";
                };
                limits = {
                  cpu = "500m";
                  memory = "512Mi";
                };
              };
            };
            volumes = {
              config.configMap.name = "otel-collector-config";
            };
          };
        };
      };

      services.otel-collector.spec = {
        selector = labels;
        ports = {
          grpc = {
            port = 4317;
            targetPort = 4317;
            protocol = "TCP";
          };
          http = {
            port = 4318;
            targetPort = 4318;
            protocol = "TCP";
          };
        };
      };
    };
  };
}
