{ charts, ... }:
{
  applications.kube-prometheus-stack = {
    namespace = "observability";
    createNamespace = true;

    syncPolicy.syncOptions.serverSideApply = true;

    helm.releases.kube-prometheus-stack = {
      chart = charts.prometheus-community.kube-prometheus-stack;

      values = {
        grafana = {
          enabled = true;
          adminPassword = "admin";
          service = {
            type = "NodePort";
            nodePort = 30300;
          };

          additionalDataSources = [
            {
              name = "Loki";
              type = "loki";
              url = "http://loki.observability:3100";
              access = "proxy";
              isDefault = false;
            }
            {
              name = "Tempo";
              type = "tempo";
              url = "http://tempo.observability:3200";
              access = "proxy";
              isDefault = false;
              jsonData = {
                tracesToLogsV2 = {
                  datasourceUid = "loki";
                  spanStartTimeShift = "-1h";
                  spanEndTimeShift = "1h";
                  filterByTraceID = true;
                  filterBySpanID = false;
                };
                tracesToMetrics.datasourceUid = "prometheus";
                serviceMap.datasourceUid = "prometheus";
                nodeGraph.enabled = true;
                lokiSearch.datasourceUid = "loki";
              };
            }
          ];
        };

        prometheus = {
          service = {
            type = "NodePort";
            nodePort = 30090;
          };
          prometheusSpec = {
            replicas = 1;
            retention = "24h";
            enableRemoteWriteReceiver = true;

            storageSpec = {
              volumeClaimTemplate.spec = {
                accessModes = [ "ReadWriteOnce" ];
                resources.requests.storage = "5Gi";
              };
            };

            serviceMonitorSelectorNilUsesHelmValues = false;
            podMonitorSelectorNilUsesHelmValues = false;
          };
        };

        alertmanager = {
          enabled = true;
          service = {
            type = "NodePort";
            nodePort = 30093;
          };
        };
        nodeExporter.enabled = true;
        kubeStateMetrics.enabled = true;
      };
    };
  };
}
