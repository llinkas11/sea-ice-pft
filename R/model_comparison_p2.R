#!/usr/bin/env Rscript
# Phase 2: 12 predictors (adds siconc_lag1, sithick_lag1), 5 deg spatial block CV, May-Aug.

source(file.path(Sys.getenv("RF_PROJECT_ROOT", unset = "."), "R/rf_utils.R"))
setup_rlibs()

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(ranger)
})

out_dir    <- rf_out_root()
model_dir  <- file.path(out_dir, "models_p2")
result_dir <- file.path(out_dir, "results")
data_path  <- file.path(rf_data_root(), "final-spatial-matchup-p2.parquet")

dir.create(model_dir,  recursive = TRUE, showWarnings = FALSE)
dir.create(result_dir, recursive = TRUE, showWarnings = FALSE)

message("Reading Phase 2 parquet: ", data_path)
df <- arrow::read_parquet(data_path)
message("Dimensions: ", paste(dim(df), collapse = " x "))

# Rename ERA5 cols to match Phase 1 convention
rename_map <- c(
  era5_qnet_ocean_loss_wm2 = "qnet_wm2",
  era5_u10_ms              = "u10_ms",
  era5_v10_ms              = "v10_ms"
)
for (old in names(rename_map)) {
  new <- rename_map[old]
  if (old %in% names(df) && !(new %in% names(df))) {
    names(df)[names(df) == old] <- new
    message("Renamed: ", old, " -> ", new)
  }
}

# ---- Spatial block assignment ----
df$block_lat <- floor(df$latitude  / 5) * 5
df$block_lon <- floor(df$longitude / 5) * 5
df$block_id  <- paste0(df$block_lat, "_", df$block_lon)
unique_blocks <- unique(df$block_id)
message("Unique 5° blocks: ", length(unique_blocks))

set.seed(42)
block_fold <- data.frame(
  block_id = unique_blocks,
  fold     = sample(rep(1:5, length.out = length(unique_blocks)))
)
df <- df %>% dplyr::left_join(block_fold, by = "block_id")

rows_per_fold <- as.integer(table(df$fold))
message("Rows per fold: ", paste(rows_per_fold, collapse = ", "))

# ---- Model configuration ----
pft_responses <- c(
  "Coccolithophores" = "class_fraction__coccolithophores",
  "Diatoms"          = "class_fraction__diatoms",
  "Phaeocystis"      = "class_fraction__phaeocystis"
)

model_specs <- list(
  list(name = "Full (12 predictors)", short = "full",
    vars = c("thetao","so","mlotst","qnet_wm2","u10_ms","v10_ms",
             "sithick","siconc","sithick_lag1","siconc_lag1",
             "latitude","longitude")),
  list(name = "No spatial (10)", short = "no_spatial",
    vars = c("thetao","so","mlotst","qnet_wm2","u10_ms","v10_ms",
             "sithick","siconc","sithick_lag1","siconc_lag1")),
  list(name = "No sea ice (8)", short = "no_ice",
    vars = c("thetao","so","mlotst","qnet_wm2","u10_ms","v10_ms",
             "latitude","longitude")),
  list(name = "No atmospheric (9)", short = "no_atm",
    vars = c("thetao","so","mlotst",
             "sithick","siconc","sithick_lag1","siconc_lag1",
             "latitude","longitude")),
  list(name = "Ocean only (7)", short = "ocean_only",
    vars = c("thetao","so","mlotst",
             "sithick","siconc","sithick_lag1","siconc_lag1"))
)

# ---- Train and evaluate across folds ----
results    <- data.frame()
fold_detail <- data.frame()

