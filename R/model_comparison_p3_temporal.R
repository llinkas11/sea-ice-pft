#!/usr/bin/env Rscript
# =============================================================================
# Phase 3 — leave-one-year-out temporal CV
#
# Complementary to model_comparison_p3.R (spatial 5°-block CV). Motivation:
# spatial block CV is structurally favorable to spatially-constant temporal
# predictors (e.g. basin-scale ice flux is identical across all held-out grid
# cells in a given month, so the model has already seen the same value during
# training in other regions). Local ice cover, being spatially varying, has no
# such advantage. Running the same ablation under leave-one-year-out temporal
# CV holds out flux too (a held-out year's flux time series is unseen during
# training) and provides an orthogonal test of the flux effect.
#
# CV design: 22 folds (one per year, 2003-2024). Each fold holds out all
# May-August observations from one year; trains on the other 21 years.
#
# Spec set: same 6 as spatial-block Phase 3 + 2 isolation specs ("Export
# only" and "Local ice only") that directly compare flux vs local cover as
# predictors in the absence of other variables. 8 specs × 22 folds × 3 PFTs.
#
# num.trees = 100, seed = 42 — matches spatial-block P3 so R² values are
# directly comparable across CV schemes.
# =============================================================================

source(file.path(Sys.getenv("RF_PROJECT_ROOT", unset = "."), "R/rf_utils.R"))
setup_rlibs()

suppressPackageStartupMessages({
  library(arrow); library(dplyr); library(ranger)
})

P3_DATA_PATH      <- file.path(P2_OUT_DIR, "data_model/final-spatial-matchup-p3.parquet")
P3_TEMPORAL_DIR   <- file.path(P2_OUT_DIR, "models_p3_temporal")
dir.create(P3_TEMPORAL_DIR, recursive = TRUE, showWarnings = FALSE)

pft_filter <- Sys.getenv("P3_PFT_FILTER", unset = "")
pft_responses_active <- if (nzchar(pft_filter)) {
  if (!(pft_filter %in% names(PFT_RESPONSES))) {
    stop("P3_PFT_FILTER='", pft_filter, "' not in PFT_RESPONSES: ",
         paste(names(PFT_RESPONSES), collapse = ", "))
  }
  message("PFT filter active: ", pft_filter)
  PFT_RESPONSES[pft_filter]
} else {
  PFT_RESPONSES
}
pft_suffix <- if (nzchar(pft_filter)) paste0("_", tolower(pft_filter)) else ""

message("Reading Phase 3 parquet: ", P3_DATA_PATH)
df <- arrow::read_parquet(P3_DATA_PATH)
message("Dimensions: ", paste(dim(df), collapse = " x "))

df <- rename_era5_cols(df)

# Year-based fold index. No spatial block split, no seed-shuffle —
# the natural year ordering IS the fold identity.
years <- sort(unique(df$year))
df$fold <- match(df$year, years)
n_folds <- length(years)
message(sprintf("Temporal CV: %d year-folds (%d..%d)",
                n_folds, min(years), max(years)))

test_idx <- split(seq_len(nrow(df)), df$fold)
fold_sizes <- sapply(test_idx, length)
message(sprintf("  fold sizes: min=%d  median=%d  max=%d  total=%d",
                min(fold_sizes), as.integer(median(fold_sizes)),
                max(fold_sizes), sum(fold_sizes)))

stopifnot(all(P3_ALL_VARS %in% names(df)))

# 6 original spatial-block specs + 2 new isolation specs.
model_specs <- list(
  list(name = "Full (20 predictors)", short = "full",
       vars = P3_ALL_VARS),
  list(name = "No spatial (18)", short = "no_spatial",
       vars = setdiff(P3_ALL_VARS, P3_SPATIAL_VARS)),
  list(name = "No local ice (16)", short = "no_local_ice",
       vars = setdiff(P3_ALL_VARS, P3_LOCAL_ICE_VARS)),
  list(name = "No export (12)", short = "no_export",
       vars = setdiff(P3_ALL_VARS, P3_EXPORT_VARS)),
  list(name = "No atmospheric (17)", short = "no_atm",
       vars = setdiff(P3_ALL_VARS, P3_ATM_VARS)),
  list(name = "Ocean only (3)", short = "ocean_only",
       vars = P3_OCEAN_VARS),
  # New isolation specs — the head-to-head flux-vs-local-ice test.
  list(name = "Export only (8)", short = "export_only",
       vars = P3_EXPORT_VARS),
  list(name = "Local ice only (4)", short = "local_ice_only",
       vars = P3_LOCAL_ICE_VARS)
)
stopifnot(identical(sapply(model_specs, function(s) length(s$vars)),
                    c(20L, 18L, 16L, 12L, 17L, 3L, 8L, 4L)))

