---
title: Download and copy page HTML
heading: Annotated artifacts can be downloaded or copied as HTML; the change is merged but not yet in your live checkout.
session: 55c231ff-61a7-424b-b0dd-11bf8a30c5ce
base: c2b56fcc2ebb59e6ebd5338fdd91bb62b0abb500
head: 9d5da32bcf9e077a9f45626683c610979ce0a863
asks: ["55c231ff:1", "55c231ff:175", "55c231ff:180", "55c231ff:184"]
story: |
  You asked for a "download/copy as HTML" button that works without access to the artifact. Pages built with the updated layer get a **This page** row: Copy HTML is always shown, Download HTML uses the viewer’s save capability or a browser-download path outside the viewer, and a reader without the save permission is meant to see Download greyed out ([the row](#item-page-row)). The file is the page as parsed when the layer starts, before it restores the reader’s comments ([what the file holds](#item-snapshot)).

  The change is merged into `origin/main` as #203, but the checkout that `~/.claude` and your `PATH` read from does not contain it yet ([found afterwards](#item-live-tree)). Your two messages after "Sure you can merge" asked for more; I added that and merged it without another reported viewer check ([merge](#item-merge-unseen)).
stats:
  - {n: 7, label: "commits, squash-merged as #203", item: git-state}
  - {n: 7, label: "files changed, +1707 −20 lines", item: git-state}
  - {n: 266, label: "of 271 layer tests pass; the 5 failures are in a group that also fails without this change", item: test-suite, warn: true}
foryou:
  - "Free `main` from the worktree `/home/yulong/code/dotfiles/.claude/worktrees/artifact-download-html`, which has it checked out, before you check out `main` anywhere else."
  - "Bring `c947b3a` into `/home/yulong/code/dotfiles` (now on `website-vault-publish`); until then, `md2artifact` on your `PATH` and the `artifact-writing` skill in `~/.claude` are the old versions."
  - "Add a row file for `artifacts/awake-while-connected/` and run `scripts/build_artifacts_index.py`, so the probe page's row appears in `ARTIFACTS.md`."
sections:
  - {id: row, title: The page row}
  - {id: followup, title: Changes after your check}
---

## The updated annotation layer adds a "This page" row holding Download HTML and Copy HTML

```yaml
id: page-row
section: row
nav: The page row
lede: "The row is in the shared annotation layer, so `md2artifact` and `annotate-html` both add it. Copy HTML is always shown; copying depends on clipboard access. Download HTML depends on where the page is read."
```

The row sits under the "Your comments" panel. What each reader gets from it, as the code stands at `9d5da32`:

| Where the page is read | Download HTML | Copy HTML |
|---|---|---|
| Artifact viewer that grants the `downloads` capability | Saves through the viewer, which shows a confirmation first | Attempts to copy the page |
| Viewer where `claude.use("downloads")` returns `null` | Shown greyed out as "Download HTML (not available here)" | Attempts to copy the page |
| A downloaded copy without the viewer API | Browser-download path; opening from disk is untested | Attempts to copy the page |

You reported obtaining a downloaded copy. The second row's greyed-out button was added after your check and no viewer check of it is recorded ([open question](#item-public-v3)).

Strings the reader sees, all in the row:

- Labels: "This page", "Download HTML", "Copy HTML", and "Download HTML (not available here)" with the hover text "This viewer does not let the page save files. Copy HTML works everywhere."
- Notes beside the buttons after a click: "saved", "a save prompt is already open", "download unavailable here — use Copy HTML", "page HTML copied", "clipboard blocked here".

The file name comes from the page title, lowercased with runs of other characters turned into hyphens: a page titled "Review sample" saves as `review-sample.html`. When the clipboard refuses, Copy HTML falls back to a hidden textarea and `execCommand("copy")`.

```ref
diff: custom_bins/_annotation_layer.py
title: The row and its buttons
focus: L334-L339, L1450-L1516
labels:
  - {line: 335, where: "Row label, under the Your comments panel"}
  - {line: 336, where: "Download button"}
  - {line: 337, where: "Copy button"}
  - {line: 1472, where: "Download button, when the viewer gives no save permission"}
  - {line: 1473, where: "Hover text on the greyed-out Download button"}
  - {line: 1493, where: "Note beside the row after a save"}
  - {line: 1497, where: "Note when a save prompt is already open"}
  - {line: 1499, where: "Note when the viewer refuses the save"}
  - {line: 1514, where: "Note after Copy HTML works"}
  - {line: 1515, where: "Note when the clipboard refuses"}
```

## The file captures the parsed page before the layer restores the reader’s comments

```yaml
id: snapshot
section: row
nav: What the file holds
lede: "The layer copies the page's HTML when its script starts, before it puts back any reader's highlights, suggested edits or ticks."
judgement-call: true
alternatives:
  - "Copy the live page at click time and strip the reader's marks: it would include anything drawn after the script started, but every kind of mark must be stripped correctly, or one reader's notes go into the file."
  - "Remove the comment layer from the file: a smaller file, but the copy could no longer be annotated and would have no Copy or Download buttons."
```

A reader's comments live in their own browser storage and are painted onto the page after it loads. I took the copy before that painting starts, so the file holds none of them. Without that, the next reader's quoted passages could anchor inside the first reader's inserted text. Saving or copying the page also does not mark the comments as exported, because the page is not the feedback.

The worked example in the tests: a comment "zqx reader note" and a suggested edit "replacement words" are saved, the page is reloaded so both come back from storage, and then Download is pressed. The saved file contains neither string and no highlight elements, and both comments are still marked as not copied out.

The cost of copying at script start: anything another script adds to the page after that moment is not in the file. One case where that may matter is [Mermaid diagrams](#item-mermaid-copy).

The first version had a bug caught by a test added after the final review ([the check](#item-advisor-review)). The script contained the full text of the layer's closing marker, `<!-- /annotation-layer -->`, and `strip_layer` ends its removal at the first copy of that text. So `annotate-html --force` would have removed only part of an old layer and left the rest on the page. In `8adbf5b` I split that text in two inside the script and always add the real marker back to the copy.

```ref
diff: custom_bins/_annotation_layer.py
title: Copying the page at script start
focus: L370-L382
```

```ref
transcript: 55c231ff:147, 55c231ff:162
summary:
  - The new round-trip test fails on the first version
  - The fix is committed as 8adbf5b
```

## The artifact-writing skill now tells agents to publish every annotated page with the downloads capability

```yaml
id: capability-rule
section: row
nav: Skill rule
lede: "The skill’s claim about who can download rests on a single check: \"Download reaches the owner only\"."
judgement-call: true
alternatives:
  - "Declare `downloads` only on pages meant to leave the viewer: fewer pages carry the capability, but a page without it would show a greyed-out Download to you as the owner too."
```

Download in the viewer works only when the publish declared `capabilities: {"downloads": true}`, so I made that the default in the skill. The skill also says a later publish that leaves `capabilities` out keeps what was declared before.

What could mislead a future agent: the skill says "Download reaches the owner only", citing your check on 2026-09-24. Your report said "when I'm a public member", without saying whether that reader was signed in, so "owner only" is wider than what was established.

The section heading also changed from "The viewer sandbox refuses modals and downloads" to "… refuses modals and plain downloads", and the old claim that a page with a plain download link makes every publish warn is removed ([why](#item-local-copy)).

```ref
diff: claude/skills/artifact-writing/SKILL.md
title: The skill's new rules
focus: L59-L61, L90-L94
```

## The final change leaves older pages without the new This page row

```yaml
id: existing-pages
section: row
nav: Old pages
lede: "A hosted page gets the row when it is rebuilt with the new layer and republished; the capability enables its viewer download. I asked whether you want that done and stopped there."
judgement-call: true
alternatives:
  - "Rebuild and republish every page in artifacts/: each needs its own rebuild and one publish, and each publish to an existing URL first needs the live version read, so content saved from inside a page is not lost."
```

The built HTML under `artifacts/*/` is a frozen copy of the layer from when each page was built; The final diff leaves those existing files unchanged. My final reply asked you to say if you want the sweep done.

```ref
transcript: 55c231ff:68
summary:
  - The old "no download path" comment is still in several built pages under artifacts/
```

## A copy without the viewer API now gets a browser-download path

```yaml
id: local-copy
section: followup
nav: Download in a copy
lede: "You noticed the downloaded file had no Download button. With no callable viewer API, the copy now uses an ordinary browser download."
```

The first version had this fallback, and I removed it before the first commit. An existing test forbade it, and the skill said a page with a plain download link "makes every publish warn". After your message I put it back, but only when there is no callable `window.claude.use`. The skill records that a plain download link does nothing inside the viewer.

I tested the warning claim with one publish (version 3 of the probe page) that carried the download link. No warning came back, so I removed that claim from the skill. That is one publish, not a rule about every page.

```ref
transcript: 55c231ff:42, 55c231ff:197
summary:
  - I remove the plain-download fallback to satisfy the old test
  - Version 3 publishes with the fallback in it and no warning
```

## A reader without the save permission now sees Download greyed out, not hidden

```yaml
id: public-shows-disabled
section: followup
nav: Greyed-out Download
lede: "This is how I read \"it might be nice to see the download HTML button / When public\": keep the button visible when the viewer withholds the save capability."
judgement-call: true
alternatives:
  - "Keep it hidden, as in the version you checked: a public reader sees only Copy HTML and no button that does nothing."
  - "Show it enabled and, on click, show a note pointing to Copy HTML: the button looks the same for everyone, but a public reader learns that it does nothing only after clicking."
```

Your public-view check did not yield a download. I treated that as missing save permission: when the viewer withholds the capability, the button is greyed out, labelled "(not available here)", and its hover text points to Copy HTML.

If the viewer turns out to give a public reader a capability that then rejects the save as unavailable, the button shows enabled until it is clicked, and then turns grey and shows "download unavailable here — use Copy HTML". Which of the two happens is [still open](#item-public-v3).

```ref
diff: tests/test_md2artifact_browser.py
title: Tests for the three cases
focus: L1288-L1320
```

## Your check: you obtained a downloaded copy; as a public viewer Copy HTML worked and Download did not

```yaml
id: user-check
section: checked
nav: Your check
lede: "This led to three commits: one recorded the result in the skill and the probe's index row, one added the greyed-out button and the local-copy download, and one updated the skill to match."
```

You checked version 2 of the probe page. Your words: "Copy HTML works when I'm a public member, but download HTML doesn't", and "the downloaded HTML doesn't have a download HTML button". Version 2 hid Download when the viewer gave no capability, so it is not clear whether you saw a button that failed or no button at all. The work after this check is in [the greyed-out button](#item-public-shows-disabled) and [Download in a copy](#item-local-copy).

```ref
transcript: 55c231ff:175
summary:
  - You report the result of your check and say I can merge
```

## A round-trip test after the final review caught the broken annotate-html --force path

```yaml
id: advisor-review
section: checked
nav: Final review
lede: "The review was an advisor call, and its text is stored encrypted in the transcript. What followed is visible: a test that failed, then a fix."
```

I wrote a test that adds the layer to a page, removes it again, and requires the original page back. It failed on the first version and passed after the fix. The fix is described in [what the file holds](#item-snapshot).

```ref
diff: tests/test_annotate_html.py
title: The round-trip test
focus: L93-L106
```

## Layer test suites: 266 of 271 pass; the 5 failures are in a group of suggested-edit timing tests that also fails without this change

```yaml
id: test-suite
section: checked
nav: Test suites
lede: "Which suggested-edit tests failed changed between full-suite runs (3, 4 or 5 of them), and 2 of the same 4 failed on the checkout without this change."
```

I ran the eight layer suites several times. After the test-setup fixes, the full-suite failures reported were 3-second timeouts in suggested-edit tests, and the set of failing tests changed between runs. To check whether my change caused them, I ran the same 4 tests in the main checkout, which was then on `website-vault-publish`; its layer file is the same as `origin/main`'s at the time. 2 of the 4 failed there too. The fifth test that failed was not run there. I take them as flaky tests from before this change (about 85% confident). This was not tested more closely, for example by running the suites many times on each side.

```ref
transcript: 55c231ff:46, 55c231ff:49, 55c231ff:192
summary:
  - 2 of the 4 timing tests fail on the checkout without this change
  - In the worktree, 2 and then 1 of the same 4 fail
  - The last full run, 266 passed and 5 failed
```

## Four browser tests and one round-trip test cover the new row

```yaml
id: new-tests
section: checked
nav: New tests
lede: "They check the local-copy download, the greyed-out button, the clean saved file and Copy HTML; the viewer's own capability is replaced by a stub."
lower-priority: true
```

The stub stands in for `claude.use("downloads")`, so these tests check the page's side only. Whether the real viewer gives the capability was checked only by you. The new and revised tests initially had four bugs (two text matches that also hit other text on the page, a count that also matched the function's own definition, and an event handler Playwright refused), which I fixed in the tests, not the code. The test that used to forbid any download path now allows the plain download only where there is no viewer.

```ref
diff: tests/test_annotate_html.py
title: The changed no-download test
focus: L188-L204
```

## One publish with the plain download link raised no warning

```yaml
id: no-warning-check
section: checked
nav: Publish warning
lede: "Version 3 of the probe page published without a warning, which removed a claim the skill had made; the evidence is in Download in a copy."
lower-priority: true
```

See [Download in a copy](#item-local-copy).

## Does a public-link reader of version 3 see Download greyed out, or an enabled button that fails?

```yaml
id: public-v3
section: unverified
nav: Public view of v3
lede: "You checked version 2; version 3, with the greyed-out button, was published after your last message."
```

The check: open the probe page from its public link in a private window and look at the This page row, click Download if it is enabled. Estimated effort: about a minute. This checks [the greyed-out button](#item-public-shows-disabled) for a signed-out reader, not whether signed-in non-owners can download ([the skill rule](#item-capability-rule)). Probe page: https://claude.ai/artifact/DHxg1ZG6BqraAdXUJtr5n6

## Does a downloaded copy show Mermaid diagrams?

```yaml
id: mermaid-copy
section: unverified
nav: Mermaid in a copy
lede: "md2artifact leaves Mermaid diagrams for the viewer to draw, and a downloaded file has no viewer."
```

If the viewer draws the diagrams before the layer copies the page, the copy holds the drawn diagrams. If it draws them later, the copy holds only the diagram source as text. The check: build a page with a Mermaid block, publish it with the capability, download it, and open the file. Estimated effort: a few minutes. The answer affects [what the file holds](#item-snapshot), and a viewer that injects other content before or after the copy would raise the same question.

```ref
file: custom_bins/md2artifact
at: head
range: L80-L88
```

## Does Download work in a copy opened from disk (file://)?

```yaml
id: file-protocol
section: unverified
nav: Download from disk
lede: "The tests serve the page from a local web server, not from file://, and the copy you opened was made before this path existed."
```

The check: download a page with version 3 of the layer, open the file from disk, and press Download. Estimated effort: about a minute. The answer affects [Download in a copy](#item-local-copy).

## Git state: squash-merged into origin/main as c947b3a, and the worktree was left with main checked out

```yaml
id: git-state
section: landing
nav: Git state
lede: "Found afterwards: `gh pr merge --delete-branch`, run inside the worktree, switched it to `main`. Git normally blocks checking out `main` in a second worktree."
judgement-call: true
alternatives:
  - "Merge without `--delete-branch` and delete the branch afterwards: the worktree would have stayed on its own branch, and `main` would be free."
  - "Remove the worktree right after the merge: `main` would be free, and the scratch files in its `tmp/` would be gone too."
```

- The 7 commits `c635d43`..`9d5da32` sit on `c2b56fc`, which was `origin/main` when I rebased. PR #203 squash-merged them as `c947b3a`, and its files are the same as `9d5da32`'s.
- The remote branch was deleted by the merge. Locally, the branch `worktree-artifact-download-html` is gone, and a stale remote-tracking ref to it is still listed today.
- The worktree `/home/yulong/code/dotfiles/.claude/worktrees/artifact-download-html` has `main` checked out at `c947b3a`, now 7 commits behind `origin/main`. The "create mode" lines in the merge output came from that update. Removing the worktree frees `main`.
- I also rewrote the PR body on GitHub and marked the PR ready before merging.

```ref
git: true
```

```ref
transcript: 55c231ff:203, capture:worktree-state
summary:
  - The PR is marked ready and squash-merged; the merge updates a local main
  - The worktree today, on main and 7 behind origin/main
```

## Found afterwards: a week later, the checkout that ~/.claude and PATH use still lacks the change

```yaml
id: live-tree
section: landing
nav: Not yet live
lede: "`~/.claude` links to `/home/yulong/code/dotfiles/claude`, and that checkout is on `website-vault-publish`, which does not contain `c947b3a`."
```

My final reply said the change "takes effect once your main checkout pulls `c947b3a`; the daily `dotfiles-sync` job will do that." On 2026-10-01 the checkout is on `website-vault-publish` and does not contain the commit. Its layer file has no Copy HTML button, and its `artifact-writing` skill has no This page rule. So pages built with `md2artifact` from your `PATH` still get the old layer, and agents still read the old skill. I did not find out why the sync job has not brought it in.

```ref
transcript: capture:live-tree
summary:
  - "The checkout's branch, whether it contains c947b3a, and counts of the new button and the new skill rule"
```

## I merged three commits after your check without another reported viewer check

```yaml
id: merge-unseen
section: landing
nav: Merge
lede: "\"Sure you can merge\" came at 06:34:31 UTC; your two follow-up messages came 9 and 20 seconds later; I started the merge command at 06:38:47 with the greyed-out button and the local-copy download in it."
judgement-call: true
alternatives:
  - "Push the follow-up commits, republish the probe and wait for you to look before merging: one more round with you, and you could have checked the changed buttons in the viewer before the merge."
```

I took your merge permission to cover the follow-up changes. The three commits after your check were `f120eee` (recording your check), `f066fb5` (the button changes) and `9d5da32` (the skill update). The code commit passed the new tests, and version 3 of the probe published without a warning. No viewer check of those changes is recorded before the merge ([open question](#item-public-v3)).

```ref
transcript: 55c231ff:175, 55c231ff:180, 55c231ff:184, 55c231ff:196
summary:
  - You say I can merge
  - You ask to see the Download button
  - "\"When public\""
  - I commit the greyed-out button and the local-copy download
```

## The index rebuild was discarded and its republish refused, leaving no probe row in ARTIFACTS.md

```yaml
id: index-deferred
section: landing
nav: Artifacts index
lede: "The probe's row file `artifacts/download-probe/meta.yml` is committed, but on `main` the generator stops on `artifacts/awake-while-connected/`, which has no row file."
judgement-call: true
alternatives:
  - "Add a row file for awake-while-connected myself and regenerate: the index would be complete now, but I would be writing the record for another session's page."
```

The house rule is to republish the index page after every publish. My first attempt, from the worktree, was refused because I had not read the live source in full. Comparing the two showed that the worktree was missing rows the live page had, so republishing from it would have dropped them. After the rebase onto `origin/main`, the generator stopped on `awake-while-connected`. So I committed only my row file and left `ARTIFACTS.md` and the index page as `main` had them. As of the last fetch, `origin/main` still has no row file for that directory and no probe row in `ARTIFACTS.md`.

```ref
transcript: 55c231ff:105, 55c231ff:108, 55c231ff:121
summary:
  - The index republish is refused until the live source is read in full
  - The live index has rows the worktree does not
  - The generator stops on a directory with no row file
```

## The branch first forked from website-vault-publish; I rebased my commits onto origin/main before pushing

```yaml
id: rebase
section: landing
nav: Rebase
lede: "Without this, the PR would have carried 4 unrelated commits from website-vault-publish."
lower-priority: true
```

The worktree was created from the local checkout's `HEAD`, which was `website-vault-publish`. I rebased my 3 commits onto `origin/main` with `git rebase --onto`. The third commit conflicted: `origin/main` had already made the same fix I had made to `scripts/build_artifacts_index.py` (accepting the new short artifact URL form) and its test. I kept `main`'s version and dropped mine, so that commit was reduced to the probe's row file.

```ref
transcript: 55c231ff:111, 55c231ff:115, 55c231ff:129
summary:
  - The branch carries commits from website-vault-publish
  - The rebase onto origin/main stops on the index commit
  - After the rebase, 3 commits on origin/main
```

## I published a probe page with the downloads capability, in three versions

```yaml
id: probe-page
section: landing
nav: Probe page
lede: "Its source is committed under `artifacts/download-probe/`, and the publish results reported it readable only by you; I did not change its sharing."
lower-priority: true
```

Version 1 tested whether a publish accepts the `downloads` declaration (it does). Version 2 carried the marker fix, and version 3 the greyed-out button and the local-copy download. My first publish from `tmp/` was blocked by a hook that requires a committed source under `artifacts/`, which is why the probe is in the repo.

```ref
transcript: 55c231ff:79, 55c231ff:165, 55c231ff:197
summary:
  - Version 1 published with the downloads capability
  - Version 2, with the marker fix
  - Version 3, with the greyed-out button and the local-copy download
```

```ref
diff: artifacts/download-probe/download-probe.md
title: The probe page's source
```

```ref
diff: artifacts/download-probe/meta.yml
title: The probe page's index row
```

```ref
diff: artifacts/download-probe/download-probe.html
title: The built probe page
```

## Scratch files are left in the worktree's tmp/ and in the session's job directory

```yaml
id: scratch-files
section: side-effects
nav: Scratch files
lede: "`tmp/probe/`, `tmp/fix_marker.py`, `tmp/t.md` and `tmp/t.html` in the worktree (ignored by git), and the PR body draft at `~/.claude/jobs/55c231ff/tmp/pr203.md`."
lower-priority: true
```

The cleanup commands for `tmp/probe/` and `tmp/fix_marker.py` prompted for confirmation and left them in place. They go when the worktree is removed, except the PR body draft.

```ref
transcript: 55c231ff:77, 55c231ff:162
summary:
  - rm asks before removing tmp/probe, and it stays
  - rm asks before removing the patch script, and it stays
```