for (pft_name in names(pft_responses)) {
  resp <- pft_responses[[pft_name]]
  message("\n===== ", pft_name, " (", resp, ") =====")

  for (spec in model_specs) {
    message("  Spec: ", spec$name)
    fold_r2  <- numeric(5)
    fold_mse <- numeric(5)

    for (fold in 1:5) {
      model_file <- file.path(model_dir, paste0(
        "p2_", spec$short, "_", gsub(" ", "_", tolower(pft_name)),
        "_fold", fold, ".rds"
      ))

      train_df <- df %>% dplyr::filter(fold != !!fold)
      test_df  <- df %>% dplyr::filter(fold == !!fold)

      if (file.exists(model_file)) {
        model <- readRDS(model_file)
      } else {
        f <- as.formula(paste(resp, "~", paste(spec$vars, collapse = " + ")))
        t0 <- Sys.time()
        model <- ranger(f, data = train_df, num.trees = 100,
                        importance = "impurity", seed = 42, verbose = FALSE)
        elapsed_min <- as.numeric(difftime(Sys.time(), t0, units = "mins"))
        message(sprintf("    fold %d trained in %.2f min", fold, elapsed_min))
        saveRDS(model, model_file)
      }

      preds  <- predict(model, data = test_df)$predictions
      y_true <- test_df[[resp]]
      ss_res <- sum((y_true - preds)^2)
      ss_tot <- sum((y_true - mean(y_true))^2)
      fold_r2[fold]  <- 1 - ss_res / ss_tot
      fold_mse[fold] <- mean((y_true - preds)^2)

      fold_detail <- rbind(fold_detail, data.frame(
        pft          = pft_name,
        model_short  = spec$short,
        fold         = fold,
        n_train      = nrow(train_df),
        n_test       = nrow(test_df),
        r2_fold      = fold_r2[fold],
        mse_fold     = fold_mse[fold],
        stringsAsFactors = FALSE
      ))

      message(sprintf("    fold %d: R2 = %.4f  MSE = %.6f  (n_train=%d, n_test=%d)",
                      fold, fold_r2[fold], fold_mse[fold],
                      nrow(train_df), nrow(test_df)))
    }

    results <- rbind(results, data.frame(
      pft          = pft_name,
      model_name   = spec$name,
      model_short  = spec$short,
      n_predictors = length(spec$vars),
      r2_mean      = mean(fold_r2),
      r2_sd        = sd(fold_r2),
      mse_mean     = mean(fold_mse),
      mse_sd       = sd(fold_mse),
      stringsAsFactors = FALSE
    ))

    message(sprintf("  MEAN R2 = %.4f  (sd %.4f)   MEAN MSE = %.6f",
                    mean(fold_r2), sd(fold_r2), mean(fold_mse)))
  }
}

# ---- Compute drop-from-Full per PFT, similar to Phase 1 convention ----
results <- results %>%
  group_by(pft) %>%
  mutate(
    r2_drop     = r2_mean[model_short == "full"] - r2_mean,
    r2_drop_pct = round(100 * r2_drop / r2_mean[model_short == "full"], 1)
  ) %>%
  ungroup()

# ---- Optional: side-by-side with Phase 1 ----
p1_path <- file.path(result_dir, "p1_nan_fix_results.csv")
if (file.exists(p1_path)) {
  p1 <- read.csv(p1_path, stringsAsFactors = FALSE)
  results <- results %>%
    dplyr::left_join(
      p1 %>% dplyr::select(pft, model_short, p1_r2 = r_squared, p1_oob_mse = oob_mse),
      by = c("pft", "model_short")
    ) %>%
    mutate(
      delta_r2_vs_p1  = r2_mean - p1_r2,
      delta_mse_vs_p1 = mse_mean - p1_oob_mse
    )
}

write.csv(results,    file.path(result_dir, "p2_block_cv_results.csv"),     row.names = FALSE)
write.csv(fold_detail, file.path(result_dir, "p2_block_cv_fold_detail.csv"), row.names = FALSE)

message("\n===== Phase 2 results =====")
print(results)

message("\nDone. Main results: ", file.path(result_dir, "p2_block_cv_results.csv"))
message("Per-fold detail:    ", file.path(result_dir, "p2_block_cv_fold_detail.csv"))
