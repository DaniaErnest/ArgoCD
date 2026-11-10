# ArgoCD GitOps Lab

A hands-on lab on a local kind cluster. This repo teaches GitOps by doing it, not by reading about it.

> Lab only. This is not production, and it is not work done at WithinLabs.
> Everything here runs on kind on a laptop, with ArgoCD installed from the official install manifest.

## What is ArgoCD?

ArgoCD is a continuous delivery tool for Kubernetes. It implements GitOps.

In the normal push flow, you write YAML, push to Git, and a CI job runs `kubectl apply` or `helm upgrade` into the cluster. GitHub Actions pushes the change in.

In GitOps, Git is still the source of truth, but nothing pushes into the cluster. A tool *inside* the cluster pulls from Git, compares what Git wants with what the cluster actually has, and makes the cluster match Git.

Think of it like this:

- Git is the plan on paper.
- The cluster is the real building.
- ArgoCD is the supervisor who walks around every 3 minutes, compares the paper to the building, and fixes any difference.

ArgoCD does not build Docker images and it does not run tests. That is still CI work. ArgoCD only does delivery, the CD part.

## What is GitOps, in one paragraph?

1. You change YAML in Git and push it.
2. ArgoCD sees the change, pulls the new YAML, and applies it to the cluster.
3. If someone changes the cluster by hand, ArgoCD sees that the cluster no longer matches Git, marks the app OutOfSync, and, if self-heal is on, puts it back to match Git.

Git wins. Always.

## The parts of ArgoCD

ArgoCD runs inside the cluster as a set of pods, in its own namespace called `argocd`.

| Pod | What it does |
| --- | --- |
| `argocd-server` | The website and API you log into. This is the UI. |
| `argocd-application-controller` | The brain. It reads Git, reads the cluster, compares them, and decides Synced or OutOfSync. |
| `argocd-repo-server` | The Git reader. It clones the repo and hands the YAML files to the controller. |
| `argocd-redis` | A fast cache, so ArgoCD does not clone Git from scratch every time. |
| `argocd-dex-server` | Handles login. In this lab it just lets the `admin` user log in. |
| `argocd-applicationset-controller` | Watches ApplicationSet objects and generates Applications from a template. Not used in this lab. |
| `argocd-notifications-controller` | Sends alerts when a sync fails. Not used in this lab. |

## How this lab was built

### Prerequisites

- kind installed locally
- kubectl installed locally
- A kind cluster, created with:
  ```bash
  kind create cluster --name k8s-class
  ```
- GitHub account: `DaniaErnest`

### 1. Install ArgoCD

From the official ArgoCD getting started guide:

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

`kubectl create namespace argocd` makes a separate room in the cluster just for ArgoCD, so its pods do not mix with your apps.

`kubectl apply -f install.yaml` applies one long list of Deployments, Services, Roles and Secrets that creates all the pods in the table above. `stable` means the latest stable release. The version installed in this lab was ArgoCD v3.6.1.

Wait, then check:

```bash
kubectl get pods -n argocd
```

Healthy looks like this: every pod `1/1 Running`, 0 restarts.

```text
argocd-application-controller-0                     1/1     Running   0
argocd-applicationset-controller-794bb95c9d-9bbkt   1/1     Running   5
argocd-dex-server-66cf64bfcf-kvxv2                  1/1     Running   0
argocd-notifications-controller-5878c8d644-24lsg    1/1     Running   0
argocd-redis-5869b7547-l7xcw                        1/1     Running   0
argocd-repo-server-7d55cc466b-d4zg2                 1/1     Running   0
argocd-server-85b849c688-rtdfs                      1/1     Running   0
```

Note: in this lab the `applicationset-controller` kept restarting. See "Known issues" below. It does not block the apps in this lab.

### 2. Log into the UI

A kind cluster has no public IP and no LoadBalancer, so you cannot just open ArgoCD in a browser. You make a tunnel with port-forward.

