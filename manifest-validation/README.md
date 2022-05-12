# Manifest Validation

This action performs validation of Kubernetes manifests at a specified path and ensures that the manifest is valid and can be built by kustomize.

## Usage

```yaml
name: "Cluster Manifest Validation"

on:
  pull_request:
    branches: [main]
    paths:
      - "overlays/**"
jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: "Validate Overlay Manifests"
        uses: kualibuild/github-actions/manifest-validation@master
        with:
          path: "overlays/"
```
