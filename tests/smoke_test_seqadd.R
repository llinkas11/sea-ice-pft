#!/usr/bin/env Rscript
# Smoke test for the seqadd script — same pattern as smoke_test_p2.R but with
# the ocean-3 predictor set. Should finish in ~5 s.

source(file.path(Sys.getenv("RF_PROJECT_ROOT", unset = "."), "R/rf_utils.R"))
setup_rlibs()

suppressPackageStartupMessages({
  library(arrow); library(dplyr); library(ranger)
})

df_full <- arrow::read_parquet(P2_DATA_PATH)
stopifnot(nrow(df_full) > 1e6)

set.seed(0)
df <- df_full %>% dplyr::slice_sample(n = 10000)
df <- rename_era5_cols(df)
df <- assign_5deg_blocks(df)

blocks <- unique(df$block_id)
stopifnot(length(blocks) >= 5)
block_fold <- split_blocks_to_folds(blocks, 5L, DEFAULT_SEED)
df <- df %>% dplyr::left_join(block_fold, by = "block_id")
stopifnot(all(1:5 %in% df$fold))

preds_ocean3 <- c("thetao", "so", "mlotst")
stopifnot(all(preds_ocean3 %in% names(df)))
for (c in c("class_fraction__phaeocystis", preds_ocean3)) {
  stopifnot(!any(is.na(df[[c]])))
}
cat("Schema + no-NaN assertions OK\n")

test_idx <- split(seq_len(nrow(df)), df$fold)
train_df <- df[-test_idx[[1]], ]
test_df  <- df[ test_idx[[1]], ]

f <- as.formula(paste("class_fraction__phaeocystis ~",
                      paste(preds_ocean3, collapse = " + ")))
t0 <- Sys.time()
model <- ranger(f, data = train_df, num.trees = 10, seed = DEFAULT_SEED,
                verbose = FALSE, num.threads = ranger_threads())
cat("Trained in", round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1), "s\n")

preds <- predict(model, data = test_df)$predictions
r2 <- compute_r2(test_df$class_fraction__phaeocystis, preds)
cat(sprintf("Fold-1 smoke R² (ocean-3, 10 trees, 10k sample) = %.4f\n", r2))
stopifnot(!is.na(r2))
cat("SEQADD SMOKE TEST PASSED\n")
