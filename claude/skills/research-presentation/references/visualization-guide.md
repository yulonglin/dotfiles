# Visualization Guide

## Common Experiment Types & Recommended Plots

**Method Comparison:**
- Bar chart with 95% confidence intervals
- Show baseline clearly
- Annotate statistical significance if tested
- Order bars by performance (not alphabetically)

**Ablation Study:**
- Bar chart showing component contributions
- Full model on left, ablations to the right
- Show what each component adds/removes
- Consider waterfall chart for cumulative effects

**Scaling Experiments:**
- Line plot with error bands (not just error bars)
- Log scale if spanning orders of magnitude
- Show compute budget or sample size on x-axis
- Include baseline as horizontal line

**Failure Mode Analysis:**
- Confusion matrix or error breakdown
- Highlight where model fails most
- Show representative examples of failures
- Quantify frequency of each failure type

**Hyperparameter Sweeps:**
- Heatmap for 2D sweeps
- Line plot for 1D sweeps
- Highlight optimal region
- Consider showing multiple metrics as small multiples

## Visualization Best Practices

**Statistical Rigor:**
- Always show uncertainty (95% CI or standard error)
- Report sample sizes (n=X)
- Show baselines for comparison
- Indicate if differences are statistically significant
- Don't cherry-pick: show all conditions, or clearly state selection criteria

**Clarity:**
- Large, readable fonts (14pt+ for labels)
- Clear axis labels with units
- Informative title stating the takeaway
- Legends only when necessary (direct labeling preferred)
- Consistent color scheme across slides
- **Always show values directly on bars** (data labels) for easy reading without needing to reference axes

**Honesty:**
- Start y-axis at zero for bar charts (or clearly mark truncation)
- Use appropriate scales (linear vs. log)
- Don't hide negative results
- Show full distributions, not just means
- Flag outliers or data quality issues

## Further Reading

- LessWrong: "Tips on Empirical Research" (https://www.lesswrong.com/posts/i3b9uQfjJjJkwZF4f)
- Tufte, Edward: "The Visual Display of Quantitative Information"
- Few, Stephen: "Show Me the Numbers"
