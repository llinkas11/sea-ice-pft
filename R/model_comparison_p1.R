#!/usr/bin/env Rscript
# Phase 1: 10 predictors, OOB, NaN rows dropped (not imputed to zero).

source(file.path(Sys.getenv("RF_PROJECT_ROOT", unset = "."), "R/rf_utils.R"))
setup_rlibs()

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(tidyr)
  library(ranger)
  library(ggplot2)
})

out_dir    <- rf_out_root()
model_dir  <- file.path(out_dir, "models_p1")
result_dir <- file.path(out_dir, "results")
data_path  <- file.path(rf_data_root(), "final-spatial-matchup.parquet")

dir.create(model_dir,  recursive = TRUE, showWarnings = FALSE)
dir.create(result_dir, recursive = TRUE, showWarnings = FALSE)

message("Reading parquet: ", data_path)
PFT_spatial <- arrow::read_parquet(data_path)
message("Raw dimensions: ", paste(dim(PFT_spatial), collapse = " x "))

# ---- Rename ERA5 columns to match the downstream predictor names ----
rename_map <- c(
  era5_qnet_ocean_loss_wm2 = "qnet_wm2",
  era5_qnet_downward_wm2   = "qnet_wm2",
  era5_u10_ms              = "u10_ms",
  era5_v10_ms              = "v10_ms"
)
for (old_name in names(rename_map)) {
  new_name <- rename_map[old_name]
  if (old_name %in% names(PFT_spatial) && !new_name %in% names(PFT_spatial)) {
    names(PFT_spatial)[names(PFT_spatial) == old_name] <- new_name
    message("Renamed: ", old_name, " -> ", new_name)
  }
}

# ---- CHANGE vs rf_exploring2: drop the is.na -> 0 imputation ----
# Keep only the numerical-noise cleanup on observed values. NaN rows now
# fall through to drop_na().
n_raw     <- nrow(PFT_spatial)
n_sic_na  <- sum(is.na(PFT_spatial$siconc))
n_sit_na  <- sum(is.na(PFT_spatial$sithick))
message("NaN counts before drop_na: siconc=", n_sic_na, " sithick=", n_sit_na)

PFT_spatial <- PFT_spatial |>
  mutate(siconc  = if_else(!is.na(siconc)  & siconc  < 1e-14, 0, siconc)) |>
  mutate(sithick = if_else(!is.na(sithick) & sithick < 1e-14, 0, sithick)) |>
  drop_na(
    class_fraction__diatoms, class_fraction__phaeocystis,
    class_fraction__coccolithophores,
    thetao, sithick, siconc, so, mlotst,
    latitude, longitude, qnet_wm2, u10_ms, v10_ms
  )

n_filt <- nrow(PFT_spatial)
message("Filtered dimensions: ", paste(dim(PFT_spatial), collapse = " x "))
message(sprintf("Row loss from raw: %d (%.2f%%)", n_raw - n_filt, 100 * (n_raw - n_filt) / n_raw))
stopifnot(sum(is.na(PFT_spatial$siconc))  == 0)
stopifnot(sum(is.na(PFT_spatial$sithick)) == 0)
message("Confirmed: 0 NaNs remain in siconc, sithick after filtering.")

# ---- Model configuration (identical to rf_exploring2) ----
pft_responses <- c(
  "Coccolithophores" = "class_fraction__coccolithophores",
  "Diatoms"          = "class_fraction__diatoms",
  "Phaeocystis"      = "class_fraction__phaeocystis"
)

model_specs <- list(
  list(name = "Full (10 predictors)", short = "full",
    vars = c("thetao","so","mlotst","qnet_wm2","u10_ms","v10_ms","sithick","siconc","latitude","longitude")),
  list(name = "No spatial (8)", short = "no_spatial",
    vars = c("thetao","so","mlotst","qnet_wm2","u10_ms","v10_ms","sithick","siconc")),
  list(name = "No sea ice (8)", short = "no_ice",
    vars = c("thetao","so","mlotst","qnet_wm2","u10_ms","v10_ms","latitude","longitude")),
  list(name = "No atmospheric (7)", short = "no_atm",
    vars = c("thetao","so","mlotst","sithick","siconc","latitude","longitude")),
  list(name = "Ocean only (5)", short = "ocean_only",
    vars = c("thetao","so","mlotst","sithick","siconc"))
)

rf2_baseline_path <- Sys.getenv("RF2_BASELINE_CSV", unset = "")
rf2_baseline <- if (nzchar(rf2_baseline_path) && file.exists(rf2_baseline_path)) {
  read.csv(rf2_baseline_path, stringsAsFactors = FALSE)
} else {
  NULL
}

results <- data.frame(
  pft = character(), model_name = character(), model_short = character(),
  n_predictors = integer(), r_squared = numeric(), oob_mse = numeric(),
  stringsAsFactors = FALSE
)

for (pft_name in names(pft_responses)) {
  resp_col <- pft_responses[[pft_name]]
  message("\n===== ", pft_name, " (", resp_col, ") =====")
  for (spec in model_specs) {
    model_file <- file.path(model_dir, paste0("p1_", spec$short, "_", gsub(" ", "_", tolower(pft_name)), ".rds"))
    if (file.exists(model_file)) {
      message("  Loading cached: ", spec$name)
      model <- readRDS(model_file)
    } else {
      formula_text <- paste(resp_col, "~", paste(spec$vars, collapse = " + "))
      f <- as.formula(formula_text)
      t0 <- Sys.time()
      message("  Training: ", spec$name, " (", length(spec$vars), " predictors)")
      model <- ranger(f, data = PFT_spatial, num.trees = 100,
                      importance = "impurity", seed = 42, verbose = FALSE)
      elapsed <- difftime(Sys.time(), t0, units = "mins")
      message(sprintf("    Trained in %.2f min", as.numeric(elapsed)))
      saveRDS(model, model_file)
    }
    message(sprintf("    R2 = %.4f  OOB MSE = %.6f",
                    model$r.squared, model$prediction.error))
    results <- rbind(results, data.frame(
      pft = pft_name, model_name = spec$name, model_short = spec$short,
      n_predictors = length(spec$vars), r_squared = model$r.squared,
      oob_mse = model$prediction.error, stringsAsFactors = FALSE
    ))
  }
}

# ---- Compute ablation ΔR² within Phase 1, and cross-phase ΔR² vs rf_exploring2 ----
results <- results |>
  group_by(pft) |>
  mutate(
    r2_drop     = r_squared[model_short == "full"] - r_squared,
    r2_drop_pct = round(100 * r2_drop / r_squared[model_short == "full"], 1)
  ) |>
  ungroup()

if (!is.null(rf2_baseline)) {
  results <- results |>
    left_join(
      rf2_baseline |> select(pft, model_short, rf2_r2 = r_squared, rf2_oob_mse = oob_mse),
      by = c("pft", "model_short")
    ) |>
    mutate(
      delta_r2_vs_rf2   = r_squared - rf2_r2,
      delta_mse_vs_rf2  = oob_mse - rf2_oob_mse
    )
}

write.csv(results, file.path(result_dir, "p1_nan_fix_results.csv"), row.names = FALSE)

message("\n===== Phase 1 results =====")
print(results |> select(pft, model_short, n_predictors,
                        r_squared, rf2_r2, delta_r2_vs_rf2,
                        oob_mse, rf2_oob_mse))

message(sprintf("\nFinal training set: %d rows (vs %d in rf_exploring2, diff = %d)",
                n_filt, 3417067, n_filt - 3417067))
message("\nDone. Results: ", file.path(result_dir, "p1_nan_fix_results.csv"))
