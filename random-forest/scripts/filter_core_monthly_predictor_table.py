from __future__ import annotations

import argparse
from pathlib import Path

import pandas as pd

from scaffold_utils import timestamp, write_json


def main() -> None:
    parser = argparse.ArgumentParser(description="Filter the core monthly predictor table to the April-August PFT observation window.")
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--report", required=True)
    args = parser.parse_args()

    input_path = Path(args.input)
    frame = pd.read_parquet(input_path)
    filtered = frame[frame["month"].between(4, 8)].copy()

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    filtered.to_parquet(output_path, index=False)

    write_json(
        args.report,
        {
            "generated_utc": timestamp(),
            "input_table": str(input_path),
            "output_table": str(output_path),
            "input_row_count": int(len(frame)),
            "output_row_count": int(len(filtered)),
            "year_count": int(filtered["year"].nunique()),
            "years": sorted(int(value) for value in filtered["year"].unique().tolist()),
            "month_count": int(filtered["month"].nunique()),
            "months": sorted(int(value) for value in filtered["month"].unique().tolist()),
            "year_month_min": str(filtered["year_month"].min()),
            "year_month_max": str(filtered["year_month"].max()),
            "null_counts": {column: int(filtered[column].isna().sum()) for column in filtered.columns if column not in {"time", "year", "month", "year_month", "latitude", "longitude"}},
        },
    )
    print(f"Wrote April-August predictor table to {output_path}")
    print(f"Wrote predictor filter report to {args.report}")


if __name__ == "__main__":
    main()
