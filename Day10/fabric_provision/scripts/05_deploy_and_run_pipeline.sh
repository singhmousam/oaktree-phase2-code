#!/usr/bin/env bash
# =============================================================================
# 05_deploy_and_run_pipeline.sh
# -----------------------------------------------------------------------------
# The step that makes this genuinely END-TO-END rather than "infrastructure
# only": imports the Bronze -> Silver -> Gold (+ SCD2) notebook into the
# workspace via the Fabric Items API, then triggers a real run via the
# Job Scheduler API and polls it to completion.
#
# No `jq` used anywhere in this script — JSON construction and field
# extraction both use inline `python3 -c`.
#
# Requires: ./fabric_environment.env from scripts 01-04.
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/fabric_api_helpers.sh"

if [[ ! -f "./fabric_environment.env" ]]; then
  echo "ERROR: fabric_environment.env not found. Run scripts 01-04 first." >&2
  exit 1
fi
# shellcheck disable=SC1091
source ./fabric_environment.env

NOTEBOOK_PATH="${1:-../notebook/fabric_intro_etl_notebook.py}"
NOTEBOOK_NAME="pipeline_bronze_silver_gold_scd2"
STORAGE_ACCOUNT_NAME="${STORAGE_ACCOUNT_NAME:-}"
STORAGE_ACCOUNT_KEY="${STORAGE_ACCOUNT_KEY:-}"
WINDOW_DATE="${WINDOW_DATE:-2026-05-01}"
SNAPSHOT_DATE="${SNAPSHOT_DATE:-2026-06-01}"

if [[ ! -f "${NOTEBOOK_PATH}" ]]; then
  echo "ERROR: notebook file not found at ${NOTEBOOK_PATH}" >&2
  echo "Pass its path explicitly: $0 /path/to/notebook.py" >&2
  exit 1
fi

echo "=============================================================="
echo " Deploying and running the end-to-end pipeline notebook"
echo "   Notebook  : ${NOTEBOOK_NAME}"
echo "   Workspace : ${WORKSPACE_NAME}"
echo "   Lakehouse : ${LAKEHOUSE_NAME}"
echo "=============================================================="

# ---------------------------------------------------------------------
# 1. Build the notebook item definition. A Fabric notebook item needs
#    TWO parts: the actual source content, and a small ".platform"
#    metadata file. Both are base64-encoded and sent inline.
#    This JSON construction (nested, multi-part, base64) is exactly the
#    kind of thing that's clearer in python3 -c than in a jq filter --
#    another place we deliberately reach for inline python.
# ---------------------------------------------------------------------
echo ">> [1/4] Building the notebook definition payload..."

NOTEBOOK_CONTENT_B64=$(python3 -c 'import base64,sys; print(base64.b64encode(open(sys.argv[1], "rb").read()).decode())' "${NOTEBOOK_PATH}")

