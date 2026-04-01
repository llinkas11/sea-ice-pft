# Random Forest Method Template for Arctic Sea Ice + PFT Analysis

## Purpose

This document defines which parts of the Jin et al. (2024) random forest workflow should be adopted for the Arctic sea ice and phytoplankton functional type (PFT) project, which parts should be adapted, and which parts should not be copied directly.

The goal is to avoid ad hoc model development and to keep the Arctic workflow scientifically grounded in an interpretable ocean-biogeochemical RF framework.

---

## Primary References

- **Jin et al. (2024)**: methodological template for interpretable ocean-biogeochemical random forests
- **CEMAC LIFD_RandomForests**: code and workflow structure template
- **Project rules in this repository**: Arctic-specific scientific constraints

---

## High-Level Position

For this project:

- **Use Jin et al. (2024) as the primary methodological template**
- **Use CEMAC as the structural / coding template**
- **Do not copy Jin et al. train/test splitting directly**

This project is closer to Jin et al. than to CEMAC in scientific purpose because both use random forests to interpret environmental controls on ocean biological or biogeochemical fields rather than using RF only as a generic machine-learning exercise.

---

## What To Adopt From Jin et al. (2024)

### 1. RF role in the project

Random forest should be used primarily as:

- a **covariance identification tool**
- a **driver-ranking tool**
- a **nonlinear sensitivity-analysis tool**

It should not be framed only as a black-box predictive model.

### 2. Interpretation framing

Interpret all inferred RF relationships as:

- **apparent relationships**
- not direct causal physiological laws

This is especially important because Arctic ocean predictors covary strongly and because ecological structure, sea ice, light, stratification, and grazing-related processes are not cleanly separable in observational data.

### 3. Importance diagnostics

The workflow should include:

- **permutation importance** on held-out data
- **partial dependence plots (PDPs)** or equivalent single-variable sensitivity diagnostics
- **median-replacement analysis** or an equivalent perturbation diagnostic for mapping where a driver matters most

These diagnostics are directly useful for the Arctic project because the main question is about environmental controls on PFT variability, not only predictive skill.

### 4. Continuous-target transformation logic

For strongly right-skewed continuous targets, especially:

- `chlorophyll_guesses`

the workflow should test a **log10 transform** or similar stabilized transform before model fitting.

This should be treated as the default starting point for regression unless exploratory diagnostics show that an untransformed target is more appropriate.

### 5. Harmonized predictor-target grid logic

All target and predictor fields must be harmonized onto a common spatiotemporal support before modeling.

This is directly aligned with Jin et al., even though the exact Arctic resolution and time structure will differ.

---

## What To Adapt For The Arctic Project

### 1. Target setup

Jin et al. modeled only continuous regression targets.

This project has two target families:

- **Regression**: `chlorophyll_guesses`
- **Classification**: `pixel_class`

Therefore:

- Jin-style regression methods should be used for `chlorophyll_guesses`
- classification workflows must be developed separately for `pixel_class`
- interpretation logic for classification should be implemented carefully and not assumed to transfer one-to-one from the regression case

### 2. Temporal structure

Jin et al. used monthly climatological data on a common large-scale grid.

This project uses:

- daily PFT files
- April-August seasonal availability
- multi-year overlap with environmental predictors

So we must explicitly choose among:

- daily matched rows
- monthly aggregated matchups
- year-month grouped tables

The recommended first defensible version is:

- build **daily or monthly matched tables**
- evaluate with **year-based blocking**
- preserve the April-August observation window

### 3. Spatial harmonization

Jin et al. regridded satellite targets to 1 degree.

For this Arctic project, the harmonization scale must be chosen based on:

- the native PFT resolution
- the predictor resolution
- computational cost
- the need to reduce oversampling and small-scale noise

This means we should not commit to 4 km modeling rows if the predictor data are substantially coarser. Aggregation or regridding may be necessary before modeling.

### 4. Predictor design

Jin et al. used 11 predictors and emphasized physically interpretable environmental drivers.

For this project, the core predictor family should begin with:

- sea ice concentration
- sea ice thickness
- temperature
- salinity
- mixed layer depth
- light-related variables if available

The expanded model can then add:

- biogeochemical predictors

This staged design preserves interpretability and matches the project rules already defined in the repository.

### 5. Metrics

Jin et al. reported:

- correlation
- `R^2`
- RMSE
- bias

For this project:

- keep those metrics for regression where appropriate
- add classification metrics for `pixel_class`
- evaluate both global skill and blocked held-out performance

Recommended first regression metrics:

- RMSE
- MAE
- `R^2`
- correlation
- bias

Recommended first classification metrics:

- balanced accuracy
- macro F1
- confusion matrix
- per-class recall

---

## What Not To Copy Directly From Jin et al. (2024)

### 1. Random 80/20 row split

This should **not** be used as the default split strategy for the Arctic PFT project.

Reason:

- the data are spatially autocorrelated
- the data are temporally autocorrelated
- neighboring rows and adjacent dates are not independent
- a random split will likely inflate apparent model skill

