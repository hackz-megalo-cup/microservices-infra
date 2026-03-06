{ charts, ... }:
{
  applications.loki = {
    namespace = "observability";
    createNamespace = false; # kube-prometheus-stack が作成

    helm.releases.loki = {
      chart = charts.grafana.loki;

      values = {
        deploymentMode = "SingleBinary";

        loki = {
          auth_enabled = false;
          commonConfig.replication_factor = 1;

          storage = {
            type = "s3";
            bucketNames = {
              chunks = "loki-chunks";
              ruler = "loki-chunks";
              admin = "loki-chunks";
            };
            s3 = {
              endpoint = "http://garage.storage:3900";
              region = "garage";
              insecure = true;
              s3forcepathstyle = true;
            };
          };

          schemaConfig.configs = [
            {
              from = "2024-01-01";
              store = "tsdb";
              object_store = "s3";
              schema = "v13";
              index = {
                prefix = "loki_index_";
                period = "24h";
              };
            }
          ];
        };

        singleBinary = {
          replicas = 1;
          persistence = {
            enabled = true;
            size = "5Gi";
          };
          extraEnvFrom = [
            {
              secretRef.name = "garage-s3-credentials";
            }
          ];
        };

        read.replicas = 0;
        write.replicas = 0;
        backend.replicas = 0;
        gateway.enabled = false;
        chunksCache.enabled = false;
        resultsCache.enabled = false;
      };
    };
  };
}
