from __future__ import annotations

import argparse
from pathlib import Path

from scaffold_utils import timestamp, write_json


def main() -> None:
    parser = argparse.ArgumentParser(description="Build a simple scaffold summary report.")
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--report-dir", required=True)
    args = parser.parse_args()

    project_root = Path(args.project_root)
    report_dir = Path(args.report_dir)
    json_reports = sorted(path.name for path in report_dir.glob("*.json"))

    write_json(
        report_dir / "project_summary.json",
        {
            "generated_utc": timestamp(),
            "project_root": str(project_root),
            "json_reports": json_reports,
            "status": "scaffold complete",
            "next_step": "Replace placeholder scripts with real ingestion, matchup, training, and evaluation code.",
        },
    )
    print("Wrote project summary scaffold")


if __name__ == "__main__":
    main()