### 2. Implicit reliance on coarse regridding alone to address autocorrelation

Even if spatial aggregation is used, it should not be assumed that this alone solves dependence problems.

The Arctic workflow still needs explicit blocked evaluation.

### 3. Direct reuse of RF hyperparameters

Jin et al. used:

- MATLAB `treebagger`
- 50 trees
- 4 predictors sampled per tree from 11 total predictors
- random split without replacement

These settings are informative, but should not be copied blindly.

For this project, hyperparameters should be:

- initialized using Jin et al. as a starting reference
- then checked against Arctic data behavior
- documented explicitly in the repo

---

## Recommended Arctic Train/Test Design

### Core principle

**Do not randomly split rows.**

This rule exists because the Arctic PFT matchup data are not independent at the row level.
Nearby pixels and nearby dates are often highly similar due to spatial and temporal
autocorrelation. A random row split would therefore allow the model to train on samples
that are extremely close to the test samples in both space and time, which would
artificially inflate apparent model skill. In practice, that would make it harder to tell
whether the RF is learning defensible large-scale environmental relationships or simply
exploiting local similarity in gridded data.

The blocked design is intended to answer a stricter and more scientifically useful
question: can a model trained on earlier periods generalize to later periods with similar
environmental structure but different realized observations?

### Recommended first implementation

- Train on earlier years
- Hold out the final full year for test
- During training, use grouped CV by `year_month` or by year

Example:

- training years: all but final year
- test year: final year
- grouped CV unit: `year_month`

This is more scientifically defensible than Jin et al.'s random 80/20 split for the Arctic use case.

### Optional stronger design

If enough matched years are available:

- hold out multiple years
- test robustness across early vs late periods
- optionally test geographic holdouts if regional generalization becomes important

---

## Recommended Modeling Sequence

### Phase 1. Response-only preparation

- Build PFT extraction workflow
- Inventory class and chlorophyll structure
- Decide whether regression target uses raw or log10-transformed values

### Phase 2. Core matchup table

- Match PFT response data with:
  - sea ice
  - physics
  - light if available
- Restrict to overlapping April-August periods
- Harmonize onto a defensible common grid/time support

### Phase 3. Core RF models

- Regression RF for `chlorophyll_guesses`
- Classification RF for `pixel_class`
- Use blocked train/test design

### Phase 4. Interpretation products

- Held-out permutation importance
- PDPs / sensitivity curves
- median-replacement or equivalent perturbation maps

### Phase 5. Expanded-model comparison

- Add biogeochemical predictors
- Compare:
  - predictive skill
  - variable-importance rankings
  - sensitivity structure

---

## Recommended Initial Hyperparameter Policy

Until Arctic-specific tuning is implemented, start with a modest, transparent configuration and document it.

Suggested initial regression/classification baseline:

- `n_estimators`: begin above Jin et al.'s 50, for example 200-500
- `max_features`: test values analogous to Jin et al.'s subset-per-tree logic
- `min_samples_leaf`: tune conservatively to reduce overfitting
- `random_state`: fixed
- `oob_score`: optional diagnostic, not a replacement for blocked testing

This should be treated as an initial benchmark only.

---

## Correlated Predictors

Environmental predictors in the Arctic system will covary strongly.

Therefore:

- importance rankings must be interpreted cautiously
- correlation structure should be inspected explicitly
- if possible, use importance methods that are more robust to correlated predictors
- all writeups should state that the RF identifies variance-explaining environmental structure, not isolated causal mechanisms

---

## Winter / Missing-Data Policy

Jin et al. filled low-light seasonal gaps with low percentile values.

That should **not** be adopted automatically here.

For this project:

- the PFT product is already limited to April-August
- first-pass analysis should stay within the observed seasonal window
- no winter infilling should be introduced unless there is a separate scientific justification

---

## Practical Repo Rule

When implementing RF code in this repository:

- if a choice is borrowed from Jin et al., document it as such
- if a choice differs from Jin et al., explain why the Arctic PFT workflow requires the change
- do not introduce train/test logic, aggregation rules, or importance methods without tying them to either:
  - Jin et al. (2024)
  - project rules already present in `random-forest/rules/`
  - or explicit new methodological justification recorded in the repo

---

## Current Best-Practice Summary

### Use directly

- RF for environmental driver-ranking
- held-out permutation importance
- PDP-style interpretation
- median-replacement sensitivity mapping
- apparent-relationship framing

### Use with adaptation

- target transformation
- predictor harmonization
- spatial aggregation
- hyperparameter defaults
- performance metrics

### Reject for this project

- random 80/20 row split as the main validation design
- uncritical transfer of monthly climatology assumptions
- direct copying of MATLAB-specific implementation choices without Arctic testing

---

## Immediate Next Coding Step

The next implementation step should be:

- build the first true core matchup table from PFT response summaries plus Arctic predictor datasets

Only after that should the project implement:

- blocked RF training
- held-out evaluation
- variable-importance and sensitivity diagnostics
