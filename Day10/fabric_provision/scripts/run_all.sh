#!/usr/bin/env bash
# =============================================================================
# run_all.sh — runs the full provisioning sequence: capacity -> workspace +
# lakehouse -> sample data upload -> warehouse + dbt credentials ->
# deploy & run the pipeline notebook end to end.
#
# Usage: ./run_all.sh <unique-suffix>
#   e.g. ./run_all.sh oaktreefabric01
#
# Each step also runs standalone if you'd rather go one at a time (useful
# for a live training session, pausing to inspect the portal between steps).
# =============================================================================
set -euo pipefail
SUFFIX="${1:?Usage: $0 <unique-suffix>, e.g. oaktreefabric01}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

echo "################################################################"
echo "# STEP 1 of 5 — Fabric capacity (F2, Sweden Central)"
echo "################################################################"
./01_create_fabric_capacity.sh "${SUFFIX}"

echo "################################################################"
echo "# STEP 2 of 5 — Workspace + Lakehouse"
echo "################################################################"
./02_create_workspace_and_lakehouse.sh "${SUFFIX}"

echo "################################################################"
echo "# STEP 3 of 5 — Upload sample data"
echo "################################################################"
./03_upload_sample_data.sh

echo "################################################################"
echo "# STEP 4 of 5 — Warehouse + dbt credentials"
echo "################################################################"
./04_create_warehouse_and_get_dbt_creds.sh

echo "################################################################"
echo "# STEP 5 of 5 — Deploy and RUN the end-to-end pipeline notebook"
echo "################################################################"
source ./fabric_environment.env
# shellcheck disable=SC2153
export STORAGE_ACCOUNT_NAME="${STORAGE_ACCOUNT_NAME:-}"
export STORAGE_ACCOUNT_KEY="${STORAGE_ACCOUNT_KEY:-}"
./05_deploy_and_run_pipeline.sh

echo ""
echo "################################################################"
echo "# ALL STEPS COMPLETE — infrastructure provisioned AND the pipeline"
echo "# has actually run. See fabric_environment.env for every ID/"
echo "# connection string generated, and dbt_fabric_output/profiles.yml"
echo "# for the dbt-ready configuration if you want to run the"
echo "# alternative SQL-based transformation path too."
echo "################################################################"
