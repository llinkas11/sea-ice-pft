#!/bin/bash
#SBATCH --job-name=rf_p3_pred
#SBATCH --time=01:00:00
#SBATCH --cpus-per-task=8
#SBATCH --mem=24G
#SBATCH --partition=main

set -euo pipefail
: "${RF_PROJECT_ROOT:?set RF_PROJECT_ROOT before sbatch}"
set -a; source "$RF_PROJECT_ROOT/.env"; set +a
cd "$RF_PROJECT_ROOT"

Rscript "$RF_PROJECT_ROOT/R/predict_p3.R"
