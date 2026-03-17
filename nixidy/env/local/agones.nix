{ charts, ... }:
{
  applications.agones = {
    namespace = "agones-system";
    createNamespace = true;

    helm.releases.agones = {
      chart = charts.agones.agones;
      values = {
        agones = {
          allocator = {
            service.serviceType = "ClusterIP";
          };

          # Passthrough port range for game servers
          gameservers = {
            minPort = 7000;
            maxPort = 8000;
          };
        };

        # Disable Prometheus ServiceMonitor (already managed by kube-prometheus-stack)
        agones.metrics.prometheusEnabled = false;
      };
    };
  };
}
