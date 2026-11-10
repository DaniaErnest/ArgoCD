# Terraform — ArgoCD on kind

A hands-on GitOps lab. Terraform installs the platform (ArgoCD itself).
ArgoCD installs the apps, from Git.

> Lab, not production. Cluster is a local `kind` cluster, single node.
> Nothing here is claimed as production work, or as WithinLabs work.

## What this installs

- ArgoCD **v3.6.1** (app version), via the official Helm chart
  **argo-cd 10.17.1** (chart version — chart and app versions are different numbers)
- Namespace: `argocd`
- Cluster: `kind-k8s-class`, Kubernetes v1.37.0, single node
- Terraform v1.17.0, providers: `hashicorp/kubernetes ~> 3.0`,
  `hashicorp/helm ~> 3.0`
- Server Service: `ClusterIP` — log in with a port-forward, there is no
  LoadBalancer on kind

Verified 10 Nov 2026: after `terraform apply`, all 7 ArgoCD pods were
`1/1 Running, 0 restarts`, and all 3 `argoproj.io` CRDs were present
(`applications`, `applicationsets`, `appprojects`, created
2026-11-10T13:48:04Z). The Helm install fixed the missing
`applicationsets.argoproj.io` CRD that caused repeated restarts of
`argocd-applicationset-controller` in the earlier `kubectl install.yaml`
install (5 restarts on day 1, 70 by day 2).

## Repo layout

```
.
├── applications/
│   ├── guestbook-app.yaml      # demo app from argoproj, Synced / Healthy
│   └── my-web-app.yaml         # own nginx app, from manifests/
├── manifests/
│   ├── deployment.yaml         # Deployment my-web, nginx:1.27
│   ├── service.yaml            # Service my-web, ClusterIP, port 80
│   └── README.md               # manifests explained line by line
├── terraform/
│   ├── README.md               # this file
│   ├── versions.tf             # Terraform >= 1.5.0, provider pins
│   ├── providers.tf            # kubeconfig ~/.kube/config, context kind-k8s-class
│   ├── main.tf                 # calls module "argocd"
│   ├── outputs.tf              # namespace, release name, chart version
│   └── modules/
│       └── argocd/
│           ├── main.tf         # kubernetes_namespace_v1 + helm_release
│           ├── variables.tf    # namespace, release_name, chart_version,
│           │                   # server_service_type, create_secret
│           ├── outputs.tf
│           └── values.yaml.tmpl  # TEMPLATED Helm values (see below)
├── argocd-secret.yaml.tmpl     # TEMPLATE for the manual Secret (see below)
├── argocd-secret.yaml          # FILLED-IN Secret — LOCAL ONLY, DO NOT COMMIT
└── .gitignore                  # ignores argocd-secret.yaml, tfstate, etc.
```

Separation of duties, on purpose:

| Layer | Tool | Installs |
|---|---|---|
| Platform | Terraform + Helm | ArgoCD itself |
| Apps | ArgoCD | guestbook and my-web, from Git |

Terraform never touches the apps. ArgoCD never installs itself.

## Prerequisites

- `kind`, `kubectl`, `terraform` installed
- A kind cluster named `k8s-class`. Do not touch `odin-cluster`.
  ```bash
  kind get clusters
  kubectl config current-context   # expect kind-k8s-class
  ```
- `helm` CLI is **not** required. Terraform's Helm provider has Helm
  built in and does not call the `helm` CLI. `brew install helm` fails
  on this Mac at the moment because the Command Line Tools are too
  outdated — fix that separately in System Settings, it does not block
  Terraform.

## Step 0 — The Secret, before Terraform

ArgoCD's admin password lives in a Secret called `argocd-secret`.
The chart hard-codes that name. There is no `secretName` field in
`values.yaml` to point at a different name — naming your Secret
`argocd-secret`, in namespace `argocd`, *is* the reference.

You create that Secret by hand, before Terraform runs. Terraform only
tells the chart not to create its own.

### The Secret manifest

File: `argocd-secret.yaml` — filled in locally, **never committed**.
The committed template is `argocd-secret.yaml.tmpl` (same file, with
placeholders). Copy the template to `argocd-secret.yaml` and fill it in:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: argocd-secret
  namespace: argocd
  labels:
    app.kubernetes.io/name: argocd-secret
    app.kubernetes.io/part-of: argocd
type: Opaque
stringData:
  admin.password: "<BCRYPT_HASH_OF_YOUR_NEW_PASSWORD>"
  admin.passwordMtime: "<2026-11-10T15:30:00Z>"
  server.secretkey: "<RANDOM_32_BYTE_HEX_STRING_FROM_openssl_rand_-hex_32>"
