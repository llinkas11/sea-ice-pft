#!/bin/bash
#SBATCH --job-name=rf_p2_seqadd
#SBATCH --time=06:00:00
#SBATCH --cpus-per-task=16
#SBATCH --mem=32G
#SBATCH --partition=main

set -euo pipefail
: "${RF_PROJECT_ROOT:?set RF_PROJECT_ROOT before sbatch}"
set -a; source "$RF_PROJECT_ROOT/.env"; set +a
cd "$RF_PROJECT_ROOT"

echo "Seqadd job started: $(date) on $(hostname)"
Rscript "$RF_PROJECT_ROOT/R/model_comparison_p2_seqadd.R"
echo "Seqadd job finished: $(date)"
