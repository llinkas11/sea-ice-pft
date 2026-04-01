from __future__ import annotations

import argparse
from pathlib import Path

from scaffold_utils import ensure_dir, timestamp, write_json, write_text


def main() -> None:
    parser = argparse.ArgumentParser(description="Create placeholder model artifacts for the scaffold.")
    parser.add_argument("--model-family", choices=["core", "expanded"], required=True)
    parser.add_argument("--task", choices=["classifier", "regressor"], required=True)
    parser.add_argument("--target", required=True)
    parser.add_argument("--model-dir", required=True)
    parser.add_argument("--report-dir", required=True)
    args = parser.parse_args()

    model_dir = ensure_dir(args.model_dir)
    report_dir = ensure_dir(args.report_dir)

    stem = f"{args.model_family}_{args.task}"
    write_text(
        model_dir / f"{stem}.placeholder.txt",
        f"Placeholder artifact for {args.model_family} {args.task}\n"
        f"Target: {args.target}\n"
        "Replace with a serialized scikit-learn model once training code is implemented.\n",
    )
    write_json(
        report_dir / f"{stem}_training_manifest.json",
        {
            "generated_utc": timestamp(),
            "model_family": args.model_family,
            "task": args.task,
            "target": args.target,
            "status": "scaffold placeholder",
        },
    )
    print(f"Wrote training scaffold for {stem}")


if __name__ == "__main__":
    main()
