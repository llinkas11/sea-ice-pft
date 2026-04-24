# Arctic PFT Random-Forest: Fram Strait sea-ice export and phytoplankton

Random-forest regression of monthly class fractions for three Arctic phytoplankton functional types — Coccolithophores, Diatoms, *Phaeocystis* — on ocean, sea-ice, atmospheric, spatial, and Fram Strait ice-export predictors. Training domain 70–86°N, 25°W–35°E, May–August 2003–2024. The paper-target configuration ("Phase 3") adds eight features derived from the CMEMS OMI Fram Strait ice-transport reanalysis to the Phase 2 local-ice-only specification, raising block-CV R² across all three PFTs.

## Block-CV R² (Full model, fold-mean)

| PFT              | Phase 1 (OOB) | Phase 2 (12 pred., block-CV) | Phase 3 (20 pred., block-CV) |
|------------------|---------------|------------------------------|------------------------------|
| Coccolithophores | 0.913 | 0.302 | 0.351 |
| Diatoms          | 0.700 | 0.257 | 0.367 |
| *Phaeocystis*    | 0.880 | 0.459 | 0.545 |

Phase 1 OOB is not comparable to Phase 2/3 block-CV; the OOB value is inflated by spatial autocorrelation between neighbouring pixels. See `docs/methods.md`.

## Layout

```
R/            production R scripts (rf_utils.R + phase scripts + ALE + maps)
scripts/      Python data builders (CMEMS/OMI downloads, parquet construction)
slurm/        SLURM templates for every stage; local_fallback.sh for non-SLURM
config.R      env-var readers used by every R script
config.py     Python equivalent
docs/         methods, data sources, reproducibility, results summary
figures/      paper figure PNGs + source-data CSVs
tests/        parse + smoke tests
Makefile      pipeline orchestration
```

## Quick start

```
git clone <this repo> sea-ice-pft && cd sea-ice-pft
cp .env.example .env                 # edit paths for your machine
R -e 'renv::restore()'               # installs pinned R packages
conda env create -f environment.yml  # Python env
# fetch the phase 3 parquet + fitted model from Zenodo <DOI>
Rscript R/model_comparison_p3.R      # runs the paper model
```

Smoke test (no parquet, ~30 s) once the env is set up:

```
RF_PROJECT_ROOT=$(pwd) Rscript tests/smoke_test_p3.R
```

## Full reproduction (Phase 3)

1. `cp .env.example .env`; set `RF_PROJECT_ROOT`, `RF_DATA_ROOT`, `RF_OUT_ROOT`, `R_LIBS_USER`, `RF_N_THREADS`.
2. Install R packages: `R -e 'renv::restore()'`.
3. Install Python env: `conda env create -f environment.yml && conda activate sea-ice-pft`.
4. Fetch the Zenodo deposit into `$RF_DATA_ROOT` (see `docs/DATA.md`).
5. On SLURM: `sbatch slurm/run_phase3.sh`. Without SLURM: `bash slurm/local_fallback.sh phase3`.
6. Regenerate figures: `Rscript R/compute_ale_p3.R`, `Rscript R/build_p3_block_r2_map.R`, `Rscript R/spatial_maps.R`.

Headline Phase 3 R² should match 0.351 / 0.367 / 0.545 (Cocco / Diatoms / Phaeo) within ±0.005.

## Data availability

The training parquets, raw-data manifest, and the fitted Phase 3 ranger model are archived on Zenodo: `<DOI>`. Primary input products:

- CMEMS Arctic Physics Reanalysis (TOPAZ4), `cmems_mod_arc_phy_my_topaz4_P1M`
- CMEMS Arctic Sea Ice Reanalysis (neXtSIM), `cmems_mod_arc_phy_my_nextsim_P1M-m`
- CMEMS OMI Arctic Ice Transport (Fram Strait), `OMI_CLIMATE_SI_ARCTIC_transport`
- ERA5 monthly on single levels (Hersbach et al., 2020)
- Pan-Arctic PFT classification (Ardyna et al.)

Full retrieval commands in `docs/DATA.md`.

## Methods

`docs/methods.md` gives the complete specification — predictor blocks, calendar-aware lag-1 construction, water-year cumulative flux, ranger hyperparameters, 5° × 5° spatial block CV, ALE implementation.

## Citation

See `CITATION.cff`. Cite the Zenodo DOI for the code-and-data archive and the forthcoming journal article for the methodology.

## License

MIT. See `LICENSE`.
