# End-to-End Retail Data Platform on Databricks (Olist E-Commerce)

This repository contains the complete implementation of a production-grade retail analytics platform using **Apache Spark (PySpark & Spark SQL)** and **Delta Lake** on **Databricks Community Edition**. The pipeline follows the industry-standard **Medallion Architecture** to ingest, clean, model, and optimize e-commerce transaction data.

---

## Architecture Diagram

```
                 CSV Files (GitHub Raw Mirror)
                              │
                              ▼ (Download & Save)
                 [ Landing Zone (DBFS / Volume) ]
                              │
                              ▼ (Auto Loader / Spark Structured Streaming)
                    [ Bronze Layer (Delta) ]
                              │
                              ▼ (Deduplicate, Parse Timestamps, Cast types)
                    [ Silver Layer (Delta) ]
                              │
                              ▼ (Star Schema / Hash Surrogate Keys)
                     [ Gold Layer (Delta) ]
                              │
                              ▼ (Analytical SQL Views)
                [ Power BI / Databricks SQL ]
```

---

## Repository Structure

```
RetailAnalytics/
├── notebooks/
│   ├── 00_setup_and_download.py      # Environment config, db schemas, data downloader
│   ├── 01_bronze_ingestion.py        # Incremental ingestion with Auto Loader
│   ├── 02_silver_transformation.py  # Data cleaning, deduplication & MERGE micro-batches
│   ├── 03_gold_modeling.py          # Dimensional modeling (Star Schema)
│   ├── 04_data_quality_checks.py     # Custom null, uniqueness, and referential integrity tests
│   └── 05_delta_optimizations.py     # OPTIMIZE, Z-ORDER, VACUUM & Time Travel demo
├── sql/
│   ├── gold_views.sql                # Analytics SQL views (KPIs, trends, performance)
│   └── analytics_queries.sql         # Complex analytics queries using CTEs and window functions
├── workflows/
│   └── retail_pipeline_workflow.json # Databricks Workflow Job definition (JSON)
├── docs/
│   └── architecture.md               # Pipeline architecture, ER diagram, and Data Dictionary
└── README.md                         # This setup guide
```

---

## Detailed Notebook Workflow

### 1. [00_setup_and_download.py](notebooks/00_setup_and_download.py)
- **Purpose**: Prepares target databases (`retail_bronze`, `retail_silver`, `retail_gold`).
- **Data Source**: Fetches Olist Brazilian E-Commerce dataset directly from a public mirror.
- **Flexibility**: Supports toggling between **Unity Catalog (UC)** (using Volumes) and **Legacy DBFS** storage.

### 2. [01_bronze_ingestion.py](notebooks/01_bronze_ingestion.py)
- **Technology**: Uses **Auto Loader** (`cloudFiles`) to scan and load CSV files incrementally.
- **Metadata**: Appends `_ingestion_timestamp` and `_source_file_name`.
- **Mode**: Appends to Delta tables in `retail_bronze` using `trigger(availableNow=True)`.

### 3. [02_silver_transformation.py](notebooks/02_silver_transformation.py)
- **Cleaning Actions**: Standardizes city/state casing, casts strings to proper double/integer/timestamp types, and filters invalid negative prices.
- **Incremental Loading**: Streams from Bronze Delta tables and performs a Delta Lake **MERGE INTO** upsert in `foreachBatch` to prevent duplicates.

### 4. [03_gold_modeling.py](notebooks/03_gold_modeling.py)
- **Dimensional Modeling**: Creates a Star Schema:
  - `DimCustomer`, `DimProduct`, `DimSeller`, `DimLocation` (deduplicated geolocation with average lat/long coords), `DimDate` (dynamically generated).
  - `FactSales` (line-item level fact table).
- **Surrogate Keys**: Employs deterministic hashes (`SHA2`) on business IDs to map dimensions.
- **Proration**: Correctly prorates payment values to the line-item level (weighted by price) to prevent sales volume inflation during BI aggregations.

