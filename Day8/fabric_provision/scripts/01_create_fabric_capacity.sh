#!/usr/bin/env bash
# =============================================================================
# 01_create_fabric_capacity.sh
# -----------------------------------------------------------------------------
# Creates a Resource Group and a Microsoft Fabric capacity (F2 SKU) in Sweden
# Central. This is a REAL, PAID Azure resource (unlike the free Fabric trial
# capacity used earlier in this program) — see the cost note at the bottom.
#
# Usage: ./01_create_fabric_capacity.sh <unique-suffix>
#   e.g. ./01_create_fabric_capacity.sh oaktreefabric01
# =============================================================================
set -euo pipefail

SUFFIX="${1:?Usage: $0 <unique-suffix>, e.g. oaktreefabric01}"

# NOTE: Azure region slugs never use hyphens — "Sweden Central" is
# "swedencentral" as an --location value, not "sweden-central".
LOCATION="swedencentral"
RESOURCE_GROUP="rg-${SUFFIX}"
CAPACITY_NAME="cap${SUFFIX//[-_]/}"
CAPACITY_NAME="${CAPACITY_NAME:0:63}"   # Fabric capacity names: 3-63 chars
SKU_NAME="F2"

echo "=============================================================="
echo " Provisioning a Microsoft Fabric capacity"
echo "   Resource Group : ${RESOURCE_GROUP}"
echo "   Location       : ${LOCATION}"
echo "   Capacity Name  : ${CAPACITY_NAME}"
echo "   SKU            : ${SKU_NAME} (smallest PAID Fabric SKU — see cost note)"
echo "=============================================================="

echo ">> [1/4] Installing the 'microsoft-fabric' Azure CLI extension (if needed)..."
az extension add --name microsoft-fabric --upgrade --yes --output none 2>/dev/null || \
  az extension add --name microsoft-fabric --output none

echo ">> [2/4] Creating resource group..."
az group create \
  --name "${RESOURCE_GROUP}" \
  --location "${LOCATION}" \
  --tags project=OakTreeCapabilityProgram module="Fabric-Provisioning" \
  --output none

echo ">> [3/4] Determining the signed-in user (added as the capacity administrator)..."
ADMIN_UPN=$(az ad signed-in-user show --query userPrincipalName -o tsv)
echo "   Administrator: ${ADMIN_UPN}"

echo ">> [4/4] Creating the Fabric capacity (this typically takes 2-5 minutes)..."
az fabric capacity create \
  --resource-group "${RESOURCE_GROUP}" \
  --capacity-name "${CAPACITY_NAME}" \
  --location "${LOCATION}" \
  --sku "{name:${SKU_NAME},tier:Fabric}" \
  --administration "{members:[${ADMIN_UPN}]}"

echo ">> Waiting for the capacity to report state 'Active'..."
for i in $(seq 1 30); do
  STATE=$(az fabric capacity show \
    --resource-group "${RESOURCE_GROUP}" \
    --capacity-name "${CAPACITY_NAME}" \
    --query "properties.state" -o tsv 2>/dev/null || echo "Provisioning")
  echo "   ...state: ${STATE} (check ${i}/30)"
  if [[ "${STATE}" == "Active" ]]; then
    break
  fi
  sleep 10
done

CAPACITY_ID=$(az fabric capacity show \
  --resource-group "${RESOURCE_GROUP}" \
  --capacity-name "${CAPACITY_NAME}" \
  --query "id" -o tsv)

# The Fabric REST API (used by later scripts) needs the capacity's GUID,
# not its full ARM resource ID — it's the last path segment... actually,
# workspaces/assignToCapacity expects the CAPACITY'S FABRIC-SIDE ID, which
# for Azure-created capacities is discoverable via the Fabric Admin API.
# The simplest reliable way to get it: list capacities via the Fabric API
# and match on display name, which the next script does automatically.

cat > "./fabric_environment.env" <<EOF
RESOURCE_GROUP=${RESOURCE_GROUP}
LOCATION=${LOCATION}
CAPACITY_NAME=${CAPACITY_NAME}
CAPACITY_ARM_ID=${CAPACITY_ID}
ADMIN_UPN=${ADMIN_UPN}
EOF

echo "=============================================================="
echo " DONE. Capacity ARM resource: ${CAPACITY_ID}"
echo " Details saved to ./fabric_environment.env"
echo ""
echo " NEXT: ./02_create_workspace_and_lakehouse.sh"
echo "=============================================================="
echo ""
echo " COST NOTE: F2 is Fabric's smallest PAID SKU — this is NOT the free"
echo " trial capacity used earlier in this program. It bills continuously"
echo " while active. Pause it when not in active use:"
echo "   az fabric capacity suspend --resource-group ${RESOURCE_GROUP} --capacity-name ${CAPACITY_NAME}"
echo " Resume it later with:"
echo "   az fabric capacity resume --resource-group ${RESOURCE_GROUP} --capacity-name ${CAPACITY_NAME}"
echo " Or fully remove it with ./99_teardown.sh when the exercise is complete."
