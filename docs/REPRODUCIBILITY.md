# Reproducibility

## Environment

- R 4.4, packages pinned in `renv.lock`
- Python 3.12, packages pinned in `environment.yml`
- SLURM (optional); `slurm/local_fallback.sh` provides a non-SLURM driver

## Hardware expectations

- Full Phase 3 block-CV: ~6 h on 16 cores, ~32 GB RAM (Bowdoin `moose*` nodes)
- Phase 3 ALE (30,000-row sample, K=20): ~3 h on 8 cores
- Smoke tests (`tests/smoke_test_p3.R`): ~30 s on a laptop, uses 10 trees and 10,000 rows

## Determinism

- `RF_SEED=42` (from `.env`, surfaced by `rf_seed()` in `config.R`)
- 5° × 5° block assignment is deterministic given the input parquet order and seed
- `assert_fold_determinism()` in `rf_utils.R` checks fold row counts against `P2_EXPECTED_FOLD_SIZES = c(167335, 539129, 390003, 497511, 598809)` on every run; any mismatch aborts
- `ranger` respects the seed when `num.threads` is constant; change `RF_N_THREADS` between runs and expect float-precision differences (rarely affects headline R² beyond 3 dp)

## End-to-end Phase 3 from the Zenodo parquet

```
cp .env.example .env                             # edit paths
R -e 'renv::restore()'                           # install R pkgs
conda env create -f environment.yml && conda activate arctic-pft-rf
zenodo_get 10.5281/zenodo.PLACEHOLDER -o "$RF_DATA_ROOT"
sbatch slurm/run_phase3.sh                       # or bash slurm/local_fallback.sh phase3
Rscript R/compute_ale_p3.R                       # ALE figure (~3 h)
Rscript R/build_p3_block_r2_map.R                # block-CV R² map
Rscript R/predict_p3.R                           # out-of-sample prediction map
```

Expected outputs (under `$RF_OUT_ROOT/results/`):

- `p3_block_cv_results.csv` (18 rows: 6 specs × 3 PFTs, mean + sd R² and MSE)
- `p3_ale_raw.csv`, `p3_ale_aggregated.csv`
- `p3_block_r2.csv`
- `p3_predictions_raw.csv`, `p3_predictions_gridded.csv`

## Checking your run matches the paper

```
Rscript -e '
  d <- read.csv(file.path(Sys.getenv("RF_OUT_ROOT"), "results", "p3_block_cv_results.csv"))
  d <- d[d$model_short == "full", c("pft", "r2_mean")]
  stopifnot(abs(d$r2_mean[d$pft == "Coccolithophores"] - 0.351) < 0.005)
  stopifnot(abs(d$r2_mean[d$pft == "Diatoms"]          - 0.367) < 0.005)
  stopifnot(abs(d$r2_mean[d$pft == "Phaeocystis"]      - 0.545) < 0.005)
  message("Phase 3 Full R² reproduced within 0.005")
'
```

## Rebuilding parquets from raw data

See `docs/DATA.md`. The raw-to-parquet pipeline is independent of the RF training pipeline; the Zenodo parquets are sufficient for all published results.
