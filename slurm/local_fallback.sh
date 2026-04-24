#!/usr/bin/env bash
set -euo pipefail

: "${RF_PROJECT_ROOT:?set RF_PROJECT_ROOT in .env}"
set -a; source "$RF_PROJECT_ROOT/.env"; set +a
cd "$RF_PROJECT_ROOT"

stage="${1:-phase3}"
case "$stage" in
  phase1)   Rscript "$RF_PROJECT_ROOT/R/model_comparison_p1.R" ;;
  phase2)   Rscript "$RF_PROJECT_ROOT/R/model_comparison_p2.R" ;;
  phase3)   Rscript "$RF_PROJECT_ROOT/R/model_comparison_p3.R" ;;
  ale-p2)   Rscript "$RF_PROJECT_ROOT/R/compute_ale_p2.R" ;;
  ale-p3)   Rscript "$RF_PROJECT_ROOT/R/compute_ale_p3.R" ;;
  predict)  Rscript "$RF_PROJECT_ROOT/R/predict_p3.R" ;;
  blockmap) Rscript "$RF_PROJECT_ROOT/R/build_p3_block_r2_map.R" ;;
  maps)     Rscript "$RF_PROJECT_ROOT/R/spatial_maps.R" ;;
  *)
    echo "unknown stage: $stage" >&2
    echo "usage: $0 {phase1|phase2|phase3|ale-p2|ale-p3|predict|blockmap|maps}" >&2
    exit 2
    ;;
esac
