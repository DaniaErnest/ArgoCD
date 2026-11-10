module "argocd" {
  source = "./modules/argocd"

  namespace           = "argocd"
  release_name        = "argocd"
  chart_version       = "10.17.1"
  server_service_type = "ClusterIP"
  create_secret       = false
}