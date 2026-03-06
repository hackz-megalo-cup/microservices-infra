_:
let
  labels = {
    "app.kubernetes.io/name" = "sample-app";
    "app.kubernetes.io/version" = "0.1.0";
  };
in
{
  applications.sample-app = {
    namespace = "sample-app";
    createNamespace = true;

    resources = {
      deployments.sample-app.spec = {
        replicas = 1;
        selector.matchLabels = labels;
        template = {
          metadata.labels = labels;
          spec.containers.sample-app = {
            image = "sample-app:latest";
            imagePullPolicy = "Never";
            ports.http.containerPort = 8080;

            env = {
              OTEL_EXPORTER_OTLP_ENDPOINT.value = "http://otel-collector.observability:4317";
              OTEL_SERVICE_NAME.value = "sample-app";
              PORT.value = "8080";
            };

            livenessProbe = {
              httpGet = {
                path = "/health";
                port = 8080;
              };
              initialDelaySeconds = 5;
              periodSeconds = 10;
            };

            readinessProbe = {
              httpGet = {
                path = "/health";
                port = 8080;
              };
              initialDelaySeconds = 3;
              periodSeconds = 5;
            };

            resources = {
              requests = {
                cpu = "50m";
                memory = "64Mi";
              };
              limits = {
                cpu = "200m";
                memory = "128Mi";
              };
            };
          };
        };
      };

      services.sample-app.spec = {
        selector = labels;
        ports.http = {
          port = 80;
          targetPort = 8080;
          protocol = "TCP";
        };
      };
    };
  };
}
