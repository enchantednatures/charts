# flux/ — self-referential GitOps sync

This directory contains a minimal [Flux](https://fluxcd.io/) bootstrap that makes
**this repository sync itself** into a cluster:

| File | Purpose |
|------|---------|
| `source.yaml` | A `GitRepository` (`flux-system/charts`) that watches this repo's `main` branch over SSH, authenticating with the `charts-deploy-key` Secret. |
| `sync.yaml` | A `Kustomization` (`flux-system/charts`) that reconciles the path `./flux` from that source with pruning enabled. |
| `kustomization.yaml` | Kustomize entrypoint that ties the two resources together. |

The `Kustomization` reconciles only `./flux` — i.e. the sync loop keeps its own
bootstrap manifests up to date. It does **not** deploy the example charts; it is
infrastructure that bootstraps and maintains the GitOps wiring for this repo.

## Bootstrap

With a kubeconfig pointed at the target cluster and the `charts-deploy-key`
Secret already present in `flux-system`:

```bash
make install-flux-sync     # apply -k flux/
make flux-reconcile        # force an immediate reconcile
make uninstall-flux-sync   # remove the sync resources
```

The repository URL and branch are hard-coded to
`ssh://git@github.com/enchantednatures/charts@main` and reflect this repo's
personal infrastructure.

## Relocating to a dedicated GitOps repository

This directory is intentionally self-contained so it can be *relocated*: to move
the GitOps ownership out of this chart repository, copy `flux/` into a dedicated
`gitops` repository, update `source.yaml` to point at that repository, and drop
this directory (and `make install-flux-sync` / `make flux-reconcile`) here. Until
then, keeping it in-tree is the simplest way to version the sync alongside the
charts it ships.
