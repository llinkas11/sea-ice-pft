# Bowdoin HPC Run Guide for the Arctic Sea Ice + PFT Random Forest Project

## Purpose

This guide describes a practical workflow for running the heavy data-preparation steps on Bowdoin HPC instead of on a local laptop.

The intended pattern is:

- edit code locally when convenient
- sync the repository to HPC
- store large raw and processed data on HPC
- run extraction, matchup preparation, and model jobs on HPC

---

## Recommended Directory Pattern on HPC

Use two separate locations:

### 1. Code repository

Example:

```bash
/mnt/research/<your_user_or_project>/sea-ice/random-forest
```

This contains:

- Makefile
- scripts
- notebooks
- rules
- light configuration files

### 2. Data and outputs root

Example:

```bash
/mnt/research/<your_user_or_project>/rf_arctic_project
```

This contains:

- `data_raw/`
- `data_intermediate/`
- `data_model/`
- `models/`
- `figures/`
- `reports/`
- `logs/`
- `config/`

This separation keeps the repository clean and makes it easier to rerun jobs without duplicating large files inside the git-like code tree.

---

## Step 1. Connect to Bowdoin HPC

Example:

```bash
ssh llinkas@moosehead.bowdoin.edu
```

If you are using Dover through Jupyter for interactive work, the same directory logic still applies.

---

## Step 2. Create the HPC project folders

From the HPC shell:

```bash
mkdir -p /mnt/research/<your_user_or_project>/sea-ice
mkdir -p /mnt/research/<your_user_or_project>/rf_arctic_project
```

---

## Step 3. Sync the repository to HPC

If the repo already exists locally and you want to sync it quickly:

```bash
rsync -av --exclude '.git' \
  /path/to/local/sea-ice/random-forest/ \
  llinkas@moosehead.bowdoin.edu:/mnt/research/<your_user_or_project>/sea-ice/random-forest/
```

If you are using Git on HPC, you can also clone or pull there directly.

Recommended code location on HPC:

```bash
/mnt/research/<your_user_or_project>/sea-ice/random-forest
```

---

## Step 4. Put the raw PFT zip archives on HPC

If the yearly Arctic PFT zip files are currently only on your local machine, copy them to a dedicated HPC data location.

Example:

```bash
mkdir -p /mnt/research/<your_user_or_project>/rf_arctic_project/arctic-pfts
rsync -av \
  /path/to/local/sea-ice/random-forest/arctic-pfts/ \
  llinkas@moosehead.bowdoin.edu:/mnt/research/<your_user_or_project>/rf_arctic_project/arctic-pfts/
```

Do the same later for:

- Copernicus physical files
- Copernicus sea ice files
- Copernicus biogeochemistry files
- in-situ validation files

---

## Step 5. Configure `.env.make` on HPC

On the HPC machine:

```bash
cd /mnt/research/<your_user_or_project>/sea-ice/random-forest
cp .env.make.example .env.make
```

Then edit `.env.make` so it points to your HPC paths.

Example contents:

```make
PROJECT_ROOT ?= /mnt/research/<your_user_or_project>/sea-ice/random-forest
DATA_ROOT ?= /mnt/research/<your_user_or_project>/rf_arctic_project
PFT_ZIP_DIR ?= /mnt/research/<your_user_or_project>/rf_arctic_project/arctic-pfts
PYTHON ?= /mnt/research/<your_user_or_project>/sea-ice/random-forest/.venv/bin/python
```

This tells the Makefile:

- where the code lives
- where large data and outputs should go
- where the PFT zip archives are stored

---

## Step 6. Create or activate the Python environment

At minimum, the current workflow needs:

- `python`
- `pandas`
- `pyarrow`
- `copernicusmarine`
- `h5py`

Recommended Bowdoin setup using a project-local virtual environment:

```bash
python3 -m venv /mnt/research/<your_user_or_project>/sea-ice/random-forest/.venv
source /mnt/research/<your_user_or_project>/sea-ice/random-forest/.venv/bin/activate
python -m pip install --upgrade pip
python -m pip install pandas pyarrow copernicusmarine h5py
```

