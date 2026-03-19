{ lib, charts, ... }:
let
  mkPostgres = name: db: {
    applications."postgresql-${name}" = {
      namespace = "database";
      createNamespace = true;
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
          };
          metrics = {
            enabled = true;
            serviceMonitor = {
              enabled = true;
              namespace = "database";
            };
          };
        };
      };
    };
  };
in
lib.mkMerge [
  (mkPostgres "auth" "auth_db")
  (mkPostgres "capture" "capture_db")
  (mkPostgres "item" "item_db")
  (mkPostgres "lobby" "lobby_db")
  (mkPostgres "masterdata" "masterdata_db")
  (mkPostgres "projector" "projector_db")
  (mkPostgres "raid-lobby" "raid_lobby_db")
]
