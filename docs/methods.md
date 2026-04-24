# Random Forest PFT Prediction — Methods (Phases 1–3)

Fram Strait / Northeast Arctic. Response: monthly class fractions of three phytoplankton functional types (Coccolithophores, Diatoms, Phaeocystis). Predictors: ocean physics, sea ice, atmosphere, lateral ice export, spatial coords. Three methodological phases; Phase 3 is the publication-target model.

## 1. Study domain and temporal window

- **Region:** 70°N–90°N, 25°W–35°E.
- **Spatial unit:** 4 km × 4 km pixel (PFT native grid).
- **Time step:** monthly; one row per (pixel, year, month).
- **Years:** 2003–2024.
- **Season:** April–August (Phase 1); May–August after lag-1 requirement (Phase 2 & 3).

## 2. Data sources

| Block | Variable(s) | Product | ID / Access | Resolution | Time |
|---|---|---|---|---|---|
| Ocean | `thetao`, `so`, `mlotst` | CMEMS Arctic Physics Reanalysis (TOPAZ4) | `cmems_mod_arc_phy_my_topaz4_P1M` | native TOPAZ4 grid | monthly, 2003–2024 |
| Local sea ice | `siconc`, `sithick` | CMEMS Arctic Sea Ice Reanalysis (neXtSIM) | `cmems_mod_arc_phy_my_nextsim_P1M-m` | native neXtSIM grid | monthly, 2003–2024 |
| Atmospheric | `qnet_wm2` (net ocean heat loss), `u10_ms`, `v10_ms` | ERA5 | ECMWF/CDS | 0.25° | monthly, 2003–2024 |
| Lateral ice export (P3 only) | `SI_AT_FS_Reanalysis` (area transport), `SI_VT_FS_Reanalysis` (volume transport) | CMEMS OMI Arctic Transport — Fram Strait | `OMI_CLIMATE_SI_ARCTIC_transport` (`omi_climate_si_arctic_transport`) | Fram Strait gate integral (no grid) | monthly, 1991–2024. Sign convention: negative = southward export. |
| Response (PFT fractions) | `class_fraction__{coccolithophores,diatoms,phaeocystis}` | Ardyna et al. satellite PFT classification | daily pixel-level | 4 km | 2003–2024, Apr–Aug |

All gridded predictors were regridded to the 4 km PFT grid (KDTree-based unit-sphere nearest-neighbor snap; polar-aware, dateline-safe). Monthly aggregation: pixel-month class fraction = count(pixels classified as X) / count(total classified pixels) in that month. No sub-monthly interpolation. No inter-month temporal interpolation.

## 3. Preprocessing

### 3.1 Numerical-noise cleanup (before NA drop)
```R
siconc  = if_else(!is.na(siconc)  & siconc  < 1e-14, 0, siconc)
sithick = if_else(!is.na(sithick) & sithick < 1e-14, 0, sithick)
```
Genuine `NA` preserved; only reanalysis numerical noise zeroed.

### 3.2 Row filter (each phase drops rows with any `NA` in its predictor set and all three PFT responses)

| Phase | Row count after filter | Reason for loss |
|---|---|---|
| P1 | 3,417,067 | base matchup + predictor NA drop |
| P2 | 2,192,787 | P1 + drop April rows (no March → no `*_lag1`) |
| P3 | 2,192,787 | P2 + merge OMI export flux (no rows lost; early water-year `cumOct` already resolved by 2003) |

P2 per-fold row counts (deterministic; verified by `assert_fold_determinism()`): **167,335 / 539,129 / 390,003 / 497,511 / 598,809**.

### 3.3 ERA5 column rename (`rename_era5_cols()` in `rf_utils.R`)
`era5_qnet_ocean_loss_wm2 → qnet_wm2`, `era5_u10_ms → u10_ms`, `era5_v10_ms → v10_ms`. Prefers `qnet_ocean_loss`; falls back to `qnet_downward` only if the loss column is absent.

## 4. Feature engineering

### 4.1 Lag-1 ice features (P2 & P3)
Calendar-month-aware left join, **not** `groupby().shift()`:
```
for each (lat, lon, year, month) row:
    key = (lat, lon, year*12 + month - 1)
    pull siconc, sithick from row with that key; else NA
```
Implemented in `scripts/probe_utils.py::add_monthly_lags()`. This matters because the data is Apr–Aug-only: a naive shift would pull August-of-prior-year as "lag-1 of April". April rows (no March) → lag-1 `NA` → dropped.

