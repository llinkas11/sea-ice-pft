#!/bin/bash
#SBATCH --job-name=rf_p3t_Diatoms
#SBATCH --time=24:00:00
#SBATCH --cpus-per-task=16
#SBATCH --mem=32G
#SBATCH --partition=main

set -euo pipefail
: "${RF_PROJECT_ROOT:?set RF_PROJECT_ROOT before sbatch}"
set -a; source "$RF_PROJECT_ROOT/.env"; set +a
cd "$RF_PROJECT_ROOT"

echo "P3 temporal CV Diatoms started: $(date) on $(hostname)"
echo "SLURM_CPUS_ON_NODE=$SLURM_CPUS_ON_NODE  SLURM_JOB_ID=$SLURM_JOB_ID"
export P3_PFT_FILTER=Diatoms
Rscript "$RF_PROJECT_ROOT/R/model_comparison_p3_temporal.R"
echo "P3 temporal CV Diatoms finished: $(date)"
