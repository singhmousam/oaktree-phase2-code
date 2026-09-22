#!/usr/bin/env bash
# =============================================================================
# 02_create_workspace_and_lakehouse.sh
# -----------------------------------------------------------------------------
# Uses the Fabric REST API (api.fabric.microsoft.com) to:
#   1. Look up the Fabric-side GUID for the capacity created in script 01
#      (the ARM resource ID uses the capacity NAME, not this GUID — the
#      Fabric API's own "list capacities" call is the reliable way to get it)
#   2. Delete any existing workspace with the target name, then recreate it
#      assigned to that capacity
#   3. Create a Lakehouse inside that workspace
#
# Requires: ./fabric_environment.env from script 01 and Python 3.
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/fabric_api_helpers.sh"

if [[ ! -f "./fabric_environment.env" ]]; then
  echo "ERROR: fabric_environment.env not found. Run 01_create_fabric_capacity.sh first." >&2
  exit 1
fi
# shellcheck disable=SC1091
source ./fabric_environment.env

SUFFIX="${1:-oaktreefabric01}"
WORKSPACE_NAME="ws-${SUFFIX}"
LAKEHOUSE_NAME="oaktree_trades_lh"

echo "=============================================================="
echo " Creating Fabric workspace + Lakehouse"
echo "   Workspace : ${WORKSPACE_NAME}"
echo "   Lakehouse : ${LAKEHOUSE_NAME}"
echo "   Capacity  : ${CAPACITY_NAME}"
echo "=============================================================="

echo ">> [1/4] Looking up the Fabric-side capacity ID for '${CAPACITY_NAME}'..."
TOKEN=$(fabric_token)
CAPACITIES_JSON=$(curl -s -H "Authorization: Bearer ${TOKEN}" "${FABRIC_API_BASE}/capacities")
CAPACITY_ID=$(python3 -c 'import json,sys; data=json.load(sys.stdin); print(next((item["id"] for item in data.get("value", []) if item.get("displayName") == sys.argv[1]), ""))' "${CAPACITY_NAME}" <<< "${CAPACITIES_JSON}")

if [[ -z "${CAPACITY_ID}" || "${CAPACITY_ID}" == "null" ]]; then
  echo "ERROR: Could not find a Fabric capacity named '${CAPACITY_NAME}' via the Fabric API." >&2
  echo "It can take a few minutes after ARM creation for a capacity to appear here — wait and retry." >&2
  exit 1
fi
echo "   Fabric capacity ID: ${CAPACITY_ID}"

echo ">> [2/4] Replacing any existing workspace named '${WORKSPACE_NAME}'..."
WORKSPACES_JSON=$(curl -s -H "Authorization: Bearer ${TOKEN}" "${FABRIC_API_BASE}/workspaces")
EXISTING_WORKSPACE_ID=$(python3 -c 'import json,sys; data=json.load(sys.stdin); print(next((item["id"] for item in data.get("value", []) if item.get("displayName") == sys.argv[1]), ""))' "${WORKSPACE_NAME}" <<< "${WORKSPACES_JSON}")

if [[ -n "${EXISTING_WORKSPACE_ID}" && "${EXISTING_WORKSPACE_ID}" != "null" ]]; then
  echo "   Existing workspace found (${EXISTING_WORKSPACE_ID}); deleting it..."
  fabric_api_call DELETE "/workspaces/${EXISTING_WORKSPACE_ID}" >/dev/null
  echo "   Existing workspace deleted."
else
  echo "   No existing workspace found."
fi

echo ">> Creating the workspace, assigned to this capacity..."
WORKSPACE_JSON=$(fabric_api_call POST "/workspaces" \
  "{\"displayName\": \"${WORKSPACE_NAME}\", \"description\": \"OakTree Fabric provisioning exercise\", \"capacityId\": \"${CAPACITY_ID}\"}")
WORKSPACE_ID=$(echo "${WORKSPACE_JSON}" | python3 -c 'import json,sys; data=json.load(sys.stdin); print(data.get("id", ""))')

if [[ -z "${WORKSPACE_ID}" || "${WORKSPACE_ID}" == "null" ]]; then
  echo "ERROR: Workspace creation did not return an id. Full response:" >&2
  echo "${WORKSPACE_JSON}" >&2
  exit 1
fi
echo "   Workspace ID: ${WORKSPACE_ID}"

echo ">> [3/4] Creating the Lakehouse..."
LAKEHOUSE_JSON=$(fabric_api_call POST "/workspaces/${WORKSPACE_ID}/lakehouses" \
  "{\"displayName\": \"${LAKEHOUSE_NAME}\"}")
LAKEHOUSE_ID=$(echo "${LAKEHOUSE_JSON}" | python3 -c 'import json,sys; data=json.load(sys.stdin); print(data.get("id", ""))')

if [[ -z "${LAKEHOUSE_ID}" || "${LAKEHOUSE_ID}" == "null" ]]; then
  echo "ERROR: Lakehouse creation did not return an id. Full response:" >&2
  echo "${LAKEHOUSE_JSON}" >&2
  exit 1
fi
echo "   Lakehouse ID: ${LAKEHOUSE_ID}"

echo ">> [4/4] Saving IDs for later scripts..."
cat >> "./fabric_environment.env" <<EOF
WORKSPACE_NAME=${WORKSPACE_NAME}
WORKSPACE_ID=${WORKSPACE_ID}
LAKEHOUSE_NAME=${LAKEHOUSE_NAME}
LAKEHOUSE_ID=${LAKEHOUSE_ID}
FABRIC_CAPACITY_ID=${CAPACITY_ID}
EOF

echo "=============================================================="
echo " DONE."
echo " Workspace : ${WORKSPACE_NAME} (${WORKSPACE_ID})"
echo " Lakehouse : ${LAKEHOUSE_NAME} (${LAKEHOUSE_ID})"
echo ""
echo " NEXT: ./03_upload_sample_data.sh"
echo "=============================================================="
