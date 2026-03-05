"""Bar chart comparing MMLU benchmark scores across 4 models with Anthropic style."""

import matplotlib.pyplot as plt
from cycler import cycler

# Anthropic brand colors (PRETTY_CYCLE from anthro_colors.py)
BOOK_CLOTH = "#B86046"  # dark orange
GREY = "#656565"
DARK_BLUE = "#40668C"
KRAFT = "#D19B75"  # medium orange
PRETTY_CYCLE = [BOOK_CLOTH, GREY, DARK_BLUE, KRAFT]

# Apply Anthropic style
plt.style.use("/Users/yulong/.config/matplotlib/stylelib/anthropic.mplstyle")

# Data
models = ["GPT-4", "Claude 3.5\nSonnet", "Gemini Ultra", "Llama 3.1\n405B"]
scores = [86.4, 88.7, 83.7, 85.2]
errors = [1.2, 0.9, 1.5, 1.1]
colors = PRETTY_CYCLE[:4]

fig, ax = plt.subplots(figsize=(8, 5))

bars = ax.bar(
    models, scores, yerr=errors, capsize=5, color=colors,
    edgecolor="none", width=0.6,
    error_kw={"linewidth": 1.5, "capthick": 1.5, "color": "#141413"},
)

ax.set_ylabel("MMLU Score (%)", fontsize=12)
ax.set_xlabel("Model", fontsize=12)
ax.set_title("MMLU Benchmark Comparison", fontsize=14, fontweight="bold", pad=12)

ax.set_ylim(78, 94)
ax.spines["top"].set_visible(False)
ax.spines["right"].set_visible(False)

# Add score labels above bars
for bar, score, err in zip(bars, scores, errors):
    ax.text(
        bar.get_x() + bar.get_width() / 2,
        bar.get_height() + err + 0.3,
        f"{score}%",
        ha="center", va="bottom", fontsize=10, fontweight="medium",
    )

plt.tight_layout()
plt.savefig(
    "/Users/yulong/code/dotfiles/claude/skills/anthropic-style-workspace/iteration-2/bar-chart/without_skill/outputs/mmlu_benchmark_chart.png",
    dpi=200, bbox_inches="tight", facecolor="white",
)
plt.close()
print("Chart saved.")
