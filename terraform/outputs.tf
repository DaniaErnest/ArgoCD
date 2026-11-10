output "argocd_namespace" {
  description = "Namespace where ArgoCD was installed"
  value       = module.argocd.namespace
}

output "argocd_release_name" {
  description = "Helm release name for ArgoCD"
  value       = module.argocd.release_name
}

output "argocd_chart_version" {
  description = "Version of the argo-cd Helm chart installed"
  value       = module.argocd.chart_version
}
