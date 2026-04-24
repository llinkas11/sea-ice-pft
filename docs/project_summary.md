# Arctic PFT Random Forest — Project Status & Recent Changes

**Date:** 2026-04-22
**Study region:** 70–86°N, 25°W–35°E (Fram Strait / Greenland Sea / Barents Sea margin)
**Response:** Monthly class fractions of three phytoplankton functional types (PFTs): Coccolithophores, Diatoms, *Phaeocystis*
**Method:** Random Forest regression (`ranger`, R 4.4), three independent models per phase (one per PFT)

---

## 1. Executive summary

The project has evolved through three methodological phases. Phase 1 established an out-of-bag (OOB) baseline with 10 predictors. Phase 2 introduced 5° × 5° spatial block cross-validation and added one-month-lagged sea-ice features (12 predictors), revealing that the Phase 1 OOB scores were inflated by spatial autocorrelation. Phase 3 added eight new predictors derived from the CMEMS OMI Fram Strait ice-export flux product, yielding a 20-predictor model that improves block-CV R² by +0.05 to +0.11 across the three PFTs. A sequential ablation identified the new ice-export block as the dominant source of improvement, and the partial-dependence (ALE) curves confirmed a biologically interpretable split: *Phaeocystis* responds to ice **area** transport (habitat displacement proxy), Diatoms respond to ice **volume** transport (freshwater/mass delivery proxy). Local ice concentration/thickness — once export is in the model — carry essentially no independent predictive signal in this region.

---

## 2. Phase evolution

### Phase 1 — OOB baseline (`rf_exploring/`)
- **Predictors (10):** thetao, so, mlotst, qnet_wm2, u10_ms, v10_ms, sithick, siconc, latitude, longitude
- **Rows:** 3,004,094 (after NaN drop and seasonal filter, April–August 2003–2024)
- **Validation:** Ranger's built-in OOB
- **Results:** R² Cocco 0.91, Diatoms 0.70, *Phaeocystis* 0.88 — high, but inflated by spatial autocorrelation (neighboring pixels held out in bootstrap are near-duplicates).

### Phase 2 — spatial block CV + ice lags (`rf_exploring2/`, then ported into `rf_exploring3/`)
- **Added:** `siconc_lag1`, `sithick_lag1` via calendar-month-aware left join (not `groupby.shift()`, which would wrongly assign prior-August to April in April–August-only data).
- **Predictors (12):** Phase 1 + 2 lag features. April rows dropped (no March in dataset → lag-1 null). Season becomes May–August.
- **Rows:** 2,192,787 (deterministic fold sizes: 167,335 / 539,129 / 390,003 / 497,511 / 598,809)
- **Validation:** 5° × 5° spatial block CV, 5 folds, `seed = 42`.
- **Sequential-addition ablation:** ocean → +ice → +atm → +spatial, with marginal ΔR² at each step.
- **Results:** Full-model block-CV R² Cocco 0.302, Diatoms 0.257, *Phaeocystis* 0.459 — much lower than P1 OOB; the delta is the over-optimism spatial block CV corrected for.