### 4.2 Ice-export flux features (P3, 8 features derived from 2 base series)

For `flux ∈ {ice_area_flux, ice_volume_flux}`:
- `{flux}_current` — renamed from raw `SI_{AT,VT}_FS_Reanalysis`, units km²/day and km³/day respectively.
- `{flux}_lag1`, `{flux}_lag2` — `pandas.Series.shift(1/2)` on time-sorted monthly series.
- `{flux}_cumOct` — cumulative sum within a water year.

Water-year definition:
```python
water_year  = np.where(month >= 10, year + 1, year)
water_month = np.where(month >= 10, month - 9, month + 3)  # Oct=1 … Sep=12
fs = fs.sort_values(["water_year", "water_month"]).reset_index(drop=True)
fs[f"{flux}_cumOct"] = fs.groupby("water_year")[flux].cumsum()
```
Invariants asserted in `scripts/build_phase3_parquet.py`:
1. `cumOct` at October = that month's flux only.
2. `cumOct` at May 2004 = Σ(Oct 2003 … May 2004).
3. `cumOct` in first water year in raw data (1991) is `NaN` (Oct 1990 not in file) — removed before the P3 merge window so no P3 training row inherits `NaN`.
4. `mean(current) < 0` for both area and volume (confirms southward-export sign convention preserved through pipeline).

## 5. Predictor sets per phase

```R
# rf_utils.R — canonical, load-time length-checked.
P3_OCEAN_VARS     = c("thetao","so","mlotst")                              # 3
P3_LOCAL_ICE_VARS = c("siconc","sithick","siconc_lag1","sithick_lag1")     # 4
P3_EXPORT_VARS    = c("ice_area_flux_current","ice_area_flux_lag1",
                      "ice_area_flux_lag2","ice_area_flux_cumOct",
                      "ice_volume_flux_current","ice_volume_flux_lag1",
                      "ice_volume_flux_lag2","ice_volume_flux_cumOct")     # 8
P3_ATM_VARS       = c("qnet_wm2","u10_ms","v10_ms")                        # 3
P3_SPATIAL_VARS   = c("latitude","longitude")                              # 2
# Totals: P1 = 10 (3+2+3+2), P2 = 12 (3+4+3+2), P3 = 20 (3+4+8+3+2)
```

## 6. Random forest specification

- **Package:** R `ranger` v0.18.0, R 4.4 (`/home/llinkas/R/x86_64-redhat-linux-gnu-library/4.4/`).
- **Framing:** regression (continuous `class_fraction__*`). One model per PFT (3 independent models, not multi-output).
- **Hyperparameters (explicit):**
  - `num.trees = 100` (`RANGER_NUM_TREES`; 10 for smoke tests).
  - `importance = "impurity"`.
  - `seed = 42` (`DEFAULT_SEED`).
  - `num.threads = SLURM_CPUS_ON_NODE ?? max(1, detectCores() - 1)` (= 8 or 16 on Slurm).
- **Defaults retained:** `mtry = floor(sqrt(n_features))`, `min.node.size = 5`, `sample.fraction = 1.0`, `replace = TRUE`, `respect.unordered.factors = FALSE`.

## 7. Validation

### 7.1 Phase 1 — OOB
Ranger's built-in out-of-bag. Not comparable to P2/P3 numerically (spatial autocorrelation inflates OOB R²).

### 7.2 Phase 2 & 3 — 5° × 5° spatial block cross-validation

Block assignment (deterministic):
```R
block_lat = floor(latitude  / 5) * 5
block_lon = floor(longitude / 5) * 5
block_id  = paste0(block_lat, "_", block_lon)
```
Fold assignment:
```R
set.seed(42)
block_fold = data.frame(block_id = unique(block_id),
                        fold     = sample(rep(1:5, length.out = n_blocks)))
```
**Every block's rows land in exactly one fold**; folds are geographically disjoint patches of blocks. `assert_fold_determinism()` verifies the five fold row counts (§3.2) on every run; any mismatch halts training.

Per (model spec × PFT): 5 fits, held-out block R² and MSE recorded, mean and SD across folds reported. The Full model is fit separately per fold and cached to disk (`models_p3/p3_full_{pft}_fold{k}.rds`).

