#!/usr/bin/env Rscript
# Phase 3 ALE — 20 predictors × 3 PFTs overlaid per panel, facet titles below.

source(file.path(Sys.getenv("RF_PROJECT_ROOT", unset = "."), "R/rf_utils.R"))
setup_rlibs()

suppressPackageStartupMessages({
  library(arrow); library(dplyr); library(ranger); library(ggplot2)
})

set.seed(DEFAULT_SEED)

P3_MODEL_DIR <- file.path(P2_OUT_DIR, "models_p3")
P3_DATA_PATH <- file.path(P2_OUT_DIR, "data_model/final-spatial-matchup-p3.parquet")
dir.create(P3_RESULT_DIR, recursive = TRUE, showWarnings = FALSE)

FULL_VARS <- P3_ALL_VARS

variable_labels <- c(
  thetao                    = "Potential temperature (\u00B0C)",
  so                        = "Salinity (PSU)",
  mlotst                    = "Mixed-layer thickness (m)",
  siconc                    = "Sea-ice concentration (fraction)",
  sithick                   = "Sea-ice thickness (m)",
  siconc_lag1               = "Sea-ice concentration lag-1 (fraction)",
  sithick_lag1              = "Sea-ice thickness lag-1 (m)",
  ice_area_flux_current     = "Ice area flux, current month (km\u00B2/day)",
  ice_area_flux_lag1        = "Ice area flux, lag-1 (km\u00B2/day)",
  ice_area_flux_lag2        = "Ice area flux, lag-2 (km\u00B2/day)",
  ice_area_flux_cumOct      = "Ice area flux, cumulative since Oct (km\u00B2/day)",
  ice_volume_flux_current   = "Ice volume flux, current month (km\u00B3/day)",
  ice_volume_flux_lag1      = "Ice volume flux, lag-1 (km\u00B3/day)",
  ice_volume_flux_lag2      = "Ice volume flux, lag-2 (km\u00B3/day)",
  ice_volume_flux_cumOct    = "Ice volume flux, cumulative since Oct (km\u00B3/day)",
  qnet_wm2                  = "Net surface heat flux (W m\u207B\u00B2)",
  u10_ms                    = "10 m zonal wind (m s\u207B\u00B9)",
  v10_ms                    = "10 m meridional wind (m s\u207B\u00B9)",
  latitude                  = "Latitude (\u00B0N)",
  longitude                 = "Longitude (\u00B0E)"
)

message("Reading Phase 3 parquet: ", P3_DATA_PATH)
df <- arrow::read_parquet(P3_DATA_PATH)
df <- rename_era5_cols(df)
stopifnot(all(FULL_VARS %in% names(df)))

# build_phase3_parquet.py drops NAs on the 8 flux columns only — ocean/ice/atm
# still need a complete-cases filter for well-defined quantile bin edges.
df <- df[complete.cases(df[, FULL_VARS]), ]
df_sample <- if (nrow(df) > ALE_SAMPLE_SIZE) df[sample(nrow(df), ALE_SAMPLE_SIZE), ] else df
message("Sample shape: ", paste(dim(df_sample), collapse = " x "))

n_threads <- ranger_threads()
message("ranger num.threads = ", n_threads)

n_total <- length(PFT_RESPONSES) * 5L * length(FULL_VARS)
ale_chunks <- vector("list", n_total)
idx <- 0L
t_start <- Sys.time()

for (pft_name in names(PFT_RESPONSES)) {
  message("\n===== ", pft_name, " =====")
  for (this_fold in 1:5) {
    mf <- file.path(P3_MODEL_DIR, paste0(
      "p3_full_", gsub(" ", "_", tolower(pft_name)), "_fold", this_fold, ".rds"
    ))
    if (!file.exists(mf)) stop("Required model file missing: ", mf)
    model <- readRDS(mf)
    t0 <- Sys.time()
    for (feat in FULL_VARS) {
      res <- compute_ale(model, df_sample, feat, K = ALE_N_BINS, num.threads = n_threads)
      if (!is.null(res)) {
        res$pft  <- pft_name
        res$fold <- this_fold
        idx <- idx + 1L
        ale_chunks[[idx]] <- res
      }
    }
    message(sprintf("  fold %d: %.2f min (%d features)", this_fold,
                    as.numeric(difftime(Sys.time(), t0, units = "mins")),
                    length(FULL_VARS)))
  }
}

ale_all <- dplyr::bind_rows(ale_chunks[seq_len(idx)])
message(sprintf("\nTotal ALE time: %.1f min",
                as.numeric(difftime(Sys.time(), t_start, units = "mins"))))

write.csv(ale_all, file.path(P3_RESULT_DIR, "p3_ale_raw.csv"), row.names = FALSE)
message("Saved raw ALE -> p3_ale_raw.csv (", nrow(ale_all), " rows)")

# Bin grid is identical across folds because df_sample is fixed.
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
write.csv(ale_agg, file.path(P3_RESULT_DIR, "p3_ale_aggregated.csv"), row.names = FALSE)

# Facet order: ocean → local ice → export → atm → spatial (block order).
ale_agg$feature <- factor(ale_agg$feature, levels = FULL_VARS)
ale_agg$variable_label <- factor(variable_labels[as.character(ale_agg$feature)],
                                 levels = variable_labels[FULL_VARS])
ale_agg$pft <- factor(ale_agg$pft, levels = names(PFT_COLORS))

p <- ggplot(ale_agg, aes(x = x, y = ale_mean, colour = pft)) +
  geom_hline(yintercept = 0, linetype = "dashed", colour = "grey60", linewidth = 0.4) +
  geom_line(linewidth = 0.9) +
  facet_wrap(~ variable_label, scales = "free", ncol = 5, strip.position = "bottom") +
  scale_colour_manual(values = PFT_COLORS, name = "PFT") +
  labs(x = NULL, y = "ALE (centered effect on class fraction)") +
  theme_classic(base_size = 11) +
  theme(
    legend.position = "bottom",
    strip.text = element_text(face = "bold", size = 9),
    strip.background = element_rect(fill = "grey96", colour = NA),
    strip.placement = "outside",
    panel.grid.major.y = element_line(colour = "grey92", linewidth = 0.3)
  )

outpath <- file.path(P2_OUT_DIR, "p3_ale_all_variables.png")
ggsave(outpath, plot = p, width = 16, height = 12, dpi = 320, bg = "white")
message("Saved: ", outpath)
