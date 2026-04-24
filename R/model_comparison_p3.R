#!/usr/bin/env Rscript
# =============================================================================
# Phase 3 — CMEMS OMI Fram Strait ice-export integration
#
# New feature block: ice_export (8 features)
#   ice_area_flux_{current, lag1, lag2, cumOct}
#   ice_volume_flux_{current, lag1, lag2, cumOct}
#
# Phase 3 Full model = 20 predictors:
#   ocean (3): thetao, so, mlotst
#   local ice (4): siconc, sithick, siconc_lag1, sithick_lag1
#   export (8): ice_area_flux_*, ice_volume_flux_*
#   atm (3): qnet_wm2, u10_ms, v10_ms
#   spatial (2): latitude, longitude
#
# Six-spec ablation (primary hypothesis: Full vs No_export):
#   Full (20), No spatial (18), No local ice (16), No export (12),
#   No atmospheric (17), Ocean only (3)
#
# Block-CV: same 5° × 5° fold split as Phase 2 (different parquet but same
# spatial structure — fold determinism verified by assert_fold_determinism).
# =============================================================================

source(file.path(Sys.getenv("RF_PROJECT_ROOT", unset = "."), "R/rf_utils.R"))
setup_rlibs()

suppressPackageStartupMessages({
  library(arrow); library(dplyr); library(ranger)
})

P3_DATA_PATH  <- file.path(P2_OUT_DIR, "data_model/final-spatial-matchup-p3.parquet")
P3_MODEL_DIR  <- file.path(P2_OUT_DIR, "models_p3")
dir.create(P3_MODEL_DIR, recursive = TRUE, showWarnings = FALSE)

# Optional PFT-parallelism: if P3_PFT_FILTER env var is set (e.g., "Diatoms"),
# only process that one PFT. Model .rds cache paths are PFT-scoped so parallel
# PFT jobs don't collide. Output CSV gets a PFT suffix to avoid clobbering.
pft_filter <- Sys.getenv("P3_PFT_FILTER", unset = "")
pft_responses_active <- if (nzchar(pft_filter)) {
  if (!(pft_filter %in% names(PFT_RESPONSES))) {
    stop("P3_PFT_FILTER='", pft_filter, "' not in PFT_RESPONSES: ",
         paste(names(PFT_RESPONSES), collapse = ", "))
  }
  message("PFT filter active: ", pft_filter)
  PFT_RESPONSES[pft_filter]
} else {
  PFT_RESPONSES
}
pft_suffix <- if (nzchar(pft_filter)) paste0("_", tolower(pft_filter)) else ""

message("Reading Phase 3 parquet: ", P3_DATA_PATH)
df <- arrow::read_parquet(P3_DATA_PATH)
message("Dimensions: ", paste(dim(df), collapse = " x "))

df <- rename_era5_cols(df)
df <- assign_5deg_blocks(df)

block_fold <- split_blocks_to_folds(unique(df$block_id),
                                    n_folds = 5L, seed = DEFAULT_SEED)
df <- df %>% dplyr::left_join(block_fold, by = "block_id")
assert_fold_determinism(df)
message("Fold determinism verified (same 5° split as Phase 2)")

test_idx <- split(seq_len(nrow(df)), df$fold)

stopifnot(all(P3_ALL_VARS %in% names(df)))

model_specs <- list(
  list(name = "Full (20 predictors)", short = "full",
       vars = P3_ALL_VARS),
  list(name = "No spatial (18)", short = "no_spatial",
       vars = setdiff(P3_ALL_VARS, P3_SPATIAL_VARS)),
  list(name = "No local ice (16)", short = "no_local_ice",
       vars = setdiff(P3_ALL_VARS, P3_LOCAL_ICE_VARS)),
  list(name = "No export (12)", short = "no_export",
       vars = setdiff(P3_ALL_VARS, P3_EXPORT_VARS)),
  list(name = "No atmospheric (17)", short = "no_atm",
       vars = setdiff(P3_ALL_VARS, P3_ATM_VARS)),
  list(name = "Ocean only (3)", short = "ocean_only",
       vars = P3_OCEAN_VARS)
)
stopifnot(identical(sapply(model_specs, function(s) length(s$vars)),
                    c(20L, 18L, 16L, 12L, 17L, 3L)))

out <- run_block_cv_ablation(
  df            = df,
  test_idx      = test_idx,
  specs         = model_specs,
  pft_responses = pft_responses_active,
  model_dir     = P3_MODEL_DIR,
  model_prefix  = "p3",
  num_trees     = RANGER_NUM_TREES
)
results     <- out$results
fold_detail <- out$fold_detail

results <- results %>%
  dplyr::group_by(pft) %>%
  dplyr::mutate(
    r2_drop     = r2_mean[model_short == "full"] - r2_mean,
    r2_drop_pct = round(100 * r2_drop / r2_mean[model_short == "full"], 1)
  ) %>%
  dplyr::ungroup()

# Cross-phase comparison: join Phase 2 onto Phase 3 results.
# Phase 2 named its 8-predictor drop-ice spec "no_ice"; Phase 3 renames that
# to "no_local_ice" to distinguish from the new "no_export" spec. Rename on
# the Phase 2 side before joining so the row lines up.
p2_path <- file.path(P2_RESULT_DIR, "p2_block_cv_results.csv")
if (file.exists(p2_path)) {
  p2 <- read.csv(p2_path, stringsAsFactors = FALSE)
  p2$model_short[p2$model_short == "no_ice"] <- "no_local_ice"
  results <- results %>%
    dplyr::left_join(
      p2 %>% dplyr::select(pft, model_short, p2_r2 = r2_mean, p2_mse = mse_mean),
      by = c("pft", "model_short")
    )
}

results_path <- file.path(P2_RESULT_DIR,
                          paste0("p3_block_cv_results", pft_suffix, ".csv"))
fold_path    <- file.path(P2_RESULT_DIR,
                          paste0("p3_block_cv_fold_detail", pft_suffix, ".csv"))
write.csv(results,     results_path, row.names = FALSE)
write.csv(fold_detail, fold_path,    row.names = FALSE)

message("\n===== Phase 3 results",
        if (nzchar(pft_filter)) paste0(" (", pft_filter, " only)") else "", " =====")
print(results %>% dplyr::select(pft, model_short, n_predictors, r2_mean, r2_sd))
message("\nResults: ", results_path)
