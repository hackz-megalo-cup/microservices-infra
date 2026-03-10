{ lib, charts, ... }:
let
  mkPostgres = name: db: port: {
    applications."postgresql-${name}" = {
      namespace = "database";
      helm.releases."postgresql-${name}" = {
        chart = charts.bitnami.postgresql;
        values = {
          fullnameOverride = "postgresql-${name}";
          auth = {
            username = "devuser";
            password = "devpass";
            database = db;
          };
          primary = {
            persistence.size = "512Mi";
            resources = {
              requests = {
                cpu = "25m";
                memory = "64Mi";
              };
              limits = {
                cpu = "100m";
                memory = "128Mi";
              };
            };
            service.ports.postgresql = port;
          };
          metrics.enabled = true;
        };
      };
    };
  };
in
lib.mkMerge [
  (mkPostgres "auth" "auth_db" 5432)
  (mkPostgres "lang" "lang_db" 5432)
  (mkPostgres "greeter" "greeter_db" 5432)
  (mkPostgres "caller" "caller_db" 5432)
  (mkPostgres "gateway" "gateway_db" 5432)
]
