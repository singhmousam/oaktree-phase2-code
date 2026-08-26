#!/usr/bin/env bash
# =============================================================================
# 01_provision_infra.sh
# -----------------------------------------------------------------------------
# Provisions every Azure resource used in the Day 2 (and onward) hands-on labs:
#   - Resource Group
#   - Azure SQL Server + Database   (stands in for the legacy Oracle system)
#   - Storage Account (ADLS Gen2)   (the Lakehouse landing zone: bronze/silver)
#   - Key Vault                     (secrets: SQL admin password, conn strings)
#   - Azure Data Factory            (today's orchestration engine)
#   - Role assignments              (least-privilege, per Day 1's security-by-
#                                     design principle: ADF's managed identity
#                                     gets Storage Blob Data Contributor only)
#
# Run this ONCE per participant/team before Day 2 begins. Everything uses
# cheap SKUs (SQL Serverless, Storage Standard LRS) suitable for a training
# sandbox — see the cost note at the bottom.
#
# Prerequisites: Azure CLI installed and logged in (`az login`), and an
# active subscription selected (`az account set --subscription "<name>"`).
# =============================================================================
set -euo pipefail

# ----------------------------- CONFIGURATION --------------------------------
LOCATION="canadacentral"                     # change to your region
SUFFIX="${1:-oaktreelab01}"                 # pass a unique suffix per team, e.g. ./01_provision_infra.sh oaktreelab-team3
RESOURCE_GROUP="rg-${SUFFIX}"

SQL_SERVER_NAME="sql-${SUFFIX}"
SQL_DB_NAME="oaktree_trades_db"
SQL_ADMIN_USER="oaktreeadmin"
SQL_ADMIN_PASSWORD="$(openssl rand -base64 18 | tr -d '=+/' )Aa1!"   # generated; also saved to Key Vault below

STORAGE_ACCOUNT_NAME="st${SUFFIX//[-_]/}data"   # storage account names must be globally unique, lowercase, no hyphens
STORAGE_ACCOUNT_NAME="${STORAGE_ACCOUNT_NAME:0:24}"

KEYVAULT_NAME="kv-${SUFFIX}"
ADF_NAME="adf-${SUFFIX}"

echo "=============================================================="
echo " Provisioning Day 2 lab environment"
echo "   Resource Group : ${RESOURCE_GROUP}"
echo "   Location       : ${LOCATION}"
echo "   SQL Server     : ${SQL_SERVER_NAME}"
echo "   Storage Acct   : ${STORAGE_ACCOUNT_NAME}"
echo "   Key Vault      : ${KEYVAULT_NAME}"
echo "   Data Factory   : ${ADF_NAME}"
echo "=============================================================="

# ----------------------------- 1. RESOURCE GROUP ----------------------------
echo ">> [1/7] Creating resource group..."
az group create \
  --name "${RESOURCE_GROUP}" \
  --location "${LOCATION}" \
  --tags project=OakTreeCapabilityProgram module="Day2-ADF" \
  --output none

# ----------------------------- 2. AZURE SQL (source system stand-in) -------
echo ">> [2/7] Creating Azure SQL logical server..."
az sql server create \
  --name "${SQL_SERVER_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --location "${LOCATION}" \
  --admin-user "${SQL_ADMIN_USER}" \
  --admin-password "${SQL_ADMIN_PASSWORD}" \
  --output none

echo ">> [2/7] Creating serverless Azure SQL Database (auto-pauses to save cost)..."
az sql db create \
  --resource-group "${RESOURCE_GROUP}" \
  --server "${SQL_SERVER_NAME}" \
  --name "${SQL_DB_NAME}" \
  --edition GeneralPurpose \
  --family Gen5 \
  --capacity 2 \
  --compute-model Serverless \
  --auto-pause-delay 60 \
  --output none

echo ">> [2/7] Allowing Azure services (incl. ADF) to reach the SQL server..."
az sql server firewall-rule create \
  --resource-group "${RESOURCE_GROUP}" \
  --server "${SQL_SERVER_NAME}" \
  --name "AllowAzureServices" \
  --start-ip-address 0.0.0.0 \
  --end-ip-address 0.0.0.0 \
  --output none

echo "   NOTE: also add a rule for YOUR machine's IP so you can run the SQL setup script:"
echo "     az sql server firewall-rule create --resource-group ${RESOURCE_GROUP} --server ${SQL_SERVER_NAME} \\"
echo "       --name AllowMyIP --start-ip-address <your-ip> --end-ip-address <your-ip>"

# ----------------------------- 3. STORAGE ACCOUNT (ADLS Gen2 lakehouse) ----
echo ">> [3/7] Creating ADLS Gen2 storage account..."
az storage account create \
  --name "${STORAGE_ACCOUNT_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --location "${LOCATION}" \
  --sku Standard_LRS \
  --kind StorageV2 \
  --hierarchical-namespace true \
  --output none

