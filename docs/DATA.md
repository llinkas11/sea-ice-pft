# Data

Primary training data is archived on Zenodo; raw reanalysis products are pulled directly from their source services. All paths below are relative to `$RF_DATA_ROOT` (set in `.env`).

## Zenodo deposit

DOI: `10.5281/zenodo.PLACEHOLDER`

Contents:

| File | Size | Rows | Schema |
|---|---|---|---|
| `final-spatial-matchup.parquet` | ~500 MB | 3,004,094 | Phase 1 table, 10 predictors, Apr–Aug 2003–2024 |
| `final-spatial-matchup-p2.parquet` | ~350 MB | 2,192,787 | Phase 2 table, adds siconc_lag1/sithick_lag1, May–Aug |
| `final-spatial-matchup-p3.parquet` | ~400 MB | 2,192,787 | Phase 3 table, adds 8 Fram Strait flux features |
| `fitted_p3_ranger.rds` | ~150 MB | — | Phase 3 Full ranger model, ready for `predict()` |
| `raw_manifest.csv` | <1 MB | — | Source product IDs, date ranges, one-line retrieval per row |
| `figures_source_data/` | ~50 MB | — | CSVs backing each figure PNG |

Fetch:

```
zenodo_get 10.5281/zenodo.PLACEHOLDER -o "$RF_DATA_ROOT"
```

## Raw product retrieval

The Zenodo deposit holds derived parquets sufficient to reproduce every result in the paper. The commands below reconstruct the raw inputs if you need them.

- **CMEMS Arctic Physics Reanalysis (TOPAZ4)** — `Rscript`-callable via `scripts/download_core_copernicus_monthly.py`. Dataset ID `cmems_mod_arc_phy_my_topaz4_P1M`, variables `thetao`, `so`, `mlotst`. Domain 70–90 N, 25 W–35 E, 2003–2024.
- **CMEMS Arctic Sea-Ice Reanalysis (neXtSIM)** — same download script, dataset `cmems_mod_arc_phy_my_nextsim_P1M-m`, variables `siconc`, `sithick`.
- **CMEMS OMI Arctic Ice Transport** — `python scripts/download_omi_transport.py`. Dataset `omi_climate_si_arctic_transport`.
- **ERA5 monthly on single levels** — Copernicus CDS API request (not scripted here; see Hersbach et al. 2020 for variables `u10`, `v10`, `msshf`, `mslhf`, `msnswrf`, `msnlwrf`).
- **Pan-Arctic PFT classification (Ardyna et al.)** — daily 4 km parquet archive, separate deposit; cite per the source publication.

## Build pipeline

1. Download raw products into `$RF_DATA_ROOT/copernicus/` and `$RF_DATA_ROOT/cmems_omi/`.
2. `python scripts/build_monthly_pft_gridcell_table.py` — aggregate daily PFT to monthly 4 km grid.
3. `python scripts/join_monthly_spatial_tables.py` — join predictors to PFT response.
4. `python scripts/build_phase2_parquet.py` — add calendar-aware lag-1 ice.
5. `python scripts/build_phase3_parquet.py` — merge Fram Strait flux features; asserts sign convention and cumOct invariants.

Row counts after each stage: 3,004,094 (P1) → 2,192,787 (P2, April rows drop) → 2,192,787 (P3, no loss).
