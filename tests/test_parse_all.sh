#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

fail=0
for f in R/*.R tests/*.R; do
  Rscript -e "invisible(parse('$f'))" || { echo "PARSE FAIL: $f"; fail=1; }
done
for f in scripts/*.py; do
  python3 -c "import ast, sys; ast.parse(open('$f').read())" || { echo "PARSE FAIL: $f"; fail=1; }
done
for f in slurm/*.sh; do
  bash -n "$f" || { echo "PARSE FAIL: $f"; fail=1; }
done

exit "$fail"