out <- run_block_cv_ablation(
  df            = df,
  test_idx      = test_idx,
  specs         = model_specs,
  pft_responses = pft_responses_active,
  model_dir     = P3_TEMPORAL_DIR,
  model_prefix  = "p3t",
  num_trees     = RANGER_NUM_TREES
)
results     <- out$results
fold_detail <- out$fold_detail

# Attach the actual calendar year to each fold row for readability
fold_to_year <- data.frame(fold = seq_along(years), year = years)
fold_detail  <- dplyr::left_join(fold_detail, fold_to_year, by = "fold")

results <- results %>%
  dplyr::group_by(pft) %>%
  dplyr::mutate(
    r2_drop     = r2_mean[model_short == "full"] - r2_mean,
    r2_drop_pct = round(100 * r2_drop / r2_mean[model_short == "full"], 1)
  ) %>%
  dplyr::ungroup()

# Paired t-test per (pft, spec) against Full, across the 22 year folds.
# Nadeau-Bengio isn't applicable — disjoint-year folds share no training
# observations, so variance isn't inflated by train-overlap. Vanilla paired
# t-test is correct. df = 21 for 22 folds.
sig_rows <- list()
for (pft_name in unique(fold_detail$pft)) {
  fd <- fold_detail[fold_detail$pft == pft_name, ]
  full_r2 <- fd$r2_fold[fd$model_short == "full"]
  for (s in unique(fd$model_short)) {
    if (s == "full") next
    spec_r2 <- fd$r2_fold[fd$model_short == s]
    if (length(spec_r2) != length(full_r2)) next
    tt <- tryCatch(t.test(full_r2, spec_r2, paired = TRUE),
                   error = function(e) NULL)
    if (is.null(tt)) next
    sig_rows[[length(sig_rows) + 1L]] <- data.frame(
      pft = pft_name, model_short = s,
      drop_mean = mean(full_r2 - spec_r2),
      t_stat = unname(tt$statistic), df = unname(tt$parameter),
      p_value = tt$p.value, stringsAsFactors = FALSE
    )
  }
}
sig_df <- do.call(rbind, sig_rows)
results <- dplyr::left_join(results, sig_df, by = c("pft", "model_short"))

# Head-to-head isolation comparison: paired t-test on fold-level R² of
# "export_only" vs "local_ice_only". Reports direct flux-vs-local-ice
# difference in isolation (no other predictors confounding).
iso_rows <- list()
for (pft_name in unique(fold_detail$pft)) {
  fd <- fold_detail[fold_detail$pft == pft_name, ]
  exp_r2 <- fd$r2_fold[fd$model_short == "export_only"]
  loc_r2 <- fd$r2_fold[fd$model_short == "local_ice_only"]
  if (length(exp_r2) == length(loc_r2) && length(exp_r2) > 1L) {
    tt <- t.test(exp_r2, loc_r2, paired = TRUE)
    iso_rows[[length(iso_rows) + 1L]] <- data.frame(
      pft          = pft_name,
      export_r2    = mean(exp_r2),
      local_ice_r2 = mean(loc_r2),
      diff_mean    = mean(exp_r2 - loc_r2),
      t_stat       = unname(tt$statistic),
      df           = unname(tt$parameter),
      p_value      = tt$p.value,
      stringsAsFactors = FALSE
    )
  }
}
iso_df <- do.call(rbind, iso_rows)

results_path <- file.path(P2_RESULT_DIR,
                          paste0("p3_temporal_cv_results", pft_suffix, ".csv"))
fold_path    <- file.path(P2_RESULT_DIR,
                          paste0("p3_temporal_cv_fold_detail", pft_suffix, ".csv"))
iso_path     <- file.path(P2_RESULT_DIR,
                          paste0("p3_temporal_cv_isolation", pft_suffix, ".csv"))
write.csv(results,     results_path, row.names = FALSE)
write.csv(fold_detail, fold_path,    row.names = FALSE)
if (!is.null(iso_df)) write.csv(iso_df, iso_path, row.names = FALSE)

message("\n===== Phase 3 leave-one-year-out results",
        if (nzchar(pft_filter)) paste0(" (", pft_filter, " only)") else "", " =====")
print(results %>% dplyr::select(pft, model_short, n_predictors,
                                r2_mean, r2_sd, r2_drop, p_value))
if (!is.null(iso_df)) {
  message("\n===== Head-to-head: export-only vs local-ice-only =====")
  print(iso_df)
}
message("\nResults: ", results_path)
message("Fold detail: ", fold_path)
if (!is.null(iso_df)) message("Isolation head-to-head: ", iso_path)
