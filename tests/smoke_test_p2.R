#!/usr/bin/env Rscript
# P2 smoke: load + rename + block split + one 10-tree ranger fit on 10k rows (~30s).

source(file.path(Sys.getenv("RF_PROJECT_ROOT", unset = "."), "R/rf_utils.R"))
setup_rlibs()
suppressPackageStartupMessages({
  library(arrow); library(dplyr); library(ranger)
})

data_path <- file.path(rf_data_root(), "final-spatial-matchup-p2.parquet")

# ---- Load + subsample ----
df_full <- arrow::read_parquet(data_path)
cat("Loaded:", nrow(df_full), "rows,", ncol(df_full), "cols\n")
stopifnot(nrow(df_full) > 1e6)

set.seed(0)
df <- df_full %>% dplyr::slice_sample(n = 10000)
cat("Subsample:", nrow(df), "rows\n")

# ---- Rename ----
rename_map <- c(era5_qnet_ocean_loss_wm2 = "qnet_wm2",
                era5_u10_ms = "u10_ms", era5_v10_ms = "v10_ms")
for (old in names(rename_map)) {
  new <- rename_map[old]
  if (old %in% names(df)) names(df)[names(df) == old] <- new
}
stopifnot("qnet_wm2" %in% names(df), "u10_ms" %in% names(df), "v10_ms" %in% names(df))
cat("Rename OK\n")

# ---- NaN check on all predictors ----
preds <- c("thetao","so","mlotst","qnet_wm2","u10_ms","v10_ms",
           "sithick","siconc","sithick_lag1","siconc_lag1",
           "latitude","longitude")
targets <- c("class_fraction__phaeocystis","class_fraction__diatoms",
             "class_fraction__coccolithophores")
n_na <- sapply(df[, c(preds, targets)], function(x) sum(is.na(x)))
cat("NaN count per col (expect all 0):\n")
print(n_na)
stopifnot(all(n_na == 0))

# ---- Block assignment ----
df$block_lat <- floor(df$latitude / 5) * 5
df$block_lon <- floor(df$longitude / 5) * 5
df$block_id  <- paste0(df$block_lat, "_", df$block_lon)
blocks <- unique(df$block_id)
cat("Unique blocks in subsample:", length(blocks), "\n")
stopifnot(length(blocks) >= 5)  # need ≥5 blocks for 5-fold CV

# ---- Fold assignment ----
set.seed(42)
block_fold <- data.frame(
  block_id = blocks,
  fold     = sample(rep(1:5, length.out = length(blocks)))
)
df <- df %>% dplyr::left_join(block_fold, by = "block_id")
cat("Rows per fold:\n"); print(table(df$fold))
stopifnot(all(1:5 %in% df$fold))

# ---- One ranger fit (fold 1 held out, Full model, 10 trees) ----
this_fold <- 1L
train_df <- df %>% dplyr::filter(fold != !!this_fold)
test_df  <- df %>% dplyr::filter(fold == !!this_fold)
cat("Train:", nrow(train_df), "Test:", nrow(test_df), "\n")
stopifnot(nrow(train_df) > 0, nrow(test_df) > 0)

f <- as.formula(paste("class_fraction__phaeocystis ~", paste(preds, collapse = " + ")))
t0 <- Sys.time()
model <- ranger(f, data = train_df, num.trees = 10, seed = 42, verbose = FALSE)
cat("Trained in", round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1), "s\n")

# ---- Predict and compute R² on held-out fold ----
preds_out <- predict(model, data = test_df)$predictions
y         <- test_df$class_fraction__phaeocystis
ss_res    <- sum((y - preds_out)^2)
ss_tot    <- sum((y - mean(y))^2)
r2_smoke  <- 1 - ss_res / ss_tot
cat(sprintf("Fold-1 smoke R² = %.4f  (10 trees on 10k sample — noisy; just a sanity check)\n", r2_smoke))

# ---- Verify tidyeval fold filter isn't silently wrong ----
stopifnot(!any(train_df$fold == this_fold))
stopifnot(all(test_df$fold == this_fold))
cat("tidyeval fold filter OK\n")

cat("\nSMOKE TEST PASSED — Phase 2 R script is safe to submit\n")
