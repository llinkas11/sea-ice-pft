"""
Methods schematic: predictor-block pipeline + 8-variant inclusion grid.

Top half — five predictor-block boxes flowing into an RF box flowing into the
3 PFT outputs. Bottom half — an 8 × 5 grid showing which blocks each variant
includes (filled circle = included; open circle = dropped).
"""
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch
import numpy as np

from figlib import BLOCK_COLORS, PFT_COLORS, PFT_DISPLAY_ORDER, DOCS_DIR

OUT = str(DOCS_DIR / "methods_variant_diagram.png")

# ----- structure -----
blocks = ["Ocean", "Local ice", "Export\n(CMEMS)", "Atmospheric", "Spatial"]
block_n = [3, 4, 8, 3, 2]
block_colors = [BLOCK_COLORS[k] for k in ("ocean", "ice", "export", "atm", "spatial")]
block_predictors = [
    "thetao\nso\nmlotst",
    "siconc, sithick\n+ 1-mo lags",
    "ice area & volume\nflux × 4 lags",
    "qnet, u10, v10",
    "lat, lon",
]

variants = [
    "Full",
    "No spatial",
    "No local ice",
    "No export",
    "No atmospheric",
    "Ocean only",
    "Export only",
    "Local ice only",
]
variant_n = [20, 18, 16, 12, 17, 3, 8, 4]
M = np.array([
    [1, 1, 1, 1, 1],
    [1, 1, 1, 1, 0],
    [1, 0, 1, 1, 1],
    [1, 1, 0, 1, 1],
    [1, 1, 1, 0, 1],
    [1, 0, 0, 0, 0],
    [0, 0, 1, 0, 0],
    [0, 1, 0, 0, 0],
])

# ----- canvas -----
fig = plt.figure(figsize=(11.5, 11), dpi=150)

# Two stacked subplots: top = pipeline, bottom = inclusion grid
gs = fig.add_gridspec(2, 1, height_ratios=[1.0, 2.1], hspace=0.16)
ax_top = fig.add_subplot(gs[0])
ax_bot = fig.add_subplot(gs[1])

# =============================================================
# TOP: predictor-block pipeline
# =============================================================
ax_top.set_xlim(0, 10)
ax_top.set_ylim(0, 6)
ax_top.axis("off")

# Five predictor-block boxes across the top
n_blocks = len(blocks)
total_w = 9.0
pad = 0.25
box_w = (total_w - (n_blocks - 1) * pad) / n_blocks
y_top = 4.4
y_box_h = 1.3
x_start = 0.5

box_centers_x = []
for i in range(n_blocks):
    x = x_start + i * (box_w + pad)
    box_centers_x.append(x + box_w / 2)
    bb = FancyBboxPatch(
        (x, y_top), box_w, y_box_h,
        boxstyle="round,pad=0.02,rounding_size=0.08",
        linewidth=1.2, edgecolor="black", facecolor=block_colors[i], alpha=0.85,
    )
    ax_top.add_patch(bb)
    ax_top.text(x + box_w / 2, y_top + y_box_h - 0.27,
                f"{blocks[i]}  ({block_n[i]})",
                ha="center", va="center", color="white", fontsize=10, fontweight="bold")
    ax_top.text(x + box_w / 2, y_top + 0.45,
                block_predictors[i],
                ha="center", va="center", color="white", fontsize=7.5)

# RF box in the middle
rf_x, rf_y, rf_w, rf_h = 3.5, 2.2, 3.0, 0.95
rf_box = FancyBboxPatch(
    (rf_x, rf_y), rf_w, rf_h,
    boxstyle="round,pad=0.02,rounding_size=0.10",
    linewidth=1.6, edgecolor="black", facecolor="#222222",
)
ax_top.add_patch(rf_box)
ax_top.text(rf_x + rf_w / 2, rf_y + rf_h / 2 + 0.18,
            "Random Forest", ha="center", va="center",
            color="white", fontsize=12, fontweight="bold")
ax_top.text(rf_x + rf_w / 2, rf_y + rf_h / 2 - 0.20,
            "ranger, 100 trees, seed = 42",
            ha="center", va="center", color="#cccccc", fontsize=9)

