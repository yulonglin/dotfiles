# The container suite is the Linux half of the install check

`bash tests/test_installers_container.sh` runs the real `install.sh` and `deploy.sh` end to end on a throwaway `ubuntu:24.04`, then asserts what each run resolved. It exists because the two guards that came before it can each be satisfied by a run that did nothing: `tests/test_no_stall.sh` reads the scripts statically, and `no-stall.yml`'s unattended job runs them on the GitHub runner under `--minimal`, where "deployed nothing" and "succeeded" print the same thing.

| Command | What it does | Wall clock |
|---|---|---|
| `bash tests/test_installers_container.sh` | Full run: fresh install, fresh deploy, both re-run, then the flag contract | ~9 min cold, ~7 min warm |
| `bash tests/test_installers_container.sh --quick` | The flag contract only, no end-to-end leg | ~1 min |
| `bash tests/test_installers_container.sh --mutate` | Removes the empty-set guard in the image and requires the suite to notice | ~1 min |
| `bash tests/test_installers_container.sh --keep` | Leaves the image behind for `docker run -it --entrypoint /bin/bash …` | — |

No container runtime exits 77, the runner's skip code, rather than failing.

`tests/run-all.sh` discovers this file and caps every suite at 600 s, which a nine-minute run of live apt and upstream installers would lose a coin flip against. So the suite is opt-in whenever its output is captured: a human at a terminal gets the real run, and anything else gets exit 77 unless `DOTFILES_CONTAINER_TESTS=1` asks for it by name.

## What it asserts

Every assertion reads the banner both scripts print before they do any work, because that line is the only statement of the resolved set a user ever sees. The rule under test is the README's: flags are additive to the profile's defaults unless `--minimal` is used.

- A fresh `install.sh` and `deploy.sh` on a clean machine exit 0, and the completion line carries the same count the banner announced.
- Re-running both over the existing install exits 0 and resolves identically.
- `--minimal` resolves to nothing, says `Components: none`, and reports `(0 components)` rather than a bare "complete!".
- `--no-<x>` removes exactly one component; `--<y>` adds exactly one to the profile's set rather than replacing it; `--minimal --<y>` yields exactly that one.
- `--only <a macOS-only component>` on Linux exits 1 and says it is refusing an empty run, instead of reporting success.
- With no terminal the menu is skipped rather than waited on, and the profile's set survives unchanged.

## What it cannot cover, and what covers it instead

- **macOS.** Every platform branch is different code — Homebrew, `chsh` under PAM, `mas`, the `defaults` writes. Only a manual pass on a Mac covers it.
- **The menu drawing and being keyed.** That needs a pty with a real terminal that nobody types at; `</dev/null` and `script -qec` both close stdin and cannot reproduce it. The harness for it is `tests/pty_drive.py` in PR #134.
- **Anything with credentials, a GUI, or an App Store session** — `gh auth`, Bitwarden, `mas`, app-picker, the VPN daemon.
- **`cargo`.** The image has no Rust, so `deploy.sh`'s backgrounded `claude-tools` build is skipped rather than exercised. `no-stall.yml` bounds that build; the canary asserts the deadline exists.
- **The apt mirror and every upstream installer** are live. A run is only as green as `nodejs.org`, `deb.nodesource.com`, GitHub Releases and Homebrew are on the day.

## Why the image looks the way it does

Stock `ubuntu:24.04` plus only what a person would already have before cloning: `git`, `zsh`, `sudo`, `curl`, `ca-certificates`. Everything else is `install.sh`'s job, and installing it in the Dockerfile would hide a regression.

The repo arrives as `git archive HEAD`, so the image carries the committed tree and never the working copy; the driver warns when the installers have uncommitted edits. It is re-inited as a real, non-worktree git repo, so the `git-hooks` component has a `.git/hooks` to write into and `guard_not_worktree` sees a main checkout — passing `--allow-worktree` would mask a regression in the guard.

`SHELL` is deliberately left unset, which is how `cron`, a systemd unit and `scripts/cloud/setup.sh`'s own `sudo bash -c` invoke these scripts. That is not a synthetic condition: it is the state that found `set_zsh_default`'s unguarded `$SHELL`.
