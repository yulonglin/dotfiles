# Monitoring Prompt

#prompt/meta

Analyze these model-monitoring results as an empirical researcher. The goal is to **surface interesting qualitative behaviors and comparative failure modes**, not just aggregate metrics.

Focus on:

* **Target-model behavior:** Use LLM judges to identify and categorize interesting behaviors in the target-model rollouts. Prefer a useful emergent taxonomy over forcing examples into predefined categories.
* **Monitor evidence:** For each example, show the most relevant/highlighted parts of the monitor input and output, with the **full raw input/output available in collapsible sections**.
* **Monitor errors:** Prioritize examples where a monitor is wrong, and characterize *why* it appears to have failed.
* **Monitor disagreements:** Find cases where monitors disagree, especially:
  * Monitor A is correct and Monitor B is wrong.
  * Monitor B is correct and Monitor A is wrong.
  * Both reach the same conclusion for apparently different reasons.
* **Comparative advantages:** Identify recurring behaviors or example types where one monitor has a meaningful advantage over another, and propose hypotheses for why.
* **Representative examples:** For each important pattern, show several concrete samples rather than relying only on summary statistics.

Where possible, quantify how common each discovered pattern is and distinguish **robust recurring findings from interesting anecdotes**. The output should make it easy to move from aggregate finding → selected examples → highlighted evidence → full raw transcript.

---

We should agree on things like, the data and models to be used, and the metrics we index on.

generally all samples should be included, unless it causes a severe performance hit

So I think in general the columns should be like Excel — you should be able to click on the column header cell, and there should be a drop-down menu that allows you to select or untick the various values.

If you're comparing monitors and we see that one monitor has a false positive, it would be helpful to be able to see, for example, that Monitor A has cases where it has a false positive but Monitor B doesn't, and be able to answer similar comparative questions like this.

We should be able to filter in this way, so only the relevant rows are basically samples. We can click through to take a look at them.

---

In general, we should have scripts (plotting, report, data analysis, etc.), Artifact, figures as outputs!
