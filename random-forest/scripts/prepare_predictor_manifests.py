from __future__ import annotations

import argparse
from pathlib import Path

from scaffold_utils import timestamp, write_json


def describe(path: Path) -> dict[str, object]:
    files = sorted(item.name for item in path.glob("*") if item.is_file())
    return {"directory": str(path), "file_count": len(files), "files": files}


def main() -> None:
    parser = argparse.ArgumentParser(description="Summarize available Copernicus predictor directories.")
    parser.add_argument("--copernicus-dir", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    root = Path(args.copernicus_dir)
    payload = {
        "generated_utc": timestamp(),
        "mode": "scaffold",
        "predictor_groups": {
            "physics": describe(root / "physics"),
            "sea_ice": describe(root / "sea_ice"),
            "biogeochemistry": describe(root / "biogeochemistry"),
        },
        "intended_alignment": [
            "Subset to the PFT overlap window: April-August.",
            "Subset to the study region: 70N-90N, 25W-35E.",
            "Harmonize all predictors to the modeling grid before matchup.",
        ],
    }
    write_json(args.output, payload)
    print(f"Wrote Copernicus manifest to {args.output}")


if __name__ == "__main__":
    main()
