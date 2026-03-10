{
  charts,
  ...
}:
{
  applications.redpanda = {
    namespace = "messaging";
    createNamespace = true;

    helm.releases.redpanda = {
      chart = charts.redpanda.redpanda;
      values = {
        statefulset = {
          replicas = 1;
        };
        resources = {
          cpu = {
            cores = "0.5";
          };
          memory = {
            container = {
              max = "2Gi";
            };
          };
        };
        storage = {
          persistentVolume = {
            enabled = true;
            size = "2Gi";
          };
        };
        listeners = {
          kafka = {
            port = 9092;
          };
          schemaRegistry = {
            enabled = false;
          };
          http = {
            enabled = false;
          };
        };
        monitoring = {
          enabled = true;
        };
        console = {
          enabled = true;
          service = {
            type = "NodePort";
            nodePort = 30082;
            targetPort = 8080;
          };
        };
        tuning = {
          tune_aio_events = false;
        };
        external = {
          enabled = false;
        };
        tls = {
          enabled = false;
        };
        auth = {
          sasl = {
            enabled = false;
          };
        };
      };
    };
  };
}
