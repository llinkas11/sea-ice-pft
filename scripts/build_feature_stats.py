#!/usr/bin/env python3
"""Compute per-feature mean and SD on the Phase 3 parquet so the X-axis in
the ALE figures (`build_ale_figures.py`) can be standardized to z-score.

Outputs:
  out/results/p3_full_feature_stats.csv
"""
import os
import sys
from pathlib import Path

import pandas as pd

sys.path.insert(0, os.environ.get("RF_PROJECT_ROOT", os.getcwd()))
from config import rf_data_root, rf_out_root  # noqa: E402

sys.path.insert(0, str(Path(__file__).resolve().parent))
from probe_utils import P3_ALL_VARS, ERA5_RENAME  # noqa: E402

PQ  = rf_data_root() / "final-spatial-matchup-p3.parquet"
OUT = rf_out_root() / "results" / "p3_full_feature_stats.csv"
OUT.parent.mkdir(parents=True, exist_ok=True)

df = pd.read_parquet(PQ).rename(columns=ERA5_RENAME)
print(f"Read {len(df):,} rows × {df.shape[1]} cols")

rows = []
for f in P3_ALL_VARS:
    if f not in df.columns:
        print(f"  WARN: {f} not found, skipping")
        continue
    x = df[f].dropna()
    rows.append({"feature": f, "mean": x.mean(), "sd": x.std(), "n": len(x),
                 "p1": x.quantile(0.01), "p99": x.quantile(0.99)})

out = pd.DataFrame(rows)
out.to_csv(OUT, index=False)
print(f"Saved -> {OUT}")
print(out.to_string(index=False))
