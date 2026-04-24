from __future__ import annotations

# Requires scipy >= 1.6 for KDTree workers parameter.
# If scipy is not yet installed in the Bowdoin venv:
#   source .venv/bin/activate && pip install scipy

import argparse
import calendar
import sys
from pathlib import Path

import numpy as np
import pandas as pd
from scipy.spatial import KDTree

from scaffold_utils import timestamp, write_json

KNOWN_CLASSES = [
    "ocean",
    "phaeocystis",
    "cdom",
    "sediment",
    "coccolithophores",
    "diatoms",
]

DEFAULT_MONTHS = [4, 5, 6, 7, 8]


def normalize_longitudes(longitudes: np.ndarray) -> np.ndarray:
    return ((longitudes + 180.0) % 360.0) - 180.0


def latlon_to_unit_xyz(latitudes: np.ndarray, longitudes: np.ndarray) -> np.ndarray:
    lat_radians = np.deg2rad(latitudes)
    lon_radians = np.deg2rad(normalize_longitudes(longitudes))
    cos_lat = np.cos(lat_radians)
    return np.column_stack(
        [
            cos_lat * np.cos(lon_radians),
            cos_lat * np.sin(lon_radians),
            np.sin(lat_radians),
        ]
    )


def build_reference_grid(
    predictor_path: Path,
) -> tuple[np.ndarray, np.ndarray, np.ndarray, KDTree]:
    """
    Return (lats, lons, xyz, KDTree) from the unique grid cells in the predictor
    table. The KDTree is built in 3D unit-sphere Cartesian space so nearest-cell
    assignment is geographically meaningful near the pole and across the dateline.
    lats and lons are parallel arrays of the reference cell centres.
    """
    frame = pd.read_parquet(predictor_path, columns=["latitude", "longitude"])
    grid = (
        frame[["latitude", "longitude"]]
        .drop_duplicates()
        .sort_values(["latitude", "longitude"])
        .reset_index(drop=True)
    )
    lats = grid["latitude"].to_numpy(dtype=np.float64)
    lons = normalize_longitudes(grid["longitude"].to_numpy(dtype=np.float64))
    xyz = latlon_to_unit_xyz(lats, lons)
    tree = KDTree(xyz)
    return lats, lons, xyz, tree


