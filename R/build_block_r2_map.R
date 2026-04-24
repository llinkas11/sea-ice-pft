#!/usr/bin/env Rscript
# Phase 2 per-block R² map — geographic diagnostic of where the RF works.

source(file.path(Sys.getenv("RF_PROJECT_ROOT", unset = "."), "R/rf_utils.R"))
setup_rlibs()

suppressPackageStartupMessages({
  library(arrow); library(dplyr); library(ranger); library(ggplot2)
})

message("Reading Phase 2 parquet")
df <- arrow::read_parquet(P2_DATA_PATH)
df <- rename_era5_cols(df)
df <- assign_5deg_blocks(df)

block_fold <- split_blocks_to_folds(unique(df$block_id), n_folds = 5L, seed = DEFAULT_SEED)
df <- df %>% dplyr::left_join(block_fold, by = "block_id")
assert_fold_determinism(df)
message("Fold determinism verified")

test_idx <- split(seq_len(nrow(df)), df$fold)

block_r2_acc <- list()
for (this_fold in 1:5) {
  test_df <- df[test_idx[[this_fold]], ]
  message(sprintf("\n===== Fold %d (n=%d) =====", this_fold, nrow(test_df)))

  for (pft_name in names(PFT_RESPONSES)) {
    resp <- PFT_RESPONSES[[pft_name]]
    mp <- model_cache_path("full", pft_name, this_fold)
    if (!file.exists(mp)) stop("Required model file missing: ", mp)
    model <- readRDS(mp)
    t0 <- Sys.time()
    preds <- predict(model, data = test_df)$predictions
    message(sprintf("  %-17s predicted in %.1fs", pft_name,
                    as.numeric(difftime(Sys.time(), t0, units = "secs"))))

    y_col <- test_df[[resp]]
    block_agg <- data.frame(
      block_id  = test_df$block_id,
      block_lat = test_df$block_lat,
      block_lon = test_df$block_lon,
      y         = y_col,
      pred      = preds,
      stringsAsFactors = FALSE
    ) %>%
      dplyr::group_by(block_id, block_lat, block_lon) %>%
      dplyr::summarise(
        n_pixels = dplyr::n(),
        r2       = compute_r2(y, pred),
        mse      = mean((y - pred)^2),
        .groups  = "drop"
      ) %>%
      dplyr::mutate(pft = pft_name, fold = this_fold)

    block_r2_acc[[length(block_r2_acc) + 1]] <- block_agg
  }
}

block_r2 <- do.call(rbind, block_r2_acc)
write.csv(block_r2, file.path(P2_RESULT_DIR, "p2_block_r2.csv"), row.names = FALSE)
message("\nSaved per-block R² -> p2_block_r2.csv (", nrow(block_r2), " rows)")

summary_df <- block_r2 %>% dplyr::group_by(pft) %>%
  dplyr::summarise(
    n_blocks         = dplyr::n(),
    r2_min           = round(min(r2, na.rm = TRUE), 3),
    r2_med           = round(median(r2, na.rm = TRUE), 3),
    r2_max           = round(max(r2, na.rm = TRUE), 3),
    r2_mean          = round(mean(r2, na.rm = TRUE), 3),
    frac_r2_positive = round(mean(r2 > 0, na.rm = TRUE), 3)
  )
message("\nPer-block R² summary by PFT:")
print(summary_df)

block_r2$pft <- factor(block_r2$pft,
                      levels = c("Coccolithophores", "Diatoms", "Phaeocystis"))
block_r2$r2_display <- pmax(pmin(block_r2$r2, 0.7), -0.5)

p <- ggplot(block_r2,
            aes(x = block_lon + 2.5, y = block_lat + 2.5, fill = r2_display)) +
  geom_tile(width = 5, height = 5, colour = "grey30", linewidth = 0.2) +
  scale_fill_gradient2(
    low = "#B2182B", mid = "white", high = "#2166AC",
    midpoint = 0, limits = c(-0.5, 0.7),
    breaks = c(-0.4, -0.2, 0, 0.2, 0.4, 0.6),
    name = expression(Block~R^2)
  ) +
  facet_wrap(~ pft, ncol = 3) +
  coord_fixed(xlim = c(-25, 35), ylim = c(70, 90), expand = FALSE) +
  scale_x_continuous(breaks = seq(-20, 30, 10)) +
  scale_y_continuous(breaks = seq(70, 90, 5)) +
  labs(
    title = expression(Phase~2~block-CV~R^2~per~5*degree~block~"("*Full~model*")"),
    subtitle = "Red = RF fails in this block (R² ≤ 0); blue = RF explains variance (R² > 0.25)",
    x = "Longitude (°E)", y = "Latitude (°N)"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    panel.grid.minor = element_blank(),
    panel.grid.major = element_line(colour = "grey90", linewidth = 0.2),
    strip.background = element_rect(fill = "grey95", colour = NA),
    strip.text = element_text(face = "bold"),
    legend.position = "right",
    plot.title = element_text(face = "bold")
  )

ggsave(file.path(P2_RESULT_DIR, "p2_block_r2_map.png"), p,
       width = 13, height = 5, dpi = 300, bg = "white")
message("\nSaved map -> p2_block_r2_map.png")
