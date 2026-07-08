# garage-ready

Deploy [Garage](https://garagehq.deuxfleurs.fr/) — a lightweight, S3-compatible object store — on Kubernetes with a bucket, credentials, and connection details ready out of the box.

No manual `garage layout assign`, `bucket create`, or `key create` steps. Install the chart, read the Secret, and start uploading.

## Features

- **Single-command install** — `helm install` deploys Garage with sensible defaults
- **Pre-created upload bucket** — default bucket `uploads`, configurable via `values.yaml`
- **Credentials in a Kubernetes Secret** — `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_ENDPOINT_URL`, `S3_BUCKET`, and a `credentials` file for AWS SDKs
- **Connection details ConfigMap** — endpoint, bucket, and copy-paste upload instructions
- **Single-node mode (default)** — uses Garage v2.3 `--single-node --default-bucket` for automatic layout and key setup
- **Multi-node mode** — optional bootstrap Job assigns layout, imports the key, creates the bucket, and grants permissions
- **Optional smoke test** — post-install Job uploads a test object to verify the setup
- **Ingress support** — expose the S3 API outside the cluster when needed

## Requirements

| Component | Version |
|-----------|---------|
| Kubernetes | 1.24+ |
| Helm | 3.x |
| StorageClass | A default or explicitly configured class for PVCs |

## Quick start

### 1. Clone and install

```bash
git clone https://github.com/yunushaikh/garage-ready.git
cd garage-ready

helm install garage ./helm \
  --create-namespace \
  --namespace garage
```

### 2. Wait for the pod

```bash
kubectl wait --for=condition=ready pod/garage-0 -n garage --timeout=300s
```

### 3. Read credentials

```bash
kubectl get secret garage-upload-credentials -n garage -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d; echo
kubectl get secret garage-upload-credentials -n garage -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 -d; echo
```

### 4. Upload a file

```bash
kubectl port-forward -n garage svc/garage 3900:3900

export AWS_ACCESS_KEY_ID=$(kubectl get secret garage-upload-credentials -n garage \
  -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d)
export AWS_SECRET_ACCESS_KEY=$(kubectl get secret garage-upload-credentials -n garage \
  -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 -d)
export AWS_DEFAULT_REGION=garage
export AWS_ENDPOINT_URL=http://127.0.0.1:3900

aws s3 cp ./myfile.txt s3://uploads/myfile.txt
aws s3 ls s3://uploads/
```

### Install with smoke test

```bash
helm install garage ./helm \
  --create-namespace \
  --namespace garage \
  --set upload.testUpload.enabled=true
```

## What gets created

With release name `garage` in namespace `garage`:

| Resource | Name | Purpose |
|----------|------|---------|
| StatefulSet | `garage` | Garage server (v2.3.0) |
| Service | `garage` | S3 API on port 3900, web on 3902 |
| Secret | `garage-upload-credentials` | S3 keys and endpoint env vars for your apps |
| ConfigMap | `garage-upload-details` | Human-readable connection info |
| Secret | `garage-rpc-secret` | Internal Garage RPC and admin tokens |
| PVCs | `meta-garage-0`, `data-garage-0` | Metadata and object storage |

## Use credentials in your application

Mount the upload Secret as environment variables:

```yaml
envFrom:
  - secretRef:
      name: garage-upload-credentials
```

Your app then has `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_ENDPOINT_URL`, `S3_BUCKET`, and related variables available.

See [`helm/examples/consumer-pod.yaml`](helm/examples/consumer-pod.yaml) for a working example pod that uploads a file.

## Service DNS for pods

Garage exposes a Kubernetes `ClusterIP` Service on port **3900** (S3 API). Pods should use **plain HTTP** on this service DNS name — TLS is not terminated on the Garage Service itself.

With release name `garage` in namespace `garage`:

| Use case | DNS / URL | Notes |
|----------|-----------|-------|
| Pod in the **same namespace** | `http://garage:3900` | Shortest form; recommended |
| Pod in **any namespace** | `http://garage.garage.svc.cluster.local:3900` | Full in-cluster FQDN |
| Cross-cluster / external | Use Ingress HTTPS (below) | Requires hostname + certificate |

These values are also written into the `garage-upload-details` ConfigMap:

```bash
kubectl get configmap garage-upload-details -n garage -o yaml
```

Example pod manifest snippet (same namespace):

```yaml
env:
  - name: AWS_ENDPOINT_URL
    value: "http://garage:3900"
envFrom:
  - secretRef:
      name: garage-upload-credentials
```

The upload credentials Secret sets `AWS_ENDPOINT_URL` automatically. By default it points to the in-cluster HTTP service URL.

## HTTPS access

Garage serves S3 over HTTP on port 3900. For **HTTPS**, terminate TLS at an **Ingress** controller in front of the Service.

### Testing / development — long-lived certificates (no TLS errors)

For local or lab clusters, use a **private testing CA** with **10-year certificates** so uploads and app startup do not fail with expired or untrusted certificate errors.

> **Production:** Replace the testing CA with a real issuer — for example cert-manager `ClusterIssuer` with Let's Encrypt, or certificates from your organization's PKI. Testing certificates are not suitable for production.

**1. Install cert-manager and an ingress controller** (if not already present):

```bash
# Example: cert-manager + nginx ingress (adjust for your cluster)
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.4/cert-manager.yaml
```

**2. Create the testing CA and server certificate:**

```bash
kubectl create namespace garage --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f helm/examples/cert-manager-testing-ca.yaml
kubectl wait --for=condition=ready certificate/garage-s3 -n garage --timeout=120s
```

This creates:
- `garage-testing-ca` — private CA (valid 10 years)
- `garage-ingress-tls` — server cert for `s3.garage.test` (valid 10 years)

**3. Install Garage with ingress + HTTPS:**

```bash
helm install garage ./helm -n garage -f helm/examples/values-https-testing.yaml
```

**4. Trust the CA in pods** so HTTPS uploads work without certificate errors:

```yaml
env:
  - name: AWS_CA_BUNDLE
    value: /etc/ssl/certs/garage-ca.crt
volumeMounts:
  - name: garage-ca
    mountPath: /etc/ssl/certs/garage-ca.crt
    subPath: ca.crt
    readOnly: true
volumes:
  - name: garage-ca
    secret:
      secretName: garage-testing-ca
      items:
        - key: tls.crt
          path: ca.crt
```

A complete example is in [`helm/examples/consumer-pod-https.yaml`](helm/examples/consumer-pod-https.yaml).

**5. Resolve the ingress hostname from inside the cluster**

Pods must resolve `s3.garage.test` to your ingress controller. Options:

| Method | When to use |
|--------|-------------|
| `hostAliases` in the pod spec | Quick testing (see `consumer-pod-https.yaml`) |
| CoreDNS `hosts` plugin or stub domain | Cluster-wide dev DNS |
| `/etc/hosts` on your laptop | Local `aws s3` CLI testing outside the cluster |

Get the ingress controller ClusterIP:

```bash
kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.spec.clusterIP}'
```

**6. Upload over HTTPS from your laptop** (after adding `s3.garage.test` to `/etc/hosts` pointing at the ingress external IP):

```bash
# Trust the CA locally (one-time)
kubectl get secret garage-testing-ca -n garage -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/garage-ca.crt

export AWS_ACCESS_KEY_ID=$(kubectl get secret garage-upload-credentials -n garage \
  -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 -d)
export AWS_SECRET_ACCESS_KEY=$(kubectl get secret garage-upload-credentials -n garage \
  -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 -d)
export AWS_DEFAULT_REGION=garage
export AWS_ENDPOINT_URL=https://s3.garage.test
export AWS_CA_BUNDLE=/tmp/garage-ca.crt

aws s3 cp ./myfile.txt s3://uploads/myfile.txt
```

### Production HTTPS

For production, use real certificates from a trusted CA:

```yaml
ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
  hosts:
    - host: s3.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: garage-production-tls
      hosts:
        - s3.example.com

upload:
  endpoint: https://s3.example.com
```

Clients and pods must trust the production CA (usually already in the system trust store). No custom `AWS_CA_BUNDLE` is needed when using a public CA.


## Configuration

Key values in [`helm/values.yaml`](helm/values.yaml):

| Value | Default | Description |
|-------|---------|-------------|
| `garage.singleNode` | `true` | Auto-configure layout, bucket, and key at startup |
| `upload.bucket` | `uploads` | S3 bucket name |
| `upload.accessKeyId` | *(auto)* | Fixed access key (`GK<hex>`); auto-generated if empty |
| `upload.secretAccessKey` | *(auto)* | Fixed secret key; auto-generated if empty |
| `upload.testUpload.enabled` | `false` | Run post-install upload smoke test |
| `upload.endpoint` | *(in-cluster HTTP)* | Override S3 URL in the upload Secret (e.g. `https://s3.garage.test`) |
| `persistence.data.size` | `1Gi` | Data volume size per node |
| `persistence.meta.size` | `100Mi` | Metadata volume size per node |
| `persistence.data.storageClass` | *(default)* | StorageClass for data PVCs |
| `ingress.enabled` | `false` | Expose S3 API via Ingress |

Custom values file example:

```yaml
# my-values.yaml
upload:
  bucket: my-app-uploads

persistence:
  data:
    size: 10Gi
    storageClass: fast-ssd

ingress:
  enabled: true
  className: nginx
  hosts:
    - host: s3.example.com
      paths:
        - path: /
          pathType: Prefix
```

```bash
helm install garage ./helm -n garage -f my-values.yaml
```

Full reference:

```bash
helm show values ./helm
```

## Multi-node deployment

For replicated storage, disable single-node mode and scale replicas:

```yaml
garage:
  singleNode: false
  replicationFactor: 3

deployment:
  replicaCount: 3

bootstrap:
  zone: dc1
  capacity: 10Gi
```

A post-install Job will:

1. Assign each node in the cluster layout
2. Apply the layout
3. Import the pre-generated S3 key
4. Create the upload bucket and grant read/write/owner permissions

## Project layout

```
garage-ready/
├── README.md           # This file
└── helm/               # Helm chart
    ├── Chart.yaml
    ├── values.yaml
    ├── templates/
    ├── examples/
    │   ├── consumer-pod.yaml
    │   ├── consumer-pod-https.yaml
    │   ├── cert-manager-testing-ca.yaml
    │   └── values-https-testing.yaml
    └── README.md       # Chart-specific notes
```

## Uninstall

```bash
helm uninstall garage -n garage
```

PVCs are retained by default. To remove them:

```bash
kubectl delete pvc -n garage -l app.kubernetes.io/instance=garage
```

## Troubleshooting

**Pod not ready**

```bash
kubectl logs -n garage garage-0
kubectl describe pod -n garage garage-0
```

**TLS / certificate errors on HTTPS upload**

- Mount the testing CA and set `AWS_CA_BUNDLE` in pods (see [HTTPS access](#https-access))
- Confirm the certificate is ready: `kubectl get certificate -n garage`
- Verify hostname resolution: `kubectl run -it --rm debug --image=busybox -- nslookup s3.garage.test`

**Upload fails with access denied**

Confirm credentials match the Secret and the endpoint URL includes the scheme (`http://`):

```bash
kubectl get configmap garage-upload-details -n garage -o yaml
```

**Bucket does not exist (multi-node mode)**

Check the bootstrap Job:

```bash
kubectl logs -n garage job/garage-bootstrap
```

## About Garage

[Garage](https://garagehq.deuxfleurs.fr/) is an open-source, geo-distributed, S3-compatible object storage system designed for self-hosting. This project wraps the official `dxflrs/garage` Docker image in a Helm chart with bootstrap automation.

## License

This Helm chart is provided as-is. Garage itself is licensed under the AGPL-3.0 — see the [Garage project](https://git.deuxfleurs.fr/Deuxfleurs/garage) for details.
