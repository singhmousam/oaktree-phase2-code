#!/usr/bin/env bash
# =============================================================================
# 03_upload_sample_data.sh
# -----------------------------------------------------------------------------
# Uploads this program's sample CSVs into the Lakehouse's Files/bronze/
# section, using azcopy against OneLake's ADLS Gen2-compatible endpoint.
#
# azcopy is Microsoft's own recommended tool for this — the alternative
# would be hand-rolling the 3-step ADLS Gen2 REST protocol (PUT to create,
# PATCH to append, PATCH to flush) directly with curl, which is exactly the
# kind of thing azcopy exists to avoid.
#
# Requires: azcopy installed (https://aka.ms/downloadazcopy), and either an
# interactive `azcopy login` beforehand, or AZCOPY_AUTO_LOGIN_TYPE=AZCLI set
# (piggybacks off your existing `az login` session — no separate login step).
# =============================================================================
set -euo pipefail

if [[ ! -f "./fabric_environment.env" ]]; then
  echo "ERROR: fabric_environment.env not found. Run scripts 01 and 02 first." >&2
  exit 1
fi
# shellcheck disable=SC1091
source ./fabric_environment.env

DATA_DIR="../data"
ONELAKE_BASE="https://onelake.dfs.fabric.microsoft.com/${WORKSPACE_NAME}/${LAKEHOUSE_NAME}.Lakehouse/Files/bronze"

echo "=============================================================="
echo " Uploading sample data to:"
echo "   ${ONELAKE_BASE}"
echo "=============================================================="

# Let azcopy reuse the current `az login` session instead of a separate
# interactive `azcopy login` — the single biggest friction-reducer for
# running this non-interactively.
export AZCOPY_AUTO_LOGIN_TYPE=AZCLI

if ! command -v azcopy &> /dev/null; then
  echo "ERROR: azcopy is not installed. Install it from https://aka.ms/downloadazcopy" >&2
  echo "        (or via your package manager, e.g. 'brew install azcopy' on macOS)" >&2
  exit 1
fi

for FILE in trade_blotter.csv dim_trader.csv dim_trader_snapshot_20260601.csv dim_trader_snapshot_20260901.csv; do
  echo ">> Uploading ${FILE}..."
  azcopy copy \
    "${DATA_DIR}/${FILE}" \
    "${ONELAKE_BASE}/${FILE}" \
    --trusted-microsoft-suffixes "fabric.microsoft.com" \
    --overwrite=true
done

echo "=============================================================="
echo " DONE. All 4 files uploaded to Files/bronze/ in ${LAKEHOUSE_NAME}."
echo ""
echo " VERIFY: open the workspace in the Fabric portal, click the Lakehouse,"
echo " and confirm Files > bronze shows all 4 CSVs."
echo ""
echo " NEXT: ./04_create_warehouse_and_get_dbt_creds.sh"
echo "=============================================================="
