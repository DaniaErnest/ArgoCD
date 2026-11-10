output "namespace" {
  description = "Namespace where ArgoCD was installed"
  value       = kubernetes_namespace_v1.argocd.metadata[0].name
}

output "release_name" {
  description = "Helm release name for ArgoCD"
  value       = helm_release.argocd.name
}

output "chart_version" {
  description = "Version of the argo-cd Helm chart installed"
  value       = helm_release.argocd.version
}
