#!/usr/bin/env Rscript
# Phase 3 held-out prediction per fold; aggregates to 5 deg for obs/pred/residual map.

source(file.path(Sys.getenv("RF_PROJECT_ROOT", unset = "."), "R/rf_utils.R"))
setup_rlibs()
suppressPackageStartupMessages({
  library(arrow); library(dplyr); library(ranger); library(ggplot2); library(tidyr)
})

P3_OUT_DIR    <- rf_out_root()
P3_RESULT_DIR <- file.path(P3_OUT_DIR, "results")
P3_MODEL_DIR  <- file.path(P3_OUT_DIR, "models_p3")

p3_pq <- Sys.glob(file.path(rf_data_root(), "*p3*.parquet"))
if (length(p3_pq) == 0) stop("Could not locate Phase 3 parquet in ", rf_data_root())
message("Using Phase 3 parquet: ", p3_pq[1])
df <- arrow::read_parquet(p3_pq[1])
message("Shape: ", paste(dim(df), collapse = " x "))
message("Columns: ", paste(names(df), collapse = ", "))

# ERA5 rename to match training convention
rename_map <- c(era5_qnet_ocean_loss_wm2 = "qnet_wm2",
                era5_u10_ms = "u10_ms",
                era5_v10_ms = "v10_ms")
for (old in names(rename_map)) {
  new <- rename_map[old]
  if (old %in% names(df) && !(new %in% names(df))) {
    names(df)[names(df) == old] <- new
  }
}

# Reconstruct the same block assignment + fold split the Phase 3 job used
df$block_lat <- floor(df$latitude / 5) * 5
df$block_lon <- floor(df$longitude / 5) * 5
df$block_id  <- paste0(df$block_lat, "_", df$block_lon)
set.seed(42)
unique_blocks <- unique(df$block_id)
block_fold <- data.frame(
  block_id = unique_blocks,
  fold     = sample(rep(1:5, length.out = length(unique_blocks)))
)
df <- df %>% dplyr::left_join(block_fold, by = "block_id")
message("Rows per fold: ", paste(as.integer(table(df$fold)), collapse = ","))

PFT_RESPONSES <- c(
  "Coccolithophores" = "class_fraction__coccolithophores",
  "Diatoms"          = "class_fraction__diatoms",
  "Phaeocystis"      = "class_fraction__phaeocystis"
)

# For each (PFT × fold) load the Phase 3 Full model and predict on its held-out rows
preds_all <- data.frame()

for (pft_name in names(PFT_RESPONSES)) {
  resp <- PFT_RESPONSES[[pft_name]]
  message("\n===== ", pft_name, " =====")
  for (this_fold in 1:5) {
    # Try a few naming patterns for the cached p3 Full model
    candidates <- c(
      file.path(P3_MODEL_DIR, paste0("p3_full_", gsub(" ", "_", tolower(pft_name)), "_fold", this_fold, ".rds")),
      file.path(P3_MODEL_DIR, paste0("full_", gsub(" ", "_", tolower(pft_name)), "_fold", this_fold, ".rds")),
      file.path(P3_OUT_DIR,   "models_p3", paste0("p3_full_", gsub(" ", "_", tolower(pft_name)), "_fold", this_fold, ".rds"))
    )
    mf <- candidates[file.exists(candidates)][1]
    if (is.na(mf)) stop("P3 Full model not found for ", pft_name, " fold ", this_fold,
                        " (tried: ", paste(candidates, collapse = ", "), ")")

    model <- readRDS(mf)
    test_df <- df %>% dplyr::filter(fold == this_fold)
    t0 <- Sys.time()
    p <- predict(model, data = test_df)$predictions
    message(sprintf("  fold %d: predicted %d rows in %.1fs",
                    this_fold, length(p),
                    as.numeric(difftime(Sys.time(), t0, units = "secs"))))

    preds_all <- rbind(preds_all, data.frame(
      pft       = pft_name,
      latitude  = test_df$latitude,
      longitude = test_df$longitude,
      block_lat = test_df$block_lat,
      block_lon = test_df$block_lon,
      year      = test_df$year,
      month     = test_df$month,
      obs       = test_df[[resp]],
      pred      = p,
      fold      = this_fold,
      stringsAsFactors = FALSE
    ))
  }
}

