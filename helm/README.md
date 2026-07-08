# Helm chart

This directory contains the `garage` Helm chart used by [garage-ready](../README.md).

Install from the repository root:

```bash
helm install garage ./helm --create-namespace --namespace garage
```

For full documentation — features, configuration, upload examples, multi-node setup, and troubleshooting — see the [project README](../README.md).

## Chart-only reference

```bash
helm lint ./helm
helm template garage ./helm --namespace garage
helm show values ./helm
```

## Examples

- [`examples/consumer-pod.yaml`](examples/consumer-pod.yaml) — pod that mounts upload credentials and uploads a test object
