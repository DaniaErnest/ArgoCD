# k8s-gitops-lab

GitOps lab on kind with ArgoCD.

- App: nginx Deployment + Service in manifests/
- ArgoCD Application: my-web-app.yaml, automated sync, prune and self-heal
- Proved drift correction: scaled the Deployment by hand, ArgoCD reverted it to the Git state
