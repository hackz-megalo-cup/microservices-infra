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
          # Game servers already use passthrough ports on the node SG.
          # Disabling the sample UDP ping LB avoids a permanently broken Service on EKS.
          ping.udp.expose = false;
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
