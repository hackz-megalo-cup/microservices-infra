resource "kubectl_manifest" "cloudflared_namespace" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Namespace
    metadata:
      name: cloudflare
  YAML

  depends_on = [helm_release.argocd]
}

resource "kubectl_manifest" "cloudflared_credentials" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Secret
    metadata:
      name: tunnel-credentials
      namespace: cloudflare
    type: Opaque
    data:
      credentials.json: ${base64encode(file(pathexpand("~/.cloudflared/${var.cloudflare_tunnel_id}.json")))}
  YAML

  depends_on = [kubectl_manifest.cloudflared_namespace]
}
