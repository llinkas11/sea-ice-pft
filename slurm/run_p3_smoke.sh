#!/bin/bash
#SBATCH --job-name=p3_smoke
#SBATCH --time=00:10:00
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G
#SBATCH --partition=main

set -euo pipefail
: "${RF_PROJECT_ROOT:?set RF_PROJECT_ROOT before sbatch}"
set -a; source "$RF_PROJECT_ROOT/.env"; set +a
cd "$RF_PROJECT_ROOT"

Rscript "$RF_PROJECT_ROOT/R/scripts/smoke_test_p3.R"
