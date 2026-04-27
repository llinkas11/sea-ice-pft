#!/usr/bin/env Rscript
# Supplementary spatial random-forest using chlorophyll and sediment-fraction predictors.
# Author: Kique Ruiz.

source(file.path(Sys.getenv("RF_PROJECT_ROOT", unset = "."), "R/rf_utils.R"))
setup_rlibs()

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(tidyr)
  library(ranger)
  library(ggplot2)
})

data_path <- file.path(rf_data_root(), "core_monthly_spatial_matchup_table.parquet")
csv_path  <- file.path(rf_out_root(),  "spatial_pfts.csv")

PFT_spatial <- read_parquet(data_path) |>
  mutate(siconc  = if_else(is.na(siconc)  | siconc  < 1e-14, 0, siconc),
         sithick = if_else(is.na(sithick) | sithick < 1e-14, 0, sithick)) |>
  drop_na(thetao, so, mlotst)

dir.create(rf_out_root(), recursive = TRUE, showWarnings = FALSE)
write.csv(PFT_spatial, csv_path, row.names = FALSE)

predictors <- c("chlorophyll_mean", "thetao", "sithick", "siconc",
                "so", "mlotst", "latitude", "longitude",
                "class_fraction__sediment")

fit_pft_rf <- function(response, label, slug) {
  fml <- reformulate(predictors, response = response)
  m <- ranger(fml, data = PFT_spatial, num.trees = 100,
              importance = "impurity", seed = DEFAULT_SEED, verbose = FALSE)
  imp <- tibble(variable   = names(m$variable.importance),
                importance = as.numeric(m$variable.importance))
  p <- ggplot(imp, aes(x = importance, y = reorder(variable, importance))) +
    geom_col(fill = "steelblue") +
    labs(title = paste0("Variable importance: ", label),
         x = "Impurity importance", y = NULL) +
    theme_minimal(base_size = 11)
  out <- file.path(rf_out_root(), sprintf("spatial_varimp_%s.png", slug))
  ggsave(out, p, width = 7, height = 5, dpi = 150, bg = "white")
  message("Saved -> ", out)
  m
}

model_diatoms <- fit_pft_rf("class_fraction__diatoms",          "Diatoms",          "diatoms")
model_coco    <- fit_pft_rf("class_fraction__coccolithophores", "Coccolithophores", "coccolithophores")
model_phaeo   <- fit_pft_rf("class_fraction__phaeocystis",      "Phaeocystis",      "phaeocystis")
