from __future__ import annotations

import argparse
from pathlib import Path

import pandas as pd

from scaffold_utils import timestamp, write_json

KNOWN_CLASSES = [
    "ocean",
    "phaeocystis",
    "cdom",
    "sediment",
    "coccolithophores",
    "diatoms",
]


def summarize_file(parquet_path: Path) -> dict[str, object]:
    frame = pd.read_parquet(
        parquet_path,
        columns=["date", "year", "longitude", "latitude", "pixel_class", "chlorophyll_guesses"],
    )
    frame["pixel_class"] = frame["pixel_class"].fillna("missing")
    class_counts = frame["pixel_class"].value_counts()
    chlorophyll = frame["chlorophyll_guesses"].dropna()

    record: dict[str, object] = {
        "date": parquet_path.stem,
        "year": int(str(parquet_path.stem)[:4]),
        "month": int(str(parquet_path.stem)[4:6]),
        "day": int(str(parquet_path.stem)[6:8]),
        "year_month": str(parquet_path.stem)[:6],
        "source_file": str(parquet_path),
        "n_pixels": int(len(frame)),
        "n_chlorophyll": int(frame["chlorophyll_guesses"].notna().sum()),
        "chlorophyll_mean": float(chlorophyll.mean()) if not chlorophyll.empty else None,
        "chlorophyll_median": float(chlorophyll.median()) if not chlorophyll.empty else None,
        "chlorophyll_std": float(chlorophyll.std()) if len(chlorophyll) > 1 else None,
        "chlorophyll_min": float(chlorophyll.min()) if not chlorophyll.empty else None,
        "chlorophyll_max": float(chlorophyll.max()) if not chlorophyll.empty else None,
        "longitude_min": float(frame["longitude"].min()),
        "longitude_max": float(frame["longitude"].max()),
        "latitude_min": float(frame["latitude"].min()),
        "latitude_max": float(frame["latitude"].max()),
        "n_classes_observed": int(class_counts.size),
        "dominant_class": str(class_counts.idxmax()) if not class_counts.empty else None,
        "dominant_class_fraction": float(class_counts.iloc[0] / len(frame)) if not class_counts.empty else None,
    }

    for name in KNOWN_CLASSES:
        count = int(class_counts.get(name, 0))
        record[f"class_count__{name}"] = count
        record[f"class_fraction__{name}"] = float(count / len(frame)) if len(frame) else None

    other_classes = sorted(name for name in class_counts.index.tolist() if name not in KNOWN_CLASSES)
    record["other_classes"] = ",".join(other_classes) if other_classes else ""
    return record


def main() -> None:
    parser = argparse.ArgumentParser(description="Build a daily PFT response summary table from extracted parquet files.")
    parser.add_argument("--pft-dir", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--report", required=True)
    args = parser.parse_args()

    pft_dir = Path(args.pft_dir)
    parquet_paths = sorted(pft_dir.rglob("*.parquet"))
    if not parquet_paths:
        raise SystemExit("No extracted PFT parquet files were found. Run make extract-pfts first.")

    records = [summarize_file(path) for path in parquet_paths]
    summary = pd.DataFrame.from_records(records).sort_values("date").reset_index(drop=True)
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    summary.to_parquet(output_path, index=False)

    write_json(
        args.report,
        {
            "generated_utc": timestamp(),
            "status": "built",
            "output_table": str(output_path),
            "file_count": int(len(summary)),
            "date_min": str(summary["date"].min()),
            "date_max": str(summary["date"].max()),
            "years": sorted(int(year) for year in summary["year"].unique().tolist()),
            "months": sorted(int(month) for month in summary["month"].unique().tolist()),
            "total_pixels": int(summary["n_pixels"].sum()),
            "total_non_null_chlorophyll": int(summary["n_chlorophyll"].sum()),
            "known_classes": KNOWN_CLASSES,
        },
    )
    print(f"Wrote daily response summary table to {output_path}")


if __name__ == "__main__":
    main()
