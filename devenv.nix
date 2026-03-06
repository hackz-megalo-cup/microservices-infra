{
  pkgs,
  lib,
  ...
}:

{
  # Disable devenv container outputs (shadow package is Linux-only, breaks nix flake check on macOS)
  containers = lib.mkForce { };
  packages = [
    pkgs.nh
    pkgs.nix-output-monitor

    # Git
    pkgs.git

    # Kubernetes
    pkgs.kind
    pkgs.kubectl
    pkgs.kubernetes-helm
    pkgs.argocd

    # Cilium / Hubble
    pkgs.cilium-cli
    pkgs.hubble

    # Secret management
    pkgs.sops
    pkgs.age

    # Container image operations
    pkgs.skopeo

    # Nix tooling
    pkgs.nix-tree
    pkgs.nurl

    # Dashboards as Code
    pkgs.go-jsonnet
    pkgs.jsonnet-bundler
    pkgs.grafanactl

    # Service Mesh (nixpkgs provides 1.28.x; 1.26 is EOL)
    pkgs.istioctl

    # Monitoring
    pkgs.watchexec

    # Cloudflare Tunnel
    pkgs.cloudflared
  ];

  treefmt = {
    enable = true;
    config.programs = import ./treefmt-programs.nix;
  };

  git-hooks.hooks = {
    treefmt.enable = true;
  };

  scripts = {
    cluster-up.exec = ''
      bash "$DEVENV_ROOT/scripts/cluster-up.sh"
    '';
    cluster-down.exec = ''
      bash "$DEVENV_ROOT/scripts/cluster-down.sh"
    '';
    argocd-bootstrap.exec = ''
      bash "$DEVENV_ROOT/scripts/argocd-bootstrap.sh"
    '';
    sops-init.exec = ''
      bash "$DEVENV_ROOT/scripts/sops-init.sh"
    '';
    full-bootstrap.exec = ''
      bash "$DEVENV_ROOT/scripts/full-bootstrap.sh"
    '';
    gen-manifests.exec = ''
      bash "$DEVENV_ROOT/scripts/gen-manifests.sh"
    '';
    load-otel-collector-image.exec = ''
      bash "$DEVENV_ROOT/scripts/load-otel-collector-image.sh"
    '';
    fix-chart-hash.exec = ''
      bash "$DEVENV_ROOT/scripts/fix-chart-hash.sh"
    '';
    cilium-install.exec = ''
      bash "$DEVENV_ROOT/scripts/cilium-install.sh"
    '';
    istio-install.exec = ''
      bash "$DEVENV_ROOT/scripts/istio-install.sh"
    '';
    watch-manifests.exec = ''
      echo "Watching nixidy modules for changes..."
      watchexec --exts nix --restart -- bash -lc 'bash scripts/gen-manifests.sh && kubectl apply -f manifests/'
    '';
    nix-check.exec = ''
      SYSTEM="$(nix eval --raw --impure --expr 'builtins.currentSystem')"
      echo "Evaluating nix..."
      nix eval ".#legacyPackages.''${SYSTEM}.nixidyEnvs.local.environmentPackage" --raw >/dev/null \
        && echo "✓ nix eval OK" \
        || echo "✗ nix eval FAILED"
    '';
    bootstrap.exec = ''
      bash "$DEVENV_ROOT/scripts/bootstrap.sh"
    '';
    cloudflared-setup.exec = ''
      bash "$DEVENV_ROOT/scripts/cloudflared-setup.sh"
    '';
    debug-k8s.exec = ''
      echo "=== Pod status ==="
      kubectl get pods -A
      echo "=== Recent events ==="
      kubectl get events -A --sort-by=.lastTimestamp | tail -10
    '';
  };

  enterShell = ''
    echo "microservice-infra dev environment loaded"
    echo ""
    echo "Available commands:"
    echo "  cluster-up       : Create kind cluster"
    echo "  cluster-down     : Destroy kind cluster"
    echo "  argocd-bootstrap : Bootstrap ArgoCD on cluster"
    echo "  sops-init        : Generate age key for sops"
    echo "  bootstrap        : Lite environment setup (no Istio/ArgoCD, 1 worker)"
    echo "  full-bootstrap   : Full environment setup"
    echo "  gen-manifests    : Regenerate nixidy manifests into manifests/"
    echo "  load-otel-collector-image : Build + load custom OTel Collector into kind"
    echo "  watch-manifests  : Watch nixidy modules and apply changes"
    echo "  fix-chart-hash   : Auto-fix empty chartHash in nixidy modules"
    echo "  nix-check        : Fast nix expression sanity check"
    echo "  cilium-install    : Install Cilium + Hubble into kind cluster"
    echo "  istio-install     : Install Istio ambient mode"
    echo "  cloudflared-setup : Setup Cloudflare Tunnel + DNS"
    echo "  debug-k8s        : Kubernetes pod/event debug"
    echo ""
    echo "Cilium / Hubble:"
    echo "  cilium status            : Check Cilium health"
    echo "  cilium hubble ui         : Open Hubble UI (http://localhost:12000)"
    echo "  hubble observe -n <ns>   : Observe network flows"
  '';
}
