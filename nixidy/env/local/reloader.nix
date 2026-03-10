{ charts, ... }:
{
  applications.reloader = {
    namespace = "kube-system";
    helm.releases.reloader = {
      chart = charts.stakater.reloader;
      values = {
        reloader = {
          watchGlobally = true;
          logFormat = "json";
        };
      };
    };
  };
}
