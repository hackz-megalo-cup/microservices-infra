{ charts, ... }:
{
  applications.tempo = {
    namespace = "observability";
    createNamespace = false; # kube-prometheus-stack が作成

    helm.releases.tempo = {
      chart = charts.grafana.tempo;

      values = {
        tempo = {
          extraEnvFrom = [
            {
              secretRef.name = "garage-s3-credentials";
            }
          ];
          storage = {
            trace = {
              backend = "s3";
              s3 = {
                endpoint = "garage.storage:3900";
                bucket = "tempo-traces";
                region = "garage";
                insecure = true;
                forcepathstyle = true;
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
