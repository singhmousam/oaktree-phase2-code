### 1. Key Components Required in ADF

To build this pipeline, you need five fundamental ADF components:

* **Linked Services:** Connection strings pointing to your source storage (Blob Storage / Azure Files) and sink storage (ADLS Gen2 Data Lake).
* **Datasets:** Data schemas pointing to specific file paths or directories.
* **Pipeline:** The workflow container holding your activities.
* **Activities:**
* **Get Metadata:** Scans the folder to verify the uploaded file exists.
* **Data Flow / Copy Activity:** Reads CSV data, removes duplicate rows, adds a partition column (`LoadDate`), and writes output.


* **Storage Event / File System Trigger:** Listens for `BlobCreated` events to trigger the pipeline automatically when a new file lands.

---

### 2. End-to-End Setup & Deployment Script

This Azure CLI script provisions the storage account, creates the input/output containers, uploads sample data, and creates a Storage Event Trigger for ADF.

```bash
#!/bin/bash
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

```

---

### 3. ADF Pipeline Implementation Steps

#### Step 1: Define Datasets

* **`ds_csv_input`**: Connects to `input-files` container, pointing to `@dataset().fileName` dynamically.
* **`ds_parquet_sink`**: Connects to `datalake-sink` container using the **Parquet** format.

#### Step 2: Configure Mapping Data Flow (Deduplication & Partitioning)

Inside the Data Flow canvas:

1. **Source Transformation:**
* Source dataset: `ds_csv_input`


2. **Aggregate Transformation (Deduplicate):**
* **Group By:** Select all unique columns (`id`, `name`, `amount`, `transaction_date`).
* **Aggregates:** Leave blank (grouping by all columns collapses exact duplicates into single distinct rows).


3. **Derived Column Transformation (Partition Column):**
* Add a new column `LoadDate` with expression: `currentDate()`.


4. **Sink Transformation:**
* Sink dataset: `ds_parquet_sink`
* **Optimize Tab:** Select **Set Partitioning** $\rightarrow$ **Key Partitioning** $\rightarrow$ set column to `LoadDate`.



---

### 4. Pipeline JSON Definition

Below is the complete pipeline JSON structure incorporating a **Get Metadata** check and the **Data Flow** execution.

```json
{
  "name": "pipeline_dedup_and_partition",
  "properties": {
    "activities": [
      {
        "name": "Check_File_Exists",
        "type": "GetMetadata",
        "typeProperties": {
          "dataset": {
            "referenceName": "ds_csv_input",
            "type": "DatasetReference"
          },
          "fieldList": ["exists", "childItems"]
        }
      },
      {
        "name": "Deduplicate_And_Partition_Flow",
        "type": "ExecuteDataFlow",
        "dependsOn": [
          {
            "activity": "Check_File_Exists",
            "dependencyConditions": ["Succeeded"]
          }
        ],
        "typeProperties": {
          "dataflow": {
            "referenceName": "df_dedup_partition_logic",
            "type": "DataFlowReference"
          }
        }
      }
    ]
  }
}

```

---

### 5. Trigger Setup: Manual vs Event-Driven

#### Option A: Manual Trigger (Testing & On-Demand)

In the ADF UI header, click **Trigger** $\rightarrow$ **Trigger Now**. This executes the pipeline immediately regardless of storage events.

#### Option B: Storage Event Trigger (Automated File Upload)

To automatically trigger the pipeline when a new `.csv` file arrives:

1. In ADF, go to **Manage** $\rightarrow$ **Triggers** $\rightarrow$ **New/Edit**.
2. **Type:** Choose **Storage Events**.
3. **Storage Account:** Select your storage account name.
4. **Event:** Select **Blob Created**.
5. **Blob Path Ends With:** `.csv`
6. **Container Path:** `input-files/blobs/default/`

---

### 6. Data Lake Partition Structure Result

After the pipeline executes, your target Data Lake container (`datalake-sink`) automatically organizes the output into a partitioned directory structure based on date:

```text
datalake-sink/
└── LoadDate=2026-08-25/
    ├── part-00000-tid.c000.snappy.parquet (Contains 2 distinct deduplicated rows)

```