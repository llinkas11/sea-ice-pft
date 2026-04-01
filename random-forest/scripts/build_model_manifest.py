from __future__ import annotations

import argparse
import csv
from collections import Counter
from pathlib import Path

import pyarrow.parquet as pq

from scaffold_utils import ensure_dir, timestamp, write_json, write_text


def sample_schema(parquet_paths: list[Path]) -> dict[str, object]:
    if not parquet_paths:
        return {"columns": [], "row_count_example": 0}
    sample = pq.ParquetFile(parquet_paths[0])
    return {
        "sample_file": str(parquet_paths[0]),
        "columns": sample.schema.names,
        "row_count_example": sample.metadata.num_rows,
    }


def choose_holdout_year(year_counts: Counter[str]) -> str | None:
    if not year_counts:
        return None
    full_years = sorted(year for year, count in year_counts.items() if count >= 153)
    if full_years:
        return full_years[-1]
    return sorted(year_counts)[-1]


def count_predictor_files(feature_root: Path, predictors: list[str]) -> dict[str, int]:
    counts: dict[str, int] = {}
    for predictor in predictors:
        counts[predictor] = sum(1 for path in (feature_root / predictor).rglob("*") if path.is_file())
    return counts


def main() -> None:
    parser = argparse.ArgumentParser(description="Create model-family metadata from extracted PFT parquet files.")
    parser.add_argument("--model-family", choices=["core", "expanded"], required=True)
    parser.add_argument("--pft-dir", required=True)
    parser.add_argument("--feature-dir", required=True)
    parser.add_argument("--model-table-dir", required=True)
    parser.add_argument("--matchup-dir", required=True)
    parser.add_argument("--config-dir", required=True)
    parser.add_argument("--report-dir", required=True)
    args = parser.parse_args()

    model_family = args.model_family
    pft_dir = Path(args.pft_dir)
    model_table_dir = ensure_dir(args.model_table_dir)
    matchup_dir = ensure_dir(args.matchup_dir)
    config_dir = ensure_dir(args.config_dir)
    report_dir = ensure_dir(args.report_dir)
    feature_root = Path(args.feature_dir)

    predictors = ["physics", "sea_ice"]
    if model_family == "expanded":
        predictors.append("biogeochemistry")

    manifest_path = model_table_dir / f"{model_family}_model_manifest.json"
    split_path = config_dir / f"{model_family}_time_split_plan.json"
    matchup_note = matchup_dir / f"{model_family}_matchup_plan.txt"
    inventory_csv_path = report_dir / f"{model_family}_pft_file_inventory.csv"
    predictor_file_counts = count_predictor_files(feature_root, predictors)

    parquet_paths = sorted(pft_dir.rglob("*.parquet"))
    schema_summary = sample_schema(parquet_paths)

    year_counts: Counter[str] = Counter()
    month_counts: Counter[str] = Counter()
    inventory_rows: list[dict[str, object]] = []
    total_rows = 0

    for parquet_path in parquet_paths:
        stem = parquet_path.stem
        if len(stem) != 8 or not stem.isdigit():
            continue
        year = stem[:4]
        month = stem[4:6]
        metadata = pq.ParquetFile(parquet_path).metadata
        row_count = metadata.num_rows
        total_rows += row_count
        year_counts[year] += 1
        month_counts[month] += 1
        inventory_rows.append(
            {
                "date": stem,
                "year": year,
                "month": month,
                "path": str(parquet_path),
                "rows": row_count,
            }
        )

    with inventory_csv_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=["date", "year", "month", "path", "rows"])
        writer.writeheader()
        writer.writerows(inventory_rows)

    holdout_year = choose_holdout_year(year_counts)

    write_json(
        manifest_path,
        {
            "generated_utc": timestamp(),
            "model_family": model_family,
            "response_dataset": str(pft_dir),
            "predictor_root": str(feature_root),
            "predictor_groups": predictors,
            "predictor_file_counts": predictor_file_counts,
            "predictor_status": "ready" if all(count > 0 for count in predictor_file_counts.values()) else "pending_data",
            "targets": ["pixel_class", "chlorophyll_guesses"],
            "pft_summary": {
                "file_count": len(inventory_rows),
                "total_rows": total_rows,
                "years": sorted(year_counts),
                "files_per_year": dict(sorted(year_counts.items())),
                "files_per_month": dict(sorted(month_counts.items())),
                "schema": schema_summary,
                "inventory_csv": str(inventory_csv_path),
            },
            "intended_outputs": {
                "response_summary_table": f"{model_family}_response_daily_summary.parquet",
                "table": f"{model_family}_model_table.parquet",
                "splits": split_path.name,
            },
        },
    )

    write_json(
        split_path,
        {
            "generated_utc": timestamp(),
            "model_family": model_family,
            "strategy": "grouped temporal split",
            "group_column": "year_month",
            "holdout": holdout_year,
            "training_years": [year for year in sorted(year_counts) if year != holdout_year],
            "warning": "Do not randomly split rows.",
        },
    )

    write_text(
        matchup_note,
        f"{model_family.title()} model matchup plan\n"
        f"- Response: Ardyna PFT daily product\n"
        f"- Predictors: {', '.join(predictors)}\n"
        f"- Extracted parquet files discovered: {len(inventory_rows)}\n"
        f"- Suggested held-out year: {holdout_year or 'none available yet'}\n"
        "- Restrict to April-August overlap window\n"
        "- Preserve time-aware partitioning\n",
    )
    print(f"Wrote {model_family} model scaffold files")


if __name__ == "__main__":
    main()
