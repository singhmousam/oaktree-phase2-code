#!/usr/bin/env bash
# =============================================================================
# fabric_api_helpers.sh
# -----------------------------------------------------------------------------
# Shared functions used by every numbered script in this package. Source this
# file rather than running it directly:  source ./fabric_api_helpers.sh
#
# Handles two things every Fabric REST API caller needs:
#   1. Getting a fresh Entra ID token scoped to the Fabric API
#   2. Correctly waiting for Fabric's Long-Running-Operation (LRO) pattern —
#      many Fabric create/update calls return 202 Accepted immediately and
#      finish the actual work in the background; you must poll the
#      Location header until the operation reports "Succeeded".
# =============================================================================
set -euo pipefail

FABRIC_API_BASE="https://api.fabric.microsoft.com/v1"

fabric_token() {
  az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv
}

# Polls a Fabric long-running-operation until it finishes.
# Usage: poll_fabric_lro "<operation-location-url>"
# Prints the final operation JSON to stdout on success; exits non-zero on failure.
poll_fabric_lro() {
  local op_url="$1"
  local token
  token=$(fabric_token)
  local status="Running"
  local attempt=0

  while [[ "$status" == "Running" || "$status" == "NotStarted" ]]; do
    attempt=$((attempt + 1))
    if [[ $attempt -gt 60 ]]; then
      echo "ERROR: operation did not complete after 5 minutes of polling: ${op_url}" >&2
      return 1
    fi
    sleep 5
    local resp
    resp=$(curl -s -H "Authorization: Bearer ${token}" "${op_url}")
    status=$(echo "${resp}" | jq -r '.status // "Unknown"')
    echo "  ...operation status: ${status} (poll ${attempt}/60)" >&2
  done

  if [[ "$status" != "Succeeded" ]]; then
    echo "ERROR: operation finished with non-success status: ${status}" >&2
    echo "${resp}" >&2
    return 1
  fi

  echo "${resp}"
}

# Makes a Fabric REST API call, correctly handling both the immediate
# (200/201) and long-running (202 + Location header) response patterns.
# Usage: fabric_api_call POST "/workspaces" '{"displayName": "..."}'
# Prints the final resource JSON to stdout.
fabric_api_call() {
  local method="$1"
  local path="$2"
  local body="${3:-}"
  local token
  token=$(fabric_token)

  local tmp_headers
  tmp_headers=$(mktemp)

  local curl_args=(-s -D "${tmp_headers}" -X "${method}" \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json" \
    "${FABRIC_API_BASE}${path}")
  if [[ -n "${body}" ]]; then
    curl_args+=(-d "${body}")
  fi

  local resp
  resp=$(curl "${curl_args[@]}")

  local http_status
  http_status=$(head -n1 "${tmp_headers}" | awk '{print $2}')

  if [[ "${http_status}" == "202" ]]; then
    local location
    location=$(grep -i '^Location:' "${tmp_headers}" | sed 's/^[Ll]ocation: //' | tr -d '\r')
    echo "  ...request accepted (202), polling: ${location}" >&2
    rm -f "${tmp_headers}"
    poll_fabric_lro "${location}"
  else
    rm -f "${tmp_headers}"
    echo "${resp}"
  fi
}
