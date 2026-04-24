from __future__ import annotations

import argparse
from pathlib import Path

import pandas as pd

from scaffold_utils import timestamp, write_json


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Inner join the monthly PFT grid-cell response table with the monthly "
            "predictor table on (year, month, year_month, latitude, longitude). "
            "Produces the core spatially explicit matchup table for RF modeling."
        )
    )
    parser.add_argument(
        "--pft_gridcell",
        required=True,
        help="Path to core_monthly_pft_gridcell_table.parquet.",
    )
    parser.add_argument(
        "--predictor",
        required=True,
        help="Path to core_monthly_predictor_table_apr_aug.parquet.",
    )
    parser.add_argument("--output", required=True, help="Output parquet path.")
    parser.add_argument("--report", required=True, help="Output JSON report path.")
    args = parser.parse_args()

    pft_path = Path(args.pft_gridcell)
    predictor_path = Path(args.predictor)

    pft = pd.read_parquet(pft_path)
    predictor = pd.read_parquet(predictor_path)

    # Normalise join-key dtypes to be safe
    for frame in (pft, predictor):
        frame["year"] = frame["year"].astype(int)
        frame["month"] = frame["month"].astype(int)
        frame["year_month"] = frame["year_month"].astype(str)
        frame["latitude"] = frame["latitude"].astype(float)
        frame["longitude"] = frame["longitude"].astype(float)

    # Drop the `time` column from the predictor table — it is redundant with
    # year/month/year_month and has no equivalent in the PFT grid-cell table.
    if "time" in predictor.columns:
        predictor = predictor.drop(columns=["time"])

    join_keys = ["year", "month", "year_month", "latitude", "longitude"]

    merged = pft.merge(
        predictor,
        on=join_keys,
        how="inner",
        suffixes=("_pft", "_predictor"),
    )

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    merged.to_parquet(output_path, index=False)

    pft_year_months = set(pft["year_month"].unique())
    predictor_year_months = set(predictor["year_month"].unique())
    pft_only = sorted(pft_year_months - predictor_year_months)
    predictor_only = sorted(predictor_year_months - pft_year_months)

    joined_rows = int(len(merged))
    join_loss_fraction = (
        round(1.0 - joined_rows / len(pft), 4) if len(pft) > 0 else None
    )

    write_json(
        args.report,
        {
            "generated_utc": timestamp(),
            "pft_gridcell_table": str(pft_path),
            "predictor_table": str(predictor_path),
            "output_table": str(output_path),
            "join_keys": join_keys,
            "pft_rows": int(len(pft)),
            "predictor_rows": int(len(predictor)),
            "joined_rows": joined_rows,
            "join_loss_fraction": join_loss_fraction,
            "year_month_count": int(merged["year_month"].nunique()),
            "unique_cells": int(merged[["latitude", "longitude"]].drop_duplicates().shape[0]),
            "years": sorted(int(v) for v in merged["year"].unique().tolist()),
            "columns": list(merged.columns),
            "pft_only_year_months": pft_only,
            "predictor_only_year_months": predictor_only,
        },
    )

    print(f"Wrote spatial matchup table: {output_path}")
    print(
        f"  PFT rows: {len(pft):,}  |  Predictor rows: {len(predictor):,}  "
        f"|  Joined rows: {joined_rows:,}  |  Join loss: {join_loss_fraction}"
    )
    print(f"Wrote report: {args.report}")


if __name__ == "__main__":
    main()
