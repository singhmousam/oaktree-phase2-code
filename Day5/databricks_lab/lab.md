### Real Azure Databricks Cluster

```bash
cd Day5/databricks_lab
./01_provision_databricks.sh oaktreelab-team1   # creates workspace + cluster + imports notebooks
# wait ~5 minutes for the cluster to start, then open the workspace URL printed at the end


follow `docs/Day3_Azure_Portal_StepByStep.md` to do every one of these
steps by clicking through the Azure Portal and Databricks workspace UI
instead of running the script — useful for understanding exactly what the
script automates, or if your training environment restricts CLI access.