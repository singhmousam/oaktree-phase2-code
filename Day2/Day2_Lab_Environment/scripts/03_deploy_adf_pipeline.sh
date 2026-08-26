#!/usr/bin/env bash
# =============================================================================
# 03_deploy_adf_pipeline.sh
# -----------------------------------------------------------------------------
# Deploys every ADF artifact in adf_artifacts/ into the Data Factory created
# by 01_provision_infra.sh, in dependency order:
#   Key Vault LS -> SQL LS -> ADLS LS -> Datasets -> Pipeline -> Trigger
#
# This is the "infrastructure as code" version of everything you could also
# click together by hand in ADF Studio — run this once to deploy the whole
# lab pipeline in seconds, or use it as a reference for what each ADF Studio
# screen is actually producing under the hood.
#
# Prerequisites: run 01_provision_infra.sh first (creates lab_environment.env)
#                and 02_setup_source_database.sql against the SQL DB.
# =============================================================================
set -euo pipefail

if [ ! -f "./lab_environment.env" ]; then
  echo "ERROR: lab_environment.env not found. Run 01_provision_infra.sh first."
  exit 1
fi
# shellcheck disable=SC1091
source ./lab_environment.env

ARTIFACT_DIR="../adf_artifacts"
TMP_DIR="$(mktemp -d)"
echo ">> Using temp workspace: ${TMP_DIR}"

# Substitute the placeholder tokens in each JSON template with real values
# from lab_environment.env, writing filled-in copies to a temp directory.
substitute() {
  local infile="$1" outfile="$2"
  sed \
    -e "s/<KEYVAULT_NAME>/${KEYVAULT_NAME}/g" \
    -e "s/<SQL_SERVER_NAME>/${SQL_SERVER_NAME}/g" \
    -e "s/<SQL_DB_NAME>/${SQL_DB_NAME}/g" \
    -e "s/<SQL_ADMIN_USER>/${SQL_ADMIN_USER}/g" \
    -e "s/<STORAGE_ACCOUNT_NAME>/${STORAGE_ACCOUNT_NAME}/g" \
    "${infile}" | jq -c '.properties' > "${outfile}"
}

for f in "${ARTIFACT_DIR}"/*.json; do
  base="$(basename "$f")"
  substitute "$f" "${TMP_DIR}/${base}"
done

echo ">> [1/9] Deploying Key Vault linked service..."
az datafactory linked-service create \
  --factory-name "${ADF_NAME}" --resource-group "${RESOURCE_GROUP}" \
  --linked-service-name "LS_KeyVault_OakTree" \
  --properties "@${TMP_DIR}/01_linkedService_KeyVault.json" --output none

echo ">> [2/9] Deploying Azure SQL Database linked service..."
az datafactory linked-service create \
  --factory-name "${ADF_NAME}" --resource-group "${RESOURCE_GROUP}" \
  --linked-service-name "LS_AzureSqlDatabase_OakTreeSource" \
  --properties "@${TMP_DIR}/02_linkedService_AzureSqlDatabase.json" --output none

echo ">> [3/9] Deploying ADLS Gen2 linked service..."
az datafactory linked-service create \
  --factory-name "${ADF_NAME}" --resource-group "${RESOURCE_GROUP}" \
  --linked-service-name "LS_ADLS_OakTreeLake" \
  --properties "@${TMP_DIR}/03_linkedService_ADLS.json" --output none

echo ">> [4/9] Deploying dataset: DS_Sql_TradeBlotter..."
az datafactory dataset create \
  --factory-name "${ADF_NAME}" --resource-group "${RESOURCE_GROUP}" \
  --dataset-name "DS_Sql_TradeBlotter" \
  --properties "@${TMP_DIR}/04_dataset_SqlTradeBlotter.json" --output none

echo ">> [5/9] Deploying dataset: DS_ADLS_Bronze_Trades..."
az datafactory dataset create \
  --factory-name "${ADF_NAME}" --resource-group "${RESOURCE_GROUP}" \
  --dataset-name "DS_ADLS_Bronze_Trades" \
  --properties "@${TMP_DIR}/05_dataset_ADLS_Bronze.json" --output none

echo ">> [6/9] Deploying dataset: DS_Sql_TradeBlotterSilver..."
az datafactory dataset create \
  --factory-name "${ADF_NAME}" --resource-group "${RESOURCE_GROUP}" \
  --dataset-name "DS_Sql_TradeBlotterSilver" \
  --properties "@${TMP_DIR}/06_dataset_SqlTradeBlotterSilver.json" --output none

echo ">> [7/9] Deploying dataset: DS_ADLS_Silver_Trades..."
az datafactory dataset create \
  --factory-name "${ADF_NAME}" --resource-group "${RESOURCE_GROUP}" \
  --dataset-name "DS_ADLS_Silver_Trades" \
  --properties "@${TMP_DIR}/07_dataset_ADLS_Silver.json" --output none

echo ">> [8/9] Deploying pipeline: PL_TradeBlotter_Bronze_to_Silver..."
az datafactory pipeline create \
  --factory-name "${ADF_NAME}" --resource-group "${RESOURCE_GROUP}" \
  --pipeline-name "PL_TradeBlotter_Bronze_to_Silver" \
  --pipeline "@${TMP_DIR}/08_pipeline_TradeBlotter.json" --output none

echo ">> [9/9] Deploying + starting trigger: TR_Daily_3AM_TradeBlotter..."
az datafactory trigger create \
  --factory-name "${ADF_NAME}" --resource-group "${RESOURCE_GROUP}" \
  --trigger-name "TR_Daily_3AM_TradeBlotter" \
  --properties "@${TMP_DIR}/09_trigger_Daily.json" --output none

az datafactory trigger start \
  --factory-name "${ADF_NAME}" --resource-group "${RESOURCE_GROUP}" \
  --name "TR_Daily_3AM_TradeBlotter" --output none

rm -rf "${TMP_DIR}"

echo "=============================================================="
echo " DONE. Pipeline deployed and trigger started."
echo ""
echo " TO RUN IT RIGHT NOW (don't wait for 3 AM) — trigger an ad-hoc"
echo " run for a specific day, exactly like the lab exercise expects:"
echo ""
echo "   az datafactory pipeline create-run \\"
echo "     --factory-name ${ADF_NAME} --resource-group ${RESOURCE_GROUP} \\"
echo "     --name PL_TradeBlotter_Bronze_to_Silver \\"
echo "     --parameters windowDate=2026-05-01"
echo ""
echo " THEN WATCH IT RUN:"
echo "   az datafactory pipeline-run show --factory-name ${ADF_NAME} \\"
echo "     --resource-group ${RESOURCE_GROUP} --run-id <run-id-from-above>"
echo ""
echo " Or just open the ADF Studio Monitor tab in the Azure Portal — much"
echo " easier to watch live during class."
echo "=============================================================="