```

What each key is:

- `admin.password` — a bcrypt hash of your new password, not the plain
  password. The `admin.` prefix is the username: log in as `admin`.
  The username is fixed, built into ArgoCD, there is no username field
  in the Secret.
  - Make it with: `argocd account bcrypt --password 'YourNewPassword'`
  - Or: `htpasswd -nbBC 10 "" 'YourNewPassword' | tr -d ':\n' | sed 's/$2y/$2a/'`
  - Or in Docker, no install needed:
    `docker run --rm httpd:2.4-alpine htpasswd -nbBC 10 "" 'YourNewPassword' | tr -d ':\n' | sed 's/$2y/$2a/'`
  - A valid hash starts `$2a$10$` and is 60 characters long.
  - Do not paste the password or the hash in chat.
- `admin.passwordMtime` — when you changed the password, RFC3339.
  Do not hard-code the example time. Use the actual time you apply it:
  ```bash
  date -u +"%Y-%m-%dT%H:%M:%SZ"
  ```
  ArgoCD uses it to know the password changed, and to invalidate
  sessions/tokens issued before that time. Changing only the password
  with a stale `passwordMtime` can make a change appear not to work.
- `server.secretkey` — **not a password**. It is ArgoCD's signing key.
  ArgoCD signs your JWT session and API tokens with it (HMAC-SHA256).
  After login, the token, not your password, is sent on every request.
  If this key leaks, anyone can forge a token as `admin`. If you change
  it, everyone is logged out.
  - Make it with: `openssl rand -hex 32`
  - That is 32 random bytes, printed as 64 hex characters (`0-9`, `a-f`).
  - Fallback: `python3 -c 'import secrets; print(secrets.token_hex(32))'`
  - Set it once. A fixed key makes sessions survive a server restart;
    a key regenerated on every start invalidates them.

`stringData` means Kubernetes base64-encodes the values for you.
You write them in plain text in the file, Kubernetes stores them encoded.
The labels and `type: Opaque` are optional; the name, namespace and the
three keys are what matter.

### Apply the Secret first

```bash
kubectl apply -f argocd-secret.yaml
kubectl -n argocd get secret argocd-secret
```

Order matters. Secret first, Terraform second, so ArgoCD never starts
without a Secret to read. If Terraform ran first with
`createSecret: false` and no Secret existed yet, ArgoCD would create
its own Secret again and yours would be ignored.

## Step 1 — The templated values file

`terraform/modules/argocd/values.yaml.tmpl` is **not** a plain
`values.yaml`. It is a Terraform template, rendered at plan/apply time
by `templatefile()`.

In `modules/argocd/main.tf`, instead of:
```hcl
values = [ file("${path.module}/values.yaml") ]
```
it is:
```hcl
values = [
  templatefile("${path.module}/values.yaml.tmpl", {
    namespace           = var.namespace
    server_service_type = var.server_service_type
    create_secret       = var.create_secret
  })
]
```

`templatefile()` reads the `.tmpl`, replaces `${...}` with the values
passed in, and returns the finished YAML in memory. The rendered file is
never written to disk and never committed to Git. That is why a sensitive
value can be passed through it as a variable — it never lands in the repo.

The template itself:

```yaml
configs:
  secret:
    # false = do NOT let the chart create argocd-secret.
    # You created it manually by hand, named argocd-secret,
    # in namespace ${namespace}, with admin.password (bcrypt),
    # admin.passwordMtime, and server.secretkey.
    createSecret: ${create_secret}

server:
  service:
    type: ${server_service_type}
```

Notes on this file:

- `createSecret: false` is the only instruction about the Secret in
  values. It does not tell ArgoCD *where* the Secret is — ArgoCD already
  knows the fixed name. It only stops Helm creating/overwriting it.
- `applicationSet` is deliberately left enabled (chart default). Do not
  disable it — disabling it removes its CRD, which was the missing-CRD
  bug in the kubectl install.
- Never write a bcrypt hash directly in the `.tmpl` file. A hash starts
  `$2a$...`, and Terraform would try to read `$2a$` as a template
  expression. Pass a hash in as a variable instead, if you ever use
  `configs.secret.argocdServerAdminPassword`. This lab does not use that
  field — the password comes from the manual Secret, not from values.

The two new variables, in `modules/argocd/variables.tf`:

```hcl
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
```

And in the root `terraform/main.tf`, they are passed explicitly:

```hcl
module "argocd" {
  source = "./modules/argocd"

