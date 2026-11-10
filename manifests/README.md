# Manifests — How I Built Them

This folder holds the Kubernetes manifests for the `my-web` app. It is watched by ArgoCD.

ArgoCD Application `my-web` points here:

- Repo: `https://github.com/DaniaErnest/ArgoCD.git`
- Path: `manifests`
- Destination namespace: `my-web`

When a file in this folder changes in Git and is pushed, ArgoCD pulls it and applies it to the cluster. When a file is deleted from Git, ArgoCD deletes it from the cluster too, because prune is on.

Read this file together with the root `README.md`, which explains what ArgoCD is and how the Applications work.

## Files in this folder

```text
manifests/
├── README.md          # This file
├── deployment.yaml    # Deployment my-web
└── service.yaml       # Service my-web
```

Only these two YAML files are deployed. Nothing else in this folder is applied by ArgoCD.

The Application file itself, `applications/my-web-app.yaml`, is deliberately *not* in this folder. It lives in an `applications/` folder at the repo root. If it were in `manifests/`, ArgoCD would try to manage itself, and that gets confusing for a first lab.

## deployment.yaml — line by line

Full file:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-web
  namespace: my-web
spec:
  replicas: 1
  selector:
    matchLabels:
      app: my-web
  template:
    metadata:
      labels:
        app: my-web
    spec:
      containers:
      - name: nginx
        image: nginx:1.27
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi
```

### Why I chose each line

**`apiVersion: apps/v1`, `kind: Deployment`**

A Deployment is the Kubernetes object that manages a stateless app. It does not run a container itself. It creates a ReplicaSet, and the ReplicaSet creates and counts the Pods.

I chose a Deployment, not a bare Pod, because a Pod on its own is not restarted or replaced if it dies. A Deployment is.

**`metadata.name: my-web`, `metadata.namespace: my-web`**

The Deployment is called `my-web` and it lives in a namespace called `my-web`. ArgoCD creates that namespace for me, because the Application has `CreateNamespace=true`. Without that, the sync would fail because the namespace did not exist yet.

**`spec.replicas: 1`**

This is the number Git says. It started at 1. Later, in the Git test, I changed it to 2 in Git, pushed, and ArgoCD made it 2 pods in the cluster. That one number is the whole GitOps test.

If you change replicas by hand with `kubectl scale`, ArgoCD will put it back to the number in Git, because selfHeal is on. That is the drift test in the root README.

**`spec.selector.matchLabels: app: my-web`**

The Deployment uses this label to find its own pods. It must match the labels on the pod template below, or the Deployment will not own any pods, and the pods will not be counted or replaced.

**`spec.template.metadata.labels: app: my-web`**

Every pod created from this template gets this label. That is how the Deployment and the Service below both find it.

The label is the connection between all three objects: Deployment, ReplicaSet, and Service all use `app: my-web`.

**`containers: - name: nginx, image: nginx:1.27`**

One container per pod, called `nginx`, running the nginx web server.

I pinned the image to `nginx:1.27`, not `nginx:latest`. `latest` moves, and a new nginx release could surprise you. In a real job you always pin, so a deploy is repeatable.

**`ports: - containerPort: 80`**

Nginx listens on port 80 inside the container. This line is documentation for Kubernetes and for other tools, it does not open the port by itself. The Service below is what actually routes traffic to it.

**`resources.requests: cpu 50m, memory 64Mi`**

Requests is what Kubernetes reserves for the pod when it schedules it. `50m` means 50 millicores, 5% of one CPU core. `64Mi` is 64 mebibytes of memory.

These are small on purpose, so the pod runs easily on a kind cluster on a laptop.

**`resources.limits: cpu 200m, memory 128Mi`**

Limits is the maximum the pod is allowed to use. If it tries to use more CPU, it is throttled. If it tries to use more memory, it is killed and restarted.

Requests and limits matter in real jobs because without them one app can starve the others on the same node. In this lab they also show that I thought about sizing, even for a demo app.

### What the Deployment creates

When ArgoCD applies this file, Kubernetes creates:

1. Deployment `my-web`
2. ReplicaSet `my-web-5b7bc64955-...` — the hash in the name comes from the pod template, so a template change makes a new ReplicaSet.
3. Pod `my-web-5b7bc64955-6zc5w` — one pod to start, with the nginx container inside.

You can see that chain in the ArgoCD UI tree: Deployment points to ReplicaSet, ReplicaSet points to Pod.

## service.yaml — line by line

Full file:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-web
  namespace: my-web
spec:
  type: ClusterIP
  selector:
    app: my-web
  ports:
  - port: 80
    targetPort: 80
```

