#!/bin/bash
#SBATCH --job-name=rf_p3_export
#SBATCH --time=36:00:00
#SBATCH --cpus-per-task=16
#SBATCH --mem=32G
#SBATCH --partition=main

set -euo pipefail
: "${RF_PROJECT_ROOT:?set RF_PROJECT_ROOT before sbatch}"
set -a; source "$RF_PROJECT_ROOT/.env"; set +a
cd "$RF_PROJECT_ROOT"

echo "Phase 3 started: $(date) on $(hostname)"
echo "SLURM_CPUS_ON_NODE=$SLURM_CPUS_ON_NODE  SLURM_JOB_ID=$SLURM_JOB_ID"
Rscript "$RF_PROJECT_ROOT/R/model_comparison_p3.R"
echo "Phase 3 finished: $(date)"
