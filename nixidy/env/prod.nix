{ lib, ... }:
{
  imports = [
    ./local/argocd.nix
    ./local/kube-prometheus-stack.nix
    ./local/loki.nix
    ./local/tempo.nix
    ./local/otel-collector.nix
    ./local/traefik.nix
    ./local/grafana-dashboards.nix
    ./local/image-updater.nix
  ];

  nixidy = {
    target = {
      repository = "https://github.com/thirdlf03/microservice-infra";
      branch = "main";
      rootPath = "./manifests/prod";
    };

    defaults = {
      destination.server = "https://kubernetes.default.svc";

      syncPolicy = {
        autoSync = {
          enable = true;
          prune = true;
          selfHeal = true;
        };
      };
    };

    appOfApps = {
      name = "apps";
      namespace = "argocd";
    };
  };

  # Production overrides
  applications.argocd.helm.releases.argocd.values = {
    server = {
      service = {
        type = lib.mkForce "ClusterIP";
        nodePortHttp = lib.mkForce null;
        nodePortHttps = lib.mkForce null;
      };
      extraArgs = lib.mkForce [ ];
    };
    configs.params = {
      "server.insecure" = lib.mkForce false;
    };
  };
}
