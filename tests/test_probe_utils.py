#!/usr/bin/env python3
"""
Tests for probe_utils.py

Run: python test_probe_utils.py
     (plain-assert runner; no pytest dependency needed on HPC)

Covers every helper in probe_utils with edge cases the review agents flagged:
  - calendar-lag semantics at year boundaries and month gaps
  - duplicate-key detection in lag merge
  - NaN in year/month rejected
  - climatology math correctness
  - input non-mutation
  - partial_corr named-tuple shape and mediation behavior
  - mediation_pct at full / none / suppression / near-zero
  - load_matchup_phase1 column-subset + filter logic (integration)
"""
import sys
import traceback
import numpy as np
import pandas as pd
import probe_utils as u


# ---------- Fixture ----------
def synthetic_df():
    """3 years × 3 pixels × 5 months (Apr-Aug) = 45 rows. One (lat,lon,year,month) per row."""
    rows = []
    for y in [2020, 2021, 2022]:
        for lat, lon in [(70.0, 10.0), (75.0, 20.0), (80.0, 0.0)]:
            for m in [4, 5, 6, 7, 8]:
                rows.append({
                    'year': y, 'month': m,
                    'latitude': lat, 'longitude': lon,
                    'siconc':  0.9 - 0.2 * (m - 4) + 0.01 * (y - 2020),
                    'sithick': 2.0 - 0.4 * (m - 4) + 0.02 * (y - 2020),
                    'thetao':  2.0 + 0.5 * (m - 4),
                })
    return pd.DataFrame(rows)


# ---------- add_monthly_lags ----------
def test_lag_april_is_nan_when_march_missing():
    out = u.add_monthly_lags(synthetic_df(), ['siconc'], [1])
    apr = out[out['month'] == 4]
    assert apr['siconc_lag1'].isna().all(), "April lag1 should be NaN (March not observed)"

def test_lag_may_equals_april_same_pixel_same_year():
    df = synthetic_df()
    out = u.add_monthly_lags(df, ['siconc'], [1])
    for (lat, lon, y), group in out.groupby(['latitude', 'longitude', 'year']):
        may_lag = group[group['month'] == 5]['siconc_lag1'].iloc[0]
        apr_val = group[group['month'] == 4]['siconc'].iloc[0]
        assert np.isclose(may_lag, apr_val), f"May lag1 != April at ({lat},{lon},{y})"

def test_lag_year_boundary_on_continuous_data():
    """For 12-month continuous data, Jan's lag1 is previous Dec."""
    df = pd.DataFrame({
        'latitude':  [70.0] * 24,
        'longitude': [10.0] * 24,
        'year':      [2020] * 12 + [2021] * 12,
        'month':     list(range(1, 13)) * 2,
        'val':       list(range(1, 13)) + list(range(101, 113)),
    })
    out = u.add_monthly_lags(df, ['val'], [1])
    jan21_lag = out[(out['year'] == 2021) & (out['month'] == 1)]['val_lag1'].iloc[0]
    assert jan21_lag == 12, f"Jan 2021 lag1 should be Dec 2020 (=12), got {jan21_lag}"

def test_lag_doesnt_mutate_input():
    df = synthetic_df()
    original_cols = df.columns.tolist()
    original_hash = pd.util.hash_pandas_object(df).sum()
    _ = u.add_monthly_lags(df, ['siconc'], [1])
    assert df.columns.tolist() == original_cols
    assert pd.util.hash_pandas_object(df).sum() == original_hash, "input df was mutated"

def test_lag_multiple_lags_and_cols():
    out = u.add_monthly_lags(synthetic_df(), ['siconc', 'sithick'], [1, 2])
    for c in ['siconc_lag1', 'siconc_lag2', 'sithick_lag1', 'sithick_lag2']:
        assert c in out.columns, f"expected column {c}"

def test_lag_rejects_nan_in_year():
    df = synthetic_df()
    df.loc[0, 'year'] = np.nan
    try:
        u.add_monthly_lags(df, ['siconc'], [1])
    except ValueError:
        return
    raise AssertionError("add_monthly_lags should raise ValueError on NaN in year")

def test_lag_rejects_nan_in_month():
    df = synthetic_df()
    df.loc[0, 'month'] = np.nan
    try:
        u.add_monthly_lags(df, ['siconc'], [1])
    except ValueError:
        return
    raise AssertionError("add_monthly_lags should raise ValueError on NaN in month")

def test_lag_detects_duplicate_keys():
    """Duplicate (lat, lon, year, month) should be caught by validate='many_to_one'."""
    df = synthetic_df()
    df = pd.concat([df, df.iloc[:1]], ignore_index=True)  # duplicate first row
    try:
        u.add_monthly_lags(df, ['siconc'], [1])
    except Exception:
        return  # pd.errors.MergeError or similar
    raise AssertionError("add_monthly_lags should fail merge validation on duplicate keys")

def test_lag2_skips_two_months():
    """lag2 for June should be April's value."""
    df = synthetic_df()
    out = u.add_monthly_lags(df, ['siconc'], [2])
    for (lat, lon, y), g in out.groupby(['latitude', 'longitude', 'year']):
        jun_lag2 = g[g['month'] == 6]['siconc_lag2'].iloc[0]
        apr_val  = g[g['month'] == 4]['siconc'].iloc[0]
        assert np.isclose(jun_lag2, apr_val), f"June lag2 != April at ({lat},{lon},{y})"


