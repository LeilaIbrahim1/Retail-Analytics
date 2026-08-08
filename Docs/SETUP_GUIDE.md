# Setup Guide — Zero to Automated, for Beginners

You don't need to know Git or Databricks beyond what's here. Follow these in order.

## Part 1 — Get the code onto GitHub

1. Go to github.com, sign in (create a free account if you don't have one).
2. Click the **+** top right → **New repository**. Name it e.g. `retail-analytics-platform`. Keep it **Public** or **Private**, either works. Don't add a README (you already have one). Click **Create repository**.
3. On your computer, put all these files in one folder matching this layout:
   ```
   retail-analytics-platform/
   ├── notebooks/
   │   ├── 00_setup_and_download.py
   │   ├── 00b_pipeline_utils.py
   │   ├── 01_bronze_ingestion.py
   │   ├── 02_silver_transformation.py
   │   ├── 03_gold_modeling.py
   │   ├── 04_data_quality_checks.py
   │   └── 05_delta_optimizations.py
   ├── sql/
   │   ├── gold_views.sql
   │   └── analytics_queries.sql
   ├── workflows/
   │   └── retail_pipeline_workflow.json
   ├── docs/
   │   ├── architecture.md
   │   └── SETUP_GUIDE.md
   └── README.md
   ```
4. On the empty GitHub repo page, click **uploading an existing file**, drag the whole folder in, and commit. (No terminal/git commands needed for this first push — GitHub's web upload is enough.)

This is now your **single source of truth**. From now on, whenever you change a notebook, you edit it and re-upload/commit to GitHub — never edit code by hand inside Databricks. That's what "push to GitHub, Databricks pulls" means in practice.

## Part 2 — Connect Databricks to that GitHub repo

1. In your Databricks workspace, click your name (top right) → **Settings** → **Linked accounts** → **Git integration**. Choose provider **GitHub**, and either connect via OAuth or paste a GitHub Personal Access Token (GitHub → Settings → Developer settings → Personal access tokens → generate one with `repo` scope).
2. In Databricks, click **Workspace** in the sidebar → **Repos** (some versions call this a "Git folder") → **Add Repo**.
3. Paste your repo's HTTPS URL (`https://github.com/YOUR_USERNAME/retail-analytics-platform.git`), pick branch `main`, click **Create**.
4. Your notebooks now appear inside Databricks, live-linked to GitHub. When you push a change on GitHub, you click **Pull** in this Repo to sync — or, better, the scheduled Job below pulls the latest `main` automatically on every scheduled run without you doing anything.

## Part 3 — Create the automated Job

1. In Databricks, sidebar → **Workflows** → **Jobs** → **Create Job**.
2. Instead of clicking through the UI, use the ready-made definition: click the **⋮** menu (or the "Edit as JSON" / "..." option depending on your Databricks version) → **Edit as JSON**, and paste in the contents of `workflows/retail_pipeline_workflow.json` from this repo.
3. Before saving, edit two placeholders inside that JSON:
   - `"git_url"` → your actual repo URL.
   - `"YOUR_EMAIL@example.com"` → an email you actually check, so you're notified if a run fails.
4. Save. This single Job now represents your whole pipeline as 6 chained tasks (`Setup_and_Download` → `Bronze_Ingestion` → `Silver_Transformation` → `Gold_Modeling` → `Data_Quality_Validation` → `Delta_Optimizations`), each depending on the previous one succeeding.

## Part 4 — Turn on the schedule

The JSON already includes:
```json
"schedule": {
  "quartz_cron_expression": "0 0 3 * * ?",
  "timezone_id": "Africa/Cairo",
  "pause_status": "UNPAUSED"
}
```
That means: run automatically every day at 3:00 AM Cairo time. `UNPAUSED` means it's live the moment you save the Job — nothing else to click. To change the time, adjust the cron expression (Databricks' Job UI has a friendly "Edit schedule" button that writes the cron for you if you'd rather not hand-write it).

## Part 5 — Run it once manually first

Don't wait for 3 AM. Click **Run now** on the Job. Watch the 6 tasks turn green one by one. If one fails, click into it — the error is right there, and it's also written to `retail_ops.pipeline_logs`.

## Part 6 — Where to look afterwards

Run these in a SQL editor or a scratch notebook, any time:

```sql
-- Everything that happened, across every layer, most recent first
SELECT * FROM retail_ops.pipeline_logs ORDER BY log_timestamp DESC;

-- Only failures
SELECT * FROM retail_ops.pipeline_logs WHERE status = 'FAIL' ORDER BY log_timestamp DESC;

-- Rows that got quarantined out of order_items (bad prices, missing keys, etc.)
SELECT * FROM retail_ops.silver_order_items_quarantine ORDER BY _quarantine_timestamp DESC;

-- List every quarantine table that currently exists
SHOW TABLES IN retail_ops LIKE '*_quarantine';

-- Detailed rule-by-rule data quality results
SELECT * FROM retail_gold.data_quality_logs ORDER BY run_timestamp DESC;
```

## Keeping the $40 trial from draining

- The job cluster in the JSON is already a **single-node** cluster (`num_workers: 0`) with `autotermination_minutes: 30`, which is the cheapest configuration that still works for this dataset size — it shuts itself off if left idle.
- Don't leave an **all-purpose cluster** (the interactive kind you click "Start" on manually) running overnight — only Job clusters auto-terminate reliably. Check **Compute** in the sidebar before you log off.
- `05_delta_optimizations.py` runs `VACUUM ... RETAIN 0 HOURS`, which is fine for a learning project but deletes old file versions immediately (you lose time-travel history older than the current version). That's intentional here to save storage costs on the trial, but know that's the tradeoff.

## What "quarantine" actually looks like day to day

Say tomorrow's CSV has an order item with `price = -50` (a data entry error upstream). Before these changes: that row was silently `.filter()`-ed out in `02_silver_transformation.py` and vanished — you'd never know it existed. Now: it's written to `retail_ops.silver_order_items_quarantine` with `_quarantine_reason = 'negative price'`, and the pipeline still completes successfully with the other 99.98% of rows. You can query that table weekly and decide whether to fix it upstream or write a one-off correction.
