{ charts, ... }:
{
  applications.traefik = {
    namespace = "edge";
    createNamespace = true;

    helm.releases.traefik = {
      chart = charts.traefik.traefik;
      values = {
        image.tag = "v3.6.9";

        service = {
          type = "LoadBalancer";
          annotations = {
            "service.beta.kubernetes.io/aws-load-balancer-type" = "external";
            "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip";
            "service.beta.kubernetes.io/aws-load-balancer-scheme" = "internet-facing";
            "service.beta.kubernetes.io/aws-load-balancer-ssl-cert" =
              "arn:aws:acm:ap-northeast-1:860973283109:certificate/20647860-8ce1-4fa2-9578-fe5a197d3108";
            "service.beta.kubernetes.io/aws-load-balancer-ssl-ports" = "443";
            "service.beta.kubernetes.io/aws-load-balancer-target-group-attributes" = "stickiness.enabled=false";
          };
        };

        ports = {
          # Service port 443 → container port 8000 (web entrypoint)
          # NLB terminates TLS on 443, forwards plain TCP to Traefik 8000
          web.exposedPort = 443;
          websecure.expose.default = false;
        };

        providers = {
          kubernetesCRD.enabled = true;
          kubernetesIngress.enabled = true;
        };

        logs.general.level = "INFO";

        tracing = {
          otlp = {
            grpc = {
              enabled = true;
              endpoint = "otel-collector.observability:4317";
              insecure = true;
            };
          };
        };

        extraObjects = [
          # The microservices namespace is owned by the service manifests repo.
          {
            apiVersion = "traefik.io/v1alpha1";
            kind = "Middleware";
            metadata = {
              name = "cors-middleware";
              namespace = "microservices";
            };
            spec.headers = {
              accessControlAllowMethods = [
                "GET"
                "POST"
                "OPTIONS"
              ];
              accessControlAllowHeaders = [
                "Content-Type"
                "Authorization"
                "Connect-Protocol-Version"
                "Connect-Timeout-Ms"
                "Grpc-Timeout"
                "X-Grpc-Web"
                "X-User-Agent"
                "Idempotency-Key"
              ];
              accessControlAllowOriginList = [
                "http://localhost:5173"
                "https://app.thirdlf03.com"
              ];
              accessControlExposeHeaders = [
                "Grpc-Status"
                "Grpc-Message"
                "Grpc-Status-Details-Bin"
              ];
              accessControlMaxAge = 7200;
              addVaryHeader = true;
            };
          }
          {
            apiVersion = "traefik.io/v1alpha1";
            kind = "Middleware";
            metadata = {
              name = "rate-limit-middleware";
              namespace = "microservices";
            };
            spec.rateLimit = {
              average = 100;
              burst = 50;
            };
          }
          {
            apiVersion = "traefik.io/v1alpha1";
            kind = "IngressRoute";
            metadata = {
              name = "greeter-route";
              namespace = "microservices";
            };
            spec = {
              entryPoints = [ "web" ];
              routes = [
                {
                  match = "PathPrefix(`/greeter.v1.GreeterService`)";
                  kind = "Rule";
                  priority = 100;
                  middlewares = [
                    { name = "cors-middleware"; }
                    { name = "rate-limit-middleware"; }
                  ];
                  services = [
                    {
                      name = "greeter-service";
                      port = 80;
                      scheme = "h2c";
                    }
                  ];
                }
              ];
            };
          }
          {
            apiVersion = "traefik.io/v1alpha1";
            kind = "IngressRoute";
            metadata = {
              name = "gateway-route";
              namespace = "microservices";
            };
            spec = {
              entryPoints = [ "web" ];
              routes = [
                {
                  match = "PathPrefix(`/gateway.v1.GatewayService`)";
                  kind = "Rule";
                  priority = 100;
                  middlewares = [
                    { name = "cors-middleware"; }
                    { name = "rate-limit-middleware"; }
                  ];
                  services = [
                    {
                      name = "gateway";
                      port = 8082;
                      scheme = "h2c";
                    }
                  ];
                }
              ];
            };
          }
          {
            apiVersion = "traefik.io/v1alpha1";
            kind = "IngressRoute";
            metadata = {
              name = "auth-route";
              namespace = "microservices";
            };
            spec = {
              entryPoints = [ "web" ];
              routes = [
                {
                  match = "PathPrefix(`/auth`)";
                  kind = "Rule";
                  priority = 90;
                  middlewares = [
                    { name = "cors-middleware"; }
                    { name = "rate-limit-middleware"; }
                  ];
                  services = [
                    {
                      name = "auth-service";
                      port = 8090;
                    }
                  ];
                }
              ];
            };
          }
          {
            apiVersion = "traefik.io/v1alpha1";
            kind = "IngressRoute";
            metadata = {
              name = "raid-allocate-route";
              namespace = "microservices";
            };
            spec = {
              entryPoints = [ "web" ];
              routes = [
                {
                  match = "PathPrefix(`/api/raid`)";
                  kind = "Rule";
                  priority = 95;
                  middlewares = [
                    { name = "cors-middleware"; }
                    { name = "rate-limit-middleware"; }
                  ];
                  services = [
                    {
                      name = "gateway";
                      port = 8082;
                    }
                  ];
                }
              ];
            };
          }
          {
            apiVersion = "traefik.io/v1alpha1";
            kind = "IngressRoute";
            metadata = {
              name = "item-route";
              namespace = "microservices";
            };
            spec = {
              entryPoints = [ "web" ];
              routes = [
                {
                  match = "PathPrefix(`/item.v1.ItemService`)";
                  kind = "Rule";
                  priority = 100;
                  middlewares = [
                    { name = "cors-middleware"; }
                    { name = "rate-limit-middleware"; }
                  ];
                  services = [
                    {
                      name = "item-service";
                      port = 8080;
                      scheme = "h2c";
                    }
                  ];
                }
              ];
            };
          }
          {
            apiVersion = "traefik.io/v1alpha1";
            kind = "IngressRoute";
            metadata = {
              name = "capture-route";
              namespace = "microservices";
            };
            spec = {
              entryPoints = [ "web" ];
              routes = [
                {
                  match = "PathPrefix(`/capture.v1.CaptureService`)";
                  kind = "Rule";
                  priority = 100;
                  middlewares = [
                    { name = "cors-middleware"; }
                    { name = "rate-limit-middleware"; }
                  ];
                  services = [
                    {
                      name = "capture-service";
                      port = 8088;
                      scheme = "h2c";
                    }
                  ];
                }
              ];
            };
          }
          {
            apiVersion = "traefik.io/v1alpha1";
            kind = "IngressRoute";
            metadata = {
              name = "raid-lobby-route";
              namespace = "microservices";
            };
            spec = {
              entryPoints = [ "web" ];
              routes = [
                {
                  match = "PathPrefix(`/raid_lobby.v1.RaidLobbyService`)";
                  kind = "Rule";
                  priority = 100;
                  middlewares = [
                    { name = "cors-middleware"; }
                    { name = "rate-limit-middleware"; }
                  ];
                  services = [
                    {
                      name = "raid-lobby-service";
                      port = 8086;
                      scheme = "h2c";
                    }
                  ];
                }
              ];
            };
          }
          {
            apiVersion = "traefik.io/v1alpha1";
            kind = "IngressRoute";
            metadata = {
              name = "masterdata-route";
              namespace = "microservices";
            };
            spec = {
              entryPoints = [ "web" ];
              routes = [
                {
                  match = "PathPrefix(`/masterdata.v1.MasterdataService`)";
                  kind = "Rule";
                  priority = 100;
                  middlewares = [
                    { name = "cors-middleware"; }
                    { name = "rate-limit-middleware"; }
                  ];
                  services = [
                    {
                      name = "masterdata-service";
                      port = 8084;
                      scheme = "h2c";
                    }
                  ];
                }
              ];
            };
          }
          {
            apiVersion = "traefik.io/v1alpha1";
            kind = "IngressRoute";
            metadata = {
              name = "lobby-route";
              namespace = "microservices";
            };
            spec = {
              entryPoints = [ "web" ];
              routes = [
                {
                  match = "PathPrefix(`/lobby.v1.LobbyService`)";
                  kind = "Rule";
                  priority = 100;
                  middlewares = [
                    { name = "cors-middleware"; }
                    { name = "rate-limit-middleware"; }
                  ];
                  services = [
                    {
                      name = "lobby-service";
                      port = 8089;
                      scheme = "h2c";
                    }
                  ];
                }
              ];
            };
          }
          {
            apiVersion = "rbac.authorization.k8s.io/v1";
            kind = "ClusterRole";
            metadata = {
              name = "gateway-agones-allocator";
            };
            rules = [
              {
                apiGroups = [ "allocation.agones.dev" ];
                resources = [ "gameserverallocations" ];
                verbs = [ "create" ];
              }
            ];
          }
          {
            apiVersion = "rbac.authorization.k8s.io/v1";
            kind = "ClusterRoleBinding";
            metadata = {
              name = "gateway-agones-allocator";
            };
            roleRef = {
              apiGroup = "rbac.authorization.k8s.io";
              kind = "ClusterRole";
              name = "gateway-agones-allocator";
            };
            subjects = [
              {
                kind = "ServiceAccount";
                name = "default";
                namespace = "microservices";
              }
            ];
          }
          {
            apiVersion = "traefik.io/v1alpha1";
            kind = "IngressRoute";
            metadata = {
              name = "frontend-route";
              namespace = "microservices";
            };
            spec = {
              entryPoints = [ "web" ];
              routes = [
                {
                  match = "PathPrefix(`/`)";
                  kind = "Rule";
                  priority = 1;
                  services = [
                    {
                      name = "frontend";
                      port = 80;
                    }
                  ];
                }
              ];
            };
          }
        ];
      };
    };
  };
}
