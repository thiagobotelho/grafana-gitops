#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

load_env_file() {
  local env_file="$1"
  local line key value

  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line%$'\r'}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"

    [[ -z "${line}" || "${line}" == \#* ]] && continue

    if [[ "${line}" == export[[:space:]]* ]]; then
      line="${line#export}"
      line="${line#"${line%%[![:space:]]*}"}"
    fi

    if [[ ! "${line}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
      echo "[WARN] Linha ignorada em ${env_file}: formato inválido para .env" >&2
      continue
    fi

    key="${line%%=*}"
    value="${line#*=}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    if [[ "${value}" =~ ^\"(.*)\"$ ]]; then
      value="${BASH_REMATCH[1]}"
    elif [[ "${value}" =~ ^\'(.*)\'$ ]]; then
      value="${BASH_REMATCH[1]}"
    fi

    export "${key}=${value}"
  done < "${env_file}"
}

if [[ -f "${ROOT_DIR}/.env" ]]; then
  load_env_file "${ROOT_DIR}/.env"
fi

OC_BIN="${OC_BIN:-oc}"
GRAFANA_NAMESPACE="${GRAFANA_NAMESPACE:-grafana}"
GRAFANA_OAUTH_SECRET="${GRAFANA_OAUTH_SECRET:-grafana-oauth}"
GRAFANA_ROUTE_NAME="${GRAFANA_ROUTE_NAME:-grafana-route}"
GRAFANA_ADMIN_SECRET="${GRAFANA_ADMIN_SECRET:-grafana-admin-credentials}"
GRAFANA_ENABLE_ZABBIX_APP_PLUGIN="${GRAFANA_ENABLE_ZABBIX_APP_PLUGIN:-true}"
GRAFANA_ZABBIX_APP_PLUGIN_ID="${GRAFANA_ZABBIX_APP_PLUGIN_ID:-alexanderzobnin-zabbix-app}"
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

route_url() {
  local namespace="$1"
  local route="$2"
  local host
  host="$("${OC_BIN}" -n "${namespace}" get route "${route}" -o jsonpath='{.spec.host}' 2>/dev/null || true)"
  if [[ -n "${host}" ]]; then
    printf 'https://%s' "${host}"
  fi
}

if [[ -z "${KEYCLOAK_BASE_URL}" ]]; then
  KEYCLOAK_BASE_URL="$(route_url "${KEYCLOAK_NAMESPACE}" "${KEYCLOAK_ROUTE_NAME}")"
  if [[ -z "${KEYCLOAK_BASE_URL}" ]]; then
    echo "[ERROR] Defina KEYCLOAK_BASE_URL ou exponha a Route ${KEYCLOAK_NAMESPACE}/${KEYCLOAK_ROUTE_NAME}." >&2
    exit 1
  fi
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

enable_grafana_zabbix_app_plugin() {
  local grafana_base_url grafana_user grafana_password response_file http_code

  if [[ "${GRAFANA_ENABLE_ZABBIX_APP_PLUGIN}" != "true" ]]; then
    return 0
  fi

  grafana_base_url="$(route_url "${GRAFANA_NAMESPACE}" "${GRAFANA_ROUTE_NAME}")"
  if [[ -z "${grafana_base_url}" ]]; then
    echo "[WARN] Route ${GRAFANA_NAMESPACE}/${GRAFANA_ROUTE_NAME} não encontrada; plugin ${GRAFANA_ZABBIX_APP_PLUGIN_ID} não será habilitado agora." >&2
    return 0
  fi

  if ! "${OC_BIN}" -n "${GRAFANA_NAMESPACE}" get secret "${GRAFANA_ADMIN_SECRET}" >/dev/null 2>&1; then
    echo "[WARN] Secret ${GRAFANA_NAMESPACE}/${GRAFANA_ADMIN_SECRET} não encontrado; reexecute após o Grafana subir para habilitar ${GRAFANA_ZABBIX_APP_PLUGIN_ID}." >&2
    return 0
  fi

  grafana_user="$("${OC_BIN}" -n "${GRAFANA_NAMESPACE}" get secret "${GRAFANA_ADMIN_SECRET}" -o jsonpath='{.data.GF_SECURITY_ADMIN_USER}' | base64 -d)"
  grafana_password="$("${OC_BIN}" -n "${GRAFANA_NAMESPACE}" get secret "${GRAFANA_ADMIN_SECRET}" -o jsonpath='{.data.GF_SECURITY_ADMIN_PASSWORD}' | base64 -d)"
  response_file="$(mktemp)"

  http_code="$(curl -ksS \
    -o "${response_file}" \
    -w '%{http_code}' \
    -u "${grafana_user}:${grafana_password}" \
    -X POST \
    -H 'Content-Type: application/json' \
    -d '{"enabled":true,"pinned":true}' \
    "${grafana_base_url}/api/plugins/${GRAFANA_ZABBIX_APP_PLUGIN_ID}/settings" || true)"

  if [[ "${http_code}" =~ ^2 ]]; then
    rm -f "${response_file}"
    echo "[OK] Plugin ${GRAFANA_ZABBIX_APP_PLUGIN_ID} habilitado no Grafana."
    return 0
  fi

  echo "[WARN] Não foi possível habilitar ${GRAFANA_ZABBIX_APP_PLUGIN_ID} agora. HTTP ${http_code}." >&2
  if [[ -s "${response_file}" ]]; then
    if jq -e . "${response_file}" >/dev/null 2>&1; then
      jq -r '.message // .error // empty' "${response_file}" >&2 || true
    else
      echo "[WARN] Resposta do Grafana não estava em JSON; reexecute quando o pod estiver Ready." >&2
    fi
  fi
  rm -f "${response_file}"
}

enable_grafana_zabbix_app_plugin

echo "[OK] Secret ${GRAFANA_NAMESPACE}/${GRAFANA_OAUTH_SECRET} reconciliado a partir do Keycloak."
echo "[INFO] Client secret não foi exibido."