# Output: 3 PFT pills
out_y = 0.35
out_h = 0.85
pft_names = list(PFT_DISPLAY_ORDER)
pft_colors = [PFT_COLORS[p] for p in pft_names]
out_total_w = 7.0
out_pad = 0.3
pft_w = (out_total_w - (3 - 1) * out_pad) / 3
out_x_start = (10 - out_total_w) / 2
for i, name in enumerate(pft_names):
    x = out_x_start + i * (pft_w + out_pad)
    bb = FancyBboxPatch(
        (x, out_y), pft_w, out_h,
        boxstyle="round,pad=0.02,rounding_size=0.10",
        linewidth=1.0, edgecolor="black", facecolor=pft_colors[i], alpha=0.85,
    )
    ax_top.add_patch(bb)
    ax_top.text(x + pft_w / 2, out_y + out_h / 2,
                name, ha="center", va="center",
                fontsize=10, fontweight="bold", color="black")

# Arrows: each block → RF
for cx in box_centers_x:
    arr = FancyArrowPatch(
        (cx, y_top - 0.05), (rf_x + rf_w / 2, rf_y + rf_h + 0.05),
        arrowstyle="-|>", mutation_scale=10,
        color="#666666", linewidth=0.9, zorder=1,
    )
    ax_top.add_patch(arr)

# Arrow: RF → "predicts" label → PFT pills
ax_top.annotate("",
                xy=(5.0, out_y + out_h + 0.05),
                xytext=(rf_x + rf_w / 2, rf_y - 0.05),
                arrowprops=dict(arrowstyle="-|>", color="black", linewidth=1.4))
ax_top.text(5.4, (rf_y - 0.05 + out_y + out_h + 0.05) / 2,
            "predicts monthly\nclass fraction",
            ha="left", va="center", fontsize=8.5, style="italic", color="#444")

ax_top.set_title(
    "Random Forest predictor pipeline (Phase 3 Full model — 20 predictors)",
    fontsize=12.5, fontweight="bold", pad=10,
)

# =============================================================
# BOTTOM: 8-variant inclusion grid
# =============================================================
ax_bot.set_xlim(-1.7, n_blocks + 0.9)
ax_bot.set_ylim(-0.8, len(variants) + 0.2)
ax_bot.invert_yaxis()
ax_bot.axis("off")

# Header row — block names
for j, b in enumerate(blocks):
    ax_bot.text(j, -0.55, f"{b}\n({block_n[j]})",
                ha="center", va="bottom",
                fontsize=10, fontweight="bold", color=block_colors[j])
ax_bot.text(n_blocks + 0.1, -0.55, "n predictors",
            ha="center", va="bottom", fontsize=10, fontweight="bold")

# Body — circles per variant × block
for i, var in enumerate(variants):
    # variant label on left
    ax_bot.text(-0.4, i, var, ha="right", va="center", fontsize=11, fontweight="bold")
    # circles
    for j in range(n_blocks):
        if M[i, j]:
            ax_bot.scatter(j, i, s=600, color=block_colors[j],
                           edgecolors="black", linewidths=1.0, zorder=3)
        else:
            ax_bot.scatter(j, i, s=600, facecolors="white",
                           edgecolors="#888888", linewidths=1.0, zorder=3)
    # n on right
    ax_bot.text(n_blocks + 0.1, i, f"{variant_n[i]}",
                ha="center", va="center", fontsize=11, fontweight="bold")

# Light separator lines between rows
for i in range(len(variants) + 1):
    ax_bot.hlines(i - 0.5, -0.35, n_blocks + 0.5, colors="#dddddd", linewidth=0.6, zorder=1)

# Legend strip below the grid
legend_y = len(variants) + 0.05
ax_bot.scatter(0.5, legend_y, s=400, color="#444",
               edgecolors="black", linewidths=1.0)
ax_bot.text(0.8, legend_y, "block included", va="center", fontsize=10)
ax_bot.scatter(2.8, legend_y, s=400, facecolors="white",
               edgecolors="#888888", linewidths=1.0)
ax_bot.text(3.1, legend_y, "block dropped (= ablated)", va="center", fontsize=10)

# Footnote: note about the two CV schemes
note_y = legend_y + 0.55
ax_bot.text(-1.7, note_y,
            "Variants 1–6 evaluated by 5° spatial-block CV (headline).  "
            "Variants 7–8 (\"only\" specs) additionally evaluated by leave-one-year-out temporal CV (22 folds).",
            ha="left", va="center", fontsize=9, style="italic", color="#444")

ax_bot.set_title(
    "Variant × predictor-block inclusion matrix",
    fontsize=12.5, fontweight="bold", pad=10,
)

plt.savefig(OUT, dpi=200, bbox_inches="tight", facecolor="white")
print(f"Wrote {OUT}")
