_:
let
  labels = {
    "app.kubernetes.io/name" = "garage";
    "app.kubernetes.io/component" = "object-storage";
  };

  garageToml = ''
    metadata_dir = "/var/lib/garage/meta"
    data_dir = "/var/lib/garage/data"
    db_engine = "sqlite"

    replication_factor = 1

    rpc_bind_addr = "[::]:3901"
    rpc_public_addr = "127.0.0.1:3901"
    rpc_secret = "0000000000000000000000000000000000000000000000000000000000000000"

    [s3_api]
    s3_region = "garage"
    api_bind_addr = "[::]:3900"
    root_domain = ".s3.garage.localhost"

    [admin]
    api_bind_addr = "[::]:3903"
    admin_token = "admin"
    metrics_token = "metrics"
  '';
in
{
  applications.garage = {
    namespace = "storage";
    createNamespace = true;

    resources = {
      configMaps.garage-config = {
        data."garage.toml" = garageToml;
      };

      services.garage = {
        spec = {
          selector = labels;
          ports = {
            s3 = {
              port = 3900;
              targetPort = 3900;
              protocol = "TCP";
            };
            rpc = {
              port = 3901;
              targetPort = 3901;
              protocol = "TCP";
            };
            admin = {
              port = 3903;
              targetPort = 3903;
              protocol = "TCP";
            };
          };
        };
      };

      statefulSets.garage.spec = {
        serviceName = "garage";
        replicas = 1;
        selector.matchLabels = labels;
        template = {
          metadata.labels = labels;
          spec = {
            containers.garage = {
              image = "dxflrs/garage:v1.1.0";
              ports = {
                s3.containerPort = 3900;
                rpc.containerPort = 3901;
                admin.containerPort = 3903;
              };
              volumeMounts = {
                "/etc/garage".name = "config";
                "/var/lib/garage/meta".name = "meta";
                "/var/lib/garage/data".name = "data";
              };
              env.GARAGE_CONFIG_FILE.value = "/etc/garage/garage.toml";
              resources = {
                requests = {
                  cpu = "50m";
                  memory = "128Mi";
                };
                limits = {
                  cpu = "500m";
                  memory = "512Mi";
                };
              };
              readinessProbe = {
                httpGet = {
                  path = "/health";
                  port = 3903;
                };
                initialDelaySeconds = 5;
                periodSeconds = 10;
              };
              livenessProbe = {
                httpGet = {
                  path = "/health";
                  port = 3903;
                };
                initialDelaySeconds = 10;
                periodSeconds = 30;
              };
            };
            volumes = {
              config.configMap.name = "garage-config";
            };
          };
        };
        volumeClaimTemplates = [
          {
            metadata.name = "meta";
            spec = {
              accessModes = [ "ReadWriteOnce" ];
              resources.requests.storage = "512Mi";
            };
          }
          {
            metadata.name = "data";
            spec = {
              accessModes = [ "ReadWriteOnce" ];
              resources.requests.storage = "4Gi";
            };
          }
        ];
      };
    };
  };
}
