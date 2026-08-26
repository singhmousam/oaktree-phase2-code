#!/usr/bin/env bash
# =============================================================================
# 99_teardown.sh — deletes the entire resource group created for this lab.
# Run at the end of Day 2 (or end of the training day) if this is a shared
# or temporary training subscription, to avoid ongoing cost.
# =============================================================================
set -euo pipefail

if [ ! -f "./lab_environment.env" ]; then
  echo "ERROR: lab_environment.env not found — nothing to tear down, or you're in the wrong directory."
  exit 1
fi
# shellcheck disable=SC1091
source ./lab_environment.env

echo "This will PERMANENTLY DELETE the resource group: ${RESOURCE_GROUP}"
echo "including the SQL Database, Storage Account, Key Vault, and Data Factory."
read -r -p "Type the resource group name to confirm deletion: " CONFIRM

if [ "${CONFIRM}" != "${RESOURCE_GROUP}" ]; then
  echo "Confirmation did not match. Aborting — nothing was deleted."
  exit 1
fi

az group delete --name "${RESOURCE_GROUP}" --yes --no-wait
echo "Deletion of ${RESOURCE_GROUP} has been submitted (running in the background)."
