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

down: # Delete kind cluster + registry
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
