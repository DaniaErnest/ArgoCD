variable "namespace" {
  description = "Kubernetes namespace where ArgoCD will be installed"
  type        = string
  default     = "argocd"
}

variable "release_name" {
  description = "Helm release name for ArgoCD"
  type        = string
  default     = "argocd"
}

variable "chart_version" {
  description = "Version of the argo-cd Helm chart to install (app version v3.6.1)"
  type        = string
  default     = "10.17.1"
}

variable "server_service_type" {
  description = "Service type for the ArgoCD server: ClusterIP, NodePort or LoadBalancer"
  type        = string
  default     = "ClusterIP"
}

variable "create_secret" {
  description = "false = use the manually created argocd-secret. true = let the chart create it."
  type        = bool
  default     = false
}