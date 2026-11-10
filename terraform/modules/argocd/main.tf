resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = var.namespace
  }
}

resource "helm_release" "argocd" {
  name       = var.release_name
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.chart_version

  create_namespace = false
  wait             = true
  timeout          = 600

  values = [
  templatefile("${path.module}/values.yaml.tmpl", {
    namespace           = var.namespace
    server_service_type = var.server_service_type
    create_secret       = var.create_secret
  })
]

  depends_on = [kubernetes_namespace_v1.argocd]
}
