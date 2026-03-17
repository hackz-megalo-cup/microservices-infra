_:
let
  labels = {
    "app.kubernetes.io/name" = "kaniko-poller";
    "app.kubernetes.io/component" = "ci";
  };

  pollScript = builtins.readFile ../../../scripts/kaniko-poll-build.sh;
in
{
  applications.kaniko = {
    namespace = "ci";
    createNamespace = true;

    resources = {
      serviceAccounts.kaniko-builder = { };

      clusterRoles.kaniko-builder = {
        rules = [
          {
            apiGroups = [ "batch" ];
            resources = [ "jobs" ];
            verbs = [
              "create"
              "get"
              "list"
              "watch"
            ];
          }
        ];
      };

      clusterRoleBindings.kaniko-builder = {
        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "ClusterRole";
          name = "kaniko-builder";
        };
        subjects = [
          {
            kind = "ServiceAccount";
            name = "kaniko-builder";
            namespace = "ci";
          }
        ];
      };

      configMaps.kaniko-poll-script = {
        data."poll-build.sh" = pollScript;
      };

      # PVC to persist last-sha across CronJob runs
      persistentVolumeClaims.kaniko-poll-state.spec = {
        accessModes = [ "ReadWriteOnce" ];
        resources.requests.storage = "1Mi";
      };

      cronJobs.kaniko-poller.spec = {
        schedule = "*/3 * * * *";
        concurrencyPolicy = "Forbid";
        successfulJobsHistoryLimit = 3;
        failedJobsHistoryLimit = 3;
        jobTemplate.spec.template = {
          metadata.labels = labels;
          spec = {
            serviceAccountName = "kaniko-builder";
            restartPolicy = "Never";
            containers.poller = {
              image = "bitnami/kubectl:latest";
              command = [
                "bash"
                "/scripts/poll-build.sh"
              ];
              volumeMounts = {
                "/scripts".name = "script";
                "/state".name = "state";
              };
              resources = {
                requests = {
                  cpu = "50m";
                  memory = "64Mi";
                };
                limits = {
                  cpu = "200m";
                  memory = "128Mi";
                };
              };
            };
            volumes = {
              script.configMap = {
                name = "kaniko-poll-script";
                defaultMode = 493;
              };
              state.persistentVolumeClaim.claimName = "kaniko-poll-state";
            };
          };
        };
      };
    };
  };
}
