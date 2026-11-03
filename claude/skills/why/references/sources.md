# Evidence sources for `why`

One investigator per source. Each section says what the source holds, what reaches it, and how to search it. A source no tool reaches in this session is skipped with that reason and reported as a gap.

## Source control (always)

Holds commit messages, diffs, PR bodies and review threads, code comments, tests (whose names often encode the motivating edge case), co-changed files, CHANGELOG and docs in the repo. The most trustworthy source and the one tied to the code.

```bash
git log --follow --oneline -- <file>          # history through renames
git log -S '<exact string>' -- <file>          # commits that added/removed it
git log -G '<regex>' -- <file>
git blame -L <start>,<end> <file>
git show <hash>
gh pr view <n> --json title,body,comments,reviews
gh search prs --repo <owner/repo> '<keyword>'
rg -n -C2 '(TODO|FIXME|HACK|XXX|NOTE)' <file>
rg -l '<symbol>' --glob '*test*'
```

In this dotfiles repo also check `archive/` (dated retired versions with the reason in the folder name), `docs/`, and the commit that added a rule sentence — its message usually names the incident.

## Session transcripts and memory (always)

Holds the conversations that wrote agent-authored code: the user's actual words, the options weighed, what failed first. Files: `~/.claude/projects/<encoded-cwd>/*.jsonl`, where the encoding replaces each `/` and `.` in the working directory with `-` (worktree sessions have their own encoded directory under the repo's path); `~/.remember/<encoded-cwd>/` (`remember.md` handoff, `now.md`, `today-*.md`, `recent.md`, `archive*.md`); and `~/.claude/projects/<encoded-cwd>/memory/`.

Transcripts are large (hundreds of MB per repo). Never read a whole file. Search, then read only matching lines:

```bash
rg -l '<distinctive string>' ~/.claude/projects/<encoded>/        # which sessions
rg -n -o '.{0,300}<distinctive string>.{0,300}' <file.jsonl> | head  # context
```

Narrow by the commit dates from the anchor (file mtimes, or the `timestamp` field). Prefer the user's own messages (`"type":"user"` lines without `tool_result`) over the assistant's account of them.

## Specs, plans, artifacts and notes

Holds the design rationale written before the code. `artifacts/<slug>/` (source of each published spec or report), `ARTIFACTS.md` (URL → what it established), `docs/`, the private `dotfiles-personal` repo (`plans/`, `specs/`), and `~/vault/` (`research/`, `tooling/<repo>/`). Published Artifacts: `Artifact` action `read`. Search the local trees with `rg -l -i '<keyword>'`.

## Long-form documents

Notion (`notion-search`, `notion-fetch`), Google Drive and Docs (`search_files` with `pageSize` at most 10, paging with `pageToken`; `read_file_content`; or `gws`), Bear (macOS only; load `bear` first and follow its size-then-outline read playbook). Search the feature or symbol name and the decision's vocabulary. Read every section that matches, not only the title or first screen, since the reason is often in a comment or a later section — but never open an unsized note or page whole.

## Team chat

Slack (`slack_search_public_and_private` with `limit` at most 10 and `include_context: false`, paging with the cursor — `block_bulky_mcp_search.sh` refuses anything larger; then `slack_read_thread`). Search the symbol, the PR number and the feature name within the anchor's date window; read whole threads.

## Meetings

Granola (`search_meetings` for the topic and window, then `search_transcripts` for the specific term; notes summarise and drop specifics). Report what was said in your own words with the meeting link; do not quote transcript speech.

## Email

Gmail (load `gmail-connector`; `search_threads` with a narrowed query and `pageSize` at most 10, then `get_thread`). Useful when the forcing function was external: a reviewer, a collaborator, a vendor, a deadline.

## Issue trackers

GitHub issues (`gh issue list --search`, `gh issue view <n> --comments`) and Linear (`list_issues`, `get_issue`). Follow parent and sibling issues.

## Experiment records (research repos)

Run directories (`runs/`, `out/`, `logs/`, `/workspace/...`), `.eval` logs (`read_eval_log()`, or `check-transcripts <path> --max-samples 10` for a sampled readable view), result pages and their `ARTIFACTS.md` rows. They show what was measured before a threshold or default was set — "where did 0.7 come from" is often answered by a sweep here.

## Defensive code

When the target guards, retries, times out, limits, flags, or refuses (including a hook or a permission rule), add incident-flavoured queries in each source: commits named "fix", "revert", "re-apply", "guard", "incident", "lost", "deleted"; transcript and chat messages around those dates containing "broke", "lost", "wiped", "why did", "never again". Rules in this setup often carry the incident date in parentheses — search that date.
