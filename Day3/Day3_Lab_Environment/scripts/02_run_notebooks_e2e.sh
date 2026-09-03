#!/usr/bin/env bash
# =============================================================================
# 02_run_notebooks_e2e.sh
# -----------------------------------------------------------------------------
# Runs Notebooks 1-3 back to back on the cluster created by
# 01_provision_databricks.sh, using the Databricks Jobs API's one-off
# "run now" submission — no need to click through the UI notebook by
# notebook. Useful for a fast facilitator sanity-check before class, or
# for re-running the whole chain for a new window_date.
#
# Usage:
#   ./02_run_notebooks_e2e.sh <window_date> <storage_account_name> <storage_account_key>
# =============================================================================
set -euo pipefail

WINDOW_DATE="${1:?Usage: $0 <window_date> <storage_account_name> <storage_account_key>}"
STORAGE_ACCOUNT_NAME="${2:?Missing storage_account_name}"
STORAGE_ACCOUNT_KEY="${3:?Missing storage_account_key}"

source ./databricks_environment.env

DATABRICKS_AAD_TOKEN=$(az account get-access-token \
  --resource "2ff814a6-3304-4ab8-85cb-cd0e6f879c1d" \
  --query accessToken -o tsv)
ARM_TOKEN=$(az account get-access-token --query accessToken -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
API_BASE="${DATABRICKS_WORKSPACE_URL}/api/2.1"
AUTH_HEADERS=(-H "Authorization: Bearer ${DATABRICKS_AAD_TOKEN}" \
              -H "X-Databricks-Azure-SP-Management-Token: ${ARM_TOKEN}" \
              -H "X-Databricks-Azure-Workspace-Resource-Id: /subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Databricks/workspaces/${DATABRICKS_WORKSPACE_NAME}")

run_notebook() {
  local notebook_path="$1"
  echo ">> Submitting ${notebook_path} for window_date=${WINDOW_DATE} ..."
  RUN_RESPONSE=$(curl -s -X POST "${API_BASE}/jobs/runs/submit" \
    "${AUTH_HEADERS[@]}" -H "Content-Type: application/json" \
    -d '{
      "run_name": "day3-'"$(basename "$notebook_path")"'-'"${WINDOW_DATE}"'",
      "existing_cluster_id": "'"${DATABRICKS_CLUSTER_ID}"'",
      "notebook_task": {
        "notebook_path": "'"${notebook_path}"'",
        "base_parameters": {
          "window_date": "'"${WINDOW_DATE}"'",
          "storage_account_name": "'"${STORAGE_ACCOUNT_NAME}"'",
          "storage_account_key": "'"${STORAGE_ACCOUNT_KEY}"'"
        }
      }
    }')
  # RUN_ID=$(echo "${RUN_RESPONSE}" | jq -r '.run_id')
  # echo "   Run ID: ${RUN_ID} — poll status with:"
  # echo "   curl -s ${API_BASE}/jobs/runs/get?run_id=${RUN_ID} \"\${AUTH_HEADERS[@]}\" | jq '.state'"
  # Extract run_id value
  RUN_ID=$(echo "${RUN_RESPONSE}" | grep -o '"run_id": *[0-9]*' | cut -d':' -f2 | tr -d ' ')
  echo "   Run ID: ${RUN_ID} — poll status with:"
  echo "   curl -s \"${API_BASE}/jobs/runs/get?run_id=${RUN_ID}\" \"\${AUTH_HEADERS[@]}\" | grep -o '\"state\": *{[^}]*}'"
  echo "${RUN_ID}"
}

run_notebook "/Shared/Day3/01_bronze_to_silver"
run_notebook "/Shared/Day3/02_distributed_processing_demo"
run_notebook "/Shared/Day3/03_gold_aggregation"

echo "All three runs submitted. Watch progress in the workspace UI under Workflows > Job Runs."
