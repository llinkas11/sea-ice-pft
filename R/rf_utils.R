#!/usr/bin/env Rscript
# Self-tests run when RF_UTILS_TEST=TRUE.

source(file.path(Sys.getenv("RF_PROJECT_ROOT", unset = "."), "config.R"))

P2_OUT_DIR    <- rf_out_root()
P2_DATA_PATH  <- file.path(rf_data_root(), "final-spatial-matchup-p2.parquet")
P2_MODEL_DIR  <- file.path(P2_OUT_DIR, "models_p2")
P2_RESULT_DIR <- file.path(P2_OUT_DIR, "results")
P3_RESULT_DIR <- P2_RESULT_DIR

PFT_RESPONSES <- c(
  "Coccolithophores" = "class_fraction__coccolithophores",
  "Diatoms"          = "class_fraction__diatoms",
  "Phaeocystis"      = "class_fraction__phaeocystis"
)

# Keyed on PFT_RESPONSES names so a PFT rename can't silently desync colour↔response.
PFT_COLORS <- setNames(
  c("#E69F00", "#56B4E9", "#009E73"),
  names(PFT_RESPONSES)
)

ALE_SAMPLE_SIZE <- 30000L
ALE_N_BINS      <- 20L

DEFAULT_SEED            <- 42L
P2_MODEL_PREFIX         <- "p2"
RANGER_NUM_TREES        <- 100L
RANGER_NUM_TREES_SMOKE  <- 10L

# Deterministic split sizes on final-spatial-matchup-p2.parquet; regenerate only if the parquet changes.
P2_EXPECTED_FOLD_SIZES <- c(167335L, 539129L, 390003L, 497511L, 598809L)

P3_OCEAN_VARS     <- c("thetao", "so", "mlotst")
P3_LOCAL_ICE_VARS <- c("siconc", "sithick", "siconc_lag1", "sithick_lag1")
P3_EXPORT_VARS    <- c("ice_area_flux_current",   "ice_area_flux_lag1",
                       "ice_area_flux_lag2",      "ice_area_flux_cumOct",
                       "ice_volume_flux_current", "ice_volume_flux_lag1",
                       "ice_volume_flux_lag2",    "ice_volume_flux_cumOct")
P3_ATM_VARS       <- c("qnet_wm2", "u10_ms", "v10_ms")
P3_SPATIAL_VARS   <- c("latitude", "longitude")
P3_ALL_VARS       <- c(P3_OCEAN_VARS, P3_LOCAL_ICE_VARS, P3_EXPORT_VARS,
                       P3_ATM_VARS, P3_SPATIAL_VARS)
stopifnot(length(P3_ALL_VARS) == 20L)

# Parquet carries both qnet_ocean_loss_wm2 and qnet_downward_wm2; loss version wins.
.ERA5_RENAME_MAP <- c(
  era5_qnet_ocean_loss_wm2 = "qnet_wm2",
  era5_qnet_downward_wm2   = "qnet_wm2",
  era5_u10_ms              = "u10_ms",
  era5_v10_ms              = "v10_ms"
)

rename_era5_cols <- function(df, required = c("qnet_wm2", "u10_ms", "v10_ms")) {
  for (old in names(.ERA5_RENAME_MAP)) {
    new <- .ERA5_RENAME_MAP[[old]]
    if (old %in% names(df) && !(new %in% names(df))) {
      names(df)[names(df) == old] <- new
    }
  }
  missing <- setdiff(required, names(df))
  if (length(missing) > 0L) {
    stop("rename_era5_cols: expected columns missing after rename: ",
         paste(missing, collapse = ", "))
  }
  df
}

assign_5deg_blocks <- function(df) {
  df$block_lat <- floor(df$latitude  / 5) * 5
  df$block_lon <- floor(df$longitude / 5) * 5
  df$block_id  <- paste0(df$block_lat, "_", df$block_lon)
  df
}

# `blocks` ordering is load-bearing: set.seed + sample depends on input order.
# Pass unique(df$block_id) in parquet-read order for reproducibility across runs.
split_blocks_to_folds <- function(blocks, n_folds = 5L, seed = DEFAULT_SEED) {
  set.seed(seed)
  data.frame(
    block_id = blocks,
    fold     = sample(rep(seq_len(n_folds), length.out = length(blocks))),
    stringsAsFactors = FALSE
  )
}