def snap_to_grid(
    pixel_lats: np.ndarray,
    pixel_lons: np.ndarray,
    lats: np.ndarray,
    lons: np.ndarray,
    xyz: np.ndarray,
    tree: KDTree,
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """
    Return (lat_cell, lon_cell, snap_distance_km) arrays by querying the KDTree.
    workers=-1 uses all available CPUs (scipy >= 1.6).
    """
    coords_xyz = latlon_to_unit_xyz(pixel_lats, pixel_lons)
    _, indices = tree.query(coords_xyz, workers=-1)

    # Convert the matched unit vectors to great-circle distance.
    matched_xyz = xyz[indices]
    dots = np.einsum("ij,ij->i", coords_xyz, matched_xyz)
    central_angle = np.arccos(np.clip(dots, -1.0, 1.0))
    snap_distance_km = 6371.0 * central_angle

    return lats[indices], lons[indices], snap_distance_km


def aggregate_cell_month(snapped: pd.DataFrame, expected_days: int) -> pd.DataFrame:
    """
    Aggregate one (year, month) slice of snapped PFT pixels to one row per
    (lat_cell, lon_cell).  All operations are vectorised via pandas groupby.
    """
    snapped = snapped.copy()
    snapped["date"] = snapped["date"].astype(str)
    snapped["pixel_class"] = snapped["pixel_class"].fillna("missing")

    # ── Coverage ─────────────────────────────────────────────────────────────
    coverage = (
        snapped.groupby(["lat_cell", "lon_cell"], sort=False)
        .agg(
            n_days_observed=("date", "nunique"),
            n_pixels_total=("date", "count"),
        )
        .reset_index()
    )
    coverage["n_days_expected"] = int(expected_days)
    coverage["day_coverage_fraction"] = (
        coverage["n_days_observed"] / coverage["n_days_expected"]
    )

    # ── Chlorophyll ───────────────────────────────────────────────────────────
    chl_group = snapped.groupby(["lat_cell", "lon_cell"], sort=False)["chlorophyll_guesses"]
    chl_agg = pd.DataFrame(
        {
            "n_chlorophyll": chl_group.count(),
            "chlorophyll_mean": chl_group.mean(),
            "chlorophyll_median": chl_group.median(),
            "chlorophyll_std": chl_group.std(),
        }
    ).reset_index()

    # ── Snap-distance diagnostics ─────────────────────────────────────────────
    snap_group = snapped.groupby(["lat_cell", "lon_cell"], sort=False)["snap_distance_km"]
    snap_agg = pd.DataFrame(
        {
            "snap_distance_km_mean": snap_group.mean(),
            "snap_distance_km_median": snap_group.median(),
            "snap_distance_km_max": snap_group.max(),
        }
    ).reset_index()

    # ── Class fractions ───────────────────────────────────────────────────────
    class_counts = (
        snapped.groupby(["lat_cell", "lon_cell", "pixel_class"], sort=False)
        .size()
        .reset_index(name="count")
    )
    # Merge total pixel count so we can compute fractions
    class_counts = class_counts.merge(
        coverage[["lat_cell", "lon_cell", "n_pixels_total"]],
        on=["lat_cell", "lon_cell"],
        how="left",
    )
    class_counts["fraction"] = class_counts["count"] / class_counts["n_pixels_total"]

    # Dominant class (across all classes including "missing")
    dominant = (
        class_counts.sort_values("count", ascending=False)
        .groupby(["lat_cell", "lon_cell"], sort=False)
        .first()[["pixel_class", "fraction"]]
        .rename(
            columns={
                "pixel_class": "dominant_class",
                "fraction": "dominant_class_fraction",
            }
        )
        .reset_index()
    )

    # Pivot to one column per known class fraction
    known_mask = class_counts["pixel_class"].isin(KNOWN_CLASSES)
    fracs_pivot = (
        class_counts[known_mask]
        .pivot_table(
            index=["lat_cell", "lon_cell"],
            columns="pixel_class",
            values="fraction",
            fill_value=0.0,
        )
        .reset_index()
    )
    fracs_pivot.columns.name = None
    fracs_pivot = fracs_pivot.rename(
        columns={name: f"class_fraction__{name}" for name in KNOWN_CLASSES if name in fracs_pivot.columns}
    )
    # Guarantee all six columns exist even if a class never appeared this month
    for name in KNOWN_CLASSES:
        col = f"class_fraction__{name}"
        if col not in fracs_pivot.columns:
            fracs_pivot[col] = 0.0

    # ── Merge all aggregations ────────────────────────────────────────────────
    result = coverage
    result = result.merge(chl_agg, on=["lat_cell", "lon_cell"], how="left")
    result = result.merge(snap_agg, on=["lat_cell", "lon_cell"], how="left")
    result = result.merge(fracs_pivot, on=["lat_cell", "lon_cell"], how="left")
    result = result.merge(dominant, on=["lat_cell", "lon_cell"], how="left")

    return result


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Snap daily PFT pixels to the TOPAZ4 reference grid and aggregate "
            "to monthly per-grid-cell PFT response statistics (April-August)."
        )
    )
    parser.add_argument(
        "--pft_daily_dir",
        required=True,
        help="Root directory of extracted daily PFT parquets (data_raw/pft_daily_parquet/).",
    )
    parser.add_argument(
        "--reference_grid",
        required=True,
        help=(
            "Monthly predictor parquet used to define the reference grid "
            "(core_monthly_predictor_table_apr_aug.parquet)."
        ),
    )
    parser.add_argument("--output", required=True, help="Output parquet path.")
    parser.add_argument("--report", required=True, help="Output JSON report path.")
    parser.add_argument(
        "--min_days",
        type=int,
        default=1,
        help="Minimum days observed to retain a cell-month (default 1).",
    )
    parser.add_argument(
        "--months",
        type=int,
        nargs="+",
        default=DEFAULT_MONTHS,
        help="Months to include (default: 4 5 6 7 8).",
    )
    args = parser.parse_args()

    pft_dir = Path(args.pft_daily_dir)
    reference_path = Path(args.reference_grid)

    if not pft_dir.is_dir():
        sys.exit(f"PFT daily directory not found: {pft_dir}")
    if not reference_path.is_file():
        sys.exit(f"Reference grid parquet not found: {reference_path}")

    print(f"Building reference grid KD-tree from {reference_path}", flush=True)
    lats, lons, xyz, tree = build_reference_grid(reference_path)
    print(f"Reference grid: {len(lats):,} unique cells", flush=True)

    months_set = set(args.months)

    year_dirs = sorted(p for p in pft_dir.iterdir() if p.is_dir() and p.name.isdigit())
    if not year_dirs:
        sys.exit(f"No year subdirectories found under {pft_dir}")

    all_monthly_frames: list[pd.DataFrame] = []
    total_daily_files_read = 0
    total_pixels_read = 0

    for year_dir in year_dirs:
        year = int(year_dir.name)

        # Group daily parquet files by month
        month_files: dict[int, list[Path]] = {}
        for parquet_path in sorted(year_dir.glob("*.parquet")):
            stem = parquet_path.stem  # e.g. "20030415"
            if len(stem) < 8:
                continue
            try:
                month = int(stem[4:6])
            except ValueError:
                continue
            if month not in months_set:
                continue
            month_files.setdefault(month, []).append(parquet_path)

        for month in sorted(month_files.keys()):
            paths = month_files[month]
            print(
                f"  {year}-{month:02d}: reading {len(paths)} daily files ...",
                flush=True,
            )

            daily_frames: list[pd.DataFrame] = []
            for path in paths:
                df = pd.read_parquet(
                    path,
                    columns=["date", "latitude", "longitude", "pixel_class", "chlorophyll_guesses"],
                )
                daily_frames.append(df)
                total_daily_files_read += 1
                total_pixels_read += len(df)

            if not daily_frames:
                continue

            month_df = pd.concat(daily_frames, ignore_index=True)

            # Snap pixels to reference grid
            lat_cells, lon_cells, snap_distance_km = snap_to_grid(
                month_df["latitude"].to_numpy(dtype=np.float64),
                month_df["longitude"].to_numpy(dtype=np.float64),
                lats,
                lons,
                xyz,
                tree,
            )
            month_df["lat_cell"] = lat_cells
            month_df["lon_cell"] = lon_cells
            month_df["snap_distance_km"] = snap_distance_km

            # Aggregate to one row per grid cell
            expected_days = calendar.monthrange(year, month)[1]
            cell_month = aggregate_cell_month(month_df, expected_days=expected_days)

            # Apply minimum-days filter
            cell_month = cell_month[cell_month["n_days_observed"] >= args.min_days].copy()

            # Add temporal join keys; rename cell coords to match predictor table schema
            cell_month.insert(0, "year_month", f"{year}{month:02d}")
            cell_month.insert(0, "month", month)
            cell_month.insert(0, "year", year)
            cell_month = cell_month.rename(
                columns={"lat_cell": "latitude", "lon_cell": "longitude"}
            )

            all_monthly_frames.append(cell_month)
            print(
                f"    → {len(cell_month):,} cell-months retained (min_days={args.min_days})",
                flush=True,
            )

    if not all_monthly_frames:
        sys.exit("No cell-month data produced. Check --pft_daily_dir contents and --months filter.")

    result = pd.concat(all_monthly_frames, ignore_index=True)

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    result.to_parquet(output_path, index=False)

    unique_cells = int(result[["latitude", "longitude"]].drop_duplicates().shape[0])
    report = {
        "generated_utc": timestamp(),
        "pft_daily_dir": str(pft_dir),
        "reference_grid": str(reference_path),
        "output_table": str(output_path),
        "min_days_threshold": args.min_days,
        "months_included": sorted(args.months),
        "total_daily_files_read": total_daily_files_read,
        "total_pixels_read": total_pixels_read,
        "row_count": int(len(result)),
        "year_count": int(result["year"].nunique()),
        "years": sorted(int(v) for v in result["year"].unique().tolist()),
        "year_month_count": int(result["year_month"].nunique()),
        "year_month_min": str(result["year_month"].min()),
        "year_month_max": str(result["year_month"].max()),
        "unique_cells": unique_cells,
        "reference_grid_cells": int(len(lats)),
        "snap_distance_km_summary": {
            "mean": float(result["snap_distance_km_mean"].mean()),
            "median": float(result["snap_distance_km_median"].median()),
            "max": float(result["snap_distance_km_max"].max()),
        },
        "day_coverage_fraction_summary": {
            "mean": float(result["day_coverage_fraction"].mean()),
            "median": float(result["day_coverage_fraction"].median()),
            "min": float(result["day_coverage_fraction"].min()),
        },
        "columns": list(result.columns),
    }
    write_json(args.report, report)

    print(f"Wrote PFT grid-cell monthly table: {output_path}")
    print(
        f"  Rows: {len(result):,}  |  Year-months: {result['year_month'].nunique()}  "
        f"|  Unique cells: {unique_cells:,}"
    )
    print(f"Wrote report: {args.report}")


if __name__ == "__main__":
    main()
