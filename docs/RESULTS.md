# Results

## Headline block-CV R² (fold-mean, Full model)

| PFT              | P1 OOB | P2 block-CV (12 pred.) | P3 block-CV (20 pred.) |
|------------------|--------|------------------------|------------------------|
| Coccolithophores | 0.913  | 0.302 (±0.18)          | 0.351 (±0.20)          |
| Diatoms          | 0.700  | 0.257 (±0.05)          | 0.367 (±0.06)          |
| *Phaeocystis*    | 0.880  | 0.459 (±0.04)          | 0.545 (±0.02)          |

## Phase 3 ablation (ΔR² when the named block is dropped from Full)

| PFT              | −spatial | −local ice | −export | −atm  | ocean only |
|------------------|----------|------------|---------|-------|------------|
| Coccolithophores | +0.142   | −0.006     | +0.046  | +0.017 | +0.672    |
| Diatoms          | +0.031   | +0.003     | +0.109  | +0.008 | +0.431    |
| *Phaeocystis*    | +0.063   | −0.001     | +0.087  | +0.020 | +0.469    |

Export is the dominant driver of the P2 → P3 improvement in all three PFTs. Local ice is statistically indistinguishable from zero (ΔR² below fold-SD) once export is present: the variance local siconc/sithick carries is already captured by basin-integrated flux plus ocean state via T/S correlation.

## ALE findings

See `figures/p3_ale_combined_z.png` (all 20 predictors overlaid for 3 PFTs, z-score axis for export panels). Per-PFT dominant effects (ALE span, max − min of centred effect):

- *Phaeocystis* — thetao (0.132, monotone decrease 0→8 °C); latitude (0.120 rise 70–83°N); ice_area_flux_lag1 (0.100, negative); ice_area_flux_lag2 (0.086, negative); ice_volume_flux_cumOct (0.082, positive)
- Diatoms — ice_volume_flux_cumOct (0.054, negative), ice_volume_flux_lag2 (0.050, negative), ice_volume_flux_lag1 (0.031, negative)
- Coccolithophores — longitude (0.056, positive east), ice_area_flux_lag1 (0.034, positive), siconc (0.031)

Phaeocystis responds preferentially to ice **area** flux (habitat/edge-position proxy); Diatoms respond preferentially to ice **volume** flux (freshwater/mass transport proxy). This split is visible only in the 3-PFT overlay and is absent from Phase 2 (which has no flux features).

## Block-level R² geography

From `figures/p3_block_r2_map.png`. Mean across 5° × 5° tiles for the Full model:

| PFT              | P2 block R² mean | P3 block R² mean | P3 worst tile |
|------------------|------------------|------------------|---------------|
| Coccolithophores | −0.011           | +0.099           | −0.91 (was −2.88 in P2) |
| Diatoms          | +0.206           | +0.311           | −0.08         |
| *Phaeocystis*    | +0.383           | +0.475           | +0.22         |

Export features disproportionately help the tiles where Phase 2 failed hardest for Coccolithophores.

## Figures in this repo

| File | Shows |
|---|---|
| `p3_block_r2_map.png` | Phase 3 block-CV R² per 5° tile, one panel per PFT |
| `p3_predictions_map.png` | Observed / predicted / residual maps, one row per PFT |
| `p3_ale_significant.png` | Phase 3 ALE, 16 predictors × 3 PFTs (local ice dropped) |
| `p3_ale_combined_z.png` | Phase 3 ALE, 3×4 grid with area+volume flux combined per temporal aggregation |
| `p3_ale_nonflux.png` | Phase 3 ALE, 8 non-flux predictors, A–H panels |
| `p3_ale_flux_4x2.png` | Phase 3 ALE, 8 flux predictors, 4×2 grid with common y-axis |

Source data for each figure is under `figures/source_data/`.