# Stop with a clear error if df's per-fold row counts differ from the Phase 2
# canonical split. Used by every downstream script that relies on fold identity
# (cached .rds files assume stable fold assignment).
assert_fold_determinism <- function(df, expected = P2_EXPECTED_FOLD_SIZES) {
  if (!"fold" %in% names(df)) stop("assert_fold_determinism: df missing 'fold' column")
  actual <- as.integer(table(df$fold))
  if (length(actual) != length(expected) || !all(actual == expected)) {
    stop("Fold-split mismatch. Expected sizes: ", paste(expected, collapse = ","),
         " got: ", paste(actual, collapse = ","),
         ". Parquet or split logic may have changed.")
  }
  invisible(TRUE)
}

# Canonical path for a cached per-fold ranger model .rds file.
# Pattern: {dir}/{prefix}_{short}_{pft_lower_snake}_fold{N}.rds
model_cache_path <- function(short, pft_name, fold,
                             dir    = P2_MODEL_DIR,
                             prefix = P2_MODEL_PREFIX) {
  file.path(dir, sprintf("%s_%s_%s_fold%d.rds",
                         prefix, short,
                         gsub(" ", "_", tolower(pft_name)),
                         as.integer(fold)))
}

# Look up a scalar from a results data.frame by (pft, model_short).
# Default column is r2_mean but any numeric column works.
r2_by_spec <- function(results_df, pft_name, short, col = "r2_mean") {
  hit <- results_df[results_df$pft == pft_name & results_df$model_short == short, col]
  if (length(hit) != 1L) {
    stop("r2_by_spec: expected 1 match for pft=", pft_name, " short=", short,
         "; found ", length(hit))
  }
  hit
}

# Returns NA when y_true has zero variance (R² undefined rather than Inf/NaN surprise).
compute_r2 <- function(y_true, y_pred) {
  ss_res <- sum((y_true - y_pred)^2)
  ss_tot <- sum((y_true - mean(y_true))^2)
  if (ss_tot == 0) NA_real_ else 1 - ss_res / ss_tot
}

# Ranger's default is parallel::detectCores(), which may not respect cgroup limits
# on shared nodes. Use SLURM's allocated CPU count when available.
ranger_threads <- function() {
  slurm_cpus <- Sys.getenv("SLURM_CPUS_ON_NODE", unset = "")
  if (nzchar(slurm_cpus)) as.integer(slurm_cpus) else max(1L, parallel::detectCores() - 1L)
}

# Train a ranger model (or load from cache) for one (spec, pft, fold) cell.
# Encapsulates the cache-or-train branch + timing log.
train_or_load_fold_model <- function(train_df, formula, model_path,
                                     num_trees = RANGER_NUM_TREES,
                                     seed      = DEFAULT_SEED,
                                     n_threads = ranger_threads(),
                                     verbose   = TRUE) {
  if (file.exists(model_path)) {
    if (verbose) message("    [cache] ", basename(model_path))
    return(readRDS(model_path))
  }
  if (!requireNamespace("ranger", quietly = TRUE)) {
    stop("train_or_load_fold_model requires the ranger package")
  }
  t0 <- Sys.time()
  model <- ranger::ranger(formula, data = train_df,
                          num.trees   = num_trees,
                          importance  = "impurity",
                          seed        = seed,
                          verbose     = FALSE,
                          num.threads = n_threads)
  elapsed <- as.numeric(difftime(Sys.time(), t0, units = "mins"))
  if (verbose) message(sprintf("    trained in %.2f min  [saved %s]",
                              elapsed, basename(model_path)))
  saveRDS(model, model_path)
  model
}

