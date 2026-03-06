{ charts, ... }:
{
  applications.argocd = {
    namespace = "argocd";
    createNamespace = true;

    helm.releases.argocd = {
      chart = charts.argoproj.argo-cd;

      values = {
        global.domain = "argocd.local";

        server = {
          replicas = 1;
          service = {
            type = "NodePort";
            nodePortHttp = 30080;
            nodePortHttps = 30443;
          };
          extraArgs = [ "--insecure" ];
        };

        controller.replicas = 1;
        redis.enabled = true;
        dex.enabled = false;

        configs.params = {
          "server.insecure" = true;
        };
      };
    };
  };
}