write.csv(preds_all, file.path(P3_RESULT_DIR, "p3_predictions_raw.csv"), row.names = FALSE)
message("\nSaved raw predictions -> p3_predictions_raw.csv (", nrow(preds_all), " rows)")

# ---- Aggregate per 5° block (time-averaged 2003-2018) ----
gridded <- preds_all %>%
  dplyr::group_by(pft, block_lat, block_lon) %>%
  dplyr::summarise(
    n_obs     = dplyr::n(),
    obs_mean  = mean(obs),
    pred_mean = mean(pred),
    residual  = mean(obs - pred),
    .groups   = "drop"
  )
write.csv(gridded, file.path(P3_RESULT_DIR, "p3_predictions_gridded.csv"), row.names = FALSE)
message("Saved gridded predictions -> p3_predictions_gridded.csv")

# ---- Plot: 3 PFT × 3-panel (obs, pred, residual) ----
PFT_COLORS <- c(
  "Coccolithophores" = "Oranges",
  "Diatoms"          = "Blues",
  "Phaeocystis"      = "Greens"
)

# Pivot to long format for faceting
long <- gridded %>%
  dplyr::select(pft, block_lat, block_lon, obs_mean, pred_mean, residual) %>%
  tidyr::pivot_longer(cols = c(obs_mean, pred_mean, residual),
                      names_to = "panel", values_to = "value") %>%
  dplyr::mutate(
    panel = dplyr::case_when(
      panel == "obs_mean"  ~ "Observed",
      panel == "pred_mean" ~ "Predicted (Phase 3 Full, block-CV)",
      panel == "residual"  ~ "Residual (obs − pred)"
    ),
    panel = factor(panel, levels = c("Observed",
                                     "Predicted (Phase 3 Full, block-CV)",
                                     "Residual (obs − pred)"))
  )
long$pft <- factor(long$pft, levels = c("Coccolithophores", "Diatoms", "Phaeocystis"))

p <- ggplot(long, aes(x = block_lon + 2.5, y = block_lat + 2.5, fill = value)) +
  geom_tile(width = 5, height = 5, colour = "grey30", linewidth = 0.2) +
  scale_fill_gradient2(
    low = "#B2182B", mid = "white", high = "#2166AC",
    midpoint = 0, name = NULL
  ) +
  facet_grid(pft ~ panel) +
  coord_fixed(xlim = c(-25, 35), ylim = c(70, 90), expand = FALSE) +
  scale_x_continuous(breaks = seq(-20, 30, 10)) +
  scale_y_continuous(breaks = seq(70, 90, 5)) +
  labs(
    title    = "Phase 3 Full model — time-averaged predictions vs observations (2003–2018)",
    subtitle = "Each tile is a 5° × 5° block; values time-averaged over 2003–2018 on held-out-of-fold predictions. Residual = observed − predicted; red = model overpredicts, blue = model underpredicts.",
    x        = "Longitude (°E)", y = "Latitude (°N)"
  ) +
  theme_minimal(base_size = 11) +
  theme(
    panel.grid.minor = element_blank(),
    panel.grid.major = element_line(colour = "grey92", linewidth = 0.15),
    strip.background = element_rect(fill = "grey95", colour = NA),
    strip.text = element_text(face = "bold"),
    legend.position = "right",
    plot.title = element_text(face = "bold")
  )

ggsave(file.path(P3_RESULT_DIR, "p3_predictions_map.png"), p,
       width = 14, height = 9, dpi = 200, bg = "white")
message("Saved map -> p3_predictions_map.png")
message("\nDone.")
