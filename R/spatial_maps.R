#!/usr/bin/env Rscript
# Supplementary spatial-map figures: per-month climatologies of predictors,
# PFT class fractions, and dominant class. Writes PNGs to figures/spatial/.

source(file.path(Sys.getenv("RF_PROJECT_ROOT", unset = "."), "R/rf_utils.R"))
source(file.path(Sys.getenv("RF_PROJECT_ROOT", unset = "."), "R/plot_utils.R"))
setup_rlibs()

suppressPackageStartupMessages({
  library(arrow); library(dplyr); library(tidyr); library(ggplot2); library(patchwork)
})

data_path <- file.path(rf_data_root(), "final-spatial-matchup-p3.parquet")
out_dir   <- file.path(rf_project_root(), "figures", "spatial")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

df <- arrow::read_parquet(data_path) |> rename_era5_cols()

MONTHS <- 4:8
MONTH_NAMES <- c("April", "May", "June", "July", "August")

# Per-month climatologies
for (i in seq_along(MONTHS)) {
  m <- MONTHS[i]
  nm <- MONTH_NAMES[i]
  mdf <- monthly_mean_by_pixel(
    df, c("siconc", "sithick", "thetao", "so", "mlotst"),
    filter_month = m
  )
  plots <- list(
    siconc  = spatial_tile(mdf, "siconc",  paste("Sea-ice concentration,", nm),
                           fill_name = "siconc", limits = c(0, 1)),
    sithick = spatial_tile(mdf, "sithick", paste("Sea-ice thickness,", nm),
                           fill_name = "sithick (m)", limits = c(0, 5)),
    thetao  = spatial_tile(mdf, "thetao",  paste("Potential temperature,", nm),
                           fill_name = "°C", limits = c(-2, 15)),
    so      = spatial_tile(mdf, "so",      paste("Salinity,", nm),
                           fill_name = "PSU", limits = c(30, 36)),
    mlotst  = spatial_tile(mdf, "mlotst",  paste("Mixed-layer thickness,", nm),
                           fill_name = "m", limits = c(0, 800))
  )
  for (nm_var in names(plots)) {
    ggsave(file.path(out_dir, sprintf("%s_%02d_%s.png", nm_var, m, tolower(nm))),
           plots[[nm_var]], width = 6, height = 5, dpi = 200, bg = "white")
  }
}

# PFT class-fraction maps for June and August
for (m in c(6, 8)) {
  nm <- if (m == 6) "June" else "August"
  pdf_ <- monthly_mean_by_pixel(
    df, c("class_fraction__diatoms",
          "class_fraction__coccolithophores",
          "class_fraction__phaeocystis"),
    filter_month = m
  )
  make <- function(col, title) {
    spatial_tile(pdf_, col, paste(title, "class fraction,", nm),
                 fill_name = "fraction", limits = c(0, 1))
  }
  combo <- make("class_fraction__diatoms",          "Diatoms") /
           make("class_fraction__coccolithophores", "Coccolithophores") /
           make("class_fraction__phaeocystis",      "Phaeocystis")
  ggsave(file.path(out_dir, sprintf("pft_fractions_%02d_%s.png", m, tolower(nm))),
         combo, width = 7, height = 13, dpi = 200, bg = "white")
}

# Monthly PFT fraction climatology (stacked area)
pft_long <- pft_monthly_long(df)
pft_filled <- pft_long |>
  group_by(month) |>
  mutate(total = sum(Fraction, na.rm = TRUE)) |>
  ungroup() |>
  bind_rows(
    pft_long |>
      group_by(month) |>
      summarise(Fraction = max(0, 1 - sum(Fraction, na.rm = TRUE)),
                PFT = "Other", .groups = "drop")
  ) |>
  mutate(PFT = factor(PFT, levels = c("Other", "Coccolithophores", "Diatoms", "Phaeocystis")))

pft_colors_stack <- c(
  "Diatoms"          = "purple",
  "Coccolithophores" = "darkred",
  "Phaeocystis"      = "orange",
  "Other"            = "grey80"
)

p_stack <- ggplot(pft_filled, aes(x = month, y = Fraction, fill = PFT)) +
  geom_bar(stat = "identity") +
  scale_fill_manual(name = "PFT", values = pft_colors_stack) +
  labs(title = "Mean PFT class fractions by month",
       x = "Month", y = "Class fraction") +
  theme_bw()
ggsave(file.path(out_dir, "pft_monthly_stacked.png"),
       p_stack, width = 7, height = 4, dpi = 200, bg = "white")

# Dominant-class maps (one per month) for the latest full year in the parquet
dc_year <- max(df$year, na.rm = TRUE)
dominant_values <- c(
  "ocean"            = "white",
  "diatoms"          = "purple",
  "coccolithophores" = "darkred",
  "phaeocystis"      = "orange"
)
if ("dominant_class" %in% names(df)) {
  for (i in seq_along(MONTHS)) {
    m <- MONTHS[i]; nm <- MONTH_NAMES[i]
    mdf <- df |> filter(year == dc_year, month == m) |>
      select(latitude, longitude, dominant_class)
    if (nrow(mdf) == 0) next
    p <- spatial_tile(mdf, "dominant_class",
                      sprintf("Dominant class, %s %d", nm, dc_year),
                      fill_name = "Dominant class",
                      discrete_values = dominant_values)
    ggsave(file.path(out_dir, sprintf("dominant_%02d_%s_%d.png", m, tolower(nm), dc_year)),
           p, width = 6, height = 5, dpi = 200, bg = "white")
  }
}

message("wrote spatial maps to ", out_dir)