Get the first admin password. ArgoCD stores it once at install time in a Kubernetes Secret:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
```

That command fetches the Secret, decodes it from base64, and prints it. Copy the password. It is a Secret value, do not share it.

In a second terminal, keep this running. If you close this terminal, the tunnel closes:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

This means: take port 8080 on my laptop, connect it to port 443 on the argocd-server Service inside the cluster.

Open https://localhost:8080 in your browser. Accept the self-signed certificate warning, that is normal in a lab. Log in as username `admin` with the password above.

### 3. The Applications page

After login you land on the Applications page. Each card is one Application.

An Application is itself a Kubernetes object, like a Deployment. But instead of describing a pod, it describes a link between Git and the cluster: this Git repo, this folder, deploy it to this namespace.

Each card shows two separate labels:

- **Sync Status**
  - `Synced` means Git and the cluster match.
  - `OutOfSync` means they are different. Either Git changed and has not been applied yet, or someone changed the cluster by hand.
- **Health Status**
  - `Healthy` means the pods are running.
  - `Degraded` means a pod is crashing.
  - `Progressing` means it is still starting up.

An app can be Synced but Degraded. That means ArgoCD applied it correctly, but the app itself is crashing.

Click an app card to open its details page. Below the top bar you see the tree view. It draws every object ArgoCD created: Deployment, ReplicaSet, Pod, Service, connected like a family tree.

Click any box in the tree. On the right you see the Desired State from Git and the Live State from the cluster. If someone edited the cluster by hand, you see the difference highlighted there. That is drift, in plain sight.

Top buttons on that page:

- **Sync**: apply what is in Git to the cluster now.
- **Refresh**: ask ArgoCD to check Git again right now, instead of waiting for its 3 minute check.
- **History and Rollback**: every sync is recorded. You can roll back to an earlier sync.
- **Delete**: delete the app, and optionally delete all the resources it created.

## The applications in this lab

There are two Applications. Check them with:

```bash
kubectl get applications -n argocd
```

Result in this lab:

```text
NAME        SYNC STATUS   HEALTH STATUS
guestbook   Synced        Healthy
my-web      Synced        Healthy
```

### 1. guestbook — the example app

Source: `https://github.com/argoproj/argocd-example-apps.git`, path `guestbook`

Guestbook is ArgoCD's own public example. It is a tiny visitor book app: you type a message on a web page, it saves the message in Redis.

It is useful for learning because it is simple, plain YAML, no Helm. Inside that Git folder there are Deployments and Services for `guestbook-ui`, `redis-master`, and `redis-slave`.

The Application file used was:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: guestbook
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/argoproj/argocd-example-apps.git
    targetRevision: HEAD
    path: guestbook
  destination:
    server: https://kubernetes.default.svc
    namespace: guestbook
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
```

What the important lines mean:

- `source.repoURL` and `source.path`: which Git repo and which folder to watch.
- `destination.server: https://kubernetes.default.svc`: which cluster to deploy to. That address just means "this same cluster".
- `destination.namespace: guestbook`: create the app in a namespace called guestbook.
- `syncPolicy.automated.prune: true`: if I delete a file from Git, delete it from the cluster too.
- `syncPolicy.automated.selfHeal: true`: if someone changes the cluster by hand, change it back to match Git.
- `syncOptions: CreateNamespace=true`: create the namespace for you if it does not exist.

Apply it with:

```bash
kubectl apply -f guestbook-app.yaml
kubectl get pods -n guestbook
```

### 2. my-web — my own app, from my own repo

Source: `https://github.com/DaniaErnest/ArgoCD.git`, path `manifests`
Destination namespace: `my-web`

This is the same idea as guestbook, but in a repo I own, so I can change Git myself. That is the normal job flow.

The Application file is `my-web-app.yaml` at the root of this repo. It is deliberately *not* inside `manifests/`, so ArgoCD does not try to manage itself.

It points to this repo, `HEAD`, path `manifests`, destination namespace `my-web`, with automated sync, prune, and selfHeal, and `CreateNamespace=true`.

Apply it with:

```bash
kubectl apply -f my-web-app.yaml
kubectl get pods -n my-web
```

Result in this lab:

```text
NAME                      READY   STATUS    RESTARTS   AGE
my-web-5b7bc64955-6zc5w   1/1     Running   0          13m
```

The manifests it deploys are explained in `manifests/README.md`.

## The two tests that prove GitOps works

### Test 1: Drift — change the cluster, Git wins

This proves self-heal. Change the cluster by hand, bypassing Git:

```bash
kubectl -n guestbook scale deployment guestbook-ui --replicas=3
```

Then watch the pods live:

```bash
kubectl get pods -n guestbook -w
```

What happened in this lab:

- The old pod stayed Running at 8h old.
- Two new pods appeared as Pending, then ContainerCreating.
- After 1 second, both new pods went to Terminating.

ArgoCD saw Git says 1 replica, reverted the Deployment back to 1, and the ReplicaSet killed the extra pods. `kubectl get pods` after the test showed only the original pod.

That is drift correction. The same test with a single check also showed no new pods, only the original 7h57m old pod, because ArgoCD had already reverted it before the check.

Press Ctrl+C to stop the `-w` watch.

### Test 2: Sync — change Git, the cluster follows

This proves Git-to-cluster delivery. Do not use `kubectl scale` for this test.

In `manifests/deployment.yaml`, change:

```yaml
replicas: 1
```

to:

```yaml
replicas: 2
```

Then commit and push:

```bash
git add manifests/deployment.yaml
git commit -m "Scale my-web to 2 replicas via Git"
git push
```

In the ArgoCD UI, my-web first goes OutOfSync, then back to Synced. Click Refresh if you do not want to wait about 3 minutes for the automatic check.

Check:

```bash
kubectl get pods -n my-web
```

Result in this lab:

