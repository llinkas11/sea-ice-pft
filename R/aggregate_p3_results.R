#!/usr/bin/env Rscript
# Aggregate per-PFT Phase 3 CSVs into the unified results files.
# Avoids the 15-min cost of re-running the full model_comparison_p3.R
# unfiltered (which would re-predict every spec × fold × PFT from the cache).
#
# Expects per-PFT CSVs written by PFT-filtered model_comparison_p3.R runs:
#   p3_block_cv_results_coccolithophores.csv
#   p3_block_cv_results_diatoms.csv
#   p3_block_cv_results_phaeocystis.csv
#   p3_block_cv_fold_detail_coccolithophores.csv   (etc.)

source(file.path(Sys.getenv("RF_PROJECT_ROOT", unset = "."), "R/rf_utils.R"))
setup_rlibs()

suppressPackageStartupMessages({ library(dplyr); library(tidyr) })

EXPECTED_PFTS <- names(PFT_RESPONSES)
EXPECTED_SUFFIXES <- tolower(EXPECTED_PFTS)

concat_per_pft <- function(basename_stem) {
  parts <- Filter(Negate(is.null), lapply(EXPECTED_SUFFIXES, function(sfx) {
    p <- file.path(P2_RESULT_DIR, sprintf("%s_%s.csv", basename_stem, sfx))
    if (!file.exists(p)) {
      warning("Missing per-PFT CSV: ", p)
      return(NULL)
    }
    df <- read.csv(p, stringsAsFactors = FALSE)
    cat(sprintf("  %s: %d rows\n", basename(p), nrow(df)))
    df
  }))
  if (length(parts) == 0L) stop("No per-PFT CSVs found for ", basename_stem)
  dplyr::bind_rows(parts)
}

cat("Aggregating results rows...\n")
results <- concat_per_pft("p3_block_cv_results")
cat("\nAggregating fold detail rows...\n")
fold_detail <- concat_per_pft("p3_block_cv_fold_detail")

expected_results_rows <- length(EXPECTED_PFTS) * 6L   # 6 specs per PFT
if (nrow(results) != expected_results_rows) {
  warning(sprintf("Expected %d results rows, got %d — some PFT results missing.",
                  expected_results_rows, nrow(results)))
}

results_out <- file.path(P2_RESULT_DIR, "p3_block_cv_results.csv")
fold_out    <- file.path(P2_RESULT_DIR, "p3_block_cv_fold_detail.csv")
write.csv(results,     results_out, row.names = FALSE)
write.csv(fold_detail, fold_out,    row.names = FALSE)
cat("\nWrote unified files:\n  ", results_out, "\n  ", fold_out, "\n")

cat("\n===== Unified Phase 3 results =====\n")
print(results %>% dplyr::select(pft, model_short, n_predictors,
                                r2_mean, r2_sd, r2_drop, r2_drop_pct))

# Primary hypothesis: Full(20) vs No_export(12) per PFT
cat("\n===== Primary hypothesis: Δ(export) per PFT =====\n")
delta_export <- results %>%
  dplyr::filter(model_short %in% c("full", "no_export")) %>%
  dplyr::select(pft, model_short, r2_mean) %>%
  tidyr::pivot_wider(names_from = model_short, values_from = r2_mean) %>%
  dplyr::mutate(delta_export = full - no_export)
print(delta_export)
