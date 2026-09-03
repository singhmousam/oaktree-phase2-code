#!/usr/bin/env bash
# =============================================================================
# 01_provision_databricks.sh
# -----------------------------------------------------------------------------
# Provisions an Azure Databricks workspace, creates a small training cluster,
# and imports all five Day 3 notebooks — fully scripted, the same
# Infrastructure-as-Code discipline as Day 2's 01_provision_infra.sh.
#
# Uses the Databricks REST API authenticated with an Azure AD access token
# (obtained via `az account get-access-token`) — no manual PAT token needed.
#
# Prerequisites:
#   - Day 2's lab_environment.env (for the storage account name/key this
#     notebook set will read from)
#   - Azure CLI logged in (`az login`)
#   - `jq` installed (for parsing JSON responses)
# =============================================================================
set -euo pipefail

if [ ! -f "../../../Day2/Day2_Lab_Environment/scripts/lab_environment.env" ] && [ ! -f "./lab_environment.env" ]; then
  echo "WARNING: Day 2's lab_environment.env not found nearby."
  echo "You can still provision Databricks, but you'll need to supply the"
  echo "storage account name/key manually when running the notebooks."
fi
[ -f "./lab_environment.env" ] && source "./lab_environment.env"

LOCATION="${LOCATION:-canadacentral}"
SUFFIX="${1:-oaktreelab-ms}"
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-${SUFFIX}}"
DATABRICKS_WORKSPACE_NAME="dbw-${SUFFIX}"
CLUSTER_NAME="day5-training-cluster"

echo "=============================================================="
echo " Provisioning Day 5 Databricks environment"
echo "   Resource Group      : ${RESOURCE_GROUP}"
echo "   Databricks Workspace: ${DATABRICKS_WORKSPACE_NAME}"
echo "=============================================================="

# ----------------------------- 1. RESOURCE GROUP (reuse if it exists) ------
az group create --name "${RESOURCE_GROUP}" --location "${LOCATION}" --output none

# ----------------------------- 2. DATABRICKS WORKSPACE ----------------------
echo ">> [1/5] Creating Azure Databricks workspace (Standard tier — cheapest for training)..."
az databricks workspace create \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${DATABRICKS_WORKSPACE_NAME}" \
  --location "${LOCATION}" \
  --sku premium \
  --output none

WORKSPACE_URL=$(az databricks workspace show \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${DATABRICKS_WORKSPACE_NAME}" \
  --query "workspaceUrl" -o tsv)
echo "   Workspace URL: https://${WORKSPACE_URL}"

# ----------------------------- 3. AUTHENTICATE TO THE DATABRICKS REST API --
echo ">> [2/5] Getting an Azure AD token scoped to the Databricks resource..."
# 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d is Microsoft's fixed, well-known
# resource ID for the Azure Databricks API — the same for every tenant.
DATABRICKS_AAD_TOKEN=$(az account get-access-token \
  --resource "2ff814a6-3304-4ab8-85cb-cd0e6f879c1d" \
  --query accessToken -o tsv)
ARM_TOKEN=$(az account get-access-token --query accessToken -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

API_BASE="https://${WORKSPACE_URL}/api/2.0"
AUTH_HEADERS=(-H "Authorization: Bearer ${DATABRICKS_AAD_TOKEN}" \
              -H "X-Databricks-Azure-SP-Management-Token: ${ARM_TOKEN}" \
              -H "X-Databricks-Azure-Workspace-Resource-Id: /subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Databricks/workspaces/${DATABRICKS_WORKSPACE_NAME}")

# ----------------------------- 4. CREATE A SMALL TRAINING CLUSTER -----------
echo ">> [3/5] Creating a small training cluster (auto-terminates after 30 min idle)..."
CLUSTER_RESPONSE=$(curl -s -X POST "${API_BASE}/clusters/create" \
  "${AUTH_HEADERS[@]}" \
  -H "Content-Type: application/json" \
  -d '{
    "cluster_name": "'"${CLUSTER_NAME}"'",
    "spark_version": "14.3.x-scala2.12",
    "node_type_id": "Standard_DS3_v2",
    "num_workers": 2,
    "autotermination_minutes": 30,
    "spark_conf": {
      "spark.databricks.delta.preview.enabled": "true"
    }
  }')
# CLUSTER_ID=$(echo "${CLUSTER_RESPONSE}" | jq -r '.cluster_id')
CLUSTER_ID=$(echo "${CLUSTER_RESPONSE}" | grep -o '"cluster_id": *"[^"]*"' | cut -d'"' -f4)

if [ "${CLUSTER_ID}" == "null" ] || [ -z "${CLUSTER_ID}" ]; then
  echo "ERROR creating cluster. Response was:"
  echo "${CLUSTER_RESPONSE}"
  exit 1
fi
echo "   Cluster ID: ${CLUSTER_ID} (starting in the background — takes ~5 minutes)"

# ----------------------------- 5. IMPORT ALL FIVE NOTEBOOKS -----------------
echo ">> [4/5] Importing Day 5 notebooks into /Shared/Day3..."
curl -s -X POST "${API_BASE}/workspace/mkdirs" \
  "${AUTH_HEADERS[@]}" -H "Content-Type: application/json" \
  -d '{"path": "/Shared/Day3"}' > /dev/null

NOTEBOOK_DIR="../databricks_notebooks"
for nb in 01_bronze_to_silver 02_distributed_processing_demo 03_gold_aggregation \
          04_lab_exercise_STARTER 05_lab_solution_REFERENCE; do
  CONTENT_B64=$(base64 -w0 "${NOTEBOOK_DIR}/${nb}.py" 2>/dev/null || base64 "${NOTEBOOK_DIR}/${nb}.py")
  curl -s -X POST "${API_BASE}/workspace/import" \
    "${AUTH_HEADERS[@]}" -H "Content-Type: application/json" \
    -d '{
      "path": "/Shared/Day3/'"${nb}"'",
      "format": "SOURCE",
      "language": "PYTHON",
      "content": "'"${CONTENT_B64}"'",
      "overwrite": true
    }' > /dev/null
  echo "   Imported: /Shared/Day3/${nb}"
done

# ----------------------------- 6. SAVE ENVIRONMENT DETAILS ------------------
echo ">> [5/5] Writing databricks_environment.env ..."
cat > "./databricks_environment.env" <<EOF
DATABRICKS_WORKSPACE_NAME=${DATABRICKS_WORKSPACE_NAME}
DATABRICKS_WORKSPACE_URL=https://${WORKSPACE_URL}
DATABRICKS_CLUSTER_ID=${CLUSTER_ID}
EOF

echo "=============================================================="
echo " DONE."
echo " Workspace : https://${WORKSPACE_URL}"
echo " Cluster   : ${CLUSTER_NAME} (${CLUSTER_ID}) — starting now, ~5 min to ready"
echo " Notebooks : /Shared/Day3/ (all 5 imported)"
echo ""
echo " NEXT STEPS:"
echo "   1. Open the workspace URL above, wait for the cluster to show 'Running'"
echo "   2. Open /Shared/Day3/01_bronze_to_silver, attach it to ${CLUSTER_NAME}"
echo "   3. Fill in the storage_account_name / storage_account_key widgets"
echo "      (from Day 2's lab_environment.env) and Run All"
echo "=============================================================="
echo ""
echo " COST NOTE: the cluster auto-terminates after 30 minutes idle. Run"
echo " ./99_teardown_databricks.sh at the end of the day regardless, to"
echo " remove the workspace itself."
