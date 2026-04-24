#!/usr/bin/env python3
# cumOct = cumulative flux from the most recent October through current month.
import os
import sys
from pathlib import Path
import numpy as np
import pandas as pd
import xarray as xr

sys.path.insert(0, os.environ.get("RF_PROJECT_ROOT", os.getcwd()))
from config import rf_data_root
sys.path.insert(0, str(Path(__file__).resolve().parent))
import probe_utils as u

OMI_NC = rf_data_root() / "cmems_omi" / "arctic_omi_si_transport_nordicseas_19910115_P20251101_R19912024.nc"
OUT_PARQUET = u.DATA_MODEL_DIR / "final-spatial-matchup-p3.parquet"
FLUX_FEATURES_CSV = u.DATA_MODEL_DIR / "fram_strait_flux_features.csv"

# ---- Step 1: extract Fram Strait flux time series ----
print(f"Reading {OMI_NC.name}")
ds = xr.open_dataset(OMI_NC)
fs = pd.DataFrame({
    "time":             ds.time.values,
    "ice_area_flux":    ds.SI_AT_FS_Reanalysis.values,    # area transport, FS
    "ice_volume_flux":  ds.SI_VT_FS_Reanalysis.values,    # volume transport, FS
})
fs["year"]  = fs["time"].dt.year
fs["month"] = fs["time"].dt.month
fs = fs.sort_values(["year", "month"]).reset_index(drop=True)
print(f"  {len(fs)} monthly timesteps from {fs.time.min()} to {fs.time.max()}")
print(f"  ice_area_flux:   mean {fs['ice_area_flux'].mean():.3e}  std {fs['ice_area_flux'].std():.3e}")
print(f"  ice_volume_flux: mean {fs['ice_volume_flux'].mean():.3e}  std {fs['ice_volume_flux'].std():.3e}")

# Sign convention check — CMEMS OMI uses negative = southward (export).
# Downstream interpretation assumes this, so assert it rather than
# discover it on a reviewer's rerun.
assert fs["ice_area_flux"].mean() < 0,   "ice_area_flux unexpectedly positive-mean — sign flipped upstream?"
assert fs["ice_volume_flux"].mean() < 0, "ice_volume_flux unexpectedly positive-mean — sign flipped upstream?"

# ---- Step 2: build flux features ----
# lag1, lag2 — simple pandas shift on sorted df
fs["ice_area_flux_lag1"]   = fs["ice_area_flux"].shift(1)
fs["ice_area_flux_lag2"]   = fs["ice_area_flux"].shift(2)
fs["ice_volume_flux_lag1"] = fs["ice_volume_flux"].shift(1)
fs["ice_volume_flux_lag2"] = fs["ice_volume_flux"].shift(2)

# cumulative since most-recent October: define water year starting Oct 1
# water_year(month) =  year+1 if month >= 10 else year
# Means: Oct-Dec 2014 and Jan-Sep 2015 all belong to water year 2015
fs["water_year"] = np.where(fs["month"] >= 10, fs["year"] + 1, fs["year"])
# Within each water year, cumsum in chronological order (already sorted).
# Position within water year: Oct=1, Nov=2, ..., Sep=12
fs["water_month"] = np.where(fs["month"] >= 10, fs["month"] - 9, fs["month"] + 3)
fs = fs.sort_values(["water_year", "water_month"]).reset_index(drop=True)
fs["ice_area_flux_cumOct"]   = fs.groupby("water_year")["ice_area_flux"].cumsum()
fs["ice_volume_flux_cumOct"] = fs.groupby("water_year")["ice_volume_flux"].cumsum()

# Null out cumOct for the first water year in the data. Its preceding Oct-Dec
# are not in the dataset (data start = Jan 1991), so cumsum from Jan 1991
# onward is a partial-year partial-sum, NOT a true Oct-through-current total.
# This matters for any future rebuild with different data coverage. For the
# current run the merged parquet starts 2003, so these rows never reach the
# training set anyway — but we fix the source so it doesn't silently bite later.
first_water_year = fs["water_year"].min()
first_wy_has_oct = ((fs["water_year"] == first_water_year) & (fs["water_month"] == 1)).any()
if not first_wy_has_oct:
    mask = fs["water_year"] == first_water_year
    fs.loc[mask, "ice_area_flux_cumOct"]   = np.nan
    fs.loc[mask, "ice_volume_flux_cumOct"] = np.nan
    print(f"  Nulled cumOct for {mask.sum()} rows in water_year {first_water_year} "
          f"(preceding October not in dataset)")

