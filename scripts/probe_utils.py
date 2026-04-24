import os
import sys
from pathlib import Path
from typing import NamedTuple
import numpy as np
import pandas as pd
from scipy.stats import pearsonr
from sklearn.linear_model import LinearRegression

sys.path.insert(0, os.environ.get("RF_PROJECT_ROOT", os.getcwd()))
from config import rf_data_root, rf_out_root, rf_project_root

__all__ = [
    "PQ_PATH", "DATA_MODEL_DIR", "RESULTS_DIR", "SCRIPTS_DIR",
    "PFT_VARS", "ICE_VARS", "OCEAN_VARS", "ATM_VARS", "SPATIAL_VARS",
    "PHASE1_FILTER_COLS",
    "PartialCorrResult",
    "load_matchup_phase1", "add_monthly_lags", "add_climatology_anomaly",
    "partial_corr", "mediation_pct",
]

PQ_PATH        = rf_data_root() / "final-spatial-matchup.parquet"
DATA_MODEL_DIR = rf_data_root()
RESULTS_DIR    = rf_out_root() / "results"
SCRIPTS_DIR    = rf_project_root() / "scripts"

# Parquet-native names (pre-R rename).
PFT_VARS = [
    'class_fraction__phaeocystis',
    'class_fraction__diatoms',
    'class_fraction__coccolithophores',
]
ICE_VARS     = ['siconc', 'sithick']
OCEAN_VARS   = ['thetao', 'so', 'mlotst']
ATM_VARS     = ['era5_qnet_ocean_loss_wm2', 'era5_u10_ms', 'era5_v10_ms']
SPATIAL_VARS = ['latitude', 'longitude']

PHASE1_FILTER_COLS = PFT_VARS + ICE_VARS + OCEAN_VARS + ATM_VARS + SPATIAL_VARS


class PartialCorrResult(NamedTuple):
    r: float
    p: float


def load_matchup_phase1(columns=None, verbose=True):
    """Load the matchup parquet and apply the Phase 1 NaN filter.

    columns: extra columns to retain beyond PHASE1_FILTER_COLS. If None,
             return all columns in the parquet. If a list, read only
             PHASE1_FILTER_COLS + columns + ['year','month'].

    Raises KeyError with a readable message if PHASE1_FILTER_COLS are
    missing from the parquet (usually indicates schema drift).
    """
    if columns is None:
        df = pd.read_parquet(PQ_PATH)
    else:
        read_cols = list(dict.fromkeys(PHASE1_FILTER_COLS + list(columns) + ['year', 'month']))
        df = pd.read_parquet(PQ_PATH, columns=read_cols)

    missing = [c for c in PHASE1_FILTER_COLS if c not in df.columns]
    if missing:
        raise KeyError(f"Phase 1 filter columns missing from parquet: {missing}")

    n_raw = len(df)
    df = df.dropna(subset=PHASE1_FILTER_COLS)
    if verbose:
        print(f"Loaded {n_raw:,} rows; {len(df):,} after Phase 1 filter "
              f"({100 * (n_raw - len(df)) / n_raw:.2f}% dropped)")
    return df


def add_monthly_lags(df, cols, lags, keys=('latitude', 'longitude')):
    """Return df with calendar-month lag columns added via date-shifted merge.

    `lag-L` at row (Y, M) equals the same pixel's value at calendar month
    (Y, M-L), or NaN if that calendar month isn't observed. For datasets
    with month gaps (e.g. April–August only), April's lag-1 is NaN
    because March isn't in the data — it is NOT the previous year's August.
    Year boundaries are handled: January's lag-1 is the previous year's
    December (if observed).

    Implementation: shifts source (year, month) forward by L and merges —
    so a source row at (Y, M) lands at key (Y, M+L), where the left-side
    row at (Y, M+L) finds it. Requires (year, month) to be non-NaN and
    (keys..., year, month) to be unique in df — merge validates the latter.

    Note: this replaced an earlier `groupby.shift()` implementation which
    gave "previous row in sorted sequence" semantics — wrong for gappy
    monthly data.
    """
    if isinstance(lags, int):
        lags = [lags]
    if df['year'].isna().any() or df['month'].isna().any():
        raise ValueError("year/month must not contain NaN before add_monthly_lags")
    key_list = list(keys) + ['year', 'month']
    for L in lags:
        shifted = df[key_list + list(cols)].copy()
        new_total = shifted['year'] * 12 + shifted['month'] + L
        shifted['year']  = (new_total - 1) // 12
        shifted['month'] = ((new_total - 1) % 12) + 1
        shifted = shifted.rename(columns={c: f'{c}_lag{L}' for c in cols})
        df = df.merge(shifted, on=key_list, how='left', validate='many_to_one')
    return df


def add_climatology_anomaly(df, cols, keys=('latitude', 'longitude', 'month')):
    """Return df with per-pixel-per-month `{c}_clim` and `{c}_anomaly` columns added.

    Single groupby pass over all cols for efficiency. Uses df.assign() to
    return a new frame without mutating the caller's df or taking an
    explicit full .copy().
    """
    clim = df.groupby(list(keys))[list(cols)].transform('mean')
    new_cols = {}
    for c in cols:
        new_cols[f'{c}_clim']    = clim[c]
        new_cols[f'{c}_anomaly'] = df[c] - clim[c]
    return df.assign(**new_cols)


def partial_corr(df, x, y, controls) -> PartialCorrResult:
    """Residuals-based partial correlation between x and y, controlling for `controls`."""
    X = df[list(controls)].values
    rx = df[x].values - LinearRegression().fit(X, df[x].values).predict(X)
    ry = df[y].values - LinearRegression().fit(X, df[y].values).predict(X)
    r, p = pearsonr(rx, ry)
    return PartialCorrResult(r=float(r), p=float(p))


def mediation_pct(r_direct, r_partial, min_direct=0.01):
    """Mediation percentage: 100 = full mediation, 0 = none, negative = suppression.

    Returns NaN when |r_direct| < min_direct (formula unstable near zero).
    """
    if abs(r_direct) < min_direct:
        return float('nan')
    return 100.0 * (1.0 - abs(r_partial) / abs(r_direct))