### Phase 3 — Fram Strait ice-export integration (`rf_exploring3/`, **current**)
- **New feature block (8):** ice area transport (SI_AT_FS) and ice volume transport (SI_VT_FS) from the CMEMS OMI product `OMI_CLIMATE_SI_ARCTIC_transport` (dataset ID `omi_climate_si_arctic_transport`), each at four temporal aggregations: current month, one-month lag, two-month lag, and cumulative-since-October ("cumOct").
  - cumOct = running sum within an October–September water year, reset each October. Invariants (mean < 0 for both fluxes; cumOct at October = that month's flux; cumOct at May 2004 = Σ Oct 2003…May 2004) asserted at build time in `build_phase3_parquet.py`.
- **Predictors (20):** Phase 2 + 8 export features. Same row count as Phase 2 (2,192,787).
- **Validation:** Same 5° × 5° spatial block CV as Phase 2; fold determinism asserted on every run.
- **Ablation specs (6):** Full (20), No spatial (18), No local ice (16), No export (12), No atmospheric (17), Ocean only (3).
- **Full-model block-CV R²:** Cocco 0.351 (SD 0.202), Diatoms 0.367 (SD 0.057), *Phaeocystis* 0.545 (SD 0.022).

**Cross-phase Full-model R² (headline table):**

| PFT | P1 OOB | P2 block-CV | P3 block-CV | P2→P3 Δ |
|---|---|---|---|---|
| Coccolithophores | 0.913 | 0.302 | 0.351 | +0.049 |
| Diatoms | 0.700 | 0.257 | 0.367 | +0.110 |
| *Phaeocystis* | 0.880 | 0.459 | 0.545 | +0.086 |

---

## 3. Phase 3 ablation results

ΔR² values below are the R² change when the named block is dropped from the Full model (positive = Full better).

| PFT | Ocean only (drop everything but 3 ocean vars) | No spatial (−2) | No local ice (−4) | No export (−8) | No atm (−3) |
|---|---|---|---|---|---|
| Cocco (r²=0.351, SD 0.20) | +0.672 | +0.142 | −0.006 | **+0.046** | +0.017 |
| Diatoms (r²=0.367, SD 0.06) | +0.431 | +0.031 | +0.003 | **+0.109** | +0.008 |
| *Phaeocystis* (r²=0.545, SD 0.02) | +0.469 | +0.063 | −0.001 | **+0.087** | +0.020 |

Principal findings:

1. **Export is the largest driver of the P3 gain over P2** — the export-block ΔR² (+0.046 / +0.109 / +0.087) matches the P2→P3 improvements (+0.049 / +0.110 / +0.086) almost exactly, so essentially all of the P3 improvement is attributable to the 8 new features.
2. **Local ice is statistically redundant with export.** Dropping all four local-ice features (siconc, sithick, and their lag-1 counterparts) changes R² by less than one fold-SD in every PFT. Before Phase 3, the Phase 2 ablation appeared to show "sea ice doesn't matter"; the correct reinterpretation is that local ice is redundant with better-conditioned proxies (lateral flux and ocean state via T/S correlation), not unimportant.
3. **Spatial coordinates carry a large effect for Coccolithophores** (ΔR² = 0.142; 40% of Full R²) and a smaller but nonzero effect for the other two PFTs. This signals regional/longitudinal preferences not absorbed by the physical predictors.
4. **Atmospheric forcing is a marginal contributor** — significant only for *Phaeocystis* (ΔR² 0.020, ~1 fold-SD) and Coccolithophores (0.017).

**Block-level R² geography (Full model):**

| PFT | Phase 2 block R² mean | Phase 3 block R² mean | P2 worst block R² | P3 worst block R² |
|---|---|---|---|---|
| Cocco | −0.011 | +0.099 | −2.88 | −0.91 |
| Diatoms | +0.206 | +0.311 | −0.09 | −0.08 |
| *Phaeocystis* | +0.383 | +0.475 | +0.11 | +0.22 |

Largest geographic improvement: Cocco's deep-red (pathologically negative R²) blocks shifted substantially toward zero — the Phase 3 export features disproportionately help the hardest-to-predict regions for Cocco.

---

## 4. Accumulated Local Effects (ALE)

### 4.1 Implementation
Hand-rolled per Apley & Zhu (2020, eqs. 7–8) — no `iml` dependency. Now lives as `compute_ale()` in `rf_utils.R` (extracted during a `/simplify` pass — see §7).

- **Sample:** 30,000 rows drawn with seed 42
- **Bins:** K = 20 quantile-based edges per feature
- **Centering:** bin-count-weighted mean subtracted
- **Per-fold evaluation:** 3 PFTs × 5 folds × 20 features × 20 bins × 2 predictions → ~12,000 ranger `predict()` calls per run.
- **Runtime:** ~3h 1m on SLURM (8 cores, 32 GB) — job 54863 on moose12, finished 2026-04-22 00:37.
- **Outputs:** `p3_ale_raw.csv` (per fold), `p3_ale_aggregated.csv` (fold-mean + IQR), `p3_ale_all_variables.png` (20-panel grid from R).

### 4.2 Key ALE findings (from aggregated CSV)

Per-PFT strongest effects (span = max − min of centred ALE across the observed predictor range):

- ***Phaeocystis*** — thetao (span 0.132, monotone decrease 0–8 °C); latitude (0.120 rise 70–83°N); ice_area_flux_lag1 (0.100, negative); ice_area_flux_lag2 (0.086, negative); ice_volume_flux_cumOct (0.082, positive).
- **Diatoms** — ice_volume_flux_cumOct (0.054, negative); ice_volume_flux_lag2 (0.050, negative); ice_volume_flux_lag1 (0.031, negative); latitude (0.026). Volume-flux family dominates.
- **Coccolithophores** — longitude (0.056, positive east); ice_area_flux_lag1 (0.034, positive); ice_area_flux_cumOct (0.032, negative); siconc (0.031). Uniformly small amplitudes, consistent with their low Full-model R² and high fold-SD.

### 4.3 Biologically interpretable split (area vs volume flux)

With the 3-PFT overlay on each panel, the flux-family preference becomes visible:
- *Phaeocystis* tracks a deeper (more negative) curve along **ice area** flux than along ice volume flux at lag-1 and lag-2 → responsive to ice-edge position and habitat displacement.
- Diatoms track a deeper (more negative) curve along **ice volume** flux than along ice area flux at lag-1, lag-2, and cumOct → responsive to freshwater/mass transport.
- Coccolithophores show no consistent preference (small amplitudes for both).

This split was invisible in the Phase 2 ALE (which had no flux features at all) and could not be read off single-PFT panels — it required the 3-PFT overlay.

---

## 5. Figures and tables artifact (`rf_exploring3_figs_tables.docx`)

The main deliverable assembling Phase 3 results. Current contents (2.2 MB on HPC, mirrored to local Desktop + OneDrive):

| # | Content | Status |
|---|---|---|
| Figure 1 | Phase 3 block-CV R² per 5° tile (3-panel map, one per PFT) | in place (PNG embed, rId7) |
| Figure 2 | Phase 3 out-of-sample prediction map (obs / predicted / residual, per PFT) | in place (rId8) |
| Figure 3 | Phase 3 ALE curves, 16 significant predictors, 4×4 grid, 3-PFT overlay, titles below | in place (rId14); the 4 local-ice panels were dropped because their ablation ΔR² is below fold noise |
| Figure 4 | Phase 3 ALE curves, 12 panels in 3×4 with combined area+volume flux panels, z-score x-axis, panel labels A.–L. | in place (rId16); the 4 ice-flux panels overlay area (solid) and volume (dashed) |
| Figure 5 | Phase 3 ALE: 8 non-flux predictors (ocean, atm, spatial), 2×4, panel labels A.–H. | in place (rId17); journal-ready caption |
| Figure 6 | Phase 3 ALE: 8 ice-flux predictors, 4×2 grid (4 lags × 2 flux types), panel labels A.–H. | in place (rId18, 4×2 revision); common y-axis [−0.055, +0.055] so amplitudes compare directly across lags and flux types |
| Table 1 | PFT predictability across phases + feature-block contributions with significance | in place |
| Table 2 | Ocean-mediator correlation structure | in place |
| Table 3 | Phase 3 block-CV ablation (18 rows: 6 specs × 3 PFTs) with caption/result/**4-paragraph expanded discussion** on local-ice redundancy | in place |
| Tables S1–S4 | Phase 1 supplementary material (NaN fix, P1 Full ablation, mediation) | in place |

Captions were rewritten in journal-ready (Mayot et al., 2020 JGR-Oceans) style: dense, self-contained, axis/color-key-forward.

All three locations kept in sync:
- HPC: `/mnt/research/mlavign/llinkas/random-forest/runs/rf_exploring3/rf_exploring3_figs_tables.docx`
- Local Desktop: `/Users/llinkas/Desktop/rf_exploring3_figs_tables.docx`
- OneDrive: `/Users/llinkas/Library/CloudStorage/OneDrive-BowdoinCollege/Desktop/rf_exploring3_figs_tables.docx`

---

## 6. Methods document updates (`sea-ice-workingdoc.docx`)

Six red-highlighted edits were applied to the main methods document to bring it up to Phase 3 status:

1. **§2.5 row count fix:** `[N] rows` → **2,192,787**, `2003–2018` → **2003–2024** (with strikethroughs on the old values)
2. **§2.5 mtry addendum:** `, mtry = 6 for Phase 3` appended (ranger `⌊p/3⌋`, so ⌊20/3⌋ = 6)
3. **§2.5 Phase 3 configuration paragraph:** new paragraph describing the 20-predictor specification, the Krumpen-et-al Transpolar-Drift motivation for the export features, the cumOct definition, and the P2→P3 R² gains
4. **§2.5 ablation extension:** extends the ablation description with the sixth "no export" spec and the extended sequential-addition chain (ocean → ice → **export** → atm → spatial), plus the local-ice-redundancy finding
5. **New §2.3b "Fram Strait Ice-Export Flux" subsection:** documents the CMEMS OMI product, the sign convention, the four derived predictors per base series, and the water-year cumOct rule
6. **Works Cited additions:** Copernicus Marine Service OMI reference + Krumpen et al. 2019 (Scientific Reports 9:5459)

File: `/Users/llinkas/Desktop/sea-ice-workingdoc.docx` (updated 2026-04-21).

---

## 7. Code and infrastructure changes

### Reproducibility document
`methods.md` (15 sections, ~650 lines) in the project root documents: exact predictor-block constants (`P3_*_VARS` in `rf_utils.R`), fold row counts for `assert_fold_determinism()`, ranger hyperparameters (overrides and retained defaults), the calendar-aware lag implementation, the water-year cumOct formula with build-time invariants, ALE configuration, SLURM conventions, full citations with DOIs.

### Code cleanup (`/simplify` pass)
Extracted shared helpers from `compute_ale_p3.R` into `rf_utils.R`:
- `compute_ale()` — was duplicated verbatim between `compute_ale_p2.R` and `compute_ale_p3.R`
- `PFT_COLORS` — Okabe-Ito palette keyed on `names(PFT_RESPONSES)` so a PFT rename can't desync colours from responses
- `ALE_SAMPLE_SIZE = 30000L`, `ALE_N_BINS = 20L` — were magic numbers duplicated across scripts
- `P3_RESULT_DIR` alias for `P2_RESULT_DIR`

Also replaced O(n²) `rbind`-in-loop with preallocated list + single `bind_rows()` in `compute_ale_p3.R` (300-iteration loop).

The `/simplify` pass identified but deferred one larger optimization: batching the K × feature `predict()` calls (stack 20 × 20 × 2 = 800 query rows into one call per (PFT, fold)). Expected savings: ~60–90 min per full ALE run. Noted as a future refactor; not critical since the run only needs to be done when the feature set or training data changes.

### Permission allowlist
`.claude/settings.json` in the project root now allows `Edit`, `Write`, `NotebookEdit`, `Bash(scp *)`, `Bash(mkdir *)`, `Bash(cp *)`, `Bash(mv *)`, `Bash(pip3 install *)`, `Bash(markitdown *)`, `Bash(pandoc *)`, `Bash(unzip *)`, `Bash(zip *)`, and `mcp__Claude_in_Chrome__navigate` — reduces permission prompts for the common file-ops and figure-build workflows.

### Scripts on HPC
```
/mnt/research/mlavign/llinkas/random-forest/runs/rf_exploring3/
├── rf_utils.R                       # shared utilities, constants, compute_ale()
├── model_comparison_p1.R            # Phase 1 OOB
├── model_comparison_p2.R            # Phase 2 block-CV
├── model_comparison_p2_seqadd.R     # Phase 2 sequential addition
├── model_comparison_p3.R            # Phase 3 block-CV (6-spec ablation)
├── model_comparison_p3_temporal.R   # NEW: leave-one-year-out temporal CV (not yet run)
├── compute_ale_p2.R                 # Phase 2 ALE (12 predictors)
├── compute_ale_p3.R                 # Phase 3 ALE (20 predictors) — uses rf_utils::compute_ale
├── predict_p3.R                     # OOS predictions + 3×3 map (obs/pred/residual × PFT)
├── build_block_r2_map.R             # P2 block R² geography
├── build_p3_block_r2_map.R          # P3 block R² geography
├── scripts/
│   ├── build_phase2_parquet.py      # adds lag-1 ice features
│   ├── build_phase3_parquet.py      # merges CMEMS OMI flux with cumOct invariants
│   ├── download_omi_transport.py    # CMEMS OMI fetch
│   ├── probe_utils.py               # calendar-aware add_monthly_lags(), etc.
│   └── test_probe_utils.py
├── data_model/
│   ├── final-spatial-matchup-p2.parquet     # 2,192,787 rows, 17 cols
│   └── final-spatial-matchup-p3.parquet     # 2,192,787 rows, 25 cols
├── data_raw/cmems_omi/              # raw OMI netCDF
├── models_p{1,2,3}/                 # cached per-fold ranger models (.rds)
├── results/                         # CSVs (block-CV, fold detail, ALE, block R²)
└── logs/                            # SLURM stdout/stderr
```

### Software
- R 4.4, `ranger` 0.18.0, `arrow`, `dplyr`, `ggplot2`
- Python 3.12, `pandas`, `numpy`, `xarray`
- SLURM (Bowdoin HPC) — submit via `moosehead` scheduler; jobs run on `moose*` nodes. Typical: `--cpus-per-task=8–16`, `--mem=32G`, wall times 4–36 h by phase.

---

## 8. Outstanding / planned work

1. **Leave-one-year-out temporal CV** (`model_comparison_p3_temporal.R`) — script is ready but has not been submitted. Motivation: spatial block CV has a structural advantage for spatially-constant temporal predictors (basin-scale flux is identical across held-out cells in a given month, so the model has seen that value during training in other regions). Temporal CV holds out whole years including their flux series — an orthogonal robustness check. Adds two isolation specs ("Export only" and "Local ice only") for a direct head-to-head. 22 folds × 8 specs × 3 PFTs ≈ 528 ranger fits; probably 6–10 h on one 16-core node.

2. **Main-paper figure budget triage.** The figures doc now has six figures plus four tables. Main-paper figure budget is typically 4–5; the current set needs a prioritization pass. Likely keep: Figure 1 (block-CV R² map), Figure 4 (combined ALE, 3×4), Figure 6 (flux-only ALE, 4×2). Figures 2/3/5 either merge or move to supplementary.

3. **Ardyna et al. PFT dataset citation.** The final published reference (DOI) for the pan-Arctic PFT classification product is still a placeholder in `methods.md` and the working doc — to be filled in when the source publication reaches its final state.

4. **Batched-predict optimization for `compute_ale`.** Stack per-feature query rows into one `predict()` per (PFT, fold) — expected ~60–90 min savings per full ALE run. Useful if the feature set changes again.

5. **Discussion-section interpretive text** for the local-ice redundancy finding is drafted in the figures doc (Table 3's 4-paragraph expanded Discussion); still needs to be lifted into the main manuscript with the Transpolar Drift framing (Krumpen et al., 2019).

---

## 9. Data citations

- **Ardyna et al.** — pan-Arctic phytoplankton functional type classification, daily 4 km, 2003–2024 (April–August). *DOI TBD*
- **Copernicus Marine Service — Arctic Ocean Physics Reanalysis (TOPAZ4).** Dataset `cmems_mod_arc_phy_my_topaz4_P1M`. doi:10.48670/moi-00007. Sakov et al., 2012; Xie et al., 2017.
- **Copernicus Marine Service — Arctic Ocean Sea Ice Analysis (neXtSIM).** Dataset `cmems_mod_arc_phy_my_nextsim_P1M-m`. doi:10.48670/moi-00004. Williams et al., 2021.
- **Copernicus Marine Service — Arctic Monthly Sea Ice Volume and Area Transports through the main Arctic Straits from Reanalysis.** Product `OMI_CLIMATE_SI_ARCTIC_transport`. doi:10.48670/moi-00186.
- **ERA5 global reanalysis.** Hersbach et al., 2020. doi:10.1002/qj.3803. Copernicus Climate Change Service.

## 10. Method citations

- **Apley & Zhu (2020).** Visualizing the effects of predictor variables in black box supervised learning models. *J. R. Stat. Soc. B* 82(4):1059–1086. doi:10.1111/rssb.12377.
- **Wright & Ziegler (2017).** ranger: A Fast Implementation of Random Forests for High Dimensional Data in C++ and R. *J. Stat. Softw.* 77(1):1–17. doi:10.18637/jss.v77.i01.
- **Roberts et al. (2017).** Cross-validation strategies for data with temporal, spatial, hierarchical, or phylogenetic structure. *Ecography* 40(8):913–929. doi:10.1111/ecog.02881.
- **Ploton et al. (2020).** Spatial validation reveals poor predictive performance of large-scale ecological mapping models. *Nature Communications* 11:4540. doi:10.1038/s41467-020-18321-y.
- **Krumpen et al. (2019).** Arctic warming interrupts the Transpolar Drift and affects long-range transport of sea ice and ice-rafted matter. *Scientific Reports* 9:5459. doi:10.1038/s41598-019-41456-y.
- **Strobl et al. (2007).** Bias in random forest variable importance measures. *BMC Bioinformatics* 8:25. doi:10.1186/1471-2105-8-25.
