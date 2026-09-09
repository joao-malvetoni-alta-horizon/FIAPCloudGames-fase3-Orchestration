#!/usr/bin/env bash
# Aplica os manifestos k8s/ (a numeracao dos arquivos garante a ordem de criacao).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"

NAMESPACE="fcg"

# Regera k8s/03-kong-config.yaml de kong/kong.yml, para nunca aplicar uma
# config de gateway defasada em relacao a fonte que o Compose usa.
echo "==> Sincronizando o ConfigMap do Kong"
"$SCRIPT_DIR/../kong/sync-configmap.sh"

echo "==> Aplicando manifestos de k8s/"
kubectl apply -f k8s/

# O Kong le a config declarativa UMA VEZ, no startup: trocar o ConfigMap nao
# faz efeito nos pods que ja estao rodando. Copiamos o hash da config para uma
# annotation do pod template -- o `kubectl patch` e idempotente, entao o
# Deployment SO rola quando kong/kong.yml (ou o render-and-start.sh) mudou.
KONG_CONFIG_HASH="$(kubectl get configmap kong-declarative -n "$NAMESPACE" \
  -o jsonpath='{.metadata.annotations.fcg\.dev/kong-config-hash}' 2>/dev/null || true)"

if [ -n "$KONG_CONFIG_HASH" ]; then
  echo "==> Propagando o hash da config do Kong para o Deployment (${KONG_CONFIG_HASH})"
  kubectl patch deployment kong -n "$NAMESPACE" --type=merge -p \
    "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"fcg.dev/kong-config-hash\":\"${KONG_CONFIG_HASH}\"}}}}}"
else
  echo "!! Nao foi possivel ler a annotation de hash do ConfigMap kong-declarative." >&2
  echo "   Se editou kong/kong.yml, rode: kubectl rollout restart deployment/kong -n $NAMESPACE" >&2
fi

echo "==> Manifestos aplicados."