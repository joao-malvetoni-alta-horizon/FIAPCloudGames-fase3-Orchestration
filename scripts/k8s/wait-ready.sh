#!/usr/bin/env bash
# Espera todos os pods do namespace fcg ficarem prontos (Postgres/RabbitMQ demoram para health-check).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

NAMESPACE="fcg"
TIMEOUT="${1:-180s}"

echo "==> Esperando pods do namespace $NAMESPACE ficarem prontos (timeout ${TIMEOUT})"

if ! kubectl wait --for=condition=Ready pods --all -n "$NAMESPACE" --timeout="$TIMEOUT"; then
  echo "!! Alguns pods nao ficaram prontos a tempo. Status atual:"
  kubectl get pods -n "$NAMESPACE"
  exit 1
fi

echo "==> Todos os pods estao prontos."
kubectl get pods -n "$NAMESPACE"
