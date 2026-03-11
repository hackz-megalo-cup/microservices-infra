{ charts, ... }:
{
  applications.postgresql = {
    namespace = "database";
    createNamespace = true;

    helm.releases.postgresql = {
      chart = charts.bitnami.postgresql;

      values = {
        auth = {
          username = "devuser";
          password = "devpass";
          postgresPassword = "admin";
          database = "postgres";
        };

        primary = {
          initdb.scripts = {
            "create-databases.sql" = ''
              CREATE DATABASE auth_db;
              CREATE DATABASE lang_db;
              CREATE DATABASE greeter_db;
              CREATE DATABASE caller_db;
              CREATE DATABASE gateway_db;
              GRANT ALL PRIVILEGES ON DATABASE auth_db TO devuser;
              GRANT ALL PRIVILEGES ON DATABASE lang_db TO devuser;
              GRANT ALL PRIVILEGES ON DATABASE greeter_db TO devuser;
              GRANT ALL PRIVILEGES ON DATABASE caller_db TO devuser;
              GRANT ALL PRIVILEGES ON DATABASE gateway_db TO devuser;
            '';
          };

          persistence = {
            enabled = true;
            size = "2Gi";
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
}