# Run a block-CV ablation across (PFT × spec × fold). Returns a list
# with `results` (mean/sd per PFT×spec) and `fold_detail` (per-fold rows).
# Models are cached in `model_dir` via model_cache_path().
run_block_cv_ablation <- function(df, test_idx, specs, pft_responses,
                                  model_dir = P2_MODEL_DIR,
                                  model_prefix = P2_MODEL_PREFIX,
                                  num_trees = RANGER_NUM_TREES,
                                  seed      = DEFAULT_SEED,
                                  n_threads = ranger_threads(),
                                  verbose   = TRUE) {
  dir.create(model_dir, recursive = TRUE, showWarnings = FALSE)

  n_folds <- length(test_idx)
  results     <- data.frame()
  fold_detail <- data.frame()

  for (pft_name in names(pft_responses)) {
    resp <- pft_responses[[pft_name]]
    if (verbose) message("\n===== ", pft_name, " (", resp, ") =====")

    for (spec in specs) {
      if (verbose) message("  Spec: ", spec$name)
      fold_r2  <- numeric(n_folds)
      fold_mse <- numeric(n_folds)

      for (this_fold in seq_len(n_folds)) {
        mp <- model_cache_path(spec$short, pft_name, this_fold,
                               dir = model_dir, prefix = model_prefix)
        train_df <- df[-test_idx[[this_fold]], ]
        test_df  <- df[ test_idx[[this_fold]], ]

        model <- train_or_load_fold_model(
          train_df   = train_df,
          formula    = as.formula(paste(resp, "~", paste(spec$vars, collapse = "+"))),
          model_path = mp,
          num_trees  = num_trees,
          seed       = seed,
          n_threads  = n_threads,
          verbose    = verbose
        )

        preds  <- predict(model, data = test_df)$predictions
        y_true <- test_df[[resp]]
        fold_r2[this_fold]  <- compute_r2(y_true, preds)
        fold_mse[this_fold] <- mean((y_true - preds)^2)

        fold_detail <- rbind(fold_detail, data.frame(
          pft         = pft_name,
          model_short = spec$short,
          fold        = this_fold,
          n_train     = nrow(train_df),
          n_test      = nrow(test_df),
          r2_fold     = fold_r2[this_fold],
          mse_fold    = fold_mse[this_fold],
          stringsAsFactors = FALSE
        ))
        if (verbose) message(sprintf("    fold %d: R² = %.4f  MSE = %.6f",
                                    this_fold, fold_r2[this_fold], fold_mse[this_fold]))
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
      if (verbose) message(sprintf("  MEAN R² = %.4f (sd %.4f)",
                                  mean(fold_r2), sd(fold_r2)))
    }
  }

  list(results = results, fold_detail = fold_detail)
}


# Apley & Zhu (2020), eqs. 7-8. Quantile bins, cumsum, bin-count-weighted centering.
compute_ale <- function(model, data, feature, K = ALE_N_BINS, num.threads = 1L) {
  x <- data[[feature]]
  edges <- unique(quantile(x, probs = seq(0, 1, length.out = K + 1L), na.rm = TRUE))
  K_actual <- length(edges) - 1L
  if (K_actual < 2L) return(NULL)
  bin <- findInterval(x, edges, all.inside = TRUE, rightmost.closed = TRUE)
  local_effects <- numeric(K_actual)
  for (k in seq_len(K_actual)) {
    mask <- bin == k
    if (sum(mask) == 0L) { local_effects[k] <- 0; next }
    data_lo <- data[mask, , drop = FALSE]
    data_hi <- data_lo
    data_lo[[feature]] <- edges[k]
    data_hi[[feature]] <- edges[k + 1L]
    pred_lo <- predict(model, data = data_lo, num.threads = num.threads)$predictions
    pred_hi <- predict(model, data = data_hi, num.threads = num.threads)$predictions
    local_effects[k] <- mean(pred_hi - pred_lo, na.rm = TRUE)
  }
  ale_uncentered <- cumsum(local_effects)
  bin_counts <- tabulate(bin, nbins = K_actual)
  center <- sum(ale_uncentered * bin_counts) / max(1L, sum(bin_counts))
  data.frame(
    x         = (edges[-1L] + edges[-(K_actual + 1L)]) / 2,
    ale       = ale_uncentered - center,
    bin_count = bin_counts,
    feature   = feature,
    stringsAsFactors = FALSE
  )
}


if (isTRUE(as.logical(Sys.getenv("RF_UTILS_TEST", unset = "FALSE")))) {
  message("Running rf_utils.R self-tests...")

  # assign_5deg_blocks
  tdf <- data.frame(latitude = c(72.3, 77.8, 80.1), longitude = c(-12.5, 8.2, 31.9))
  tdf <- assign_5deg_blocks(tdf)
  stopifnot(tdf$block_lat == c(70, 75, 80))
  stopifnot(tdf$block_lon == c(-15, 5, 30))
  stopifnot(tdf$block_id  == c("70_-15", "75_5", "80_30"))
  message("  assign_5deg_blocks OK")

  # split_blocks_to_folds
  blocks <- sprintf("b%d", 1:20)
  s1 <- split_blocks_to_folds(blocks, 5, 42)
  s2 <- split_blocks_to_folds(blocks, 5, 42)
  stopifnot(identical(s1, s2))
  stopifnot(length(unique(s1$fold)) == 5L)
  s_rev <- split_blocks_to_folds(rev(blocks), 5, 42)
  map1 <- setNames(s1$fold,    s1$block_id)
  map2 <- setNames(s_rev$fold, s_rev$block_id)
  stopifnot(!identical(map1[blocks], map2[blocks]))
  message("  split_blocks_to_folds deterministic + order-sensitive OK")

  # compute_r2
  stopifnot(abs(compute_r2(c(1, 2, 3), c(1, 2, 3)) - 1) < 1e-9)
  stopifnot(compute_r2(c(1, 2, 3), c(2, 2, 2)) == 0)
  stopifnot(is.na(compute_r2(c(5, 5, 5), c(5, 5, 5))))
  message("  compute_r2 OK")

  # rename_era5_cols
  tdf <- data.frame(era5_qnet_ocean_loss_wm2 = 1, era5_u10_ms = 2, era5_v10_ms = 3, keep = 4)
  tdf <- rename_era5_cols(tdf)
  stopifnot(all(c("qnet_wm2", "u10_ms", "v10_ms", "keep") %in% names(tdf)))
  err_caught <- tryCatch({
    rename_era5_cols(data.frame(wrong_col = 1)); FALSE
  }, error = function(e) grepl("expected columns missing", e$message))
  stopifnot(err_caught)
  message("  rename_era5_cols OK")

  # ranger_threads
  old_env <- Sys.getenv("SLURM_CPUS_ON_NODE")
  Sys.setenv(SLURM_CPUS_ON_NODE = "16")
  stopifnot(ranger_threads() == 16L)
  Sys.setenv(SLURM_CPUS_ON_NODE = old_env)
  message("  ranger_threads OK")

  # model_cache_path
  stopifnot(model_cache_path("full", "Coccolithophores", 1L, dir = "/tmp", prefix = "p2") ==
            "/tmp/p2_full_coccolithophores_fold1.rds")
  stopifnot(model_cache_path("ocean3", "Phaeocystis", 5L, dir = "/a", prefix = "p3") ==
            "/a/p3_ocean3_phaeocystis_fold5.rds")
  message("  model_cache_path OK")

  # assert_fold_determinism
  tdf_ok <- data.frame(fold = rep(1:5, times = P2_EXPECTED_FOLD_SIZES))
  assert_fold_determinism(tdf_ok)  # silent
  tdf_bad <- data.frame(fold = c(rep(1, 100), rep(2, 200)))
  err2 <- tryCatch({
    assert_fold_determinism(tdf_bad); FALSE
  }, error = function(e) grepl("Fold-split mismatch", e$message))
  stopifnot(err2)
  tdf_missing <- data.frame(x = 1:5)
  err3 <- tryCatch({
    assert_fold_determinism(tdf_missing); FALSE
  }, error = function(e) grepl("missing 'fold'", e$message))
  stopifnot(err3)
  message("  assert_fold_determinism OK")

  # r2_by_spec
  tdf <- data.frame(pft = c("A", "A", "B"), model_short = c("x", "y", "x"),
                    r2_mean = c(0.1, 0.2, 0.3))
  stopifnot(r2_by_spec(tdf, "A", "x") == 0.1)
  stopifnot(r2_by_spec(tdf, "B", "x") == 0.3)
  err4 <- tryCatch({
    r2_by_spec(tdf, "A", "notfound"); FALSE
  }, error = function(e) grepl("expected 1 match", e$message))
  stopifnot(err4)
  message("  r2_by_spec OK")

  # run_block_cv_ablation + train_or_load_fold_model integration test
  if (requireNamespace("ranger", quietly = TRUE)) {
    set.seed(0)
    n <- 500
    test_df <- data.frame(
      x1   = rnorm(n), x2 = rnorm(n),
      y    = rnorm(n),
      fold = sample(rep(1:5, length.out = n))
    )
    tdir <- file.path(tempdir(), "rf_utils_test_models")
    dir.create(tdir, showWarnings = FALSE, recursive = TRUE)
    on.exit(unlink(tdir, recursive = TRUE), add = TRUE)

    test_idx <- split(seq_len(nrow(test_df)), test_df$fold)
    specs <- list(list(name = "Full", short = "full", vars = c("x1", "x2")))
    resps <- c("A" = "y")

    out <- run_block_cv_ablation(test_df, test_idx, specs, resps,
                                  model_dir = tdir, num_trees = 5L, verbose = FALSE)
    stopifnot(nrow(out$results) == 1L)
    stopifnot(nrow(out$fold_detail) == 5L)
    stopifnot("r2_mean" %in% names(out$results))
    stopifnot(out$results$n_predictors == 2L)
    # 5 .rds files written
    stopifnot(length(list.files(tdir, pattern = "\\.rds$")) == 5L)
    # Second call re-uses cache (fast)
    t0 <- Sys.time()
    out2 <- run_block_cv_ablation(test_df, test_idx, specs, resps,
                                   model_dir = tdir, num_trees = 5L, verbose = FALSE)
    cache_time <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
    stopifnot(cache_time < 5)  # loading cached models must be fast
    stopifnot(all.equal(out$results$r2_mean, out2$results$r2_mean))
    message("  run_block_cv_ablation + train_or_load_fold_model OK ",
            sprintf("(cache re-use: %.2fs)", cache_time))
  } else {
    message("  (skipping ablation integration test — ranger not installed)")
  }

  message("All rf_utils.R self-tests passed.")
}
