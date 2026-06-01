"""
Rebuild paper Figures 5 and 6 with:
  - 5-95% fold percentile bands (recomputed from /tmp/p3_ale_raw.csv).
    The aggregated CSV's ale_lo/ale_hi are 25-75% IQR, which can place the
    band off the mean line when one fold is an outlier (Cocco × longitude bug).
    Using true 5-95% percentiles ensures the band always brackets the mean
    for n=5 folds.
  - No suptitles (caption-driven figures).
  - No boxes around panel labels (plain bold letters).
  - Figure 5 panels labelled A-H (matches Figure 6 styling).
"""
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

from figlib import PFT_COLORS, BLOCK_COLORS, block_of, PRETTY, PFT_DISPLAY_ORDER, DOCS_DIR

OUT  = DOCS_DIR
RAW  = pd.read_csv("/tmp/p3_ale_raw.csv")
STAT = pd.read_csv("/tmp/p3_predictor_stats.csv", index_col=0)

# Compute fold-mean, 5%, 95% per (feature, pft, x)
agg = (RAW.groupby(["feature", "pft", "x"])
          .agg(ale_mean=("ale", "mean"),
               ale_lo  =("ale", lambda s: s.quantile(0.05)),
               ale_hi  =("ale", lambda s: s.quantile(0.95)))
          .reset_index())


# MLD is log-normally distributed in oceanographic data (Holte & Talley 2009;
# verified empirically: raw skew = 13.1, log-skew = 2.4). To prevent the rare
# deep-convection right tail from compressing 19/20 bin centers into z ∈ [-0.3,
# +0.3] with a single 18σ jump to bin 20, we log-z-score MLD instead of
# raw-z-scoring it. RF predictions are unchanged (RF is invariant to monotonic
# transforms of individual predictors); the transform is purely an axis re-label.
LOG_TRANSFORM = {
    "mlotst": {"log_mean": 2.238512, "log_sd": 0.689775},
}

def panel(ax, feat, label=None):
    """Draw one ALE panel with z-scored x-axis and 5-95% fold-range shading."""
    sub = agg[agg["feature"] == feat]
    if sub.empty:
        ax.set_visible(False); return

    if feat in LOG_TRANSFORM:
        fmean = LOG_TRANSFORM[feat]["log_mean"]
        fsd   = LOG_TRANSFORM[feat]["log_sd"]
        x_transform = np.log1p
        x_label = "log z-score (σ)"
    else:
        fmean = STAT.loc[feat, "mean"]
        fsd   = STAT.loc[feat, "sd"]
        x_transform = lambda x: x
        x_label = "z-score (σ)"

    block = block_of(feat)

    for pft in PFT_DISPLAY_ORDER:
        s = sub[sub["pft"] == pft].sort_values("x")
        if s.empty: continue
        x_z = (x_transform(s["x"].values) - fmean) / fsd
        ax.fill_between(x_z, s["ale_lo"].values, s["ale_hi"].values,
                        color=PFT_COLORS[pft], alpha=0.18, linewidth=0)
        ax.plot(x_z, s["ale_mean"].values,
                color=PFT_COLORS[pft], linewidth=1.7, label=pft)

    ax.axhline(0, color="black", linewidth=0.5, linestyle="--", alpha=0.5)
    ax.set_title(PRETTY[feat], fontsize=10, color=BLOCK_COLORS[block], fontweight="bold")
    ax.set_xlabel(x_label, fontsize=9)
    ax.set_ylabel("ALE (Δ class fraction)", fontsize=9)
    ax.tick_params(labelsize=8)
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)

    if label is not None:
        ax.text(0.025, 0.96, label, transform=ax.transAxes,
                fontsize=15, fontweight="bold", va="top", ha="left", color="black")


# =============================================================
# Figure 5 — non-flux predictors, 2x4, panel labels A-H, no title
# =============================================================
print("Building Figure 5...")
FIG5_LAYOUT = [
    [("thetao",   "A"), ("so",        "B"), ("mlotst",    "C"), ("qnet_wm2",  "D")],
    [("u10_ms",   "E"), ("v10_ms",    "F"), ("latitude",  "G"), ("longitude", "H")],
]
fig, axes = plt.subplots(2, 4, figsize=(14, 6.4), dpi=170)
for r, row in enumerate(FIG5_LAYOUT):
    for c, (feat, lab) in enumerate(row):
        panel(axes[r, c], feat, label=lab)

# Single shared legend at top-center, no suptitle
handles = [plt.Line2D([],[], color=c, linewidth=2.4, label=p) for p, c in PFT_COLORS.items()]
fig.legend(handles=handles, loc="upper center", ncol=3,
           bbox_to_anchor=(0.5, 1.025), frameon=False, fontsize=11)
plt.tight_layout(rect=[0, 0, 1, 0.985])
plt.savefig(OUT / "p3_fig5_ale_nonflux.png", dpi=200, bbox_inches="tight", facecolor="white")
plt.close()
print(f"  → {OUT / 'p3_fig5_ale_nonflux.png'}")

# =============================================================
# Figure 6 — ice-export flux, 4×2, A-H labels, no title
# =============================================================
print("Building Figure 6...")
FIG6_LAYOUT = [
    [("ice_area_flux_current", "A"), ("ice_volume_flux_current", "B")],
    [("ice_area_flux_lag1",    "C"), ("ice_volume_flux_lag1",    "D")],
    [("ice_area_flux_lag2",    "E"), ("ice_volume_flux_lag2",    "F")],
    [("ice_area_flux_cumOct",  "G"), ("ice_volume_flux_cumOct",  "H")],
]
fig, axes = plt.subplots(4, 2, figsize=(11, 12), dpi=170)
for r, row in enumerate(FIG6_LAYOUT):
    for c, (feat, lab) in enumerate(row):
        panel(axes[r, c], feat, label=lab)

# Column header strip
fig.text(0.275, 0.985, "Area transport",   ha="center", fontsize=12, fontweight="bold", color="#444")
fig.text(0.745, 0.985, "Volume transport", ha="center", fontsize=12, fontweight="bold", color="#444")

handles = [plt.Line2D([],[], color=c, linewidth=2.4, label=p) for p, c in PFT_COLORS.items()]
fig.legend(handles=handles, loc="upper center", ncol=3,
           bbox_to_anchor=(0.5, 1.020), frameon=False, fontsize=11)
plt.tight_layout(rect=[0, 0, 1, 0.97])
plt.savefig(OUT / "p3_fig6_ale_export.png", dpi=200, bbox_inches="tight", facecolor="white")
plt.close()
print(f"  → {OUT / 'p3_fig6_ale_export.png'}")

# =============================================================
# Sanity check — verify Cocco × longitude bug is fixed
# =============================================================
test = agg[(agg.feature == "longitude") & (agg.pft == "Coccolithophores")]
out_of_band = ((test.ale_mean < test.ale_lo) | (test.ale_mean > test.ale_hi)).sum()
print()
print(f"Sanity check: Cocco × longitude rows where mean is outside [5%, 95%] band: {out_of_band} / {len(test)}")
print("(should be 0 for n=5 folds with proper percentiles)")
