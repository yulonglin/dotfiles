---
name: debrief
description: Turn a finished session into one review page — what was done and why, the judgement calls most likely not to be what was meant, side effects, and how the work was checked — published as a private Artifact that takes platform comments and answers them in the next round. Use when the user asks for a debrief, a review or report of what this session did, "what did you do while I was away", or another round of an earlier debrief; offer it in one line when a long unattended stretch of work ends. Not for code this session did not write, and not for handing work to another agent (that is `externalise-handover`).
---

# Debrief

!`hive --version 2>&1 || echo 'debrief: hive CLI missing — install the release binary (see "Install" below), then retry'`

Session: `${CLAUDE_SESSION_ID}`

A port of alignment-hive's `debrief` plugin without the plugins. The authoring standard is [`references/authoring.md`](references/authoring.md), a verbatim upstream copy; the renderer is the upstream `hive debrief render`; this file holds only what differs here. Where the two disagree, this file wins.

## Run it as a fork

Unless the user asks otherwise, a fork writes the debrief (Agent with `subagent_type: "fork"`, model unset); its prompt says only that it is the debrief fork for round N, since it already has this conversation. It follows `references/authoring.md` plus the overrides below. Its fact-check subagent (Flow step 4) is part of the task, so the fork spawns it despite its usual instruction to execute directly. If the fork returns before Flow steps 4 and 5, run them yourself.

## What differs from upstream

- **Data dir**: `<data>` is `${DEBRIEF_DATA_DIR:-$HOME/.cache/debrief}`, passed as `--data` to every `hive debrief dir`, `render` and `capture` call. It is sandbox-writable and outside every repo; `block_unannotated_artifact.sh` lets pages under it publish without the md2artifact layer, because platform comments replace it.
- **Skip `hive debrief preflight`.** It needs the session-start commit stamp that only the hive plugin's SessionStart hook writes, and that plugin is deliberately not enabled (it pings alignment-hive.com on every session start). The `!` line above is the preflight.
- **`base` is mandatory in the front matter**, for the same reason. Never use `git merge-base HEAD main`: once the branch is merged into `main` it returns HEAD and the diff comes out empty.
  - Work on a branch the session created (EnterWorktree, `cw`): the commit the branch was created from, the last line of `git reflog show --format='%h %gs' <branch>` ("branch: Created from …"). This holds after a merge, as long as the branch still exists.
  - Branch already squash-merged and deleted: the parent of the squash commit (`git log --oneline main`, matched by PR number), with `head:` set to that squash commit.
  - Work directly on a branch that existed before the session: HEAD at the time of the first entry in `hive local outline <session>`, from `git rev-list -1 --before="<that time>" HEAD`.
  - A later round reuses round 1's `base`.
  - Then run `git log --format='%h %s' <base>..HEAD`. It must list every commit the transcript records; an empty or short range means the base is wrong, so stop and fix it. Another session's commits in the range belong in the `landing` item, named as not this session's.
- **Fact-checker from another family**: an agent type routed through the model-router gateway, `sol(high)` first, `astra(high)` if that fails. Name the model on the page ("fact-checked by GPT-6.1 Sol").
- **House writing rules apply on the page** — `~/.claude/rules/communication.md` and `sensitive-content.md`. The page is shareable, so no payloads, credentials, hosts or injection strings: describe the mechanism and cite the transcript locator instead.

## Publish and iterate

Publish each round's `page.html` with the Artifact tool. The first round passes `icon: "report"` and

```json
{"db": {"rules": [{"path": "seen", "read": "admin", "write": "owner"}, {"path": "seen/{self}", "read": "interact", "write": "interact"}]}, "user": {}}
```

as `capabilities`, which keeps each reader's seen marks in the artifact database. Later rounds pass the first round's `url` and omit `capabilities`, so seen marks and open sections carry over. Post the link and the "Left for you" lines in chat. The Artifact is the page's only home: no vault copy, and no `ARTIFACTS.md` row unless the debrief is the report of record for a result.

Read comments with `ArtifactComments`. A comment that asks for a change to the work is yours to act on before the next round. Then send the fork every comment, each with what it was placed on, and the new round number; spawn a fresh fork instead if the session has compacted or much has happened since the last round.

## Install

The renderer is the hive CLI release binary — no `install.sh`, no sign-in, no plugin. Version pinned to the copied reference (0.2.2):

```
curl -fSL -o ~/.cache/hive/v0.2.2/hive \
  --create-dirs \
  https://github.com/Crazytieguy/alignment-hive/releases/download/hive-cli-v0.2.2/hive-cli-darwin-arm64
chmod +x ~/.cache/hive/v0.2.2/hive
ln -sf ~/.cache/hive/v0.2.2/hive ~/.local/bin/hive
```

On Linux the asset is `hive-cli-linux-x64` or `hive-cli-linux-arm64`. On a version bump, re-copy `references/authoring.md` from the marketplace clone at `~/.claude/plugins/marketplaces/alignment-hive/plugins/debrief/references/` and update its header and this section together.
