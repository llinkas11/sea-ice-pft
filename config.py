import os
from pathlib import Path


def rf_project_root() -> Path:
    return Path(os.environ.get("RF_PROJECT_ROOT") or Path.cwd())


def rf_data_root() -> Path:
    d = os.environ.get("RF_DATA_ROOT")
    return Path(d) if d else rf_project_root() / "data"


def rf_out_root() -> Path:
    o = os.environ.get("RF_OUT_ROOT")
    return Path(o) if o else rf_data_root() / "out"


def rf_seed() -> int:
    return int(os.environ.get("RF_SEED", "42"))


def rf_n_threads() -> int:
    n = os.environ.get("SLURM_CPUS_ON_NODE") or os.environ.get("RF_N_THREADS")
    if n:
        return int(n)
    return max(1, (os.cpu_count() or 2) - 1)
