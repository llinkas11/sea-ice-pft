#!/usr/bin/env Rscript
# ALE (Accumulated Local Effects) on Phase 2 Full ranger models.
# Hand-rolled per Apley & Zhu (2020), eqs. 7 & 8. No iml dependency.
#
# Outputs:
#   p2_ale_raw.csv          — per (pft, feature, fold, x bin) ALE values
#   p2_ale_aggregated.csv   — per (pft, feature, x) mean + IQR across folds
#   p2_ale_{pft}.png        — 12-feature grid plot per PFT
#
# Future optimisation (not applied here because the script already runs inside
# budget): batch ranger predictions across features within each fold —
# a single predict() on all 12 × 2 × 20 = 480 stacked query rows instead of
# 480 separate predict() calls would save ~50-70 min on a re-run.

source(file.path(Sys.getenv("RF_PROJECT_ROOT", unset = "."), "R/rf_utils.R"))
setup_rlibs()

suppressPackageStartupMessages({
  library(arrow); library(dplyr); library(ranger); library(ggplot2)
})

SAMPLE_SIZE <- 30000L
N_BINS      <- 20L
set.seed(DEFAULT_SEED)

FULL_VARS <- c("thetao","so","mlotst","qnet_wm2","u10_ms","v10_ms",
               "sithick","siconc","sithick_lag1","siconc_lag1",
               "latitude","longitude")

message("Reading Phase 2 parquet and sampling ", SAMPLE_SIZE, " rows")
df <- arrow::read_parquet(P2_DATA_PATH)
df <- rename_era5_cols(df)
df_sample <- df[sample(nrow(df), SAMPLE_SIZE), ]
message("Sample shape: ", paste(dim(df_sample), collapse = " x "))

n_threads <- ranger_threads()
message("ranger num.threads = ", n_threads)

# ---- ALE implementation (Apley & Zhu 2020) ----
# For feature x_k with K quantile bins z_0 < z_1 < ... < z_K:
#   local_effect_k = mean over rows in bin k of [ f(x with k-th = z_k) - f(x with k-th = z_{k-1}) ]
#   ALE(z_k) = cumsum(local_effects)
#   Center so bin-weighted mean ALE = 0.
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
  data.frame(
    x          = (edges[-1L] + edges[-(K_actual + 1L)]) / 2,
    ale        = ale_uncentered - center,
    bin_count  = bin_counts,
    feature    = feature,
    stringsAsFactors = FALSE
  )
}

ale_all <- data.frame()
t_start <- Sys.time()

for (pft_name in names(PFT_RESPONSES)) {
  message("\n===== ", pft_name, " =====")
  for (this_fold in 1:5) {
    mf <- file.path(P2_MODEL_DIR, paste0(
      "p2_full_", gsub(" ", "_", tolower(pft_name)), "_fold", this_fold, ".rds"
    ))
    if (!file.exists(mf)) stop("Required model file missing: ", mf)
    model <- readRDS(mf)
    t0 <- Sys.time()
    for (feat in FULL_VARS) {
      res <- compute_ale(model, df_sample, feat, K = N_BINS, num.threads = n_threads)
      if (!is.null(res)) {
        res$pft  <- pft_name
        res$fold <- this_fold
        ale_all  <- rbind(ale_all, res)
      }
    }
    message(sprintf("  fold %d: %.2f min (12 features)", this_fold,
                    as.numeric(difftime(Sys.time(), t0, units = "mins"))))
  }
}

total_elapsed <- as.numeric(difftime(Sys.time(), t_start, units = "mins"))
message(sprintf("\nTotal ALE time: %.1f min", total_elapsed))

write.csv(ale_all, file.path(P2_RESULT_DIR, "p2_ale_raw.csv"), row.names = FALSE)
message("Saved raw ALE -> p2_ale_raw.csv (", nrow(ale_all), " rows)")

# Because df_sample is fixed, the quantile-bin grid is identical across folds per feature.
ale_agg <- ale_all %>%
  dplyr::group_by(pft, feature, x) %>%
  dplyr::summarise(
    ale_mean  = mean(ale),
    ale_lo    = as.numeric(quantile(ale, 0.25)),
    ale_hi    = as.numeric(quantile(ale, 0.75)),
    bin_count = round(mean(bin_count)),
    n_folds   = dplyr::n(),
    .groups   = "drop"
  )
write.csv(ale_agg, file.path(P2_RESULT_DIR, "p2_ale_aggregated.csv"), row.names = FALSE)

# Preserve block order (ocean / atm / ice / spatial) in the facet grid
ale_agg$feature <- factor(ale_agg$feature, levels = FULL_VARS)

for (pft_name in names(PFT_RESPONSES)) {
  sub <- ale_agg %>% dplyr::filter(pft == pft_name)
  p <- ggplot(sub, aes(x = x, y = ale_mean)) +
    geom_hline(yintercept = 0, color = "gray70", linetype = "dashed", linewidth = 0.3) +
    geom_ribbon(aes(ymin = ale_lo, ymax = ale_hi),
                fill = "steelblue", alpha = 0.3) +
    geom_line(color = "steelblue", linewidth = 0.8) +
    facet_wrap(~ feature, scales = "free", ncol = 4) +
    labs(
      title    = paste0("ALE plots — ", pft_name, " (Phase 2 Full model, 12 predictors)"),
      subtitle = "Accumulated local effect per feature. Band = IQR (25th–75th percentile) across 5 spatial folds.",
      x        = "Feature value",
      y        = "ALE (centered effect on PFT fraction)"
    ) +
    theme_minimal(base_size = 10) +
    theme(
      strip.text = element_text(face = "bold", size = 10),
      plot.title = element_text(face = "bold"),
      panel.grid.minor = element_blank()
    )
  out <- file.path(P2_RESULT_DIR,
                   paste0("p2_ale_", gsub(" ", "_", tolower(pft_name)), ".png"))
  ggsave(out, p, width = 13, height = 8, dpi = 200, bg = "white")
  message("Saved -> ", out)
}

message("\nDone.")
