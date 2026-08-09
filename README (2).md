# Retail Analytics Platform — Olist E-Commerce (Databricks + GitHub + Power BI)

An automated, end-to-end retail analytics platform built on **Databricks** using the
**Brazilian E-Commerce Public Dataset by Olist** (~100K real orders, 2016–2018). The
pipeline follows the **Medallion Architecture** (Bronze → Silver → Gold), runs itself
on a nightly schedule, validates its own data quality, and feeds a **Power BI**
dashboard. The full codebase is version-controlled on GitHub, with Databricks pulling
the latest code automatically on every scheduled run.

---

## Architecture

```
Kaggle API (direct download, no local files)
        │
        ▼
Unity Catalog Volume — /Volumes/workspace/default/retail_landing
        │
        ▼ (Auto Loader — incremental, checkpoint-tracked)
Bronze layer — workspace.retail_bronze
        │
        ▼ (clean, type, dedupe, MERGE INTO, quarantine bad rows)
Silver layer — workspace.retail_silver
        │
        ▼ (star schema, surrogate keys, MERGE INTO on FactSales)
Gold layer — workspace.retail_gold
        │
        ▼
Data Quality Validation ──► Delta Optimizations (OPTIMIZE, ZORDER, VACUUM)
        │
        ▼
Power BI (Databricks SQL Warehouse, Import mode)
```

All stages are chained into one scheduled **Databricks Job** (`Retail_Medallion_Pipeline`),
deployed via a Databricks **Git folder** linked to this repository.

---

## Repository structure

```
Retail-Analytics/
├── Notebooks/
│   ├── 00b_pipeline_utils.py         # Shared: log_event, quarantine_records, merge_upsert
│   ├── 01_bronze_ingestion.py        # Auto Loader — incremental raw ingestion
│   ├── 02_silver_transformation.py   # Cleaning, dedup, MERGE upsert, quarantine
│   ├── 03_gold_modeling.py           # Star schema (5 Dims + FactSales), MERGE upsert
│   ├── 04_data_quality_checks.py     # Null/uniqueness/range/referential-integrity checks
│   └── 05_delta_optimizations.py     # OPTIMIZE, ZORDER, VACUUM, time travel
├── sql/
│   ├── gold_views.sql                # BI-friendly views (KPIs, trends, performance)
│   └── analytics_queries.sql         # CTE / window-function analytics queries
├── docs/
│   ├── architecture.md               # Data dictionary and ER diagram
│   └── SETUP_GUIDE.md                # Full setup walkthrough
└── README.md
```

---

## What each notebook does

| Notebook | Purpose |
|---|---|
| `00b_pipeline_utils` | Shared utilities imported via `%run` by every other notebook: centralized logging, quarantine handling, and incremental upsert logic. |
| `01_bronze_ingestion` | Auto Loader ingestion — tracks already-processed files via checkpoints, so re-runs only pick up genuinely new files. |
| `02_silver_transformation` | Cleans and types each table, deduplicates, `MERGE INTO` upsert, routes invalid rows (nulls, negative values) to quarantine tables instead of dropping or crashing. |
| `03_gold_modeling` | Builds the star schema — `DimCustomer`, `DimProduct`, `DimSeller`, `DimLocation`, `DimDate`, and `FactSales` (payment proration to line-item level, `MERGE INTO` incremental upsert). |
| `04_data_quality_checks` | Validates the finished Gold/Silver output — nulls, duplicate keys, value ranges, referential integrity — logs results, can halt the pipeline on critical failure. |
| `05_delta_optimizations` | Compacts small files and Z-orders `FactSales` for query performance, demonstrates time travel, vacuums old file versions for storage cost control. |

---

## Key engineering concepts implemented

| Concept | Where |
|---|---|
| **Orchestration** | Databricks Job, 5 tasks, explicit `depends_on` chain |
| **Scheduling** | Daily automated trigger, 3:00 AM |
| **Logging** | `workspace.retail_ops.pipeline_logs` — every step of every layer writes a status row |
| **Quarantine** | `workspace.retail_ops.<table>_quarantine` — invalid rows isolated with a reason, pipeline keeps running |
| **Incremental loading** | Auto Loader (Bronze) + `MERGE INTO` upsert (Silver, Gold's FactSales) |
| **CI-style deployment** | GitHub is the source of truth; the Job's Git integration pulls `main` on every scheduled run |
| **Governance** | Unity Catalog (`workspace` catalog, managed Volumes and schemas) |

---

## Data

- **Source:** [Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) (Kaggle)
- **Scale:** ~99,441 customers · ~112,650 order line items · ~99,224 reviews
- **Ingestion:** Pulled directly via the Kaggle API from inside Databricks — no local downloads at any stage

---

## Running it

The pipeline is fully automated — no manual steps required after initial setup. To run it manually:

1. Databricks → **Jobs & Pipelines** → `Retail_Medallion_Pipeline` → **Run now**
2. Check results: `SELECT * FROM workspace.retail_ops.pipeline_logs ORDER BY log_timestamp DESC`

See `docs/SETUP_GUIDE.md` for the full first-time setup walkthrough.

---

## Connecting Power BI

1. Databricks → **SQL Warehouses** → your warehouse → **Connection details** → copy Server hostname + HTTP path
2. Generate a personal access token (Settings → Developer → Access tokens, scope: BI Tools)
3. Power BI Desktop → Get Data → Databricks → paste hostname/path → Import mode → authenticate with the token
4. Load tables from `workspace.retail_gold`: `FactSales`, `DimCustomer`, `DimProduct`, `DimSeller`, `DimLocation`, `DimDate`
