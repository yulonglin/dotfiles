"""MMLU Benchmark Comparison Bar Chart — Anthropic Style.

Uses Anthropic brand colors and styling directly (extracted from anthro_colors.py)
to avoid dependency on the custom `log` module.
"""

import matplotlib.pyplot as plt
import numpy as np
from pathlib import Path

# ---------- Anthropic brand colors (from anthro_colors.py, the source of truth) ----------
SLATE = "#141413"
DARK_ORANGE = BOOK_CLOTH = "#B86046"
GREY = "#656565"
DARK_BLUE = "#40668C"
MEDIUM_ORANGE = KRAFT = "#D19B75"
LIGHT_PURPLE = "#8778AB"
DARK_PURPLE = "#4A366F"
PRETTY_CYCLE = [DARK_ORANGE, GREY, DARK_BLUE, MEDIUM_ORANGE, LIGHT_PURPLE, DARK_PURPLE]

# ---------- Apply Anthropic style (mirrors anthropic.mplstyle) ----------
style_path = Path("~/.config/matplotlib/stylelib/anthropic.mplstyle").expanduser()
if style_path.exists():
    plt.style.use(str(style_path))
else:
    # Fallback: set key rcParams programmatically
    plt.rcParams.update({
        "figure.facecolor": "#FFFFFF",
        "axes.facecolor": "#FFFFFF",
        "savefig.facecolor": "#FFFFFF",
        "axes.edgecolor": SLATE,
        "axes.labelcolor": SLATE,
        "xtick.color": SLATE,
        "ytick.color": SLATE,
        "text.color": SLATE,
        "axes.spines.top": False,
        "axes.spines.right": False,
        "axes.prop_cycle": plt.cycler("color", PRETTY_CYCLE),
        "figure.figsize": (8, 5),
        "figure.dpi": 150,
        "savefig.dpi": 300,
        "axes.grid": False,
        "legend.frameon": False,
    })

# ---------- Data ----------
models = ["GPT-4", "Claude 3.5\nSonnet", "Gemini\nUltra", "Llama 3.1\n405B"]
scores = [86.4, 88.7, 83.7, 85.2]
stds = [1.2, 0.9, 1.5, 1.1]

# One color per bar from PRETTY_CYCLE
colors = [DARK_ORANGE, GREY, DARK_BLUE, MEDIUM_ORANGE]

# ---------- Plot ----------
fig, ax = plt.subplots(figsize=(8, 5))

x = np.arange(len(models))
bars = ax.bar(
    x,
    scores,
    yerr=stds,
    capsize=4,
    color=colors,
    width=0.6,
    error_kw=dict(color=SLATE, linewidth=1.2, capthick=1.2),
    zorder=3,
)

# Annotate each bar with its score (normal weight, not bold)
for bar, score, std in zip(bars, scores, stds):
    ax.text(
        bar.get_x() + bar.get_width() / 2,
        bar.get_height() + std + 0.4,
        f"{score:.1f}%",
        ha="center",
        va="bottom",
        fontweight="normal",
        fontsize=9,
        color=SLATE,
    )

ax.set_xticks(x)
ax.set_xticklabels(models)
ax.set_ylabel("MMLU Score (%)")
ax.set_title("MMLU Benchmark Scores by Model")
ax.set_ylim(75, 95)

fig.tight_layout()

output_dir = Path(__file__).parent
fig.savefig(output_dir / "mmlu_bar_chart.png", dpi=300, bbox_inches="tight")
plt.close(fig)
print("Saved mmlu_bar_chart.png")
