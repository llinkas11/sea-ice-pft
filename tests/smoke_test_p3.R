#!/usr/bin/env Rscript
# Phase 3 smoke test — verify load, rename, blocks, fold split, and all 6 specs
# trainable on a 10k subsample with 10 trees each. Should finish in ~20 s.

source(file.path(Sys.getenv("RF_PROJECT_ROOT", unset = "."), "R/rf_utils.R"))
setup_rlibs()

suppressPackageStartupMessages({
  library(arrow); library(dplyr); library(ranger)
})

P3_DATA_PATH <- file.path(P2_OUT_DIR, "data_model/final-spatial-matchup-p3.parquet")

df_full <- arrow::read_parquet(P3_DATA_PATH)
stopifnot(nrow(df_full) > 1e6)
stopifnot(ncol(df_full) >= 25)
cat("Loaded:", nrow(df_full), "rows,", ncol(df_full), "cols\n")

set.seed(0)
df <- df_full %>% dplyr::slice_sample(n = 10000)
df <- rename_era5_cols(df)
df <- assign_5deg_blocks(df)

blocks <- unique(df$block_id)
stopifnot(length(blocks) >= 5)
block_fold <- split_blocks_to_folds(blocks, 5L, DEFAULT_SEED)
df <- df %>% dplyr::left_join(block_fold, by = "block_id")
stopifnot(all(1:5 %in% df$fold))

stopifnot(all(P3_ALL_VARS %in% names(df)))
for (v in P3_ALL_VARS) stopifnot(!any(is.na(df[[v]])))
cat("Schema + no-NaN assertions OK (20 predictors)\n")

test_idx <- split(seq_len(nrow(df)), df$fold)
train_df <- df[-test_idx[[1]], ]
test_df  <- df[ test_idx[[1]], ]

pft <- "class_fraction__phaeocystis"
# All 6 main-script specs must train cleanly here. Adding a failing spec to
# the main run costs ~15 min to surface; a failing smoke costs 5 s.
specs_to_test <- list(
  c("full",          P3_ALL_VARS),
  c("no_spatial",    setdiff(P3_ALL_VARS, P3_SPATIAL_VARS)),
  c("no_local_ice",  setdiff(P3_ALL_VARS, P3_LOCAL_ICE_VARS)),
  c("no_export",     setdiff(P3_ALL_VARS, P3_EXPORT_VARS)),
  c("no_atm",        setdiff(P3_ALL_VARS, P3_ATM_VARS)),
  c("ocean_only",    P3_OCEAN_VARS)
)

for (test in specs_to_test) {
  short <- test[[1]]; vars <- test[-1]
  f <- as.formula(paste(pft, "~", paste(vars, collapse = " + ")))
  t0 <- Sys.time()
  m <- ranger(f, data = train_df, num.trees = 10, seed = DEFAULT_SEED,
              verbose = FALSE, num.threads = ranger_threads())
  pr <- predict(m, data = test_df)$predictions
  r2 <- compute_r2(test_df[[pft]], pr)
  dt <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1)
  stopifnot(!is.na(r2))
  cat(sprintf("  %-14s (%d vars): R² = %+.3f  trained+predicted in %.1fs\n",
              short, length(vars), r2, dt))
}

cat("\nPHASE 3 SMOKE TEST PASSED\n")
