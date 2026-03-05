"""Bar chart comparing LLM MMLU accuracy using Anthropic visual style.

Follows the anthropic-style skill: loads anthropic.mplstyle, uses PRETTY_CYCLE
colors, and applies annotate_values for bar labels.
"""

import matplotlib.pyplot as plt
from pathlib import Path

# --- Anthropic style setup (per SKILL.md / references/matplotlib.md) ---
# Load the Anthropic mplstyle directly (avoids anthro_colors.py import chain)
style_path = Path.home() / ".config" / "matplotlib" / "stylelib" / "anthropic.mplstyle"
if style_path.exists():
    plt.style.use(str(style_path))
else:
    # Fallback: key rcParams from the style
    plt.rcParams.update({
        "figure.facecolor": "#FFFFFF",
        "axes.facecolor": "#FFFFFF",
        "savefig.facecolor": "#FFFFFF",
        "axes.spines.top": False,
        "axes.spines.right": False,
        "savefig.dpi": 300,
        "savefig.bbox": "tight",
    })

# Anthropic PRETTY_CYCLE colors (from references/colors.md)
DARK_ORANGE = "#B86046"  # Primary accent
DARK_BLUE = "#40668C"    # Tertiary accent
GREY = "#656565"         # Secondary / neutral


def annotate_values(ax, y_offset=0.3, fmt=lambda x: f"{x:.1f}%", fontsize=11):
    """Annotate bar heights (simplified from anthro_colors.annotate_values)."""
    for p in ax.patches:
        x = p.get_x() + p.get_width() / 2
        y = p.get_height()
        ax.text(x, y + y_offset, fmt(y), ha="center", va="bottom", fontsize=fontsize)


# --- Data ---
models = ["GPT-4", "Claude 3.5\nSonnet", "Gemini Pro"]
accuracy = [89.2, 88.7, 83.7]
colors = [DARK_ORANGE, DARK_BLUE, GREY]

# --- Plot ---
fig, ax = plt.subplots(figsize=(7, 5))
ax.bar(models, accuracy, color=colors, width=0.55)

annotate_values(ax)

ax.set_ylabel("MMLU Accuracy (%)")
ax.set_title("LLM Performance on MMLU Benchmark")
ax.set_ylim(75, 95)

# --- Save ---
output_path = Path(__file__).parent / "mmlu_bar_chart.png"
fig.savefig(output_path)
print(f"Saved to {output_path}")
