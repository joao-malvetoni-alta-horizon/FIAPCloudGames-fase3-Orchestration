#!/usr/bin/env bash
# Builda as imagens Docker das 3 APIs e carrega no Minikube.
# Le os caminhos dos repos irmaos do .env (mesmas variaveis do docker-compose).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [ -f "$ROOT_DIR/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.env"
  set +a
fi

USERS_API_PATH="${USERS_API_PATH:-../FIAPCloudGames-fase3-UsersAPI}"
CATALOG_API_PATH="${CATALOG_API_PATH:-../FIAPCloudGames-fase3-CatalogAPI}"
PAYMENTS_API_PATH="${PAYMENTS_API_PATH:-../FIAPCloudGames-fase3-PaymentsAPI}"
# notifications-api NAO tem mais imagem de container: virou uma funcao AWS
# Lambda (repositorio FIAPCloudGames-fase3-NotificationsAPI, deploy via
# `sam deploy` naquele repo, nao pelo Minikube). Ver README.md, secao Serverless.

cd "$ROOT_DIR"

echo "==> [1/3] users-api"
docker build -t fcg/users-api:1.0 "$USERS_API_PATH" -f "$USERS_API_PATH/src/FCG.API/Dockerfile"
minikube image load fcg/users-api:1.0

echo "==> [2/3] catalog-api"
docker build -t fcg/catalog-api:1.0 "$CATALOG_API_PATH" -f "$CATALOG_API_PATH/src/CatalogAPI.API/Dockerfile"
minikube image load fcg/catalog-api:1.0

echo "==> [3/3] payments-api"
docker build -t fcg/payments-api:1.0 "$PAYMENTS_API_PATH" -f "$PAYMENTS_API_PATH/src/FCG.API/Dockerfile"
minikube image load fcg/payments-api:1.0

echo "==> Imagens buildadas e carregadas no Minikube."
