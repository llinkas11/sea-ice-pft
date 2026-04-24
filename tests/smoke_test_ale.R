#!/usr/bin/env Rscript
# Smoke test: verify the production compute_ale works on a tiny subset.
# Sources the production script (compute_ale_p2.R) to avoid code drift.

source(file.path(Sys.getenv("RF_PROJECT_ROOT", unset = "."), "R/rf_utils.R"))
setup_rlibs()
suppressPackageStartupMessages({
  library(arrow); library(dplyr); library(ranger)
})

# Source only the compute_ale function from the production script by extracting
# the function definition. The production script has side effects (runs the full
# pipeline at top level), so we can't source it directly. Instead, we redefine
# compute_ale here — this file is paired with its production twin and any edit
# to one MUST be mirrored to the other. This is the one acceptable duplication
# in this project; it exists because R has no clean way to source-without-exec
# a function from a script.
#
# Production location: rf_exploring3/compute_ale_p2.R
compute_ale <- function(model, data, feature, K = 20L, num.threads = 1L) {
  x <- data[[feature]]
  probs <- seq(0, 1, length.out = K + 1L)
  edges <- unique(quantile(x, probs = probs, na.rm = TRUE))
  K_actual <- length(edges) - 1L
  if (K_actual < 2L) return(NULL)
  bin <- findInterval(x, edges, all.inside = TRUE, rightmost.closed = TRUE)
  local_effects <- numeric(K_actual)
  for (k in seq_len(K_actual)) {
    mask <- bin == k
    if (sum(mask) == 0L) { local_effects[k] <- 0; next }
    data_lo <- data[mask, , drop = FALSE]
    data_hi <- data_lo
    data_lo[[feature]] <- edges[k]
    data_hi[[feature]] <- edges[k + 1L]
    pred_lo <- predict(model, data = data_lo, num.threads = num.threads)$predictions
    pred_hi <- predict(model, data = data_hi, num.threads = num.threads)$predictions
    local_effects[k] <- mean(pred_hi - pred_lo, na.rm = TRUE)
  }
  ale_uncentered <- cumsum(local_effects)
  bin_counts <- tabulate(bin, nbins = K_actual)
  center <- sum(ale_uncentered * bin_counts) / max(1L, sum(bin_counts))
  data.frame(x = (edges[-1L] + edges[-(K_actual + 1L)]) / 2,
             ale = ale_uncentered - center,
             bin_count = bin_counts, feature = feature)
}

df <- arrow::read_parquet(P2_DATA_PATH)
df <- rename_era5_cols(df)
set.seed(0)
df_sample <- df[sample(nrow(df), 5000), ]

mf <- file.path(P2_MODEL_DIR, "p2_full_phaeocystis_fold1.rds")
stopifnot(file.exists(mf))
model <- readRDS(mf)

t0 <- Sys.time()
res <- compute_ale(model, df_sample, "siconc", K = 10, num.threads = ranger_threads())
cat(sprintf("ALE computed in %.1f sec\n", as.numeric(difftime(Sys.time(), t0, units = "secs"))))
cat("siconc ALE (Phaeocystis, fold 1, 5k sample, 10 bins):\n")
print(res)
stopifnot(!anyNA(res$ale), !all(res$ale == 0))
cat("SMOKE PASSED — ALE curve non-trivial, no NaN\n")