### 7.3 Ablation specs (Phase 3, six specs)
| Short name | n predictors | Drop |
|---|---|---|
| `full` | 20 | — |
| `no_spatial` | 18 | P3_SPATIAL_VARS |
| `no_local_ice` | 16 | P3_LOCAL_ICE_VARS |
| `no_export` | 12 | P3_EXPORT_VARS |
| `no_atm` | 17 | P3_ATM_VARS |
| `ocean_only` | 3 | everything except P3_OCEAN_VARS |

Phase 3 `no_local_ice` was named `no_ice` in Phase 2; Phase 3 renames before the cross-phase join in `model_comparison_p3.R`.

### 7.4 Sequential-addition (Phase 2 only, `model_comparison_p2_seqadd.R`)
Chain: ocean (3) → +local ice (7) → +atm (10) → +spatial (12), with ΔR² at each step. Complements the subtractive ablation.

## 8. Accumulated Local Effects (ALE)

Hand-rolled per Apley & Zhu (2020) eqs. 7–8 — no `iml` dependency. `compute_ale_p{2,3}.R`.

- **Sample:** 30,000 rows drawn without replacement from the phase's parquet (`set.seed(42)`).
- **Bins:** `K = 20`, quantile edges (`quantile(x, seq(0,1,len=K+1))`, deduplicated).
- **Local effect at bin k:** `mean over rows in bin k of [f(x with feature = edge[k+1]) - f(x with feature = edge[k])]`.
- **ALE:** `cumsum(local_effects)`, then centered by bin-count-weighted mean so bin-weighted mean ALE = 0.
- Computed per PFT × fold (uses cached fold models). Aggregated across folds as mean + IQR (25th / 75th percentile).
- Output: per-row `p{phase}_ale_raw.csv`, aggregated `p{phase}_ale_aggregated.csv`, plot `p{phase}_ale_all_variables.png` (20-panel, 3-PFT overlay, facet titles below panels).

## 9. Per-block geographic R² map

`build_p3_block_r2_map.R`. For each test block in each fold, compute R² and MSE on the held-out rows of that block (n_pixels included as a weight / filter). Aggregate across folds per block (mean). Render three faceted maps (one per PFT), 5° × 5° tiles, diverging red-white-blue fill centered at R² = 0, continents overlaid.

Block-level means (Full model):

| PFT | P2 block-R² mean | P3 block-R² mean | P2 min | P3 min |
|---|---|---|---|---|
| Cocco | −0.011 | +0.099 | −2.88 | −0.91 |
| Diatoms | 0.206 | 0.311 | −0.09 | −0.08 |
| Phaeo | 0.383 | 0.475 | +0.11 | +0.22 |

(Block-level R² mean ≠ fold-mean R² because block weighting differs.)

## 10. Headline fold-mean block-CV R²

Phase 3 Full model:

| PFT | R² | SD across folds | MSE |
|---|---|---|---|
| Coccolithophores | 0.351 | 0.202 | 0.00876 |
| Diatoms | 0.367 | 0.057 | 0.00985 |
| Phaeocystis | 0.545 | 0.022 | 0.04902 |

ΔR² from Full per ablation block (positive = Full better):

| PFT | −spatial | −local ice | −export | −atm | ocean only |
|---|---|---|---|---|---|
| Cocco | +0.142 | −0.006 | **+0.046** | +0.017 | +0.672 |
| Diatoms | +0.031 | +0.003 | **+0.109** | +0.008 | +0.431 |
| Phaeo | +0.063 | −0.001 | **+0.087** | +0.020 | +0.469 |

Export features contribute 13–30% of Full R². Local ice is statistically indistinguishable from zero when export is present (all three PFTs |ΔR²| < fold SD) — the redundancy finding that motivates the Discussion paragraph.

## 11. Cross-phase Full-model comparison

| PFT | P1 OOB R² | P2 block-CV R² | P3 block-CV R² |
|---|---|---|---|
| Cocco | 0.913 | 0.302 | 0.351 |
| Diatoms | 0.700 | 0.257 | 0.367 |
| Phaeo | 0.880 | 0.459 | 0.545 |

P1 → P2 drop reflects switching from row-shuffled OOB to spatial block-CV, not model degradation.

## 12. Software and compute

- **R 4.4**, ranger 0.18.0, arrow, dplyr, ggplot2, cowplot.
- **Python 3.12** (`.venv/`), pandas, numpy, xarray, scipy, scikit-learn.
- **Slurm (Bowdoin HPC, moosehead scheduler):** partition `main`, `--cpus-per-task=8–16`, `--mem=32G`, wall times 4–36 h depending on phase.
- **Job scripts:** `run_phase{1,2,3}.sh`, `run_ale.sh`, `run_ale_p3.sh`, `run_p3_blockmap.sh`.

