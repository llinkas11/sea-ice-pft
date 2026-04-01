from __future__ import annotations

import argparse
from pathlib import Path

from scaffold_utils import ensure_dir, timestamp, write_json, write_text


def main() -> None:
    parser = argparse.ArgumentParser(description="Initialize the random-forest project scaffold.")
    parser.add_argument("--project-root", required=True)
    args = parser.parse_args()

    root = Path(args.project_root)
    directories = [
        "data_raw/pft_daily_parquet",
        "data_raw/copernicus/physics",
        "data_raw/copernicus/sea_ice",
        "data_raw/copernicus/biogeochemistry",
        "data_raw/insitu",
        "data_intermediate/matchups",
        "data_intermediate/features/physics",
        "data_intermediate/features/sea_ice",
        "data_intermediate/features/bgc",
        "data_model",
        "models",
        "figures/core",
        "figures/expanded",
        "reports",
        "notebooks",
        "scripts",
        "logs",
        "codex_notes",
        "config",
    ]

    for relpath in directories:
        ensure_dir(root / relpath)

    write_json(
        root / "config/project_config.json",
        {
            "created_utc": timestamp(),
            "project_name": "Northeast Arctic sea ice and PFT random forest",
            "region": "70N-90N, 25W-35E",
            "targets": ["pixel_class", "chlorophyll_guesses"],
            "model_families": ["core", "expanded"],
            "notes": [
                "Core model uses PFT + physics + sea ice predictors.",
                "Expanded model adds biogeochemistry predictors.",
                "In-situ data are for external validation only.",
                "Train/test splits must be time-blocked.",
            ],
        },
    )

    write_text(
        root / "codex_notes/codex_session_log.md",
        "# Codex Session Log\n\n"
        "This file is ready for session-by-session updates as the pipeline develops.\n",
    )

    print(f"Initialized scaffold under {root}")


if __name__ == "__main__":
    main()
