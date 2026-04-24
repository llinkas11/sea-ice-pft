#!/bin/bash
#SBATCH --job-name=rf_p3_ale
#SBATCH --time=06:00:00
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --partition=main

set -euo pipefail
: "${RF_PROJECT_ROOT:?set RF_PROJECT_ROOT before sbatch}"
set -a; source "$RF_PROJECT_ROOT/.env"; set +a
cd "$RF_PROJECT_ROOT"

echo "Phase 3 ALE job started: $(date) on $(hostname)"
Rscript "$RF_PROJECT_ROOT/R/compute_ale_p3.R"
echo "Phase 3 ALE job finished: $(date)"