# Rename current-month columns for consistency with feature-family naming
fs = fs.rename(columns={
    "ice_area_flux":   "ice_area_flux_current",
    "ice_volume_flux": "ice_volume_flux_current",
})
feat_cols = [
    "ice_area_flux_current",   "ice_area_flux_lag1",   "ice_area_flux_lag2",   "ice_area_flux_cumOct",
    "ice_volume_flux_current", "ice_volume_flux_lag1", "ice_volume_flux_lag2", "ice_volume_flux_cumOct",
]
flux_df = fs[["year", "month"] + feat_cols].sort_values(["year", "month"]).reset_index(drop=True)
flux_df.to_csv(FLUX_FEATURES_CSV, index=False)
print(f"\nSaved flux feature table -> {FLUX_FEATURES_CSV}")
print(flux_df.head(15).to_string(index=False))
print("...")
print(flux_df.tail(5).to_string(index=False))

# Sanity: for a May row, cumOct should be the sum of Oct-Apr of the prior water year + May.
# E.g. water_year 2004: Oct 2003 + Nov 2003 + Dec 2003 + Jan 2004 + ... + May 2004 = cumOct value at May 2004.
check = flux_df[(flux_df.year == 2004) & (flux_df.month == 5)]
manual = flux_df[
    ((flux_df.year == 2003) & (flux_df.month.isin([10, 11, 12]))) |
    ((flux_df.year == 2004) & (flux_df.month.isin([1, 2, 3, 4, 5])))
]["ice_area_flux_current"].sum()
print(f"\nSanity check: May 2004 cumOct (area) = {check['ice_area_flux_cumOct'].values[0]:.4e}")
print(f"              manual sum over Oct2003..May2004 = {manual:.4e}")
assert np.isclose(check["ice_area_flux_cumOct"].values[0], manual), "cumOct logic mismatch"

# Invariant: for every water-year's first month (water_month=1 = October),
# cumOct MUST equal the current-month flux (no preceding months accumulated).
# Skip the first water year (it was nulled above) and post-nulled entries.
wm1 = flux_df.merge(
    fs[["year", "month", "water_year", "water_month"]],
    on=["year", "month"]
)
wm1 = wm1[(wm1["water_month"] == 1) & wm1["ice_area_flux_cumOct"].notna()]
bad = ~np.isclose(wm1["ice_area_flux_cumOct"], wm1["ice_area_flux_current"])
assert not bad.any(), (
    f"cumOct != current at {bad.sum()} Oct rows; "
    f"first offenders: {wm1.loc[bad, ['year','month']].head().to_dict('records')}"
)
print("  CumOct logic verified (sanity + water-month-1 invariant)")

# ---- Step 3: load Phase 2 parquet, merge flux features ----
print(f"\nLoading Phase 2 parquet {u.RF_EXPLORING3 / 'data_model/final-spatial-matchup-p2.parquet'}")
p2 = pd.read_parquet(u.RF_EXPLORING3 / "data_model/final-spatial-matchup-p2.parquet")
print(f"  {len(p2):,} rows")

p3 = p2.merge(flux_df, on=["year", "month"], how="left")
print(f"After merge: {len(p3):,} rows")

# Verify no unexpected NaN loss
missing = p3[feat_cols].isna().any(axis=1).sum()
print(f"Rows with ANY missing flux feature: {missing:,}")
# lag1/lag2/cumOct will be NaN for the earliest months of each water year
# Drop them because Phase 3 needs them all present
p3 = p3.dropna(subset=feat_cols)
print(f"After dropping lag/cum-NaN: {len(p3):,} rows")

# Year coverage check
print(f"Year range: {p3['year'].min()} to {p3['year'].max()}")

# ---- Step 4: save ----
p3.to_parquet(OUT_PARQUET, index=False)
print(f"\nWrote Phase 3 parquet -> {OUT_PARQUET}")
print(f"  shape: {p3.shape}")
print(f"  cols:  {p3.columns.tolist()}")
