from __future__ import annotations

import argparse
from pathlib import Path

import pandas as pd
import json
from datetime import datetime, timezone


CLASS_COLUMNS = [
    "class_count__ocean",
    "class_count__phaeocystis",
    "class_count__cdom",
    "class_count__sediment",
    "class_count__coccolithophores",
    "class_count__diatoms",
]

FRACTION_COLUMNS = [
    "class_fraction__ocean",
    "class_fraction__phaeocystis",
    "class_fraction__cdom",
    "class_fraction__sediment",
    "class_fraction__coccolithophores",
    "class_fraction__diatoms",
]


def timestamp() -> str:
    return datetime.now(timezone.utc).isoformat()


def write_json(path: str | Path, payload: dict) -> None:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2, sort_keys=True)
        handle.write("\n")


def weighted_mean(values: pd.Series, weights: pd.Series) -> float | None:
    valid = values.notna() & weights.notna()
    if not valid.any():
        return None
    total_weight = float(weights[valid].sum())
    if total_weight == 0:
        return None
    return float((values[valid] * weights[valid]).sum() / total_weight)


def monthly_summary(group: pd.DataFrame) -> pd.Series:
    n_pixels = int(group["n_pixels"].sum())
    n_chlorophyll = int(group["n_chlorophyll"].sum())
    dominant_source = group.groupby("dominant_class")["n_pixels"].sum()
    dominant_class = str(dominant_source.idxmax()) if not dominant_source.empty else None
    dominant_fraction = float(dominant_source.max() / n_pixels) if n_pixels else None

    result: dict[str, object] = {
        "year": int(group["year"].iloc[0]),
        "month": int(group["month"].iloc[0]),
        "year_month": str(group["year_month"].iloc[0]),
        "n_days": int(len(group)),
        "n_pixels": n_pixels,
        "n_chlorophyll": n_chlorophyll,
        "chlorophyll_mean": weighted_mean(group["chlorophyll_mean"], group["n_chlorophyll"]),
        "chlorophyll_median_mean": weighted_mean(group["chlorophyll_median"], group["n_chlorophyll"]),
        "chlorophyll_std_mean": weighted_mean(group["chlorophyll_std"], group["n_chlorophyll"]),
        "chlorophyll_min": float(group["chlorophyll_min"].min()) if group["chlorophyll_min"].notna().any() else None,
        "chlorophyll_max": float(group["chlorophyll_max"].max()) if group["chlorophyll_max"].notna().any() else None,
        "latitude_min": float(group["latitude_min"].min()),
        "latitude_max": float(group["latitude_max"].max()),
        "longitude_min": float(group["longitude_min"].min()),
        "longitude_max": float(group["longitude_max"].max()),
        "dominant_class": dominant_class,
        "dominant_class_fraction": dominant_fraction,
    }

    for column in CLASS_COLUMNS:
        result[column] = int(group[column].sum())

    for column in FRACTION_COLUMNS:
        count_column = column.replace("fraction", "count")
        result[column] = float(result[count_column] / n_pixels) if n_pixels else None

    return pd.Series(result)


def main() -> None:
    parser = argparse.ArgumentParser(description="Aggregate daily PFT response summaries to monthly April-August response summaries.")
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--report", required=True)
    args = parser.parse_args()

    input_path = Path(args.input)
    frame = pd.read_parquet(input_path)
    frame = frame[frame["month"].between(4, 8)].copy()
    frame["year"] = frame["year"].astype(int)
    frame["month"] = frame["month"].astype(int)
    frame["year_month"] = frame["year_month"].astype(str)

    grouped = frame.sort_values(["year", "month", "day"]).groupby(
        ["year", "month", "year_month"], sort=True
    )
    monthly = pd.DataFrame([monthly_summary(group) for _, group in grouped])

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    monthly.to_parquet(output_path, index=False)

    write_json(
        args.report,
        {
            "generated_utc": timestamp(),
            "input_table": str(input_path),
            "output_table": str(output_path),
            "row_count": int(len(monthly)),
            "year_count": int(monthly["year"].nunique()),
            "years": sorted(int(value) for value in monthly["year"].unique().tolist()),
            "month_count": int(monthly["month"].nunique()),
            "months": sorted(int(value) for value in monthly["month"].unique().tolist()),
            "year_month_min": str(monthly["year_month"].min()),
            "year_month_max": str(monthly["year_month"].max()),
        },
    )
    print(f"Wrote monthly PFT response table to {output_path}")
    print(f"Wrote monthly PFT report to {args.report}")


if __name__ == "__main__":
    main()
