# Random Forest Analysis Plan
## Northeast Arctic Ocean Sea Ice & Primary Production
**Region:** 70°N–90°N, 25°W–35°E

---

## 1. Scientific Question

The core research question is: **How does primary production, measured through phytoplankton functional types (PFTs), vary with sea ice and ocean physical conditions across the Northeast Arctic Ocean?**

The random forest is being used primarily as a **covariance identification and variable-importance tool**, not just as a black-box predictor. The goal is to determine which environmental drivers — sea ice concentration, sea ice thickness, temperature, salinity, mixed layer depth, and light-related variables — explain the most variance in phytoplankton distributions, and whether those relationships have meaningful temporal structure.

This project uses two main RF response setups:

- **Classification RF:** predict `pixel_class`
- **Regression RF:** predict `chlorophyll_guesses`

The satellite PFT product is the primary response dataset. In-situ observations are used only for independent validation, never for training.

---

## 2. Starter Code Strategy

### 2a. CEMAC LIFD_RandomForests — Use as a Structural Template

The [cemac/LIFD_RandomForests](https://github.com/cemac/LIFD_RandomForests) repository should be used as the **structural guide and jumping-off point** for this project.

**What it provides:**
- A clean Python + scikit-learn RF workflow in Jupyter notebooks
- An existing conda environment file (`RF.yml`) that can help bootstrap the HPC environment
- Worked examples of regression and classification random forests
- Useful patterns for train/test splitting, variable-importance plotting, and general notebook organization

**What it does NOT do for this project:**
- It is built for a different scientific problem and different data structures
- It does not handle Arctic ocean / sea ice datasets
- It does not include parquet + NetCDF data ingestion for this project
- It does not include spatial matchup logic
- It does not include temporal block cross-validation or this project’s partitioned analysis design

**Adaptation plan:**
Fork or copy the CEMAC structure and reuse it as a project scaffold. Replace the original terrestrial data-loading and model-specific sections with this project’s Arctic data pipeline, matchup workflow, and train/test design. Keep the general notebook architecture, environment setup logic, and RF workflow patterns.

### 2b. Project repository and commit workflow

The active project repository is:

```text
sea-ice-pft
https://github.com/llinkas11/sea-ice-pft.git
```

This repository should be treated as the canonical project codebase for notebooks, scripts, documentation, and workflow tracking.

**Required Git behavior:**
- At the **start of every work session**, pull or otherwise sync the current state of the repository before making changes.
- At the **end of every work session**, create a Git commit summarizing what was done or changed.
- Commit messages should follow the documentation rules already established for the project and should clearly describe the substantive work completed in that session.
- The goal is that each session leaves a readable project history showing what changed, why, and what stage of the pipeline was advanced.

This start-of-session and end-of-session Git update behavior should be treated as part of the standard workflow, not something that requires a new prompt each time.

### 2c. Language and runtime environment

The RF workflow should be implemented in **Python** using **scikit-learn**, primarily through **Jupyter notebooks** running on Bowdoin HPC resources.

Primary compute environments:
- **Moosehead via SSH:** `ssh llinkas@moosehead.bowdoin.edu`
- **Dover via Jupyter notebook** for heavier memory or interactive preprocessing work

**Recommendation:**
- Use **Dover** for larger data-preparation and regridding tasks, especially when working interactively through Jupyter notebook
- Use **Moosehead** for standard RF fitting, evaluation, figure generation, and batch-oriented work

### 2d. Project storage policy

The bulk of the work should be run on Bowdoin HPC, and the project data should also be stored there.

This includes:
- downloaded raw datasets
- intermediate processed datasets
- parquet modeling tables
- trained model objects
- generated figures
- notebook files
- Codex notes and session logs

The HPC copy should be treated as the project’s working source of truth. In practice, the project should be run on Bowdoin’s high-speed computing environment through Moosehead or Dover rather than trying to process the full datasets locally.

A suggested directory layout on HPC:

```text
/mnt/research/<project_or_user_dir>/rf_arctic_project/
    data_raw/
    data_processed/
    notebooks/
    scripts/
    models/
    figures/
    logs/
    codex_notes/
```

---

## 3. Codex Collaboration Protocol

Codex will be used as a coding partner for implementation, debugging, and workflow refinement. To keep work consistent across sessions, there should be a separate running session-log file that Codex reads and updates automatically.

### 3a. Required Codex log behavior

At the **start of every work session**, Codex should:
- read the existing Codex session log file
- read the main project README / analysis plan file
- check the current repository state if relevant to the task
- prompt the user to run the start-of-session helper before new work begins
  - local helper: `scripts/start_session_local.sh`
  - HPC helper: `scripts/start_session_hpc.sh`
- summarize the current project state before making changes

At the **end of every work session**, Codex should:
- append a concise summary of what was completed
- record any new files created or modified
- note unresolved issues / next steps
- update the current state of the pipeline
- ensure the session changes are reflected in the project repository workflow

This should happen **without needing to be prompted by the user each time**.

For Bowdoin HPC work, the expected start-of-session order is:

1. sync the local project to Bowdoin
2. activate the project venv on Bowdoin
3. run the helper-based environment checks
4. only then continue with downloads, prep, or modeling

### 3b. Separate Codex log file

Use a separate file for session history, for example:

```text
codex_notes/codex_session_log.md
```

Recommended sections for that file:
- Session date / time
- Files read at session start
- Files modified
- What was completed
- Current blockers
- Next recommended step
- Git status / commit note for the session

The purpose of this file is to maintain continuity across working sessions and reduce repeated setup / re-explanation.

---

## 4. Current Data Inventory

### Main datasets for this project

| Dataset | Role in project | Main variables | Notes |
|---|---|---|---|
| **Ardyna et al. PFT daily product (2003–2024)** | Primary response dataset | `pixel_class`, `chlorophyll_guesses` | Daily, 4 km, April–August only |
| **Copernicus Arctic Physics Reanalysis** | Core predictor dataset | temperature, salinity, mixed layer depth | Physical ocean environment |
| **Copernicus Arctic Sea Ice Reanalysis** | Core predictor dataset | sea ice concentration, sea ice thickness | Central sea-ice predictors |
| **Copernicus Arctic Biogeochemistry Reanalysis** | Expanded-model predictors | chlorophyll, nutrients, oxygen, primary productivity, phytoplankton carbon | Use in secondary analysis |
| **In-situ Arctic observations** | Validation only | CHEMTAX / chlorophyll / cruise measurements | Never used for training |

### Dataset A — Ardyna et al. PFT product
- **Coverage:** 2003–2024
- **Temporal resolution:** daily
- **Seasonal window:** April–August only
- **Spatial resolution:** 4 km
- **Response variables:** `pixel_class`, `chlorophyll_guesses`
- **Role:** primary response dataset for the RF

This is the biology that the model is trying to explain.

### Dataset B — Copernicus Arctic Physics Reanalysis
- **Role:** core predictor dataset
- **Primary variables:** temperature, salinity, mixed layer depth
- **Use:** describe the physical ocean conditions associated with different PFT states

### Dataset C — Copernicus Arctic Sea Ice Reanalysis
- **Role:** core predictor dataset
- **Primary variables:** sea ice concentration, sea ice thickness
- **Use:** capture the sea-ice conditions at the center of the project question

### Dataset D — Copernicus Arctic Biogeochemistry Reanalysis
- **Role:** expanded-model predictor dataset
- **Primary variables:** chlorophyll, nutrients, oxygen, primary productivity, phytoplankton carbon
- **Use:** robustness check / secondary model, not the simplest starting point

### Dataset E — In-situ observations
Examples include:
- `glo_data_arctic.csv`
- related cruise / CHEMTAX / pigment datasets

These are used for:
- external validation
- interpretation
- checking whether the satellite response product behaves reasonably in the study region

These should **not** be merged into the main training table as the core RF response.

---

## 5. Which datasets to use first

### Core analysis (recommended first)

Use:
- **Ardyna PFT product** as the response
- **Copernicus Arctic Physics Reanalysis** as core ocean predictors
- **Copernicus Arctic Sea Ice Reanalysis** as core sea-ice predictors

This gives the cleanest and most interpretable model:
- response = biology
- predictors = physical ocean + sea ice

### Expanded analysis (secondary)

Add:
- **Copernicus Arctic Biogeochemistry Reanalysis**

This should be treated as a second-stage analysis after the core model is running.

Why it is secondary:
- it adds complexity
- some variables are conceptually close to the biology being predicted
- it is more useful as a robustness check than as the first-pass model

---

## 6. Time Range and Partitioned Analysis Design

### 6a. Important overlap logic

The Ardyna PFT dataset exists from **2003–2024**, but only **April–August** each year.

That means all matched modeling tables should be built around the PFT availability window. Any predictor dataset with broader annual coverage should be restricted to the overlapping PFT months when constructing the main response table.

### 6b. Main partitioned analysis plan

To keep the analysis both **simple** and **scientifically defensible**, use a partitioned design with two model families:

#### Model Family 1 — Core model
Use:
- Ardyna PFT
- Arctic Physics Reanalysis
- Arctic Sea Ice Reanalysis

**Target window:**
- April–August, matched over the chosen overlap period

This is the main RF analysis and should be completed first.

#### Model Family 2 — Expanded model
Use:
- Ardyna PFT
- Arctic Physics Reanalysis
- Arctic Sea Ice Reanalysis
- Arctic Biogeochemistry Reanalysis

This is the secondary analysis used to test whether adding BGC predictors changes variable importance or improves predictive performance.

### 6c. Train / test logic

**Do not randomly split rows.**

The data are spatially and temporally autocorrelated, so random row splitting would produce overly optimistic performance.

Recommended strategy:
- **Train:** earlier years
- **Test:** later held-out years
- Use grouped temporal blocks for CV during training

If using the same design logic as the earlier plan:
- train on the earlier matched years
- hold out the final full year as the test set

If the matched overlap is large enough, use:
- grouped CV by **year-month** during training
- final evaluation on a held-out year

### 6d. Validation partition

Keep in-situ observations fully separate.

They should be used only after the RF has been trained and evaluated on the gridded dataset. Then compare model outputs against in-situ observations for interpretation and external validation.
