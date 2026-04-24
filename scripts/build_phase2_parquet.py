#!/usr/bin/env python3
"""
Build the Phase 2 training parquet: Phase 1 filter + siconc_lag1 + sithick_lag1.

Output: ~17 columns, rows that have valid lag1 (May-August only).
"""
import probe_utils as u

df = u.load_matchup_phase1(columns=[])          # filtered, minimal cols
df = u.add_monthly_lags(df, u.ICE_VARS, [1])    # adds siconc_lag1, sithick_lag1

n_pre = len(df)
df = df.dropna(subset=['siconc_lag1', 'sithick_lag1'])
print(f"Kept {len(df):,} rows with valid lag1 (dropped {n_pre - len(df):,} April rows)")

out = u.DATA_MODEL_DIR / 'final-spatial-matchup-p2.parquet'
df.to_parquet(out, index=False)
print(f"Wrote -> {out}  shape {df.shape}")
print(f"Columns: {df.columns.tolist()}")
