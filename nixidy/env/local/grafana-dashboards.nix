{ pkgs, ... }:
let
  grafonnet-src = pkgs.fetchFromGitHub {
    owner = "grafana";
    repo = "grafonnet";
    rev = "7380c9c64fb973f34c3ec46265621a2b0dee0058";
    hash = "sha256-WS3Z/k9fDSleK6RVPTFQ9Um26GRFv/kxZhARXpGkS10=";
  };

  dashboardsSrc = ../../../dashboards/src;

  compileDashboard =
    name:
    builtins.readFile (
      pkgs.runCommand "grafana-dashboard-${name}" { nativeBuildInputs = [ pkgs.go-jsonnet ]; } ''
        mkdir -p $out
        mkdir -p vendor/github.com/grafana
        ln -s ${grafonnet-src} vendor/github.com/grafana/grafonnet
        export JSONNET_PATH="vendor:${grafonnet-src}/gen/grafonnet-latest:${dashboardsSrc}"
        jsonnet ${dashboardsSrc}/${name}.jsonnet \
                -o $out/${name}.json
      ''
      + "/${name}.json"
    );
in
{
  applications.kube-prometheus-stack = {
    resources.configMaps.sample-app-dashboard = {
      metadata.labels = {
        grafana_dashboard = "1";
      };
      data."sample-app.json" = compileDashboard "sample-app";
    };

    resources.configMaps.k8s-cluster-dashboard = {
      metadata.labels = {
        grafana_dashboard = "1";
      };
      data."k8s-cluster.json" = compileDashboard "k8s-cluster";
    };
  };
}
