_:
let
  labels = {
    "app.kubernetes.io/name" = "cloudflared";
    "app.kubernetes.io/component" = "tunnel";
  };

  tunnelConfig = ''
    tunnel: microservice-infra
    credentials-file: /etc/cloudflared/creds/credentials.json
    metrics: 0.0.0.0:2000
    ingress:
      - hostname: grafana.thirdlf03.com
        service: http://kube-prometheus-stack-grafana.observability:80
      - hostname: hubble.thirdlf03.com
        service: http://hubble-ui.kube-system:80
      - hostname: argocd.thirdlf03.com
        service: http://argocd-server.argocd:80
      - service: http_status:404
  '';
in
{
  applications.cloudflared = {
    namespace = "cloudflare";
    createNamespace = true;

    resources = {
      secrets.tunnel-credentials = {
        stringData."credentials.json" = "PLACEHOLDER — run cloudflared-setup to inject real credentials";
      };

      configMaps.cloudflared-config = {
        data."config.yaml" = tunnelConfig;
      };

      deployments.cloudflared.spec = {
        replicas = 2;
        selector.matchLabels = labels;
        template = {
          metadata.labels = labels;
          spec = {
            containers.cloudflared = {
              image = "cloudflare/cloudflared:latest";
              args = [
                "tunnel"
                "--config"
                "/etc/cloudflared/config/config.yaml"
                "--loglevel"
                "debug"
                "run"
              ];
              ports.metrics.containerPort = 2000;
              volumeMounts = {
                "/etc/cloudflared/config".name = "config";
                "/etc/cloudflared/creds".name = "creds";
              };
              resources = {
                requests = {
                  cpu = "50m";
                  memory = "64Mi";
                };
                limits = {
                  cpu = "200m";
                  memory = "256Mi";
                };
              };
            };
            volumes = {
              config.configMap.name = "cloudflared-config";
              creds.secret.secretName = "tunnel-credentials";
            };
          };
        };
      };
    };
  };
}