```text
NAME                      READY   STATUS    RESTARTS   AGE
my-web-5b7bc64955-6zc5w   1/1     Running   0          19m
my-web-5b7bc64955-hth67   1/1     Running   0          8s
```

The old pod, 19 minutes old, stayed. The new pod, 8 seconds old, was created by the ReplicaSet after ArgoCD updated the Deployment from Git. No kubectl command created it. A Git push created it, through ArgoCD.

## The tree: Deployment -> ReplicaSet -> Pod

In the ArgoCD UI, click guestbook, then look at the tree. You will see:

- Application `guestbook` owns a Service and a Deployment.
- The Deployment owns a ReplicaSet.
- The ReplicaSet owns a Pod.
- The Service points to that same Pod.

That chain is ownership, not something ArgoCD invented:

- **Deployment** is the manager. It says: I want 1 pod running this image. It never creates a pod directly.
- **ReplicaSet** is the worker the Deployment creates. Its only job is counting. If there are 0 pods, make 1. If there are 2, kill 1.
- **Pod** is the actual running container.

The **Service** is different. It does not own the Pod. It is a stable front door. Pods come and go and their IPs change, but the Service keeps one stable name and IP inside the cluster. It finds the Pod by a label selector, in this lab `app: guestbook-ui` or `app: my-web`, and sends traffic to it.

## Commands used in this lab

```bash
# Cluster
kind create cluster --name k8s-class
kind get clusters
kubectl cluster-info
kubectl get nodes -o wide

# Install ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl get pods -n argocd

# Log in
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Open https://localhost:8080, user: admin

# Applications
kubectl get applications -n argocd
kubectl apply -f guestbook-app.yaml
kubectl apply -f my-web-app.yaml

# Check apps
kubectl get pods -n guestbook
kubectl get pods -n my-web
kubectl get pods -n guestbook -w

# Drift test (cluster -> Git)
kubectl -n guestbook scale deployment guestbook-ui --replicas=3

# Git test (Git -> cluster)
# Edit manifests/deployment.yaml: replicas: 1 -> 2
git add manifests/deployment.yaml
git commit -m "Scale my-web to 2 replicas via Git"
git push
```

## Repo structure

```text
.
├── README.md                  # This file: what ArgoCD is, commands, applications
├── my-web-app.yaml            # ArgoCD Application for my-web, at the root, not in manifests/
├── manifests/
│   ├── README.md              # How the manifests were built
│   ├── deployment.yaml        # Deployment my-web, nginx:1.27, 1 replica to start
│   └── service.yaml           # Service my-web, ClusterIP, port 80
└── terraform/                 # Planned next step, see below
```

## Known issues seen in this lab

### 1. DNS error after a kind restart

Error seen on 10 Nov 2026:

```text
Failed to load target state: failed to generate manifest for source 1 of 1:
rpc error: code = Unavailable desc = dns: A record lookup error:
lookup argocd-repo-server on 10.96.0.10:53: read: connection refused
```

Translation: the application-controller tried to ask CoreDNS, at 10.96.0.10:53, for the IP of `argocd-repo-server`, and CoreDNS did not answer.

Cause in this lab: the whole kind node had restarted about 6 minutes before, all pods had 1 restart at the same time. During that restart CoreDNS was down for a short time.

Fix: nothing to fix in the repo or YAML. Wait for CoreDNS and repo-server to be Running again, then click Refresh in the ArgoCD UI. It went back to Synced and Healthy.

Check with:

```bash
kubectl get pods -n argocd
kubectl get pods -n kube-system
```

Both CoreDNS pods should be `1/1 Running`.

### 2. ApplicationSet CRD missing

The `argocd-applicationset-controller` pod kept restarting, 5 restarts on day 1, 70 restarts by day 2. Its logs said:

```text
failed to get restmapping: no matches for kind "ApplicationSet" in version "argoproj.io/v1alpha1"
```

And:

```bash
kubectl get crd | grep argoproj
```

showed only:

```text
applications.argoproj.io
appprojects.argoproj.io
```

`applicationsets.argoproj.io` was missing. A CRD is the dictionary entry that tells Kubernetes a new kind exists. Without it, the controller cannot watch ApplicationSet objects.

This does not block guestbook or my-web, because those are plain Applications, and the Application CRD exists. It will be fixed by reinstalling ArgoCD properly, see "Next step" below.

## Next step: Terraform

The next step in this class is to restart everything from scratch and deploy ArgoCD with a Terraform module, instead of `kubectl apply -f install.yaml`.

The idea: Terraform installs the platform only, ArgoCD itself, using the official `argo/argo-cd` Helm chart. ArgoCD then installs the apps from Git. That separation is the standard in real jobs: Terraform for the platform, GitOps for the apps.

Deleting the kind cluster is safe in this lab, because the apps are in Git and ArgoCD will recreate them. That is also a disaster recovery test.

See `terraform/` when that step is done. Do not claim Terraform in a CV until that lab is actually completed and verified.
