# Create and Upload Sample Data to Azure Storage for ADF Lab

# Configuration Variables
RESOURCE_GROUP="rg-adf-demo"
LOCATION="canadacentral"
STORAGE_ACCOUNT="stadfdemodata$RANDOM"
ADF_NAME="adf-demo-pipeline"

# 1. Create Resource Group & Storage Account (Hierarchical Namespace enabled for Data Lake)
az group create --name $RESOURCE_GROUP --location $LOCATION

az storage account create \
  --name $STORAGE_ACCOUNT \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --sku Standard_LRS \
  --kind StorageV2 \
  --enable-hierarchical-namespace true

# 2. Get Storage Connection String
STORAGE_CONN=$(az storage account show-connection-string --name $STORAGE_ACCOUNT --resource-group $RESOURCE_GROUP --query connectionString -o tsv)

# 3. Create Storage Containers
az storage container create --name "input-files" --connection-string "$STORAGE_CONN"
az storage container create --name "datalake-sink" --connection-string "$STORAGE_CONN"

# 4. Generate & Upload Sample CSV Data
echo "id,name,amount,transaction_date" > sample_data.csv
echo "101,Alice,250.00,2026-08-25" >> sample_data.csv
echo "102,Bob,150.50,2026-08-25" >> sample_data.csv
echo "101,Alice,250.00,2026-08-25" >> sample_data.csv # Intentional Duplicate Row

az storage blob upload \
  --container-name "input-files" \
  --file sample_data.csv \
  --name "sample_data.csv" \
  --connection-string "$STORAGE_CONN"

echo "Sample data successfully uploaded to input-files/sample_data.csv"