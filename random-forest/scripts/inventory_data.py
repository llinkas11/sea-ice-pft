from __future__ import annotations

import argparse
from pathlib import Path

from scaffold_utils import timestamp, write_json


def list_files(path: Path) -> list[str]:
    if not path.exists():
        return []
    return sorted(str(item.name) for item in path.iterdir() if item.is_file())


def main() -> None:
    parser = argparse.ArgumentParser(description="Inventory data directories for the project scaffold.")
    parser.add_argument("--pft-zip-dir", required=True)
    parser.add_argument("--copernicus-dir", required=True)
    parser.add_argument("--insitu-dir", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    pft_zip_dir = Path(args.pft_zip_dir)
    copernicus_dir = Path(args.copernicus_dir)
    insitu_dir = Path(args.insitu_dir)

    payload = {
        "generated_utc": timestamp(),
        "pft_zip_count": len(list(pft_zip_dir.glob("Arctic_PFTs_*.zip"))),
        "pft_archives": sorted(path.name for path in pft_zip_dir.glob("Arctic_PFTs_*.zip")),
        "extracted_parquet_count": sum(1 for _ in pft_zip_dir.parent.joinpath("pft_daily_parquet").rglob("*.parquet")),
        "copernicus": {
            "physics": list_files(copernicus_dir / "physics"),
            "sea_ice": list_files(copernicus_dir / "sea_ice"),
            "biogeochemistry": list_files(copernicus_dir / "biogeochemistry"),
        },
        "insitu_files": list_files(insitu_dir),
    }
    write_json(args.output, payload)
    print(f"Wrote dataset inventory to {args.output}")


if __name__ == "__main__":
    main()
