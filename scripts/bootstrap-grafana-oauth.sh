#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "${ROOT_DIR}/.env" ]]; then
  # shellcheck disable=SC1091
  set -a; source "${ROOT_DIR}/.env"; set +a
fi

OC_BIN="${OC_BIN:-oc}"
GRAFANA_NAMESPACE="${GRAFANA_NAMESPACE:-grafana}"
GRAFANA_OAUTH_SECRET="${GRAFANA_OAUTH_SECRET:-grafana-oauth}"
KEYCLOAK_NAMESPACE="${KEYCLOAK_NAMESPACE:-keycloak-dev}"
KEYCLOAK_ADMIN_SECRET="${KEYCLOAK_ADMIN_SECRET:-keycloak-dev-initial-admin}"
KEYCLOAK_ROUTE_NAME="${KEYCLOAK_ROUTE_NAME:-keycloak}"
KEYCLOAK_BASE_URL="${KEYCLOAK_BASE_URL:-}"
KEYCLOAK_REALM="${KEYCLOAK_REALM:-observability}"
KEYCLOAK_GRAFANA_CLIENT_ID="${KEYCLOAK_GRAFANA_CLIENT_ID:-grafana}"

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[ERROR] Comando obrigatório não encontrado: $1" >&2
    exit 1
  }
}

require "${OC_BIN}"
require curl
require jq
require base64

if [[ -z "${KEYCLOAK_BASE_URL}" ]]; then
  keycloak_route_host="$("${OC_BIN}" -n "${KEYCLOAK_NAMESPACE}" get route "${KEYCLOAK_ROUTE_NAME}" -o jsonpath='{.spec.host}' 2>/dev/null || true)"
  if [[ -z "${keycloak_route_host}" ]]; then
    echo "[ERROR] Defina KEYCLOAK_BASE_URL ou exponha a Route ${KEYCLOAK_NAMESPACE}/${KEYCLOAK_ROUTE_NAME}." >&2
    exit 1
  fi
  KEYCLOAK_BASE_URL="https://${keycloak_route_host}"
fi

admin_user="$("${OC_BIN}" -n "${KEYCLOAK_NAMESPACE}" get secret "${KEYCLOAK_ADMIN_SECRET}" -o jsonpath='{.data.username}' | base64 -d)"
admin_password="$("${OC_BIN}" -n "${KEYCLOAK_NAMESPACE}" get secret "${KEYCLOAK_ADMIN_SECRET}" -o jsonpath='{.data.password}' | base64 -d)"

token_response="$(curl -ksS \
  -d grant_type=password \
  -d client_id=admin-cli \
  --data-urlencode "username=${admin_user}" \
  --data-urlencode "password=${admin_password}" \
  "${KEYCLOAK_BASE_URL}/realms/master/protocol/openid-connect/token")"

access_token="$(printf '%s' "${token_response}" | jq -r '.access_token // empty')"
if [[ -z "${access_token}" ]]; then
  echo "[ERROR] Não foi possível autenticar no Keycloak Admin API." >&2
  exit 1
fi

client_uuid="$(curl -ksS \
  -H "Authorization: Bearer ${access_token}" \
  "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_REALM}/clients?clientId=${KEYCLOAK_GRAFANA_CLIENT_ID}" |
  jq -r '.[0].id // empty')"

if [[ -z "${client_uuid}" ]]; then
  echo "[ERROR] Client ${KEYCLOAK_GRAFANA_CLIENT_ID} não encontrado no realm ${KEYCLOAK_REALM}." >&2
  exit 1
fi

client_secret="$(curl -ksS \
  -H "Authorization: Bearer ${access_token}" \
  "${KEYCLOAK_BASE_URL}/admin/realms/${KEYCLOAK_REALM}/clients/${client_uuid}/client-secret" |
  jq -r '.value // empty')"

if [[ -z "${client_secret}" ]]; then
  echo "[ERROR] Client secret vazio para ${KEYCLOAK_GRAFANA_CLIENT_ID}." >&2
  exit 1
fi

"${OC_BIN}" create namespace "${GRAFANA_NAMESPACE}" --dry-run=client -o yaml | "${OC_BIN}" apply -f - >/dev/null
"${OC_BIN}" -n "${GRAFANA_NAMESPACE}" create secret generic "${GRAFANA_OAUTH_SECRET}" \
  --from-literal=client-id="${KEYCLOAK_GRAFANA_CLIENT_ID}" \
  --from-literal=client-secret="${client_secret}" \
  --dry-run=client -o yaml | "${OC_BIN}" apply -f - >/dev/null

echo "[OK] Secret ${GRAFANA_NAMESPACE}/${GRAFANA_OAUTH_SECRET} reconciliado a partir do Keycloak."
echo "[INFO] Client secret não foi exibido."
