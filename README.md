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

## Lab Architecture

Three views of the same lab — bootstrap, GitOps fan-out, and the event-driven image-update loop.

### 1. Bootstrap topology

What `just up` brings online and how the host talks to the cluster.

```mermaid
flowchart LR
  HOST[Host machine<br/>scripts/*.sh + just] -->|kind create| KIND[kind cluster: argo-lab]
  HOST -->|docker run| REG[(local-registry<br/>localhost:5001)]
  KIND -. containerd mirror .- REG

  subgraph KIND[kind cluster]
    GITEA[gitea ns<br/>Gitea + repos]
    ARGOCD[argocd ns<br/>Argo CD]
    PLATFORM[platform ns<br/>MinIO, Prometheus]
  end

  HOST -->|helm install| GITEA
  HOST -->|helm install| ARGOCD
  HOST -->|seed repos: platform, demo-app| GITEA
```

### 2. GitOps fan-out (app-of-apps)

Argo CD reads one root app and creates everything else.

```mermaid
flowchart TD
  GITEA[(Gitea: argo-lab/platform)] --> ROOT[root Application<br/>charts/app-of-apps + envs/lab/values.yaml]
  ROOT --> WF[argo-workflows]
  ROOT --> EV[argo-events]
  ROOT --> RO[argo-rollouts]
  ROOT --> IU[argocd-image-updater]
  ROOT --> NO[argocd-notifications]
  ROOT --> APP[demo-app + sync-waves-app]
  ROOT --> DEMOS[Phase-2 demos<br/>bluegreen · analysis · playwright · calendar]
```

### 3. Event-driven image update loop

The headline end-to-end flow exercised by `tests/test-e2e-chain.sh`.

```mermaid
flowchart LR
  DEV[git push to demo-app repo] --> WH[Gitea webhook]
  WH --> ES[EventSource /gitea]
  ES --> BUS[EventBus NATS]
  BUS --> SEN[Sensor]
  SEN --> WFT[WorkflowTemplate<br/>image-build-stub]
  WFT -->|push tag| REG[(local-registry)]
  REG --> IU[Image Updater]
  IU -->|git write-back| GITEA[(Gitea: demo-app)]
  GITEA --> ARGO[Argo CD sync]
  ARGO --> RO[Rollout canary<br/>20% -> promote -> 100%]
  RO --> NOTIF[Notifications -> log sink]
```

## Commands (Just)

- `just up` bootstraps the full lab
- `just status` prints cluster/application status
- `just test` runs `scripts/e2e-test.sh`
- `just down` tears down cluster and registry
- `just reset` does down then up

## Demo Workflows

Each demo lives in its own chart under [charts/](charts) and ships with a matching test under [tests/](tests).

### Blue/Green rollout — manual promotion

[charts/rollout-bluegreen-demo](charts/rollout-bluegreen-demo) · [tests/test-rollout-bluegreen.sh](tests/test-rollout-bluegreen.sh)

```mermaid
flowchart LR
  U[User: kubectl argo rollouts promote] --> R[Rollout bluegreen-demo]
  R -->|preReady: spin up new RS| RS2[ReplicaSet v2 preview]
  RS2 --> PSVC[preview Service]
  R -->|active stays on v1 until promoted| RS1[ReplicaSet v1 active]
  RS1 --> ASVC[active Service]
  U -. promote .-> SWAP{cut over}
  SWAP --> ASVC2[active Service -> v2]
  SWAP --> SCALE[scale down v1 after scaleDownDelay]
```

### Canary with Prometheus AnalysisTemplate

[charts/rollout-analysis-demo](charts/rollout-analysis-demo) · [tests/test-rollout-analysis.sh](tests/test-rollout-analysis.sh)

```mermaid
flowchart LR
  R[Rollout analysis-demo] -->|step: setWeight 25| C[Canary pods]
  R -->|step: analysis| AR[AnalysisRun]
  AR -->|HTTP query| P[Prometheus in-cluster]
  P -->|metric: success rate| AR
  AR -->|Successful| R
  AR -->|Failed| ABORT[Abort + rollback]
  R -->|setWeight 100| STABLE[Stable replicas v2]
```

### Playwright e2e with browseable MinIO artifacts

[charts/playwright-e2e-demo](charts/playwright-e2e-demo) · [tests/test-playwright-e2e.sh](tests/test-playwright-e2e.sh)

```mermaid
flowchart LR
  WT[WorkflowTemplate playwright-e2e] --> POD[playwright pod]
  POD -->|HTTP| APP[sync-waves-app Service]
  POD -->|html-report dir, archive: none| MINIO[(MinIO bucket: argo-artifacts)]
  POD -->|traces.tgz| MINIO
  POD -->|echo browse URL| LOG[workflow log]
  USER[User browser] -->|policy: download| MINIO
  MINIO -->|index.html + assets| USER
```

### Calendar EventSource → Workflow

[charts/calendar-event-demo](charts/calendar-event-demo) · [tests/test-calendar-event.sh](tests/test-calendar-event.sh)

```mermaid
flowchart LR
  CRON[Calendar EventSource<br/>schedule: * * * * *] --> EB[EventBus NATS]
  EB --> SEN[Sensor calendar-workflow-sensor]
  SEN -->|operate-workflow-sa| WF[Workflow calendar-hello-*]
  WF --> POD[alpine pod: echo tick]
  POD -. archiveLogs: false .- MINIO[(MinIO)]
```

> Note: the cluster-default `archiveLogs` is set to `false` in [charts/argo-workflows/templates/artifact-repository.yaml](charts/argo-workflows/templates/artifact-repository.yaml) so high-frequency demos don't fill the bucket. Workflows that need artifacts declare them explicitly via `outputs.artifacts` (see Playwright above).

