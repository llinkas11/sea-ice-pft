from __future__ import annotations

from pathlib import Path

import copernicusmarine


OUTPUT_ROOT = Path("/mnt/research/mlavign/llinkas/random-forest/data_raw/copernicus")

REGION = {
    "minimum_longitude": -25.0,
    "maximum_longitude": 35.0,
    "minimum_latitude": 70.0,
    "maximum_latitude": 90.0,
}

START = "2003-04-01T00:00:00"
END = "2024-08-31T23:59:59"

DATASETS = {
    "physical": {
        "dataset_id": "cmems_mod_arc_phy_my_topaz4_P1M",
        "variables": ["thetao", "so", "mlotst"],
        "output_filename": "arctic_physical_monthly_2003_2024.nc",
    },
    "sea_ice": {
        "dataset_id": "cmems_mod_arc_phy_my_nextsim_P1M-m",
        "variables": ["siconc", "sithick"],
        "output_filename": "arctic_sea_ice_monthly_2003_2024.nc",
    },
}


def run_subset(group: str, config: dict[str, object]) -> None:
    output_directory = OUTPUT_ROOT / group
    output_directory.mkdir(parents=True, exist_ok=True)

    print(f"Downloading {group}")
    print(f"  dataset_id: {config['dataset_id']}")
    print(f"  variables: {', '.join(config['variables'])}")
    print(f"  output: {output_directory / config['output_filename']}")

    copernicusmarine.subset(
        dataset_id=config["dataset_id"],
        variables=config["variables"],
        start_datetime=START,
        end_datetime=END,
        minimum_longitude=REGION["minimum_longitude"],
        maximum_longitude=REGION["maximum_longitude"],
        minimum_latitude=REGION["minimum_latitude"],
        maximum_latitude=REGION["maximum_latitude"],
        output_directory=str(output_directory),
        output_filename=str(config["output_filename"]),
    )

    print(f"Completed {group}\n")


def main() -> None:
    print("Starting monthly core Copernicus download for the Northeast Arctic")
    print(f"Domain: {REGION}")
    print(f"Time window: {START} to {END}\n")

    for group, config in DATASETS.items():
        run_subset(group, config)

    print("All monthly core Copernicus downloads completed.")


if __name__ == "__main__":
    main()
