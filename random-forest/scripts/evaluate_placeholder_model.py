from __future__ import annotations

import argparse
from pathlib import Path

from scaffold_utils import ensure_dir, timestamp, write_json, write_text


def main() -> None:
    parser = argparse.ArgumentParser(description="Create evaluation placeholders for a model family.")
    parser.add_argument("--model-family", choices=["core", "expanded"], required=True)
    parser.add_argument("--report-dir", required=True)
    parser.add_argument("--figure-dir", required=True)
    args = parser.parse_args()

    report_dir = ensure_dir(args.report_dir)
    figure_root = ensure_dir(args.figure_dir)
    family_figure_dir = ensure_dir(Path(figure_root) / args.model_family)

    write_json(
        report_dir / f"{args.model_family}_evaluation_manifest.json",
        {
            "generated_utc": timestamp(),
            "model_family": args.model_family,
            "status": "scaffold placeholder",
            "expected_metrics": ["held_out_skill", "feature_importance", "temporal_generalization"],
        },
    )
    write_text(
        family_figure_dir / "README.txt",
        f"{args.model_family.title()} evaluation figure placeholders.\n"
        "Replace with variable-importance, performance, and temporal summary plots.\n",
    )
    print(f"Wrote evaluation scaffold for {args.model_family}")


if __name__ == "__main__":
    main()
