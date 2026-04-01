from __future__ import annotations

import argparse
from pathlib import Path

import pandas as pd
import json
from datetime import datetime, timezone


def timestamp() -> str:
    return datetime.now(timezone.utc).isoformat()


def write_json(path: str | Path, payload: dict) -> None:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2, sort_keys=True)
        handle.write("\n")


def main() -> None:
    parser = argparse.ArgumentParser(description="Join monthly PFT response summaries with monthly domain-level predictor summaries on year_month.")
    parser.add_argument("--response", required=True)
    parser.add_argument("--predictors", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--report", required=True)
    args = parser.parse_args()

    response_path = Path(args.response)
    predictors_path = Path(args.predictors)

    response = pd.read_parquet(response_path)
    predictors = pd.read_parquet(predictors_path)
    response["year_month"] = response["year_month"].astype(str)
    predictors["year_month"] = predictors["year_month"].astype(str)

    merged = response.merge(
        predictors,
        on=["year", "month", "year_month"],
        how="inner",
        suffixes=("_response", "_predictor"),
    )

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    merged.to_parquet(output_path, index=False)

    write_json(
        args.report,
        {
            "generated_utc": timestamp(),
            "response_table": str(response_path),
            "predictor_table": str(predictors_path),
            "output_table": str(output_path),
            "response_rows": int(len(response)),
            "predictor_rows": int(len(predictors)),
            "joined_rows": int(len(merged)),
            "response_only_year_months": sorted(set(response["year_month"]) - set(predictors["year_month"])),
            "predictor_only_year_months": sorted(set(predictors["year_month"]) - set(response["year_month"])),
        },
    )
    print(f"Wrote joined monthly domain table to {output_path}")
    print(f"Wrote join report to {args.report}")


if __name__ == "__main__":
    main()
