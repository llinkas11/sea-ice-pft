#!/usr/bin/env python3
# CMEMS OMI_CLIMATE_SI_ARCTIC_transport (area + volume transport, Fram Strait + Barents Sea).
import os
import sys
from pathlib import Path
import xarray as xr

sys.path.insert(0, os.environ.get("RF_PROJECT_ROOT", os.getcwd()))
from config import rf_data_root

OUT_DIR = rf_data_root() / "cmems_omi"
OUT_DIR.mkdir(parents=True, exist_ok=True)

DATASET_ID = "omi_climate_si_arctic_transport"

from copernicusmarine import get

print(f"Downloading {DATASET_ID}...")
result = get(
    dataset_id=DATASET_ID,
    output_directory=str(OUT_DIR),
    no_directories=True,
    overwrite=True,
    disable_progress_bar=True,
)
print("Download result:")
print(result)

# List what landed
print("\nFiles in", OUT_DIR)
for p in sorted(OUT_DIR.iterdir()):
    print(f"  {p.name}  {p.stat().st_size:,} bytes")

# Inspect the first NetCDF
ncs = sorted(OUT_DIR.glob("*.nc"))
if ncs:
    print(f"\nInspecting {ncs[0].name}")
    ds = xr.open_dataset(ncs[0])
    print(ds)
    print("\nTime range:", ds.time.values[0], "to", ds.time.values[-1])
    print("N timesteps:", len(ds.time))
