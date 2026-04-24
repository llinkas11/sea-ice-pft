#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
  library(maps)
})

MAP_WORLD <- map_data("world")
DEFAULT_XLIM <- c(-25, 35)
DEFAULT_YLIM <- c(70, 85)

spatial_tile <- function(data, fill, title, fill_name = NULL,
                         limits = NULL, palette = "plasma",
                         xlim = DEFAULT_XLIM, ylim = DEFAULT_YLIM,
                         discrete_values = NULL) {
  p <- ggplot() +
    geom_tile(data = data,
              aes(x = longitude, y = latitude, fill = .data[[fill]]))
  if (!is.null(discrete_values)) {
    p <- p + scale_fill_manual(name = fill_name %||% fill,
                               values = discrete_values, na.value = "grey95")
  } else {
    p <- p + scale_fill_viridis_c(name = fill_name %||% fill,
                                   option = palette, limits = limits)
  }
  p +
    geom_polygon(data = MAP_WORLD,
                 aes(x = long, y = lat, group = group),
                 fill = "grey80", colour = "black", linewidth = 0.2) +
    coord_fixed() +
    xlim(xlim) + ylim(ylim) +
    labs(title = title, x = "Longitude", y = "Latitude") +
    theme_bw()
}

`%||%` <- function(a, b) if (is.null(a)) b else a

monthly_mean_by_pixel <- function(df, vars, filter_month = NULL) {
  if (!is.null(filter_month)) df <- df |> filter(month == filter_month)
  df |>
    group_by(latitude, longitude) |>
    summarise(across(all_of(vars), \(x) mean(x, na.rm = TRUE)), .groups = "drop")
}

pft_monthly_long <- function(df) {
  df |>
    group_by(month) |>
    summarise(
      Diatoms          = mean(class_fraction__diatoms,          na.rm = TRUE),
      Coccolithophores = mean(class_fraction__coccolithophores, na.rm = TRUE),
      Phaeocystis      = mean(class_fraction__phaeocystis,      na.rm = TRUE),
      .groups = "drop"
    ) |>
    tidyr::pivot_longer(-month, names_to = "PFT", values_to = "Fraction")
}
