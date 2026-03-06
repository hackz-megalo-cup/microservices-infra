{ charts, ... }:
{
  applications.image-updater = {
    namespace = "argocd";
    createNamespace = false;

    helm.releases.argocd-image-updater = {
      chart = charts.argoproj.argocd-image-updater;

      values = {
        config.registries = [
          {
            name = "GitHub Container Registry";
            prefix = "ghcr.io";
            api_url = "https://ghcr.io";
            credentials = "secret:argocd/ghcr-credentials#token";
          }
        ];
      };
    };
  };
}
