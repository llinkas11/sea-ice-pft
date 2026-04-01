from __future__ import annotations

import argparse
import zipfile
from pathlib import Path
from typing import Iterable

from scaffold_utils import ensure_dir, timestamp, write_json


def parse_years(raw: str | None) -> set[str]:
    if not raw:
        return set()
    return {token.strip() for token in raw.split(",") if token.strip()}


def iter_archives(input_dir: Path, selected_years: set[str]) -> Iterable[Path]:
    for archive in sorted(input_dir.glob("Arctic_PFTs_*.zip")):
        year = archive.stem.split("_")[-1]
        if selected_years and year not in selected_years:
            continue
        yield archive


def main() -> None:
    parser = argparse.ArgumentParser(description="Extract Ardyna PFT parquet archives into year directories.")
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--manifest", required=True)
    parser.add_argument(
        "--years",
        help="Comma-separated year list to extract, for example 2003,2004. Default is all available years.",
    )
    args = parser.parse_args()

    input_dir = Path(args.input)
    output_dir = ensure_dir(args.output)
    selected_years = parse_years(args.years)
    archives = list(iter_archives(input_dir, selected_years))

    if not archives:
        raise SystemExit("No matching PFT zip archives were found for extraction.")

    extracted_files = 0
    skipped_files = 0
    extracted_years: list[str] = []
    year_counts: dict[str, int] = {}
    archive_summaries: list[dict[str, object]] = []

    for archive in archives:
        year = archive.stem.split("_")[-1]
        year_dir = ensure_dir(output_dir / year)
        extracted_years.append(year)

        with zipfile.ZipFile(archive) as handle:
            members = [name for name in handle.namelist() if name.endswith(".parquet")]
            archive_summaries.append(
                {
                    "archive": archive.name,
                    "year": year,
                    "member_count": len(members),
                    "sample_members": members[:5],
                }
            )
            year_counts[year] = len(members)

            for member in members:
                destination = year_dir / Path(member).name
                if destination.exists():
                    skipped_files += 1
                    continue
                with handle.open(member) as source, destination.open("wb") as target:
                    target.write(source.read())
                extracted_files += 1

    write_json(
        args.manifest,
        {
            "generated_utc": timestamp(),
            "mode": "extracted",
            "archive_count": len(archives),
            "output_directory": str(output_dir),
            "selected_years": extracted_years,
            "archive_summaries": archive_summaries,
            "per_year_member_count": year_counts,
            "extracted_file_count": extracted_files,
            "skipped_existing_file_count": skipped_files,
        },
    )
    print(f"Wrote PFT extraction manifest to {args.manifest}")
    print(f"Extracted {extracted_files} parquet files and skipped {skipped_files} existing files")


if __name__ == "__main__":
    main()
