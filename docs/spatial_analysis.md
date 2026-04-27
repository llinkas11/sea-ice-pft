# Spatial analysis

Documentation of the spatial PFT × predictor data pipeline that produces `core_monthly_spatial_matchup_table.parquet`. Author: Kique Ruiz.

## Layout

- `data_raw/` — raw or lightly processed source data; includes extracted daily PFT parquet files and source PFT archives.
- `data_model/` — analysis-ready parquet tables used for modeling and exploration. Monthly domain and spatial matchup tables live here.
- `reports/` — JSON/CSV summaries documenting what was built, coverage, and QC notes.
- `scripts/` — Python scripts that build, summarize, and join the monthly datasets.
- `slurm/` — batch job wrappers for Bowdoin runs when Slurm is available.

## Parquets ready for preliminary data exploration

### `core_response_daily_summary.parquet`

Daily PFT response summary derived from the extracted daily PFT files. Carries:

- chlorophyll statistics by class
- counts/fractions for diatoms, phaeocystis, ocean, etc.
- dominant class information

Raw daily pixel observations are aggregated into:

- daily summary — one row per day
- monthly summary — one row per month
- spatial monthly summary — one row per month per grid cell

Useful for checking coverage, counts, and source-data completeness.

### `core_monthly_pft_response_table.parquet`

Monthly domain-level PFT summary. One row per `(year, month)`.

### `core_monthly_predictor_table.parquet`

Monthly physical and sea-ice predictor table from Copernicus outputs.

### `core_monthly_predictor_table_apr_aug.parquet`

April–August subset of the predictor table for the core study season.

### `core_monthly_domain_model_table.parquet`

Combines PFT + sea-ice + physical fields into a domain-level benchmark modeling table. Currently the main table for preliminary EDA and smoke-test modeling.

## Steps already taken to build those exploration parquets

1. Extract the PFT archive into daily parquet files by year.
2. Build a daily PFT response summary from those daily files.
3. Download and validate monthly Copernicus physical and sea-ice products.
4. Build a monthly predictor parquet from those environmental fields.
5. Filter predictors to April–August.
6. Aggregate daily PFT summaries to monthly domain-level summaries.
7. Join monthly PFT response with monthly predictors to make the domain modeling table.

### Exploratory QC

- 2003–2024 coverage
- April–August only
- 110 expected month rows
- known incomplete month: 2022-04
- no obvious negative or invalid physical values

### Scientific use

The domain table is appropriate for exploratory plots, seasonal/interannual summaries, correlation checks, and benchmark/smoke-test models. It is **not** the final core modeling product because it collapses the whole domain to one row per month.

## Spatial component

Goal: move from one row per month to one row per `(year, month, grid_cell)`; preserve spatial variation for the main RF modeling table.

Inputs:

- daily PFT pixels
- April–August monthly predictor grid

### Step 1 — `build_monthly_pft_gridcell_table.py`

- Snaps daily PFT pixels onto the TOPAZ4 predictor grid.
- Aggregates them to monthly per-grid-cell PFT summaries.
- Output: `core_monthly_pft_gridcell_table.parquet`.

### Step 2 — `join_monthly_spatial_tables.py`

- Joins the monthly PFT gridcell table to the predictor table.
- Join keys: `year, month, year_month, latitude, longitude`.
- Output: `core_monthly_spatial_matchup_table.parquet`.

### Steps taken 2026-04-01

Synced these files from local to Bowdoin and verified they exist on the cluster, so the spatial build can run on the full dataset:

- `scripts/build_monthly_pft_gridcell_table.py`
- `scripts/join_monthly_spatial_tables.py`
- `slurm/build_monthly_pft_gridcell_table.slurm`

## Why the spatial table matters

- Keeps spatial structure instead of averaging the whole Arctic domain together.
- Greatly increases sample size compared with the 110-row domain table.
- Is the intended main table for the scientifically meaningful RF analysis.

## Known caveat

April 2022 PFT source data are incomplete (2022-04-01 to 2022-04-15 missing), so any spatial or domain product covering 2022-04 should be flagged or excluded from formal analysis.
