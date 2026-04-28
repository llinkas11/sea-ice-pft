#!/usr/bin/env python3
"""
Build two paper-ready ALE figures from the Phase 3 aggregated ALE CSV.

  Figure A — Sea-ice export flux ALE (4×2 grid):
    rows: current month / lag-1 / lag-2 / cum-since-October
    cols: area transport (km² day⁻¹) / volume transport (km³ day⁻¹)
    Y = ALE (centred effect on PFT class fraction, raw)
    X = z-score of feature value (SDs from long-term mean)
    3 PFT lines per panel (Cocco orange, Diatom blue, Phaeo green)
    Vertical grey line at z = 0; horizontal dashed line at ALE = 0.

  Figure B — Non-flux ALE (4×2 grid):
    A) qnet  B) thetao  C) so  D) mlotst  E) u10  F) v10  G) lat  H) lon

Inputs (under `out/results/`):
  p3_ale_aggregated.csv   — produced by R/compute_ale_p3.R
  p3_full_feature_stats.csv — produced by build_feature_stats.py

Outputs (under `out/figures/`):
  p3_ale_flux_zscore.png
  p3_ale_nonflux_zscore.png
"""
import os
import sys
from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd

sys.path.insert(0, os.environ.get("RF_PROJECT_ROOT", os.getcwd()))
from config import rf_out_root  # noqa: E402

sys.path.insert(0, str(Path(__file__).resolve().parent))
from probe_utils import PFT_COLORS, PFT_DISPLAY  # noqa: E402

RESULTS = rf_out_root() / "results"
FIGURES = rf_out_root() / "figures"

ALE_CSV   = RESULTS / "p3_ale_aggregated.csv"
STATS_CSV = RESULTS / "p3_full_feature_stats.csv"
FLUX_PNG  = FIGURES / "p3_ale_flux_zscore.png"
NFLX_PNG  = FIGURES / "p3_ale_nonflux_zscore.png"

# Panel layouts (row, col, label, feature, x_unit, descriptor).
FLUX_LAYOUT = [
    (0, 0, "A", "ice_area_flux_current",   "km² day⁻¹", "current month, area"),
    (0, 1, "B", "ice_volume_flux_current", "km³ day⁻¹", "current month, volume"),
    (1, 0, "C", "ice_area_flux_lag1",      "km² day⁻¹", "1-month lag, area"),
    (1, 1, "D", "ice_volume_flux_lag1",    "km³ day⁻¹", "1-month lag, volume"),
    (2, 0, "E", "ice_area_flux_lag2",      "km² day⁻¹", "2-month lag, area"),
    (2, 1, "F", "ice_volume_flux_lag2",    "km³ day⁻¹", "2-month lag, volume"),
    (3, 0, "G", "ice_area_flux_cumOct",    "km² day⁻¹", "cum. since Oct, area"),
    (3, 1, "H", "ice_volume_flux_cumOct",  "km³ day⁻¹", "cum. since Oct, volume"),
]
NONFLUX_LAYOUT = [
    (0, 0, "A", "qnet_wm2",  "W m⁻²", "Net surface heat flux"),
    (0, 1, "B", "thetao",    "°C",    "Potential temperature"),
    (1, 0, "C", "so",        "PSU",   "Salinity"),
    (1, 1, "D", "mlotst",    "m",     "Mixed-layer thickness"),
    (2, 0, "E", "u10_ms",    "m s⁻¹", "Zonal 10 m wind"),
    (2, 1, "F", "v10_ms",    "m s⁻¹", "Meridional 10 m wind"),
    (3, 0, "G", "latitude",  "°N",    "Latitude"),
    (3, 1, "H", "longitude", "°E",    "Longitude"),
]


def build_figure(layout, agg, stats, title, out_path):
    fig, axes = plt.subplots(4, 2, figsize=(11, 12), sharey=False)
    for r, c, label, feat, xunit, desc in layout:
        ax = axes[r, c]
        if feat not in stats.index:
            raise KeyError(
                f"Feature {feat!r} missing from feature-stats CSV — "
                f"re-run build_feature_stats.py before this script."
            )
        mu, sd = stats.loc[feat, "mean"], stats.loc[feat, "sd"]
        for pft in PFT_DISPLAY:
            sub = agg[(agg["pft"] == pft) & (agg["feature"] == feat)].sort_values("x")
            if sub.empty:
                continue
            x_z = (sub["x"].values - mu) / sd
            color = PFT_COLORS[pft]
            ax.fill_between(x_z, sub["ale_lo"].values, sub["ale_hi"].values,
                            color=color, alpha=0.18, lw=0)
            ax.plot(x_z, sub["ale_mean"].values, color=color, linewidth=1.6, label=pft)

        ax.axvline(0, color="gray", linewidth=0.8)
        ax.axhline(0, color="black", linewidth=0.5, linestyle="--")
        ax.set_xlabel(f"({label}) {desc}\n[z-score; raw {xunit}: μ={mu:.3g}, σ={sd:.3g}]",
                      fontsize=9)
        ax.set_ylabel("ALE", fontsize=9)
        ax.tick_params(axis='both', labelsize=8)
        ax.grid(True, linewidth=0.3, alpha=0.4)
        ax.spines['top'].set_visible(False)
        ax.spines['right'].set_visible(False)

    handles = [plt.Line2D([0], [0], color=PFT_COLORS[p], linewidth=2, label=p)
               for p in PFT_DISPLAY]
    fig.legend(handles=handles, loc='upper right', bbox_to_anchor=(0.98, 0.985),
               ncol=3, frameon=False, fontsize=10)
    fig.suptitle(title, fontsize=12, fontweight='bold', y=0.995)
    fig.tight_layout(rect=[0, 0, 1, 0.96])
    fig.savefig(out_path, dpi=200, bbox_inches='tight', facecolor='white')
    plt.close(fig)
    print(f"Saved -> {out_path}")


def main():
    if not ALE_CSV.exists():
        sys.exit(f"ERROR: ALE CSV not found at {ALE_CSV} — run R/compute_ale_p3.R first.")
    if not STATS_CSV.exists():
        sys.exit(f"ERROR: feature stats CSV not found at {STATS_CSV} — run build_feature_stats.py first.")

    FIGURES.mkdir(parents=True, exist_ok=True)
    agg = pd.read_csv(ALE_CSV)
    stats = pd.read_csv(STATS_CSV).set_index("feature")
    print(f"Loaded {len(agg)} aggregated ALE rows; {len(stats)} feature stats")

    build_figure(FLUX_LAYOUT, agg, stats,
                 "Phase 3 Full model — ALE for 8 ice-export flux predictors (X = z-score)",
                 FLUX_PNG)
    build_figure(NONFLUX_LAYOUT, agg, stats,
                 "Phase 3 Full model — ALE for 8 non-flux predictors (X = z-score)",
                 NFLX_PNG)


if __name__ == "__main__":
    main()
