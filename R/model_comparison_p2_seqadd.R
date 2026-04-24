#!/usr/bin/env Rscript
# Phase 2 sequential-addition ablation — add the true "ocean-only" spec.
#
# Combined with Phase 2's existing results, this gives the sequential-addition
# sequence:
#   1. ocean     (3 predictors) — added by this script
#   2. + ice  =  7              → Phase 2 "Ocean only"
#   3. + atm  = 10               → Phase 2 "No spatial"
#   4. + spatial = 12 = Full    → Phase 2 "Full"

source(file.path(Sys.getenv("RF_PROJECT_ROOT", unset = "."), "R/rf_utils.R"))
setup_rlibs()

suppressPackageStartupMessages({
  library(arrow); library(dplyr); library(ranger)
})

message("Reading Phase 2 parquet")
df <- arrow::read_parquet(P2_DATA_PATH)
df <- rename_era5_cols(df)
df <- assign_5deg_blocks(df)

block_fold <- split_blocks_to_folds(unique(df$block_id),
                                    n_folds = 5L, seed = DEFAULT_SEED)
df <- df %>% dplyr::left_join(block_fold, by = "block_id")
assert_fold_determinism(df)
message("Fold determinism verified vs Phase 2")

test_idx <- split(seq_len(nrow(df)), df$fold)

specs <- list(
  list(name  = "Ocean (3 predictors, seqadd baseline)",
       short = "ocean3",
       vars  = c("thetao", "so", "mlotst"))
)
stopifnot(all(specs[[1]]$vars %in% names(df)))

out <- run_block_cv_ablation(
  df            = df,
  test_idx      = test_idx,
  specs         = specs,
  pft_responses = PFT_RESPONSES,
  num_trees     = RANGER_NUM_TREES
)
results     <- out$results
fold_detail <- out$fold_detail

write.csv(results,     file.path(P2_RESULT_DIR, "p2_seqadd_ocean3_results.csv"),     row.names = FALSE)
write.csv(fold_detail, file.path(P2_RESULT_DIR, "p2_seqadd_ocean3_fold_detail.csv"), row.names = FALSE)

# -------- Sequential-addition decomposition --------
p2_path <- file.path(P2_RESULT_DIR, "p2_block_cv_results.csv")
if (!file.exists(p2_path)) {
  stop("Missing Phase 2 results at ", p2_path,
       ". Run model_comparison_p2.R first.")
}
p2 <- read.csv(p2_path, stringsAsFactors = FALSE)

seqadd <- data.frame()
for (pft_name in names(PFT_RESPONSES)) {
  r_ocean        <- r2_by_spec(results, pft_name, "ocean3")
  r_ocean_ice    <- r2_by_spec(p2,       pft_name, "ocean_only")
  r_ocean_ice_at <- r2_by_spec(p2,       pft_name, "no_spatial")
  r_full         <- r2_by_spec(p2,       pft_name, "full")

  seqadd <- rbind(seqadd, data.frame(
    pft                    = pft_name,
    r2_ocean3              = round(r_ocean, 4),
    r2_plus_ice            = round(r_ocean_ice, 4),
    r2_plus_ice_atm        = round(r_ocean_ice_at, 4),
    r2_full                = round(r_full, 4),
    delta_ice_over_ocean   = round(r_ocean_ice - r_ocean, 4),
    delta_atm_over_ice     = round(r_ocean_ice_at - r_ocean_ice, 4),
    delta_spatial_over_atm = round(r_full - r_ocean_ice_at, 4),
    stringsAsFactors = FALSE
  ))
}

write.csv(seqadd, file.path(P2_RESULT_DIR, "p2_seqadd_table.csv"), row.names = FALSE)

message("\n===== Sequential-addition decomposition =====")
print(seqadd)
message("\nResults: ", file.path(P2_RESULT_DIR, "p2_seqadd_ocean3_results.csv"))
message("Table:   ", file.path(P2_RESULT_DIR, "p2_seqadd_table.csv"))
