from __future__ import annotations

import argparse
from pathlib import Path

import xarray as xr
import json
from datetime import datetime, timezone


EXPECTED = {
    "physical": {
        "variables": ["thetao", "so", "mlotst"],
        "time_start_prefix": "2003-04",
        "time_end_prefix": "2024-08",
    },
    "sea_ice": {
        "variables": ["siconc", "sithick"],
        "time_start_prefix": "2003-04",
        "time_end_prefix": "2024-08",
    },
}


def timestamp() -> str:
    return datetime.now(timezone.utc).isoformat()


def write_json(path: str | Path, payload: dict) -> None:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2, sort_keys=True)
        handle.write("\n")


def choose_coord_name(candidates: list[str], available: list[str]) -> str | None:
    for name in candidates:
        if name in available:
            return name
    return None


def summarize_variable(ds: xr.Dataset, variable: str) -> dict[str, object]:
    da = ds[variable]
    summary: dict[str, object] = {
        "dims": list(da.dims),
        "shape": list(da.shape),
        "dtype": str(da.dtype),
    }
    try:
        summary["null_count"] = int(da.isnull().sum().item())
    except Exception:
        summary["null_count"] = None
    try:
        summary["min"] = float(da.min(skipna=True).item())
        summary["max"] = float(da.max(skipna=True).item())
    except Exception:
        summary["min"] = None
        summary["max"] = None
    return summary


def validate_dataset(group: str, path: Path) -> dict[str, object]:
    ds = xr.open_dataset(path)
    expected = EXPECTED[group]
    dims = list(ds.dims)
    coords = list(ds.coords)
    data_vars = list(ds.data_vars)

    time_name = choose_coord_name(["time", "time_counter"], coords)
    lat_name = choose_coord_name(["latitude", "lat", "nav_lat", "y"], coords)
    lon_name = choose_coord_name(["longitude", "lon", "nav_lon", "x"], coords)

    missing_variables = [var for var in expected["variables"] if var not in data_vars]
    variable_summaries = {
        var: summarize_variable(ds, var) for var in expected["variables"] if var in data_vars
    }

    result: dict[str, object] = {
        "path": str(path),
        "dims": dims,
        "coords": coords,
        "data_vars": data_vars,
        "missing_variables": missing_variables,
        "variable_summaries": variable_summaries,
        "time_coord": time_name,
        "lat_coord": lat_name,
        "lon_coord": lon_name,
    }

    if time_name is not None:
        time_values = ds[time_name].values
        result["time_count"] = int(ds.sizes[time_name])
        if len(time_values) > 0:
            start = str(time_values[0])
            end = str(time_values[-1])
            result["time_start"] = start
            result["time_end"] = end
            result["time_start_ok"] = start.startswith(expected["time_start_prefix"])
            result["time_end_ok"] = end.startswith(expected["time_end_prefix"])
    else:
        result["time_count"] = None
        result["time_start"] = None
        result["time_end"] = None
        result["time_start_ok"] = False
        result["time_end_ok"] = False

    if lat_name is not None:
        lat = ds[lat_name]
        try:
            result["lat_min"] = float(lat.min().item())
            result["lat_max"] = float(lat.max().item())
        except Exception:
            result["lat_min"] = None
            result["lat_max"] = None
    if lon_name is not None:
        lon = ds[lon_name]
        try:
            result["lon_min"] = float(lon.min().item())
            result["lon_max"] = float(lon.max().item())
        except Exception:
            result["lon_min"] = None
            result["lon_max"] = None

    result["open_ok"] = True
    result["valid"] = (
        result["open_ok"]
        and not missing_variables
        and result.get("time_start_ok", False)
        and result.get("time_end_ok", False)
    )
    ds.close()
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description="Validate monthly core Copernicus files before harmonization.")
    parser.add_argument("--physical", required=True)
    parser.add_argument("--sea-ice", required=True, dest="sea_ice")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    report = {
        "generated_utc": timestamp(),
        "physical": validate_dataset("physical", Path(args.physical)),
        "sea_ice": validate_dataset("sea_ice", Path(args.sea_ice)),
    }
    report["all_valid"] = bool(report["physical"]["valid"] and report["sea_ice"]["valid"])

    write_json(args.output, report)
    print(f"Wrote validation report to {args.output}")
    print(f"Overall valid: {report['all_valid']}")


if __name__ == "__main__":
    main()
