{ charts, ... }:
{
  applications.tempo = {
    namespace = "observability";
    createNamespace = false; # kube-prometheus-stack が作成

    helm.releases.tempo = {
      chart = charts.grafana.tempo;

      values = {
        tempo = {
          storage = {
            trace = {
              backend = "s3";
              s3 = {
                bucket = "microservices-infra-eks-obs";
                region = "ap-northeast-1";
              };
              wal.path = "/var/tempo/wal";
            };
          };

          receivers = {
            otlp = {
              protocols = {
                grpc.endpoint = "0.0.0.0:4317";
                http.endpoint = "0.0.0.0:4318";
              };
            };
          };

          metricsGenerator = {
            enabled = true;
            remoteWriteUrl = "http://kube-prometheus-stack-prometheus.observability:9090/api/v1/write";
          };
        };

        persistence = {
          enabled = true;
          size = "5Gi";
        };
      };
    };
  };
}
