#!/usr/bin/env Rscript
# Spatial PFT × predictor matchup table preparation.
# Author: Kique Ruiz.

source(file.path(Sys.getenv("RF_PROJECT_ROOT", unset = "."), "R/rf_utils.R"))
setup_rlibs()

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(tidyr)
})

data_path <- file.path(rf_data_root(), "core_monthly_spatial_matchup_table.parquet")
csv_path  <- file.path(rf_out_root(),  "spatial_pfts.csv")

PFT_spatial <- read_parquet(data_path) |>
  mutate(siconc  = if_else(is.na(siconc)  | siconc  < 1e-14, 0, siconc),
         sithick = if_else(is.na(sithick) | sithick < 1e-14, 0, sithick)) |>
  drop_na(thetao, so, mlotst)

dir.create(rf_out_root(), recursive = TRUE, showWarnings = FALSE)
write.csv(PFT_spatial, csv_path, row.names = FALSE)
