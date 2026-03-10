{ ... }:
{
  imports = [
    ./local/argocd.nix
    ./local/garage.nix
    ./local/kube-prometheus-stack.nix
    ./local/loki.nix
    ./local/tempo.nix
    ./local/otel-collector.nix
    ./local/sample-app.nix
    ./local/traefik.nix
    ./local/grafana-dashboards.nix
    ./local/image-updater.nix
    ./local/cloudflared.nix
    ./local/postgresql.nix
    ./local/redpanda.nix
    ./local/reloader.nix
  ];

  nixidy = {
    target = {
      repository = "https://github.com/thirdlf03/microservice-infra";
      branch = "main";
      rootPath = "./manifests";
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
}
