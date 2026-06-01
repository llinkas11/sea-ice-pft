"""
Replace the PCA biplot with a clean loadings-only "correlation circle" — the
standard interpretive PCA visualization. Score-cloud subplot in a small inset.
"""
import math

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

from figlib import BLOCK_COLORS, block_of, short_label, DOCS_DIR

OUT = DOCS_DIR

# Load
loadings = pd.read_csv("/tmp/p3_pca_loadings.csv", index_col=0)
ve       = pd.read_csv("/tmp/p3_pca_variance.csv")

# Convert from sqrt(eigenvalue)-scaled loadings back to correlations of feature with PC.
# Standard formula:   loading_corr = component * sqrt(eigenvalue)
# We saved exactly this as the columns. The feature-PC correlation is bounded by [-1, +1].
# But because we built it as components_.T * sqrt(explained_variance_) and explained_variance_
# is the eigenvalue (variance of PC scores in standardized data), the loadings ARE feature-PC
# correlations. So no further scaling needed.

fig, ax = plt.subplots(figsize=(11, 10), dpi=170)

# Reference circles
for r in (0.5, 1.0):
    circle = plt.Circle((0,0), r, fill=False, color="#888", linestyle="--", linewidth=0.6)
    ax.add_patch(circle)
ax.text(0.97, 0.06, "r = 1", fontsize=8, color="#888", ha="left")
ax.text(0.47, 0.06, "r = 0.5", fontsize=8, color="#888", ha="left")

# Origin
ax.axhline(0, color="black", linewidth=0.4, alpha=0.5)
ax.axvline(0, color="black", linewidth=0.4, alpha=0.5)

# Loading vectors with collision-avoiding label placement.
# Sort labels by angle so we can offset them outward.
items = []
for f in loadings.index:
    pc1 = loadings.loc[f, "PC1"]
    pc2 = loadings.loc[f, "PC2"]
    angle = math.atan2(pc2, pc1)
    mag   = math.hypot(pc1, pc2)
    items.append((f, pc1, pc2, angle, mag))

# Draw arrows
for f, pc1, pc2, ang, mag in items:
    block = block_of(f)
    ax.arrow(0, 0, pc1, pc2,
             head_width=0.025, head_length=0.04,
             fc=BLOCK_COLORS[block], ec=BLOCK_COLORS[block],
             linewidth=1.6, alpha=0.9, length_includes_head=True, zorder=5)

# Labels: offset each by 0.06 along its angle, beyond the arrow tip
for f, pc1, pc2, ang, mag in items:
    block = block_of(f)
    pad = 0.06
    lx = pc1 + pad * math.cos(ang)
    ly = pc2 + pad * math.sin(ang)
    ax.text(lx, ly, short_label.get(f, f),
            fontsize=10, fontweight="bold",
            color=BLOCK_COLORS[block],
            ha="center", va="center", zorder=6,
            bbox=dict(boxstyle="round,pad=0.15", fc="white", ec="none", alpha=0.7))

# Block legend
block_handles = [plt.Line2D([],[], color=c, linewidth=2.5, label=b.title())
                 for b, c in BLOCK_COLORS.items()]
ax.legend(handles=block_handles, title="Predictor block",
          loc="upper left", fontsize=10, title_fontsize=11, frameon=True)

ax.set_xlim(-1.15, 1.15)
ax.set_ylim(-1.15, 1.15)
ax.set_aspect("equal")
ax.set_xlabel(f"PC1  ({ve.iloc[0,1]*100:.1f}% variance)", fontsize=12)
ax.set_ylabel(f"PC2  ({ve.iloc[1,1]*100:.1f}% variance)", fontsize=12)
ax.set_title(
    "Phase 3 PCA — predictor loadings on PC1 vs PC2\n"
    f"(20 standardized predictors, n = 200,000 random sample, "
    f"cumulative variance through PC2 = {ve.iloc[1,2]*100:.1f}%)",
    fontsize=12.5, fontweight="bold", pad=12,
)
ax.spines["top"].set_visible(False)
ax.spines["right"].set_visible(False)

plt.tight_layout()
plt.savefig(OUT / "p3_pca_loadings.png", dpi=200, bbox_inches="tight", facecolor="white")
plt.close()
print(f"Wrote {OUT / 'p3_pca_loadings.png'}")
print()
print("Loadings (PC1, PC2):")
print(loadings[["PC1","PC2"]].round(2).to_string())
