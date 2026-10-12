# Handover: Download HTML and Copy HTML on annotated artifacts (session 55c231ff)

Format: a Markdown file, not an Artifact, because the reader is an agent comparing it with a debrief of the same session. Written 2026-10-01 from the transcript `/home/yulong/.claude/projects/-home-yulong-code-dotfiles--claude-worktrees-artifact-download-html/55c231ff-61a7-424b-b0dd-11bf8a30c5ce.jsonl` (session ran 2026-09-24 01:48–06:35 UTC) and from git as it stands today. Locators such as `55c231ff:148` are `hive local` entry numbers. The session started no subagents; its advisor calls are at `55c231ff:22`–`24` (approach; advice reflected at `55c231ff:26`) and `55c231ff:142`–`143` (final review).

## Status: merged as c947b3a, but not live in the working checkout

The work is done and merged: PR https://github.com/yulonglin/dotfiles/pull/203 was squash-merged into `main` as `c947b3a` (`55c231ff:203`), and `c947b3a` is an ancestor of `origin/main`. However, as of 2026-10-01 the main checkout `/home/yulong/code/dotfiles` is on branch `website-vault-publish`, which does not contain `c947b3a`; `grep -c anPageCopy custom_bins/_annotation_layer.py` there returns 0. Because `claude/` and `custom_bins/` are used live from that checkout, the `md2artifact` on PATH still builds pages without the new buttons, and the `artifact-writing` skill that loads still has the old text. The session's closing claim that the change "takes effect once your main checkout pulls `c947b3a`; the daily `dotfiles-sync` job will do that" (`55c231ff:207`) does not hold while the checkout is on another branch.

## Goal and motivation

Yulong wanted every artifact to carry a "download / copy as HTML" button, so that a reader can take the page itself to someone who has no permission to open the Artifact link (`55c231ff:1`). The shared injection point is the annotation layer, `custom_bins/_annotation_layer.py`, which `md2artifact` and `annotate-html` put on every reviewable page, so the button went there (`55c231ff:6`).

## Next tasks

- Bring the change into the live checkout. Either merge `main` into `website-vault-publish` or finish that branch and switch the main tree back to `main`. This needs Yulong's choice, because the main tree carries a dirty working copy, including the permanent gateway diff on `claude/settings.json`.
- Free the `main` branch. `git worktree list` shows `/home/yulong/code/dotfiles/.claude/worktrees/artifact-download-html c947b3a [main]`: `gh pr merge --delete-branch` (`55c231ff:203`) left `main` checked out in the worktree, so no other tree can check out `main`. Local `main` is also 7 commits behind `origin/main`. Remove the worktree (it is clean) or switch it off `main`.
- Fix the stale `established` field in `artifacts/download-probe/meta.yml`. It says "the downloaded copy shows only Copy HTML, since a local file has no viewer", which was true for probe version 2 but not after `f066fb5`, which added a blob download to the local copy.
- Get the probe's row into the index. `artifacts/awake-while-connected/` still has no `meta.yml` on `main` or `origin/main`, so `scripts/build_artifacts_index.py` stops on it (`55c231ff:121`), and `ARTIFACTS.md` on `origin/main` has no row for the probe (grep for `DHxg1` returns 0). That directory belongs to other work; the session left it alone on purpose (`55c231ff:125`).
- Optional, offered and not yet answered (`55c231ff:207`): rebuild and republish existing artifacts with `capabilities: {"downloads": true}` so they get the buttons. Pages published before this change show no "This page" row until rebuilt.
- Optional: have Yulong open probe version 3 from the public link to confirm the greyed-out Download button (see Uncertainties).

## What was accomplished

### The feature as merged

Every annotated page now ends with a "This page" row under the comments panel, with two buttons:

- **Copy HTML** puts the page on the clipboard. It needs no capability and is always shown.
- **Download HTML** behaves by context. In the viewer, with the `downloads` capability declared at publish, it calls `claude.use("downloads")` and the viewer asks the reader to confirm the save. In the viewer without the capability (for example, a public-link viewer), it shows disabled with a "not available here" note pointing to Copy HTML. In a downloaded copy opened as a local file (no `window.claude`), it saves through a blob URL on an `<a download>`.
- The HTML handed over is a snapshot taken at the top of the layer script, before any reader highlight, suggested edit or tick is restored, so none of the reader's notes leak into the file and the copy stays annotatable.

The `artifact-writing` skill (`claude/skills/artifact-writing/SKILL.md`, line 61 and section "The viewer sandbox refuses modals and plain downloads" at line 90 in `c947b3a`) now tells publishers to declare `capabilities: {"downloads": true}` and corrects an older note that a blob download makes every publish warn.

### Commits (worktree branch `worktree-artifact-download-html`, rebased onto `origin/main` at `c2b56fc`)

| Commit | What |
|---|---|
| `c635d43` | Layer: Download HTML (capability only, hidden when it resolves null) and Copy HTML; tests; skill text |
| `031dd9a` | Probe page `artifacts/download-probe/download-probe.{md,html}` |
| `fe28d7f` | Probe row `artifacts/download-probe/meta.yml` |
| `8adbf5b` | Fix: keep the closing-marker literal out of the layer JS; `strip(inject(p)) == p` test |
| `f120eee` | Skill and `meta.yml`: Download reaches the owner only; Copy HTML carries the page outside |
| `f066fb5` | Show Download everywhere: disabled without the capability, blob save in a local copy |
| `9d5da32` | Skill: disabled state documented; blob saves no longer warn |

