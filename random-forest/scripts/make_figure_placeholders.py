from __future__ import annotations

import argparse
from pathlib import Path

from scaffold_utils import ensure_dir, write_text


def main() -> None:
    parser = argparse.ArgumentParser(description="Create figure placeholder notes.")
    parser.add_argument("--figure-dir", required=True)
    parser.add_argument("--report-dir", required=True)
    args = parser.parse_args()

    figure_dir = ensure_dir(args.figure_dir)
    ensure_dir(Path(figure_dir) / "core")
    ensure_dir(Path(figure_dir) / "expanded")

    write_text(
        Path(figure_dir) / "figure_plan.txt",
        "Planned figure sets\n"
        "- Study region maps\n"
        "- Core model performance and variable importance\n"
        "- Expanded model performance and variable importance\n"
        "- Temporal summaries across April-August and across years\n",
    )
    print("Wrote figure scaffold")


if __name__ == "__main__":
    main()
