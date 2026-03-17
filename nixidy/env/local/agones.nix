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
          metrics.prometheusEnabled = false;
        };

        # Passthrough port range for game servers (top-level, not under agones)
        gameservers = {
          minPort = 7000;
          maxPort = 8000;
        };
      };
    };
  };
}