Then sanity check:

```bash
python -c "import pandas, pyarrow, copernicusmarine, h5py; print('ok')"
```

---

## Step 7. Verify paths before running

Inside the HPC project directory:

```bash
make hpc-check
```

You should see:

- `PROJECT_ROOT`
- `DATA_ROOT`
- `PFT_ZIP_DIR`
- `PYTHON`
- `PREP_LOG`

If any of those are wrong, fix `.env.make` before continuing.

---

## Step 8. Initialize the HPC project layout

Run:

```bash
make init
make inventory
```

This creates the HPC-side directory tree under `DATA_ROOT` and writes the first inventory report.

---

## Step 9. Run heavy prep on HPC

For the full prep workflow:

```bash
make hpc-prep-full
```

This currently runs:

- `make init`
- `make inventory`
- `make extract-pfts`
- `make ingest-copernicus`
- `make prep-core`

and writes a timestamped log under:

```text
<DATA_ROOT>/logs/
```

You can also use the helper script:

```bash
./scripts/run_full_prep.sh
```

---

## Step 10. Smoke-test before running all years

Before launching the entire extraction or future matchup workflow, do a smaller run first.

Example:

```bash
make extract-pfts EXTRACT_YEARS=2003
make prep-core
```

This checks:

- path configuration
- parquet read performance
- write permissions
- manifest generation

without committing to the full data volume immediately.

---

## Step 11. Recommended work split between Moosehead and Dover

### Moosehead

Best for:

- batch jobs
- extraction
- table building
- RF fitting
- figure generation

### Dover

Best for:

- interactive notebook exploration
- inspecting intermediate products
- debugging heavy memory preprocessing

A good pattern is:

- prototype and inspect in Dover
- run repeatable full jobs on Moosehead

---

## Step 12. What should stay off the laptop

Try not to keep these as the main working copy on the laptop:

- full extracted PFT parquet archive
- full Copernicus predictor collections
- full matchup tables
- trained model outputs from large runs

Instead, pull back only:

- figures
- reports
- logs
- small sample tables if needed

---

## Suggested Session Workflow

### Local

```bash
edit code
test on a tiny subset
rsync repo to HPC
```

### HPC

```bash
cd /mnt/research/<your_user_or_project>/sea-ice/random-forest
conda activate <your_env_name>
make hpc-check
make hpc-prep-full
```

### Back to local

Copy back only:

- `reports/`
- `figures/`
- selected logs

### Start-of-session checklist

Before starting a new HPC work session, do this in order:

```bash
1. sync the local repository copy to Bowdoin HPC
2. ssh to Bowdoin
3. activate the project virtual environment
4. run make hpc-check
5. only then start new downloads, prep, or modeling
```

This is the recommended habit for keeping the local codebase and HPC working copy aligned.

### Session helper scripts

Two helper scripts are available in `scripts/`:

- `start_session_local.sh`
  - run this on the local machine
  - syncs the local repo to Bowdoin
  - then calls the HPC-side start-of-session check
- `start_session_hpc.sh`
  - run this on Bowdoin
  - activates the project venv
  - verifies key Python packages
  - runs `make hpc-check`

Example local usage:

```bash
cd /path/to/local/random-forest
./scripts/start_session_local.sh
```

Example HPC usage:

```bash
cd /mnt/research/mlavign/llinkas/random-forest
bash scripts/start_session_hpc.sh
```

---

## Good Practice Rules

- Always run `make hpc-check` after editing `.env.make`
- Always smoke-test on a small subset before launching a full run
- Keep logs for every large prep run
- Store raw and processed data on HPC, not inside the synced code tree
- Do not assume local paths will work on HPC
- Do not run all-years jobs from a laptop terminal session that may disconnect unless the HPC environment is configured for persistent execution

---

## Immediate Next Step For This Project

Once the PFT zips and Copernicus files are on HPC, the next coding target should be:

- building the first true core matchup table on HPC from PFT response summaries plus sea ice and physical predictors

That is the point where HPC becomes especially important, because repeated spatial-temporal harmonization and table construction will be much more expensive than the current response-only preparation step.