## 13. File manifest (Bowdoin HPC)

```
/mnt/research/mlavign/llinkas/random-forest/
├── data_model/final-spatial-matchup{,-p2,-p3}.parquet      # row counts §3.2
├── scripts/
│   ├── build_monthly_pft_gridcell_table.py                 # PFT→4 km matchup
│   ├── join_monthly_spatial_tables.py                      # feature merge
│   └── download_core_copernicus_monthly.py                 # CMEMS fetch
└── runs/rf_exploring3/
    ├── rf_utils.R                                          # constants, folding, run_block_cv_ablation
    ├── model_comparison_p{1,2,3}.R                         # training entry points
    ├── model_comparison_p2_seqadd.R                        # sequential addition
    ├── compute_ale_p{2,3}.R                                # ALE
    ├── build_{,p3_}block_r2_map.R                          # block-R² maps
    ├── predict_p3.R                                        # OOS predictions + gridded map
    ├── scripts/
    │   ├── build_phase{2,3}_parquet.py                     # feature engineering
    │   ├── download_omi_transport.py                       # CMEMS OMI fetch
    │   └── probe_utils.py                                  # add_monthly_lags, etc.
    ├── data_model/final-spatial-matchup-p{2,3}.parquet
    ├── data_raw/{copernicus,cmems_omi}/                    # raw NetCDFs
    ├── models_p{1,2,3}/                                    # cached fold models
    ├── results/                                            # CSVs + PNGs
    └── logs/                                               # Slurm stdout/stderr
```

## 14. Reproducibility determinism summary

- Random seed: **42** everywhere (ranger, block-to-fold sample, ALE subsample).
- `num.trees`: **100** (production).
- P2/P3 fold row counts asserted each run.
- Model caches keyed by `p{phase}_{spec}_{pft}_fold{k}.rds` — reruns reuse.
- Predictor set constants (`P{n}_*_VARS`) are length-checked at source time with `stopifnot(length(P3_ALL_VARS) == 20L)`.

## 15. Citations

**Datasets**
- Copernicus Marine Service. *Arctic Ocean Physics Reanalysis* (TOPAZ4). Product `ARCTIC_MULTIYEAR_PHY_002_003`, dataset `cmems_mod_arc_phy_my_topaz4_P1M`. doi:10.48670/moi-00007.
- Copernicus Marine Service. *Arctic Ocean Sea Ice Analysis and Forecast* (neXtSIM). Dataset `cmems_mod_arc_phy_my_nextsim_P1M-m`. doi:10.48670/moi-00004.
- Copernicus Marine Service. *Arctic Sea Ice Area and Volume Transport through Fram Strait*. OMI product `OMI_CLIMATE_SI_ARCTIC_transport` (`omi_climate_si_arctic_transport`). doi:10.48670/moi-00186.
- Hersbach, H., et al. (2020). *The ERA5 global reanalysis.* Q. J. R. Meteorol. Soc. 146:1999–2049. doi:10.1002/qj.3803.
- Ardyna, M., et al. *Satellite-derived phytoplankton functional type classifications, pan-Arctic, 2003–2024* (daily, 4 km). [add final DOI / citation when paper supplies it].

**Methods**
- Apley, D. W., & Zhu, J. (2020). *Visualizing the effects of predictor variables in black box supervised learning models.* J. R. Stat. Soc. B 82(4):1059–1086. doi:10.1111/rssb.12377.
- Wright, M. N., & Ziegler, A. (2017). *ranger: A Fast Implementation of Random Forests for High Dimensional Data in C++ and R.* J. Stat. Softw. 77(1):1–17. doi:10.18637/jss.v77.i01.
- Roberts, D. R., et al. (2017). *Cross-validation strategies for data with temporal, spatial, hierarchical, or phylogenetic structure.* Ecography 40(8):913–929. doi:10.1111/ecog.02881. (motivates spatial block CV)
- Krumpen, T., et al. (2019). *Arctic warming interrupts the Transpolar Drift and affects long-range transport of sea ice and ice-rafted matter.* Sci. Rep. 9:5459. doi:10.1038/s41598-019-41456-y. (supports ice-export framing)