### 5. [04_data_quality_checks.py](notebooks/04_data_quality_checks.py)
- **Rules Suite**: Checks null key counts, verifies uniqueness of primary keys, checks ranges (e.g. price >= 0, score 1-5), and checks referential integrity (foreign keys in Fact have matches in Dim).
- **Metadata Audit Trail**: Validation results are appended to a Delta table: `retail_gold.data_quality_logs`.
- **Enforcement**: If configured, raises a notebook exception on critical validation failures to stop workflow executions.

### 6. [05_delta_optimizations.py](notebooks/05_delta_optimizations.py)
- **Performance**: Performs file compaction via `OPTIMIZE` and multidimensional clustering via `Z-ORDER BY (order_purchase_date_key, product_key)` on `FactSales`.
- **Time Travel**: Demonstrates querying historic data versions (`VERSION AS OF`).
- **Maintenance**: Runs `VACUUM` with safety checks disabled for demo purposes to purge stale files from memory.

---

## Databricks Community Edition Setup Guide

Follow these steps to run the complete platform on Databricks Community Edition (CE):

### Step 1: Create a Compute Cluster
1. Log in to your Databricks Community Edition workspace.
2. Click **Compute** in the left sidebar, then click **Create Compute**.
3. Set the cluster name (e.g., `Retail-Cluster`).
4. Select a standard **Databricks Runtime (DBR)** (Recommended: `14.3 LTS` or higher).
5. Click **Create Cluster**.

### Step 2: Clone the Git Repository
1. Select **Repos** on the left sidebar, click **Add Repo**.
2. Paste the URL of your GitHub repository containing these files.
3. Click **Create Repo**. The folders and notebooks will automatically populate in your workspace workspace.

### Step 3: Configure and Run Setup Notebook
1. Open the notebook `00_setup_and_download` inside the `notebooks` directory.
2. Review the parameters (widgets) at the top of the notebook:
   - `Use Unity Catalog`: Select `false` (Databricks CE uses legacy Hive Metastore by default).
   - `Schema Prefix`: `retail` (this builds `retail_bronze`, `retail_silver`, and `retail_gold` databases).
   - `Landing Path`: `/FileStore/retail_landing`.
3. Click **Run All** in the top right to create database schemas and download Olist raw data.

### Step 4: Run the Pipelines
Run the remaining notebooks sequentially by clicking **Run All** in each notebook:
1. `01_bronze_ingestion` (loads landing data into Bronze Delta tables).
2. `02_silver_transformation` (cleans and loads to Silver Delta tables).
3. `03_gold_modeling` (models into Gold Star Schema).
4. `04_data_quality_checks` (validates tables and logs audit trail).
5. `05_delta_optimizations` (runs table compactions and maintenance).

---

## SQL Analytics & Views

You can run queries in **Databricks SQL** or in a notebook cell (using the `%sql` magic).

1. Execute the DDL script in [`sql/gold_views.sql`](sql/gold_views.sql) inside a SQL query window to define analytical views (`v_kpi_summary`, `v_delivery_kpis`, `v_monthly_sales_trend`, etc.) in the active gold database.
2. Use [`sql/analytics_queries.sql`](sql/analytics_queries.sql) to run custom analytics queries, including customer decile spending, late delivery vs. review score correlations, and product performance by customer state.

---

## Connecting Power BI

1. **Locate Server Hostname & HTTP Path**:
   - In Databricks, navigate to **Compute** -> click on your running cluster -> expand **Advanced Options** -> click the **JDBC/ODBC** tab.
   - Copy the **Server Hostname** and **HTTP Path**.
2. **Generate Token**:
   - Click **User Settings** (bottom-left corner) -> **Developer** -> **Access tokens** -> click **Generate new token**. Copy the token value.
3. **Connect in Power BI Desktop**:
   - In Power BI Desktop, select **Get Data** -> search for **Databricks**.
   - Input the **Server Hostname** and **HTTP Path** copied above. Set data connectivity mode to **DirectQuery** for real-time querying.
   - Select **Personal Access Token** as the authentication method and paste your token.
   - Connect and select the views created in `v_kpi_summary`, `v_delivery_kpis`, etc., under `retail_gold` to build interactive charts!
