from __future__ import annotations

import argparse
from pathlib import Path

from scaffold_utils import ensure_dir, timestamp, write_json


def main() -> None:
    parser = argparse.ArgumentParser(description="Create a validation placeholder using in-situ data inventory.")
    parser.add_argument("--insitu-dir", required=True)
    parser.add_argument("--report-dir", required=True)
    args = parser.parse_args()

    insitu_dir = Path(args.insitu_dir)
    report_dir = ensure_dir(args.report_dir)
    insitu_files = sorted(item.name for item in insitu_dir.glob("*") if item.is_file())

    write_json(
        report_dir / "insitu_validation_summary.json",
        {
            "generated_utc": timestamp(),
            "status": "scaffold placeholder",
            "insitu_file_count": len(insitu_files),
            "insitu_files": insitu_files,
            "rule": "In-situ observations are not used for RF training.",
        },
    )
    print("Wrote in-situ validation scaffold")


if __name__ == "__main__":
    main()