# ---------- add_climatology_anomaly ----------
def test_clim_is_per_pixel_per_month_mean():
    df = synthetic_df()
    out = u.add_climatology_anomaly(df, ['thetao'])
    for (lat, lon, m), g in df.groupby(['latitude', 'longitude', 'month']):
        expected = g['thetao'].mean()
        actual = out.loc[
            (out['latitude'] == lat) & (out['longitude'] == lon) & (out['month'] == m),
            'thetao_clim'
        ].iloc[0]
        assert np.isclose(expected, actual), f"clim mismatch at ({lat},{lon},m={m})"

def test_clim_anomaly_equals_value_minus_clim():
    df = synthetic_df()
    out = u.add_climatology_anomaly(df, ['thetao'])
    assert np.allclose(out['thetao_anomaly'], out['thetao'] - out['thetao_clim'])

def test_clim_doesnt_mutate_input():
    df = synthetic_df()
    original_cols = df.columns.tolist()
    original_hash = pd.util.hash_pandas_object(df).sum()
    _ = u.add_climatology_anomaly(df, ['thetao'])
    assert df.columns.tolist() == original_cols
    assert pd.util.hash_pandas_object(df).sum() == original_hash

def test_clim_multi_col_single_pass():
    df = synthetic_df()
    out = u.add_climatology_anomaly(df, ['thetao', 'siconc', 'sithick'])
    for c in ['thetao_clim', 'thetao_anomaly', 'siconc_clim', 'siconc_anomaly', 'sithick_clim', 'sithick_anomaly']:
        assert c in out.columns


# ---------- partial_corr ----------
def test_partial_corr_is_named_tuple():
    np.random.seed(0)
    df = pd.DataFrame({'x': np.random.randn(100), 'y': np.random.randn(100), 'z': np.random.randn(100)})
    r = u.partial_corr(df, 'x', 'y', ['z'])
    assert isinstance(r, u.PartialCorrResult)
    assert isinstance(r.r, float) and isinstance(r.p, float)
    # Also tuple-unpackable for backwards compat
    rr, pp = r
    assert rr == r.r and pp == r.p

def test_partial_corr_near_zero_when_fully_mediated():
    """If x = a*z + noise and y = b*z + noise, partial(x,y|z) ≈ 0."""
    np.random.seed(42)
    n = 2000
    z = np.random.randn(n)
    x = 2.0 * z + 0.1 * np.random.randn(n)
    y = 3.0 * z + 0.1 * np.random.randn(n)
    df = pd.DataFrame({'x': x, 'y': y, 'z': z})
    r = u.partial_corr(df, 'x', 'y', ['z'])
    assert abs(r.r) < 0.1, f"expected near-zero partial corr; got {r.r}"

def test_partial_corr_preserves_direct_when_controls_unrelated():
    np.random.seed(42)
    n = 2000
    x = np.random.randn(n)
    y = 0.8 * x + 0.1 * np.random.randn(n)
    z = np.random.randn(n)  # independent control
    df = pd.DataFrame({'x': x, 'y': y, 'z': z})
    direct_r = df['x'].corr(df['y'])
    partial_r = u.partial_corr(df, 'x', 'y', ['z']).r
    assert abs(direct_r - partial_r) < 0.05, f"uncorrelated control shouldn't change r much"


# ---------- mediation_pct ----------
def test_mediation_pct_full():
    assert u.mediation_pct(0.5, 0.0) == 100.0

def test_mediation_pct_none():
    assert u.mediation_pct(0.5, 0.5) == 0.0

def test_mediation_pct_half():
    assert np.isclose(u.mediation_pct(0.5, 0.25), 50.0)

def test_mediation_pct_nan_near_zero():
    assert np.isnan(u.mediation_pct(0.001, 0.0005))

def test_mediation_pct_suppression_negative():
    assert u.mediation_pct(0.3, 0.6) == -100.0


# ---------- load_matchup_phase1 (integration, skipped if parquet missing) ----------
def test_load_phase1_none_returns_full_frame():
    if not u.PQ_PATH.exists():
        return  # skip — parquet not present in test env
    df = u.load_matchup_phase1(columns=None, verbose=False)
    assert df.shape[0] > 0
    assert df.shape[1] >= 15
    # All PHASE1_FILTER_COLS must be non-NaN after filter
    for c in u.PHASE1_FILTER_COLS:
        assert df[c].notna().all(), f"{c} should be fully non-NaN post-filter"

def test_load_phase1_empty_list_returns_minimal_set():
    if not u.PQ_PATH.exists():
        return
    df = u.load_matchup_phase1(columns=[], verbose=False)
    expected = set(u.PHASE1_FILTER_COLS + ['year', 'month'])
    assert set(df.columns) == expected, f"unexpected col set: {set(df.columns) - expected}"


# ---------- runner ----------
if __name__ == '__main__':
    tests = [(k, v) for k, v in sorted(globals().items()) if k.startswith('test_') and callable(v)]
    failed = 0
    for name, t in tests:
        try:
            t()
            print(f"PASS {name}")
        except Exception as e:
            print(f"FAIL {name}")
            traceback.print_exc()
            failed += 1
    print(f"\n{len(tests) - failed}/{len(tests)} passed")
    sys.exit(1 if failed else 0)
