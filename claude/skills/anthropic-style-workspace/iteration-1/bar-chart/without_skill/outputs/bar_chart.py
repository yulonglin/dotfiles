import matplotlib.pyplot as plt

models = ["GPT-4", "Claude 3.5 Sonnet", "Gemini Pro"]
accuracy = [89.2, 88.7, 83.7]
colors = ["#74AA9C", "#D97757", "#4285F4"]

fig, ax = plt.subplots(figsize=(8, 5))

bars = ax.bar(models, accuracy, color=colors, width=0.5, edgecolor="white")

for bar, val in zip(bars, accuracy):
    ax.text(bar.get_x() + bar.get_width() / 2, bar.get_height() + 0.5,
            f"{val}%", ha="center", va="bottom", fontsize=13, fontweight="bold")

ax.set_ylabel("MMLU Accuracy (%)", fontsize=12)
ax.set_title("MMLU Accuracy Comparison", fontsize=14, fontweight="bold")
ax.set_ylim(0, 100)
ax.spines["top"].set_visible(False)
ax.spines["right"].set_visible(False)

plt.tight_layout()
plt.savefig("/Users/yulong/code/dotfiles/claude/skills/anthropic-style-workspace/iteration-1/bar-chart/without_skill/outputs/mmlu_comparison.png", dpi=150)
print("Saved mmlu_comparison.png")
