#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 /path/to/hpc_project_root [data_root]"
  exit 1
fi

PROJECT_ROOT="$1"
DATA_ROOT="${2:-$PROJECT_ROOT}"

mkdir -p "$PROJECT_ROOT"
mkdir -p "$DATA_ROOT"

cat <<EOF
HPC setup recommendations
- Put the code repository at: $PROJECT_ROOT
- Put large data and generated outputs at: $DATA_ROOT
- Copy .env.make.example to .env.make and edit it for these paths
- Then run:
    make hpc-check
    make init
    make inventory
EOF
