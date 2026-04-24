#!/bin/bash
#SBATCH --job-name=p2_blockmap
#SBATCH --time=01:00:00
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G
#SBATCH --partition=main

set -euo pipefail
: "${RF_PROJECT_ROOT:?set RF_PROJECT_ROOT before sbatch}"
set -a; source "$RF_PROJECT_ROOT/.env"; set +a
cd "$RF_PROJECT_ROOT"

echo "Block-map build started: $(date) on $(hostname)"
Rscript "$RF_PROJECT_ROOT/R/scripts/build_block_r2_map.R"
echo "Block-map build finished: $(date)"
