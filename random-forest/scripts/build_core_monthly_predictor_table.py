from __future__ import annotations

import argparse
from pathlib import Path

import pandas as pd
import xarray as xr

from scaffold_utils import timestamp, write_json


COORD_CANDIDATES = {
    "time": ["time", "time_counter"],
    "latitude": ["latitude", "lat", "nav_lat"],
    "longitude": ["longitude", "lon", "nav_lon"],
}

PHYSICAL_VARS = ["thetao", "so", "mlotst"]
SEA_ICE_VARS = ["siconc", "sithick"]
DEPTH_DIM_CANDIDATES = ["depth", "deptht", "depthu", "depthv", "depthw", "olevel", "lev", "z"]


def choose_name(candidates: list[str], available: list[str]) -> str | None:
    for candidate in candidates:
        if candidate in available:
            return candidate
    return None


def rename_standard_coords(ds: xr.Dataset) -> tuple[xr.Dataset, dict[str, str | None]]:
    coords = list(ds.coords)
    mapping: dict[str, str] = {}
    chosen: dict[str, str | None] = {}
    for standard_name, candidates in COORD_CANDIDATES.items():
        name = choose_name(candidates, coords)
        chosen[standard_name] = name
        if name is not None and name != standard_name:
            mapping[name] = standard_name
    if mapping:
        ds = ds.rename(mapping)
    return ds, chosen


def reduce_surface(da: xr.DataArray) -> tuple[xr.DataArray, dict[str, int]]:
    selections: dict[str, int] = {}
    for dim in da.dims:
        if dim in DEPTH_DIM_CANDIDATES:
            da = da.isel({dim: 0})
            selections[dim] = 0
    return da, selections


def prepare_dataset(ds: xr.Dataset, variables: list[str]) -> tuple[xr.Dataset, dict[str, dict[str, int]]]:
    surface_selection: dict[str, dict[str, int]] = {}
    prepared: dict[str, xr.DataArray] = {}
    for variable in variables:
        da = ds[variable]
        da, selections = reduce_surface(da)
        surface_selection[variable] = selections
        prepared[variable] = da
    out = xr.Dataset(prepared)
    return out, surface_selection


def can_interp_like(source: xr.Dataset, target: xr.Dataset) -> bool:
    required = {"time", "latitude", "longitude"}
    return required.issubset(source.coords) and required.issubset(target.coords)


def add_time_columns(frame: pd.DataFrame) -> pd.DataFrame:
    frame["time"] = pd.to_datetime(frame["time"])
    frame["year"] = frame["time"].dt.year.astype(int)
    frame["month"] = frame["time"].dt.month.astype(int)
    frame["year_month"] = frame["time"].dt.strftime("%Y%m")
    return frame


def summarize_nulls(frame: pd.DataFrame, variables: list[str]) -> dict[str, int]:
    return {variable: int(frame[variable].isna().sum()) for variable in variables}


def main() -> None:
    parser = argparse.ArgumentParser(description="Build a core monthly predictor parquet table from validated Copernicus NetCDF files.")
    parser.add_argument("--physical", required=True)
    parser.add_argument("--sea-ice", required=True, dest="sea_ice")
    parser.add_argument("--output", required=True)
    parser.add_argument("--report", required=True)
    args = parser.parse_args()

    physical_path = Path(args.physical)
    sea_ice_path = Path(args.sea_ice)

    physical_ds = xr.open_dataset(physical_path)
    sea_ice_ds = xr.open_dataset(sea_ice_path)

    physical_ds, physical_coords = rename_standard_coords(physical_ds)
    sea_ice_ds, sea_ice_coords = rename_standard_coords(sea_ice_ds)

    physical_prepared, physical_surface = prepare_dataset(physical_ds, PHYSICAL_VARS)
    sea_ice_prepared, sea_ice_surface = prepare_dataset(sea_ice_ds, SEA_ICE_VARS)

    interpolation_used = False
    if can_interp_like(sea_ice_prepared, physical_prepared):
        if not sea_ice_prepared["latitude"].equals(physical_prepared["latitude"]) or not sea_ice_prepared["longitude"].equals(physical_prepared["longitude"]):
            sea_ice_prepared = sea_ice_prepared.interp_like(physical_prepared)
            interpolation_used = True

    merged = xr.merge([physical_prepared, sea_ice_prepared], compat="override", join="inner")
    frame = merged.to_dataframe().reset_index()
    frame = add_time_columns(frame)

    columns = ["time", "year", "month", "year_month"]
    for coord in ["latitude", "longitude"]:
        if coord in frame.columns:
            columns.append(coord)
    columns.extend(PHYSICAL_VARS + SEA_ICE_VARS)
    frame = frame[columns]

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    frame.to_parquet(output_path, index=False)

    report = {
        "generated_utc": timestamp(),
        "physical_path": str(physical_path),
        "sea_ice_path": str(sea_ice_path),
        "output_table": str(output_path),
        "row_count": int(len(frame)),
        "columns": list(frame.columns),
        "time_start": str(frame["time"].min()),
        "time_end": str(frame["time"].max()),
        "year_count": int(frame["year"].nunique()),
        "years": sorted(int(value) for value in frame["year"].unique().tolist()),
        "month_count": int(frame["month"].nunique()),
        "months": sorted(int(value) for value in frame["month"].unique().tolist()),
        "null_counts": summarize_nulls(frame, PHYSICAL_VARS + SEA_ICE_VARS),
        "physical_coord_mapping": physical_coords,
        "sea_ice_coord_mapping": sea_ice_coords,
        "physical_surface_selection": physical_surface,
        "sea_ice_surface_selection": sea_ice_surface,
        "sea_ice_interpolated_to_physical_grid": interpolation_used,
    }
    write_json(args.report, report)

    physical_ds.close()
    sea_ice_ds.close()
    print(f"Wrote monthly predictor parquet table to {output_path}")
    print(f"Wrote predictor report to {args.report}")


if __name__ == "__main__":
    main()
