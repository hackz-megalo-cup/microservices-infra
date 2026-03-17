resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "7.8.13"
  namespace        = "argocd"
  create_namespace = true
  wait             = true
  timeout          = 600

  set {
    name  = "server.replicas"
    value = "1"
  }

  set {
    name  = "server.service.type"
    value = "ClusterIP"
  }

  set {
    name  = "controller.replicas"
    value = "1"
  }

  set {
    name  = "redis.enabled"
    value = "true"
  }

  set {
    name  = "dex.enabled"
    value = "false"
  }

  depends_on = [
    aws_eks_node_group.workers,
  ]
}

resource "kubectl_manifest" "argocd_infra_app" {
  yaml_body = <<-YAML
    apiVersion: argoproj.io/v1alpha1
    kind: Application
    metadata:
      name: apps
      namespace: argocd
    spec:
      project: default
      source:
        repoURL: https://github.com/hackz-megalo-cup/microservices-infra.git
        targetRevision: main
        path: manifests/apps
      destination:
        server: https://kubernetes.default.svc
        namespace: argocd
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
  YAML

  depends_on = [helm_release.argocd]
}

resource "kubectl_manifest" "argocd_services_appset" {
  yaml_body = <<-YAML
    apiVersion: argoproj.io/v1alpha1
    kind: ApplicationSet
    metadata:
      name: services
      namespace: argocd
    spec:
      generators:
        - git:
            repoURL: https://github.com/hackz-megalo-cup/microservices-app.git
            revision: main
            directories:
              - path: services/*/k8s/generated
              - path: frontend/k8s/generated
      template:
        metadata:
          name: '{{path[0]}}-{{path[1]}}'
          annotations:
            argocd.argoproj.io/manifest-generate-paths: '{{path}}'
        spec:
          project: default
          source:
            repoURL: https://github.com/hackz-megalo-cup/microservices-app.git
            targetRevision: main
            path: '{{path}}'
          destination:
            server: https://kubernetes.default.svc
          syncPolicy:
            automated:
              prune: true
              selfHeal: true
  YAML

  depends_on = [helm_release.argocd]
}
