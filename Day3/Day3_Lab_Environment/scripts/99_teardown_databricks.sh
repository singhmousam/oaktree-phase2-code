#!/usr/bin/env bash
# =============================================================================
# 99_teardown_databricks.sh — deletes the Databricks workspace created for
# this lab. Run at the end of Day 3 to avoid ongoing cluster/DBU cost.
# (This does NOT delete the Day 2 resource group / SQL DB / storage / ADF —
#  run day2_lab/scripts/99_teardown.sh separately for those.)
# =============================================================================
set -euo pipefail

if [ ! -f "./databricks_environment.env" ]; then
  echo "ERROR: databricks_environment.env not found — nothing to tear down,"
  echo "or you're in the wrong directory."
  exit 1
fi
# shellcheck disable=SC1091
source ./databricks_environment.env
[ -f "./lab_environment.env" ] && source ./lab_environment.env

echo "This will delete the Databricks workspace: ${DATABRICKS_WORKSPACE_NAME}"
read -r -p "Type the workspace name to confirm: " CONFIRM

if [ "${CONFIRM}" != "${DATABRICKS_WORKSPACE_NAME}" ]; then
  echo "Confirmation did not match. Aborting."
  exit 1
fi

az databricks workspace delete \
  --resource-group "${RESOURCE_GROUP:?Set RESOURCE_GROUP or source lab_environment.env first}" \
  --name "${DATABRICKS_WORKSPACE_NAME}" \
  --yes --no-wait

echo "Deletion of ${DATABRICKS_WORKSPACE_NAME} has been submitted (running in the background)."
