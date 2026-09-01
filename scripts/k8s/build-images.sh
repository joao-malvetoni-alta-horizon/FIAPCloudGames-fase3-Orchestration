#!/usr/bin/env bash
# Builda as imagens Docker das 4 APIs e carrega no Minikube.
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
NOTIFICATIONS_API_PATH="${NOTIFICATIONS_API_PATH:-../FIAPCloudGames-fase3-NotificationsAPI}"

cd "$ROOT_DIR"

echo "==> [1/4] users-api"
docker build -t fcg/users-api:1.0 "$USERS_API_PATH" -f "$USERS_API_PATH/src/FCG.API/Dockerfile"
minikube image load fcg/users-api:1.0

echo "==> [2/4] catalog-api"
docker build -t fcg/catalog-api:1.0 "$CATALOG_API_PATH" -f "$CATALOG_API_PATH/src/CatalogAPI.API/Dockerfile"
minikube image load fcg/catalog-api:1.0

echo "==> [3/4] payments-api"
docker build -t fcg/payments-api:1.0 "$PAYMENTS_API_PATH" -f "$PAYMENTS_API_PATH/src/FCG.API/Dockerfile"
minikube image load fcg/payments-api:1.0

echo "==> [4/4] notifications-api"
docker build -t fcg/notifications-api:1.0 "$NOTIFICATIONS_API_PATH/NotificationsAPI" -f "$NOTIFICATIONS_API_PATH/NotificationsAPI/src/Notifications.API/Dockerfile"
minikube image load fcg/notifications-api:1.0

echo "==> Imagens buildadas e carregadas no Minikube."