echo ">> [3/7] Creating bronze/ and silver/ containers..."
STORAGE_KEY=$(az storage account keys list \
  --account-name "${STORAGE_ACCOUNT_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "[0].value" -o tsv)

for CONTAINER in bronze silver; do
  az storage container create \
    --name "${CONTAINER}" \
    --account-name "${STORAGE_ACCOUNT_NAME}" \
    --account-key "${STORAGE_KEY}" \
    --output none
done

# ----------------------------- 4. KEY VAULT (secrets) -----------------------
echo ">> [4/7] Creating Key Vault and storing the SQL admin password..."
if az keyvault show \
  --name "${KEYVAULT_NAME}" \
  --only-show-errors \
  --output none 2>/dev/null; then
  echo "   Key Vault '${KEYVAULT_NAME}' already exists; skipping creation."
else
  az keyvault create \
    --name "${KEYVAULT_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --location "${LOCATION}" \
    --output none
fi

az keyvault secret set \
  --vault-name "${KEYVAULT_NAME}" \
  --name "sql-admin-password" \
  --value "${SQL_ADMIN_PASSWORD}" \
  --output none

az keyvault secret set \
  --vault-name "${KEYVAULT_NAME}" \
  --name "sql-connection-string" \
  --value "Server=tcp:${SQL_SERVER_NAME}.database.windows.net,1433;Database=${SQL_DB_NAME};User ID=${SQL_ADMIN_USER};Password=${SQL_ADMIN_PASSWORD};Encrypt=true;" \
  --output none

# ----------------------------- 5. AZURE DATA FACTORY ------------------------
echo ">> [5/7] Creating Azure Data Factory (with a system-assigned managed identity)..."
az datafactory create \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${ADF_NAME}" \
  --location "${LOCATION}" \
  --output none

ADF_PRINCIPAL_ID=$(az datafactory show \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${ADF_NAME}" \
  --query "identity.principalId" -o tsv)

# ----------------------------- 6. LEAST-PRIVILEGE ROLE ASSIGNMENTS ----------
echo ">> [6/7] Granting ADF's managed identity 'Storage Blob Data Contributor' (least privilege — not Owner)..."
STORAGE_ID=$(az storage account show \
  --name "${STORAGE_ACCOUNT_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "id" -o tsv)

az role assignment create \
  --assignee-object-id "${ADF_PRINCIPAL_ID}" \
  --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Contributor" \
  --scope "${STORAGE_ID}" \
  --output none

echo ">> [6/7] Granting ADF's managed identity read access to Key Vault secrets..."
KEYVAULT_RBAC=$(az keyvault show \
  --name "${KEYVAULT_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "properties.enableRbacAuthorization" -o tsv)

if [[ "${KEYVAULT_RBAC}" == "true" ]]; then
  az role assignment create \
    --assignee-object-id "${ADF_PRINCIPAL_ID}" \
    --assignee-principal-type ServicePrincipal \
    --role "Key Vault Secrets User" \
    --scope "$(az keyvault show --name "${KEYVAULT_NAME}" --resource-group "${RESOURCE_GROUP}" --query id -o tsv)" \
    --output none
else
  az keyvault set-policy \
    --name "${KEYVAULT_NAME}" \
    --object-id "${ADF_PRINCIPAL_ID}" \
    --secret-permissions get list \
    --output none
fi

# ----------------------------- 7. SUMMARY / HANDOFF -------------------------
echo ">> [7/7] Writing connection details to lab_environment.env for later scripts..."
cat > "./lab_environment.env" <<EOF
RESOURCE_GROUP=${RESOURCE_GROUP}
LOCATION=${LOCATION}
SQL_SERVER_NAME=${SQL_SERVER_NAME}
SQL_DB_NAME=${SQL_DB_NAME}
SQL_ADMIN_USER=${SQL_ADMIN_USER}
SQL_SERVER_FQDN=${SQL_SERVER_NAME}.database.windows.net
STORAGE_ACCOUNT_NAME=${STORAGE_ACCOUNT_NAME}
KEYVAULT_NAME=${KEYVAULT_NAME}
ADF_NAME=${ADF_NAME}
EOF

echo "=============================================================="
echo " DONE. Resources created in resource group: ${RESOURCE_GROUP}"
echo " SQL admin password stored in Key Vault '${KEYVAULT_NAME}' as secret 'sql-admin-password'"
echo " Connection details saved to ./lab_environment.env"
echo ""
echo " NEXT STEPS:"
echo "   1. Add your IP to the SQL firewall (see note above), then run"
echo "      sql/02_setup_source_database.sql against ${SQL_DB_NAME}"
echo "   2. Run ./03_deploy_adf_pipeline.sh to deploy the ADF linked"
echo "      services, datasets, pipeline, and trigger"
echo "=============================================================="
echo ""
echo " COST NOTE: SQL Database uses Serverless (auto-pauses after 60 min"
echo " idle) and Storage uses Standard LRS. Run ./99_teardown.sh at the"
echo " end of each day if this is a shared/temporary training subscription."
