{ charts, ... }:
{
  applications.cilium = {
    namespace = "kube-system";

    helm.releases.cilium = {
      chart = charts.cilium.cilium;

      values = {
        # AWS VPC CNI chaining mode — Cilium runs on top of aws-node
        cni = {
          chainingMode = "aws-cni";
          exclusive = false;
        };

        # VPC CNI handles masquerade and routing
        enableIPv4Masquerade = false;
        routingMode = "native";

        # Keep kube-proxy (safe coexistence)
        kubeProxyReplacement = false;

        # Hubble observability
        hubble = {
          enabled = true;
          relay.enabled = true;
          ui.enabled = true;
        };
      };
    };
  };
}
