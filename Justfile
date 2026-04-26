set shell := ["bash", "-cu"]

default:
  @just --list

up: # Full lab: cluster + all components
  ./scripts/01-create-cluster.sh
  ./scripts/02-deploy-gitea.sh
  ./scripts/02b-configure-gitea.sh
  ./scripts/03-push-demo-image.sh
  ./scripts/04-bootstrap-argocd.sh
  ./scripts/035b-configure-gitea-webhook.sh
  ./scripts/05-wait-for-apps.sh
  just port-forward

down: # Delete kind cluster + registry
  just port-forward-stop
  kind delete cluster --name argo-lab || true
  docker rm -f local-registry || true

test: # Run e2e-test.sh
  ./scripts/e2e-test.sh

status: # Print status of all components
  kubectl get nodes
  kubectl get ns
  kubectl get applications -n argocd || true
  kubectl get pods -A

reset: # Tear down and rebuild from scratch
  just down
  just up

port-forward: # Background kubectl port-forwards & print all lab URLs
  ./scripts/port-forward.sh

port-forward-stop: # Stop background port-forwards started by 'just port-forward'
  ./scripts/port-forward-stop.sh
