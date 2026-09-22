#!/usr/bin/env bash
# =============================================================================
# 99_teardown.sh — deletes the entire resource group, which removes the
# Fabric capacity (an Azure resource). This does NOT delete the workspace,
# Lakehouse, or Warehouse themselves (those are Fabric-native items, managed
# separately from the Azure capacity resource) -- delete those from the
# Fabric portal, or via the Fabric REST API's delete-workspace call, if you
# want them gone too.
# =============================================================================
set -euo pipefail

if [[ ! -f "./fabric_environment.env" ]]; then
  echo "ERROR: fabric_environment.env not found -- nothing to tear down, or wrong directory." >&2
  exit 1
fi
# shellcheck disable=SC1091
source ./fabric_environment.env

echo "This will PERMANENTLY DELETE the resource group: ${RESOURCE_GROUP}"
echo "(which contains the Fabric capacity '${CAPACITY_NAME}')."
echo ""
echo "NOTE: this does NOT delete the Fabric workspace '${WORKSPACE_NAME:-<not created>}',"
echo "the Lakehouse, or the Warehouse -- those are separate Fabric items."
echo "Delete them from the Fabric portal (Workspace settings > Remove this workspace)"
echo "if you want a fully clean teardown."
echo ""
read -r -p "Type the resource group name to confirm deletion of the CAPACITY: " CONFIRM

if [[ "${CONFIRM}" != "${RESOURCE_GROUP}" ]]; then
  echo "Confirmation did not match. Aborting -- nothing was deleted."
  exit 1
fi

az group delete --name "${RESOURCE_GROUP}" --yes --no-wait
echo "Deletion of ${RESOURCE_GROUP} (and the Fabric capacity within it) has been submitted."
