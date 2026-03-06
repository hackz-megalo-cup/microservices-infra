{
  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    devenv.url = "github:cachix/devenv/v2.0.1";
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    devenv.inputs.nixpkgs.follows = "nixpkgs";
    devenv-root = {
      url = "file+file:///dev/null";
      flake = false;
    };
    nix2container.url = "github:nlewo/nix2container";
    nix2container.inputs.nixpkgs.follows = "nixpkgs";
    mk-shell-bin.url = "github:rrbutani/nix-mk-shell-bin";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    nixidy = {
      url = "github:arnarg/nixidy";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixhelm = {
      url = "github:farcaller/nixhelm";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    opentelemetry-nix = {
      url = "github:FriendsOfOpenTelemetry/opentelemetry-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  nixConfig = {
    extra-trusted-public-keys = "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw=";
    extra-substituters = "https://devenv.cachix.org";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    let
      devenvRootFileContent = builtins.readFile inputs.devenv-root.outPath;
      devenvRoot = if devenvRootFileContent != "" then devenvRootFileContent else builtins.toString ./.;
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.devenv.flakeModule
        inputs.treefmt-nix.flakeModule
      ];

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      perSystem =
        { pkgs, system, ... }:
        let
          nix2containerPkgs = inputs.nix2container.packages.${system};

          # Map host system to corresponding Linux system for container builds
          # e.g. aarch64-darwin -> aarch64-linux, x86_64-darwin -> x86_64-linux
          linuxSystem = builtins.replaceStrings [ "darwin" ] [ "linux" ] system;

          otelPkgs = import inputs.nixpkgs {
            system = linuxSystem;
            overlays = [ inputs.opentelemetry-nix.overlays.default ];
          };

          otel-collector = otelPkgs.buildOtelCollector {
            pname = "otel-collector";
            version = "0.147.0";
            config = {
              receivers = [
                { gomod = "go.opentelemetry.io/collector/receiver/otlpreceiver v0.147.0"; }
              ];
              processors = [
                { gomod = "go.opentelemetry.io/collector/processor/batchprocessor v0.147.0"; }
              ];
              exporters = [
                { gomod = "go.opentelemetry.io/collector/exporter/otlpexporter v0.147.0"; }
                { gomod = "go.opentelemetry.io/collector/exporter/otlphttpexporter v0.147.0"; }
                {
                  gomod = "github.com/open-telemetry/opentelemetry-collector-contrib/exporter/prometheusremotewriteexporter v0.147.0";
                }
              ];
            };
            vendorHash = "sha256-NtieNKEtGgdKK1K4JWGzk/z5SME9fuhqE7vXZEdrRcs=";
          };

          otel-collector-image = nix2containerPkgs.nix2container.buildImage {
            name = "otel-collector";
            tag = "latest";
            config = {
              entrypoint = [ "${otel-collector}/bin/otel-collector" ];
            };
            layers = [
              (nix2containerPkgs.nix2container.buildLayer { deps = [ otel-collector ]; })
            ];
          };
        in
        {
          devenv.shells.default = {
            devenv.root = devenvRoot;
            imports = [ ./devenv.nix ];
          };

          treefmt = {
            projectRootFile = "flake.nix";
            programs = import ./treefmt-programs.nix;
          };

          # Nixidy environments
          legacyPackages.nixidyEnvs = {
            local = inputs.nixidy.lib.mkEnv {
              inherit pkgs;
              charts = inputs.nixhelm.chartsDerivations.${system};
              modules = [ ./nixidy/env/local.nix ];
            };
            prod = inputs.nixidy.lib.mkEnv {
              inherit pkgs;
              charts = inputs.nixhelm.chartsDerivations.${system};
              modules = [ ./nixidy/env/prod.nix ];
            };
          };

          # Nixidy CLI
          packages.nixidy = inputs.nixidy.packages.${system}.default;

          # OTel Collector (custom build)
          packages.otel-collector = otel-collector;
          packages.otel-collector-image = otel-collector-image;
        };
    };
}