### Why I chose each line

**`apiVersion: v1`, `kind: Service`**

A Service is a stable front door for a set of pods. Pods come and go, and their IPs change when they are recreated. The Service keeps one stable name and IP inside the cluster.

**`metadata.name: my-web`, `metadata.namespace: my-web`**

Same name and same namespace as the Deployment. That is a convention, not a requirement, but it makes it obvious which Service belongs to which app.

**`spec.type: ClusterIP`**

ClusterIP means internal only. The Service gets an IP that is only reachable inside the cluster. That is correct for kind on a laptop.

I did not use LoadBalancer or NodePort. A LoadBalancer needs a cloud load balancer, which kind does not have by default, and a NodePort would expose the app on the laptop's ports for no reason in this lab.

**`spec.selector: app: my-web`**

This is the key line. The Service looks for pods labelled `app: my-web`, and sends traffic to them. It must match the pod template labels in `deployment.yaml`, or the Service will have no endpoints and traffic will go nowhere.

The Service does not own the Pod, and it does not create anything. It just routes to pods that match its selector.

**`spec.ports: - port: 80, targetPort: 80`**

- `port: 80` is the port the Service itself listens on.
- `targetPort: 80` is the port inside the container, nginx on port 80.

They are the same number here because nginx listens on 80. In a real app they can be different, for example Service port 80 to container port 8080.

## How the two files work together

1. ArgoCD reads `manifests/` from Git.
2. It applies `deployment.yaml` first, then `service.yaml`, in the `my-web` namespace.
3. The Deployment creates a ReplicaSet, the ReplicaSet creates a Pod with label `app: my-web`.
4. The Service finds that pod by the same label and routes traffic to it on port 80.
5. If the pod dies, the ReplicaSet creates a new one with the same label, and the Service automatically starts routing to the new pod. The Service itself never changes.

Check it with:

```bash
kubectl get deployment -n my-web
kubectl get service -n my-web
kubectl get pods -n my-web
kubectl get endpoints -n my-web
```

`kubectl get endpoints` shows the actual pod IPs the Service is routing to. That is a good way to prove the selector is working.

## How I change the app — the GitOps way

Do not change the app with `kubectl scale` or `kubectl edit`. That is a manual change, and ArgoCD will revert it. That is the drift test, not a deploy.

To deploy a change:

1. Edit the file in Git. For example, in `deployment.yaml` change `replicas: 1` to `replicas: 2`.
2. Commit and push:
   ```bash
   git add manifests/deployment.yaml
   git commit -m "Scale my-web to 2 replicas via Git"
   git push
   ```
3. In ArgoCD, my-web goes OutOfSync, then back to Synced. Click Refresh if you do not want to wait about 3 minutes.
4. Check:
   ```bash
   kubectl get pods -n my-web
   ```

In this lab that test gave 2 pods:

```text
my-web-5b7bc64955-6zc5w   1/1     Running   0          19m
my-web-5b7bc64955-hth67   1/1     Running   0          8s
```

The old pod stayed, the new pod was created from the Git change alone.

You can change other things the same way: the image tag, the resources, the port. Change it in Git, push, ArgoCD applies it. Never edit it live in the cluster first.

## What I did not put in manifests

- No Ingress. This app is internal only on kind, and ingress would need an ingress controller installed first. That is a later module.
- No ConfigMap or Secret. Nginx needs no configuration in this lab. Secrets must never be committed to Git in plain text in a real job.
- No PersistentVolumeClaim. Nginx serves static content from its image, it does not need storage. Storage is a later module.
- No HorizontalPodAutoscaler. Scaling here is manual, by changing `replicas` in Git. Autoscaling is a later module.
- No NetworkPolicy or PodSecurity. Security hardening is a later module.

Each of those is a real topic, and each will get its own lab, with its own manifests, instead of being crammed into this first one.

## How to reuse this

To use these manifests for your own app:

1. Copy the folder, change `my-web` to your app name in all three places: the Deployment name, the Service name, and the label `app: my-web`.
2. Change the image to your image, pinned to a version.
3. Change the container port to your app's port, and match it in the Service `targetPort`.
4. Adjust `resources.requests` and `resources.limits` to what your app actually needs.
5. Point an ArgoCD Application at your repo and path, with the same sync policy, automated, prune, selfHeal, CreateNamespace.
6. Push, let ArgoCD sync, and check the pods are Running before you change anything else.
