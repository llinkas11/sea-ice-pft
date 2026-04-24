#!/bin/bash
#SBATCH --job-name=p3_blockmap
#SBATCH --time=00:30:00
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G
#SBATCH --partition=main

set -euo pipefail
: "${RF_PROJECT_ROOT:?set RF_PROJECT_ROOT before sbatch}"
set -a; source "$RF_PROJECT_ROOT/.env"; set +a
cd "$RF_PROJECT_ROOT"

Rscript "$RF_PROJECT_ROOT/R/scripts/build_p3_block_r2_map.R"
