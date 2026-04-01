#!/bin/bash
#SBATCH --job-name=rf_cmems_core_monthly
#SBATCH --output=/mnt/research/mlavign/llinkas/random-forest/logs/rf_cmems_core_monthly_%j.out
#SBATCH --error=/mnt/research/mlavign/llinkas/random-forest/logs/rf_cmems_core_monthly_%j.err
#SBATCH --time=08:00:00
#SBATCH --cpus-per-task=2
#SBATCH --mem=16G

set -euo pipefail

PROJECT_ROOT="/mnt/research/mlavign/llinkas/random-forest"

cd "$PROJECT_ROOT"
source .venv/bin/activate

echo "Starting monthly core Copernicus download job"
echo "Project root: $PROJECT_ROOT"
echo "Python: $(which python)"
echo "Time: $(date)"

python -c "import pandas, pyarrow, copernicusmarine, h5py; print('env ok')"
make hpc-check
python scripts/download_core_copernicus_monthly.py

echo "Job completed at $(date)"
