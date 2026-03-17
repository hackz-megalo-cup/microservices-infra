{ ... }:
{
  imports = [
    ./local/argocd.nix
    ./local/cilium.nix
    # garage disabled on EKS (using AWS S3 instead)
    # ./local/garage.nix
    ./local/kube-prometheus-stack.nix
    ./local/loki.nix
    ./local/tempo.nix
    # otel-collector and sample-app disabled on EKS (imagePullPolicy: Never)
    # ./local/otel-collector.nix
    # ./local/sample-app.nix
    ./local/traefik.nix
    ./local/grafana-dashboards.nix
    ./local/image-updater.nix
    ./local/cloudflared.nix
    ./local/aws-lb-controller.nix
    ./local/agones.nix
    ./local/kaniko.nix
    ./local/postgresql.nix
    ./local/redpanda.nix
    ./local/reloader.nix
  ];

  nixidy = {
    target = {
      repository = "https://github.com/hackz-megalo-cup/microservices-infra";
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