PLATFORM_B64=$(python3 -c '
import json, base64, sys
platform_doc = {
    "$schema": "https://developer.microsoft.com/json-schemas/fabric/gitIntegration/platformProperties/2.0.0/schema.json",
    "metadata": {"type": "Notebook", "displayName": sys.argv[1], "description": "Bronze->Silver->Gold with SCD2, deployed by 05_deploy_and_run_pipeline.sh"},
    "config": {"version": "2.0", "logicalId": "00000000-0000-0000-0000-000000000000"},
}
print(base64.b64encode(json.dumps(platform_doc).encode()).decode())
' "${NOTEBOOK_NAME}")

NOTEBOOK_BODY=$(python3 -c '
import json, sys
body = {
    "displayName": sys.argv[1],
    "description": "End-to-end capstone pipeline: Bronze -> Silver -> Gold, SCD2 at Gold",
    "definition": {
        "format": "fabricGitSource",
        "parts": [
            {"path": "notebook-content.py", "payload": sys.argv[2], "payloadType": "InlineBase64"},
            {"path": ".platform", "payload": sys.argv[3], "payloadType": "InlineBase64"},
        ],
    },
}
print(json.dumps(body))
' "${NOTEBOOK_NAME}" "${NOTEBOOK_CONTENT_B64}" "${PLATFORM_B64}")

# ---------------------------------------------------------------------
# 2. Create the notebook item in the workspace
# ---------------------------------------------------------------------
echo ">> [2/4] Finding or creating the notebook item in the workspace..."
NOTEBOOKS_JSON=$(curl -s -H "Authorization: Bearer ${TOKEN:-$(fabric_token)}" \
  "${FABRIC_API_BASE}/workspaces/${WORKSPACE_ID}/notebooks")
NOTEBOOK_ID=$(echo "${NOTEBOOKS_JSON}" | python3 -c 'import json,sys; data=json.load(sys.stdin); print(next((item.get("id", "") for item in data.get("value", []) if item.get("displayName") == sys.argv[1]), ""))' "${NOTEBOOK_NAME}")

if [[ -n "${NOTEBOOK_ID}" && "${NOTEBOOK_ID}" != "null" ]]; then
  echo "   Existing notebook found; reusing it."
else
  NOTEBOOK_JSON=$(fabric_api_call POST "/workspaces/${WORKSPACE_ID}/notebooks" "${NOTEBOOK_BODY}")
  # NOTEBOOK_ID=$(echo "${NOTEBOOK_JSON}" | jq -r '.id')
  NOTEBOOK_ID=$(echo "${NOTEBOOK_JSON}" | python3 -c 'import json,sys; v=json.load(sys.stdin).get("id"); print(v or "")')

  if [[ -z "${NOTEBOOK_ID}" || "${NOTEBOOK_ID}" == "null" ]]; then
    NOTEBOOKS_JSON=$(curl -s -H "Authorization: Bearer ${TOKEN:-$(fabric_token)}" \
      "${FABRIC_API_BASE}/workspaces/${WORKSPACE_ID}/notebooks")
    NOTEBOOK_ID=$(echo "${NOTEBOOKS_JSON}" | python3 -c 'import json,sys; data=json.load(sys.stdin); print(next((item.get("id", "") for item in data.get("value", []) if item.get("displayName") == sys.argv[1]), ""))' "${NOTEBOOK_NAME}")
  fi
fi

if [[ -z "${NOTEBOOK_ID}" || "${NOTEBOOK_ID}" == "null" ]]; then
  echo "ERROR: Notebook creation did not return an id. Full response:" >&2
  echo "${NOTEBOOK_JSON:-${NOTEBOOKS_JSON}}" >&2
  exit 1
fi
echo "   Notebook ID: ${NOTEBOOK_ID}"

# ---------------------------------------------------------------------
# 3. Trigger a real run via the Job Scheduler API, passing this
#    notebook's parameters (storage credentials + window/snapshot
#    dates) exactly as base_parameters, the same pattern used for the
#    Day 2 ADF windowDate parameter and the dbt SNAPSHOT_DATE variable.
# ---------------------------------------------------------------------
echo ">> [3/4] Triggering a run..."

RUN_BODY=$(python3 -c '
import json, sys
storage_account_name, storage_account_key, window_date, snapshot_date, lakehouse_name, lakehouse_id, workspace_id = sys.argv[1:8]
body = {
    "executionData": {
        "parameters": {
            "storage_account_name": {"value": storage_account_name, "type": "string"},
            "storage_account_key": {"value": storage_account_key, "type": "string"},
            "window_date": {"value": window_date, "type": "string"},
            "snapshot_date": {"value": snapshot_date, "type": "string"},
        },
        "configuration": {
            "useStarterPool": True,
            "defaultLakehouse": {"name": lakehouse_name, "id": lakehouse_id, "workspaceId": workspace_id},
        },
    }
}
print(json.dumps(body))
' "${STORAGE_ACCOUNT_NAME}" "${STORAGE_ACCOUNT_KEY}" "${WINDOW_DATE}" "${SNAPSHOT_DATE}" "${LAKEHOUSE_NAME}" "${LAKEHOUSE_ID}" "${WORKSPACE_ID}")

TOKEN=$(fabric_token)
TMP_HEADERS=$(mktemp)
curl -s -D "${TMP_HEADERS}" -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${RUN_BODY}" \
  "${FABRIC_API_BASE}/workspaces/${WORKSPACE_ID}/items/${NOTEBOOK_ID}/jobs/instances?jobType=RunNotebook" \
  -o /dev/null

JOB_STATUS_URL=$(grep -i '^Location:' "${TMP_HEADERS}" | sed 's/^[Ll]ocation: //' | tr -d '\r')
rm -f "${TMP_HEADERS}"

if [[ -z "${JOB_STATUS_URL}" ]]; then
  echo "ERROR: no job status URL returned — the run may not have started. Check the workspace's Monitoring Hub." >&2
  exit 1
fi
echo "   Job submitted. Status URL: ${JOB_STATUS_URL}"

# ---------------------------------------------------------------------
# 4. Poll until the run finishes, and report the result
# ---------------------------------------------------------------------
echo ">> [4/4] Waiting for the run to finish (this can take several minutes)..."
JOB_RESULT=$(poll_notebook_job "${JOB_STATUS_URL}")
# EXIT_VALUE=$(echo "${JOB_RESULT}" | jq -r '.exitValue // "n/a"')
EXIT_VALUE=$(echo "${JOB_RESULT}" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("exitValue") or "n/a")')

cat >> "./fabric_environment.env" <<EOF
NOTEBOOK_ID=${NOTEBOOK_ID}
NOTEBOOK_NAME=${NOTEBOOK_NAME}
EOF

echo "=============================================================="
echo " DONE. Pipeline ran to completion."
echo " Notebook exit value: ${EXIT_VALUE}"
echo ""
echo " VERIFY in the Fabric portal:"
echo "   Open ${LAKEHOUSE_NAME} -> Tables -> confirm silver_trades,"
echo "   gold_fact_trades_daily, and gold_dim_trader_scd2 all exist"
echo "   and show the row counts documented in this program's guides"
echo "   (Silver: 554 rows for the full sample; Gold SCD2 dimension:"
echo "   6 -> 10 rows after the June snapshot)."
echo "=============================================================="
