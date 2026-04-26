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

### Experiment — baseline + candidate side-by-side

[charts/rollout-experiment-demo](charts/rollout-experiment-demo) · [tests/test-rollout-experiment.sh](tests/test-rollout-experiment.sh)

```mermaid
flowchart LR
  E[Experiment side-by-side<br/>duration: 30s] --> RS1[ReplicaSet baseline]
  E --> RS2[ReplicaSet candidate]
  E --> AR[Inline AnalysisRun]
  AR -->|query| P[Prometheus in-cluster]
  P -->|metric ≥ 0.95| AR
  AR -->|Successful| DONE[Experiment Successful]
  DONE --> SCALE0[both ReplicaSets scale to 0]
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

### Mattermost threaded notifications

[charts/mattermost](charts/mattermost) · [charts/mattermost-thread-demo](charts/mattermost-thread-demo) · [tests/test-mattermost-thread.sh](tests/test-mattermost-thread.sh)

A `WorkflowTemplate` opens a Mattermost thread by POSTing a parent message, then every later step replies into that thread by passing the parent's `root_id`. Threading state lives entirely in the `Workflow` CR (output parameters between DAG tasks) — no DB needed.

```mermaid
flowchart LR
  subgraph WF[Workflow mm-thread-test-*]
    direction LR
    START[start: post-parent<br/>POST /api/v4/posts<br/>→ outputs.root_id] --> S1[step-1: post-reply<br/>root_id from start]
    S1 --> S2[step-2: post-reply]
    S2 --> S3[done: post-reply]
  end
  WF -.reads.- SEC[(Secret mattermost-creds<br/>url / token / channel_id)]
  WF -->|HTTPS| MM[Mattermost<br/>lab/Workflow Status]
  MM --> THR[Thread:<br/>parent + 3 replies]
```

The `mattermost-creds` Secret is created by a PostSync bootstrap Job in the mattermost chart and replicated into every namespace listed in [charts/mattermost/values.yaml](charts/mattermost/values.yaml) `credsNamespaces`.

### Shop — PreSync/PostSync hooks as Argo Workflows (success path)

[charts/shop](charts/shop) · [tests/test-shop-thread.sh](tests/test-shop-thread.sh)

The same threading pattern applied to Argo CD lifecycle hooks. Every sync of the `shop` Application opens a fresh thread, reports each phase, and runs an in-cluster e2e check. All five hooks are `kind: Workflow` so they show up in the Workflows UI.

```mermaid
flowchart TB
  subgraph PRE[PreSync]
    direction LR
    R[wave -3<br/>RBAC: SA + Role + RoleBinding]
    T[wave -2<br/>shop-thread-start<br/>POST parent → CM root_id]
    M[wave -1<br/>shop-migration<br/>fake DB migration → reply]
    R --> T --> M
  end
  subgraph SYNC[Sync]
    APP[Deployment + Service<br/>nginx:stable-alpine]
  end
  subgraph POST[PostSync]
    direction LR
    SS[wave 1<br/>shop-sync-status<br/>:white_check_mark: reply]
    E2E[wave 2<br/>shop-e2e<br/>curl Service → reply<br/>cleanup CM]
    SS --> E2E
  end
  PRE --> SYNC --> POST

  CM[(ConfigMap<br/>argo/shop-mm-thread<br/>root_id)]
  T -. writes .-> CM
  M -. reads .-> CM
  SS -. reads .-> CM
  E2E -. reads + deletes .-> CM

  POST --> MM[Mattermost thread:<br/>parent + 3 replies]
```

Coordination state is the single ConfigMap `argo/shop-mm-thread` — wave -2 writes it, every later hook reads it via `configMapKeyRef`, and the terminal hook deletes it. Argo CD itself has zero Mattermost knowledge; it just applies hook resources at the right phase and watches their `.status.phase`.

### Shop — failed-deploy (SyncFail path)

[charts/shop-failed-deploy](charts/shop-failed-deploy)

Variant of the `shop` chart whose PreSync migration is hardwired to `exit 1`. Demonstrates that the SyncFail hook can post into the same thread the (now-failed) PreSync workflow opened.

```mermaid
flowchart TB
  subgraph PRE[PreSync]
    direction LR
    R[wave -3<br/>RBAC]
    T[wave -2<br/>thread-start<br/>POST parent → CM]
    M[wave -1<br/>migration<br/>:boom: reply<br/>then exit 1]
    R --> T --> M
  end
  M -- failure --> X{Argo CD:<br/>sync Failed}
  X -. skips .-> SYNC[Sync phase<br/>never runs]
  X --> SF[SyncFail hook<br/>shop-failed-deploy-syncfail<br/>:x: reply<br/>cleanup CM]
  SF --> MM[Mattermost thread:<br/>parent + :boom: + :x:]

  CM[(ConfigMap<br/>argo/shop-failed-deploy-mm-thread)]
  T -. writes .-> CM
  M -. reads .-> CM
  SF -. reads + deletes .-> CM
```

Trigger manually: `kubectl -n argocd patch app shop-failed-deploy --type merge -p '{"operation":{"sync":{}}}'`.