Squash-merged as `c947b3a` (7 files, +1707/−20). New tests: `test_strip_undoes_inject_exactly` in `tests/test_annotate_html.py`, and `test_a_local_copy_downloads_itself`, `test_download_shows_disabled_when_the_capability_is_not_granted`, `test_download_saves_the_clean_page_without_the_readers_marks`, `test_copy_html_puts_the_page_on_the_clipboard` in `tests/test_md2artifact_browser.py`. The download tests stub `window.claude.use`, so they test the page's side only, not the viewer.

### Commands that matter

Test run used throughout (from the worktree root):

```
timeout 600 uv run --no-project \
  --with pytest --with playwright \
  --with markdown-it-py --with mdit-py-plugins \
  python -m pytest -q -p no:cacheprovider \
  tests/test_annotate_html.py tests/test_md2artifact_browser.py \
  tests/test_md2artifact_states.py tests/test_md2artifact_ios.py
```

Results: 175 pass / 4 fail on the first run (`55c231ff:43`), 267 pass / 3 fail after the rebase (`55c231ff:132`), and 4–5 failures per run after the final change, all in the flaky suggested-edit group (`55c231ff:192`, `55c231ff:193`). `--with markdown` is wrong; md2artifact needs `markdown-it-py` (`55c231ff:42`).

Probe build and publish: `custom_bins/md2artifact artifacts/download-probe/download-probe.md -o artifacts/download-probe/download-probe.html`, then the Artifact tool with `capabilities: {"downloads": true}` on the first publish only. Probe URL https://claude.ai/artifact/DHxg1ZG6BqraAdXUJtr5n6 — version 1 at `55c231ff:79`, version 2 (marker fix) at `55c231ff:165`, version 3 (disabled button and blob path) at `55c231ff:197`. Later publishes omitted `capabilities`, and the result confirmed the declaration carried forward.

## Bugs hit

- **Closing-marker literal in the layer JS** (found by the advisor at `55c231ff:142`, confirmed by a failing round-trip test at `55c231ff:147`, fixed in `8adbf5b`). The JS contained the whole string `<!-- /annotation-layer -->`, so `strip_layer` stopped mid-script and `annotate-html --force` would have written half a layer onto pages. Fix: split the literal and always re-add the marker to the snapshot.
- **Flaky suggested-edit Playwright tests** (`test_inserted_text_is_invisible_to_re_anchoring`, `test_a_fresh_selection_comes_back_in_comment_mode`, `test_the_badge_and_the_count_include_edits`, `test_the_export_carries_a_suggested_edits_section`, `test_a_selection_overlapping_an_edit_points_at_it`). They fail intermittently on unchanged `main` too (2 of 4 at `55c231ff:46`), so they predate this work. Not fixed.
- **Test bugs, not code bugs:** substring assertions matched help text and status text (`55c231ff:57`–`55c231ff:62`); `js.count("saveLocally()")` also counted the function definition, and Playwright rejects a bare `list.append` as an event handler (`55c231ff:190`–`55c231ff:192`).
- **Worktree git guard** refused commands with runtime variables or complex heredocs (`55c231ff:34`, `55c231ff:150`), and the Write tool refused a path in the job directory (`55c231ff:153`). Workaround: write patch scripts to the worktree's gitignored `tmp/` and run them as separate plain commands.
- **`block_throwaway_artifact_path` hook** refused publishing from `tmp/` (`55c231ff:74`); the probe moved to `artifacts/download-probe/` and was committed first.
- **Branch base:** the worktree forked from `website-vault-publish` (base `ec2ad5c`), carrying unrelated commits. It was rebased with `git rebase --onto origin/main ec2ad5c` (`55c231ff:115`). The index script's `URL_RE` fix for short `claude.ai/artifact/<id>` URLs conflicted because `main` had already made the same fix; the session took main's version (`55c231ff:117`–`55c231ff:128`).
- **Index republish aborted on purpose:** a diff of the live index page against the worktree rebuild showed the worktree would drop rows that exist only on the live page (`55c231ff:108`–`55c231ff:110`), so the index page was not republished.

## Uncertainties

- **Which outcomes Yulong observed, and which only tests show.** Yulong's report at `55c231ff:175` ("owner download works, public Copy works, public Download doesn't, the downloaded copy has no Download button") was against probe version 2. The version 3 behaviour — a greyed-out Download for public viewers and a working blob download in a local copy — is shown only by stubbed Playwright tests; Yulong sent no message after `55c231ff:184`, so no human has seen version 3.
- **"The viewer grants the save only to the owner"** (`55c231ff:207`, skill text in `f120eee`) is an inference from that one observation, not a documented platform rule.
- **Does the blob path work in every local context?** It is tested in headless Chromium only.
- **"No publish warning for a blob download"** rests on one publish (version 3, `55c231ff:197`); the older note it replaced may have described a platform behaviour that changed.
- **Remote branch:** a local remote-tracking ref `origin/worktree-artifact-download-html` still exists; whether `--delete-branch` removed it on GitHub was not checked.
- **`dotfiles-sync` interaction:** it is unknown whether the daily sync job, which commits and pushes this repo, will move the main checkout onto `main` or leave it on `website-vault-publish`.

## Yulong's instructions, cleaned up

1. (`55c231ff:1`) Add a "Download / Copy as HTML" button to artifacts, so the page can be shared with people who cannot open the Artifact itself.
2. (`55c231ff:175`) Report: it works; the downloaded HTML has no Download button ("I guess it's not needed?"); as a public-link viewer ("public member"), Copy HTML works but Download HTML does not. Approval: "Sure you can merge."
3. (`55c231ff:180`, `55c231ff:184`, read together) Show the Download HTML button to public viewers too, even where it cannot work. The session read this as: show it disabled with an explanation in the public viewer, and make it work in a downloaded local copy (`55c231ff:186`). That reading is an assumption; Yulong did not confirm it.