  namespace           = "argocd"
  release_name        = "argocd"
  chart_version       = "10.17.1"
  server_service_type = "ClusterIP"
  create_secret       = false
}
```

## Step 2 — Terraform init, plan, apply

From `terraform/`:

```bash
terraform fmt -recursive
terraform init
terraform validate
terraform plan
terraform apply
```

Do not use `-auto-approve`. Type `yes` at the prompt.

First install, expected plan: **2 to add, 0 to change, 0 to destroy**
(the 2 are the namespace and the `helm_release`).

After the Secret step, expected plan on re-apply: **1 to change**
(the `helm_release` only — an in-place upgrade, not a recreate).

Then check:

```bash
kubectl get pods -n argocd
kubectl get crd | grep argoproj
kubectl get applications -n argocd
```

Expected: all 7 ArgoCD pods `1/1 Running`, all 3 `argoproj.io` CRDs
present, and `No resources found` for Applications until you re-apply
them (Step 4).

## Step 3 — Restart argocd-server, then log in

`values.yaml` never picks up the Secret. The **argocd-server pod**
picks it up, and only when that pod starts. It loaded the old password
into memory when it started, so after `terraform apply` the old password
still works and the new one does not, until the server restarts.

Do not rely on the Helm upgrade to restart it. Restart it explicitly:

```bash
kubectl rollout restart deployment argocd-server -n argocd
kubectl rollout status deployment argocd-server -n argocd
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server
```

Only after the new pod is `1/1 Running` will the new password work and
the old password stop working.

Then log in:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Open https://localhost:8080, username `admin`, password = the plain
password you hashed (not the hash).

## Step 4 — Re-apply the Applications

The Applications are GitOps links, not installed by Terraform. They must
be bootstrapped once, from the repo root:

```bash
kubectl apply -f applications/guestbook-app.yaml
kubectl apply -f applications/my-web-app.yaml
kubectl get applications -n argocd
kubectl get pods -n my-web
kubectl get pods -n guestbook
```

Expected: guestbook and my-web both `Synced` and `Healthy`.
`my-web` should have 2 pods, because Git still says `replicas: 2` in
`manifests/deployment.yaml`.

## Step 5 — Prove it (the two lab tests)

1. **Git-to-cluster:** change `replicas: 2` to `3` in
   `manifests/deployment.yaml`, commit and push. ArgoCD should create
   a third `my-web` pod with no `kubectl scale`.
2. **Drift correction:** `kubectl scale deployment guestbook-ui -n guestbook --replicas=3`
   (or `my-web`), watch ArgoCD revert it to the Git state.

## .gitignore — what is committed, what is not

This repo is public. The filled-in Secret must never be committed.

Put this in the repo-root `.gitignore`:

```gitignore
# --- Secrets: local only, never commit ---
argocd-secret.yaml
secrets/
*.tfvars
terraform.tfvars

# --- Terraform state and working files ---
terraform.tfstate
terraform.tfstate.backup
.terraform/
.terraform.lock.hcl
*.tfplan

# --- macOS ---
.DS_Store
```

What that means:

| File | Commit? |
|---|---|
| `argocd-secret.yaml.tmpl` (placeholders only) | Yes — safe, it has no values |
| `argocd-secret.yaml` (filled in) | **No** — ignored by `.gitignore` |
| `terraform/modules/argocd/values.yaml.tmpl` | Yes — it has `${...}` placeholders, no secrets |
| `terraform.tfvars` (if you ever use one for a hash) | **No** |
| `terraform.tfstate`, `.terraform/` | **No** — local state, can contain rendered values |

Check before you push, every time:
```bash
git status
git check-ignore -v argocd-secret.yaml
```
The second command should print the `.gitignore` line that ignores it.
If it prints nothing, the file is not ignored — do not push.

> Warning: `.gitignore` only stops *new* files being added. If a filled-in
> Secret was ever committed, adding it to `.gitignore` does not remove it
> from history. That file would need to be removed from Git history and
> the password and `server.secretkey` rotated.

## Troubleshooting

- **New password does not work after `terraform apply`:** the old
  `argocd-server` pod is still running. Run the Step 3 restart and check
  the pod age.
- **`applicationsets.argoproj.io` missing / applicationset-controller
  restarting:** this was the kubectl-install bug. The Helm install fixed
  it. If you see it again, check `kubectl get crd | grep argoproj` — all
  3 CRDs should be present.
- **DNS error `lookup argocd-repo-server ... connection refused`:** transient,
  seen after a kind node restart while CoreDNS was not yet answering.
  Click Refresh in the UI, or wait and re-check. Not a repo/YAML problem.
- **Plan shows a deprecation warning about `kubernetes_namespace`:**
  rename the resource to `kubernetes_namespace_v1` in
  `modules/argocd/main.tf` and in `modules/argocd/outputs.tf`. This was
  already fixed in the delivered code.
- **`terraform plan` shows a hash or a secret in the output:** stop.
  Do not paste plan output in chat or commit it. The password and
  `server.secretkey` should never appear in plan output in this setup,
  because they are not Terraform variables — they are in the manual Secret.
