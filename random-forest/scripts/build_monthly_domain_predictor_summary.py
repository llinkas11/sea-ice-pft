from __future__ import annotations

import argparse
from pathlib import Path

import pandas as pd
import json
from datetime import datetime, timezone


PREDICTOR_COLUMNS = ["thetao", "so", "mlotst", "siconc", "sithick"]


def timestamp() -> str:
    return datetime.now(timezone.utc).isoformat()


def write_json(path: str | Path, payload: dict) -> None:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2, sort_keys=True)
        handle.write("\n")


def summarize_group(group: pd.DataFrame) -> pd.Series:
    result: dict[str, object] = {
        "year": int(group["year"].iloc[0]),
        "month": int(group["month"].iloc[0]),
        "year_month": str(group["year_month"].iloc[0]),
        "n_grid_cells": int(len(group)),
    }

    for column in PREDICTOR_COLUMNS:
        result[f"{column}_mean"] = float(group[column].mean(skipna=True)) if group[column].notna().any() else None
        result[f"{column}_median"] = float(group[column].median(skipna=True)) if group[column].notna().any() else None
        result[f"{column}_min"] = float(group[column].min(skipna=True)) if group[column].notna().any() else None
        result[f"{column}_max"] = float(group[column].max(skipna=True)) if group[column].notna().any() else None
        result[f"{column}_null_count"] = int(group[column].isna().sum())

    return pd.Series(result)


def main() -> None:
    parser = argparse.ArgumentParser(description="Aggregate the April-August monthly predictor table to one row per year_month over the study domain.")
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--report", required=True)
    args = parser.parse_args()

    input_path = Path(args.input)
    frame = pd.read_parquet(input_path)
    frame["year"] = frame["year"].astype(int)
    frame["month"] = frame["month"].astype(int)
    frame["year_month"] = frame["year_month"].astype(str)

    grouped = frame.sort_values(["year", "month"]).groupby(["year", "month", "year_month"], sort=True)
    summary = pd.DataFrame([summarize_group(group) for _, group in grouped])

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    summary.to_parquet(output_path, index=False)

    write_json(
        args.report,
        {
            "generated_utc": timestamp(),
            "input_table": str(input_path),
            "output_table": str(output_path),
            "row_count": int(len(summary)),
            "year_count": int(summary["year"].nunique()),
            "years": sorted(int(value) for value in summary["year"].unique().tolist()),
            "month_count": int(summary["month"].nunique()),
            "months": sorted(int(value) for value in summary["month"].unique().tolist()),
            "year_month_min": str(summary["year_month"].min()),
            "year_month_max": str(summary["year_month"].max()),
        },
    )
    print(f"Wrote monthly domain predictor summary to {output_path}")
    print(f"Wrote predictor summary report to {args.report}")


if __name__ == "__main__":
    main()
