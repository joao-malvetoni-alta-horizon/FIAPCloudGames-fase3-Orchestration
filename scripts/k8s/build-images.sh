#!/usr/bin/env bash
# Builda as imagens Docker das 4 APIs e carrega no Minikube.
# Le os caminhos dos repos irmaos do .env (mesmas variaveis do docker-compose).
#
# ----------------------------------------------------------------------
# A ARMADILHA QUE ESTE SCRIPT RESOLVE (leia antes de simplificar)
# ----------------------------------------------------------------------
# `minikube image load fcg/users-api:1.0` NAO sobrescreve uma tag que ja existe
# no cluster quando um container esta usando aquela imagem: o comando termina
# com SUCESSO, sem aviso, e o cluster continua rodando a imagem antiga.
#
# Somado ao `imagePullPolicy: IfNotPresent` e a uma tag fixa (`:1.0`), isso cria
# um `make k8s-up` que parece funcionar e nao muda nada: o `kubectl apply` nao
# altera o pod spec (a tag e a mesma), entao nem ha rollout.
#
# Sintoma real que isso ja causou: o users-api seguiu rodando um build antigo,
# de antes da claim `iss` existir, e TODA chamada autenticada pelo gateway
# voltava `401 {"message":"No mandatory 'iss' in claims"}` -- com o codigo-fonte,
# o manifesto e a config do Kong todos corretos.
#
# Por isso, para cada servico, comparamos o ID da imagem no host com o ID no
# cluster e, se divergirem, derrubamos os pods (a tag so pode ser trocada quando
# nenhum container a usa), trocamos a imagem e subimos de novo.
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

NAMESPACE="fcg"

# nome do servico | contexto de build | Dockerfile (relativo ao contexto)
SERVICES=(
  "users-api|$USERS_API_PATH|src/FCG.API/Dockerfile"
  "catalog-api|$CATALOG_API_PATH|src/CatalogAPI.API/Dockerfile"
  "payments-api|$PAYMENTS_API_PATH|src/FCG.API/Dockerfile"
  "notifications-api|$NOTIFICATIONS_API_PATH/NotificationsAPI|src/Notifications.API/Dockerfile"
)

host_image_id() {
  docker images --no-trunc --format '{{.ID}}' "$1" 2>/dev/null | head -1
}

cluster_image_id() {
  minikube ssh -- "docker images --no-trunc --format '{{.ID}}' $1" 2>/dev/null | tr -d '\r' | head -1
}

total="${#SERVICES[@]}"
i=0
SKIPPED=()

for entry in "${SERVICES[@]}"; do
  i=$((i + 1))
  IFS='|' read -r name ctx dockerfile <<< "$entry"
  image="fcg/$name:1.0"

  echo "==> [$i/$total] $name"

  # Um repo de servico pode ter sido reestruturado e nao ter mais o Dockerfile
  # neste caminho. Sem esta checagem, o `set -e` mataria o script no meio e os
  # servicos seguintes (e a conferencia final) nunca rodariam.
  if [ ! -f "$ctx/$dockerfile" ]; then
    echo "    [skip] Dockerfile nao encontrado em $ctx/$dockerfile" >&2
    echo "           o repo do $name provavelmente foi reestruturado." >&2
    SKIPPED+=("$name")
    continue
  fi

  docker build -t "$image" "$ctx" -f "$ctx/$dockerfile"

  host_id="$(host_image_id "$image")"
  cluster_id="$(cluster_image_id "$image")"

  if [ -n "$cluster_id" ] && [ "$host_id" = "$cluster_id" ]; then
    echo "    imagem do cluster ja e identica a do host (${host_id:7:12}) - nada a fazer"
    continue
  fi

  # A tag no cluster esta ausente ou desatualizada. Se ha Deployment de pe, ele
  # precisa sair do ar para a tag ficar livre (docker nao remove imagem em uso).
  replicas=""
  if kubectl get deployment "$name" -n "$NAMESPACE" >/dev/null 2>&1; then
    replicas="$(kubectl get deployment "$name" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')"
    echo "    imagem do cluster desatualizada; escalando $name para 0 para liberar a tag"
    kubectl scale deployment/"$name" --replicas=0 -n "$NAMESPACE" >/dev/null
    kubectl wait --for=delete pod -l app="$name" -n "$NAMESPACE" --timeout=120s >/dev/null 2>&1 || true
  fi

  minikube image rm "$image" >/dev/null 2>&1 || true
  minikube image load "$image"

  if [ -n "$replicas" ]; then
    echo "    voltando $name para $replicas replica(s) com a imagem nova"
    kubectl scale deployment/"$name" --replicas="$replicas" -n "$NAMESPACE" >/dev/null
  fi
done

# Cinto de seguranca: um "load" que nao pegou passa desapercebido, entao
# conferimos explicitamente e falhamos alto se o cluster ficou defasado.
echo "==> Conferindo se o cluster ficou com as imagens do host"
divergentes=0
for entry in "${SERVICES[@]}"; do
  IFS='|' read -r name _ _ <<< "$entry"
  image="fcg/$name:1.0"
  host_id="$(host_image_id "$image")"
  cluster_id="$(cluster_image_id "$image")"

  # Servico sem Dockerfile: nao foi rebuildado agora. O cluster segue com a
  # imagem carregada em algum build anterior - dizemos isso em voz alta.
  if [[ " ${SKIPPED[*]-} " == *" $name "* ]]; then
    if [ -n "$cluster_id" ]; then
      printf '    [skip] %-20s sem Dockerfile; cluster mantem %s (build anterior)\n' "$name" "${cluster_id:7:12}"
    else
      printf '    [!!]  %-20s sem Dockerfile e sem imagem no cluster\n' "$name"
      divergentes=$((divergentes + 1))
    fi
    continue
  fi

  if [ "$host_id" = "$cluster_id" ]; then
    printf '    [ok]  %-20s %s\n' "$name" "${host_id:7:12}"
  else
    printf '    [!!]  %-20s host=%s cluster=%s\n' "$name" "${host_id:7:12}" "${cluster_id:7:12}"
    divergentes=$((divergentes + 1))
  fi
done

if [ "$divergentes" -gt 0 ]; then
  echo "!! $divergentes imagem(ns) do cluster nao confere(m) com o host." >&2
  echo "   Os pods rodariam codigo antigo. Verifique se o minikube esta de pe e rode de novo." >&2
  exit 1
fi

if [ "${#SKIPPED[@]-0}" -gt 0 ] 2>/dev/null && [ -n "${SKIPPED[*]-}" ]; then
  echo "!! Sem Dockerfile, nao rebuildado(s): ${SKIPPED[*]}" >&2
  echo "   O cluster continua com a imagem de um build anterior desses servicos." >&2
fi

echo "==> Imagens buildadas e carregadas no Minikube."
