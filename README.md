# Kind Argo Lab

Self-contained local platform lab for Argo CD, Argo Workflows, Argo Events, Argo Rollouts, Argo Notifications, and Argo CD Image Updater.

This project bootstraps a kind cluster, deploys local Gitea and a local Docker registry, seeds GitOps repos, and hands control to Argo CD through an app-of-apps root. The test flow validates the full event-driven loop from Git push to rollout promotion path.

## What It Builds

- kind cluster (`argo-lab`) with local registry wiring
- Local Gitea org/repos for platform and demo app
- Argo CD root app rendering child applications from `charts/app-of-apps` (Helm) with env overrides in `envs/lab/values.yaml`
- Helm wrapper charts for Argo components and demo app
- Event pipeline: Gitea webhook -> Argo Events -> Workflow trigger
- Image update loop: registry tag -> Image Updater git write-back -> Argo CD sync
- Canary delivery via Argo Rollouts

## Top-to-Bottom Flow

```mermaid
flowchart TD
  A[Host Machine] --> B[kind cluster argo-lab]
  A --> C[local-registry localhost:5001]

  subgraph B[kind cluster]
    D[gitea namespace]
    E[argocd namespace]
    F[argo-events namespace]
    G[argo namespace]
    H[argo-rollouts namespace]
    I[demo namespace]
  end

  A -->|bootstrap scripts| D
  A -->|bootstrap scripts| E
  A -->|push demo images| C

  D --> J[Repo: argo-lab/platform]
  D --> K[Repo: argo-lab/demo-app]

  E --> L[root-app: charts/app-of-apps + envs/lab/values.yaml]
  J --> L
  L --> M[argo-workflows app]
  L --> N[argo-events app]
  L --> O[argo-rollouts app]
  L --> P[argocd-image-updater app]
  L --> Q[argocd-notifications app]
  L --> R[demo-app app]

  K -->|push webhook| S[EventSource /gitea]
  S --> T[EventBus]
  T --> U[Sensor]
  U --> V[WorkflowTemplate image-build-stub]
  V -->|publish/update image tag| C

  P -->|detect new tag| C
  P -->|git write-back| K
  R -->|sync| I
  I --> W[Rollout canary 20% -> promote -> 100%]
  Q --> X[sync result logs]
```

## Commands (Just)

- `just up` bootstraps the full lab
- `just status` prints cluster/application status
- `just test` runs `scripts/e2e-test.sh`
- `just down` tears down cluster and registry
- `just reset` does down then up
