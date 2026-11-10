provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "kind-k8s-class"
}

provider "helm" {
  kubernetes = {
    config_path    = "~/.kube/config"
    config_context = "kind-k8s-class"
  }
}
