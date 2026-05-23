# 2-week learning-loop check-in (auto-generated)

Anchor commit: 57dca35 (2026-05-02). Check-in date: 2026-05-16.

---

## Scaffold status

| Scaffold | Present | Modified after 2026-05-02 | Commits |
|---|---|---|---|
| `claude/skills/log-gap/SKILL.md` | ✓ | N | 57dca35 (creation) |
| `claude/skills/recall-feedback/SKILL.md` | ✓ | N | 57dca35 (creation) |
| `claude/docs/external-resources.md` | ✓ | **Y** | 12962d5 (2026-05-07): "consult before improving setup"; cross-machine sync + Cat Wu |
| `claude/output-styles/10x-mentor.md` | ✓ | N | 21daa2e (creation) |

Stray `gaps.md` commits (any branch, last 14 days): **none found**.

Signal: `external-resources.md` got an editorial pass within a week. The three skill/style scaffolds show no post-creation commits — no gaps logged, no explain-back invocations visible from this side.

---

## Local grep block (run this yourself)

You (remote agent) do NOT have access to `~/.claude/projects` transcripts. Paste this locally:

```bash
SINCE=$(date -u -v-14d +%Y-%m-%d)
T=$(find ~/.claude/projects -name '*.jsonl' -newermt "$SINCE")
echo '## /log-gap mentions:';          rg -h 'log-gap'                    $T | wc -l
echo '## I assumed X but actually:';   rg -h '[Ii] assumed.*but actually' $T | head -10
echo '## /recall-feedback mentions:';  rg -h 'recall-feedback'            $T | wc -l
echo '## learning style switches:';    rg -h '/output-style.*learning'    $T | head -5
find / -name 'gaps.md' 2>/dev/null | grep -v Trash
```

---

## Three questions

**(a) Which scaffolds stuck?**
`external-resources.md` got used (one edit). Did you actually skim it, or just tidy it?

**(b) Which never got used?**
`/log-gap` and `/recall-feedback` show zero post-creation commits and no gaps.md files. If the local grep above also shows zero invocations — they didn't land.

**(c) Which need a different shape?**
`/log-gap` requires you to remember to run it after realising you were wrong — a high-friction moment. Consider a hook or a prompt to `pre_tool_use` that captures errors automatically. `/recall-feedback` requires manually picking a commit; the explain-back gate in `10x-mentor.md` may be doing the same job at lower friction.

---

## Next step

> If a scaffold didn't stick, retire it (delete file, prune MEMORY.md). If it stuck, encode harder (skill→rule, hook, CLAUDE.md). One more 4-week check-in if anything's worth a longer soak.
