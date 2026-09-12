---
name: server-storage-tiering
description: "Relieve a full root disk on a server or cloud box with an attached volume: expose it at /workspace, tier data by access pattern, move never rm."
---

# Server Storage Tiering

Two jobs, often at once: **(A) organize storage with portable conventions**, and **(B) place each thing where its access pattern wants it.** The forcing function differs by platform but the method is the same: measure, exclude what's live, relocate cold data to the volume with a symlink left behind, verify.

## Cardinal rules

- **Never `rm` user data.** Relocate with `mv` (or `rsync --remove-source-files`), leave a symlink at the original path, archive with `mv` to `/workspace/archive/`. `rmdir` (empty dirs only) and `unlink` (a single symlink you created) are the only deletions allowed.
- **Exclude live/hot directories first** — see [Live-writer gate](#the-live-writer-gate). This is the rule that prevents the worst failures.
- **Verify every relocation** before the next: the symlink resolves, the target is readable, the live job is still alive, `df` moved the right way.

---

## Pillar A — Conventions (portable layout)

Goal: the same paths resolve on every box, so projects and configs don't care which machine they're on.

### Expose the volume at `/workspace`
```bash
sudo chown "$USER:$USER" /mnt/<VOLUME>          # cloud volumes mount root:root — you can't write until this
sudo ln -s /mnt/<VOLUME> /workspace             # reversible; no fstab edit needed for the symlink itself
mkdir -p /workspace/{cache,share,outputs,archive,hf,torch,bun,projects-data}
```
`/workspace` is the RunPod convention; adopting it everywhere gives path parity.

**Prefer a bind mount over a symlink for `/workspace`**: `mount --bind /mnt/<VOLUME> /workspace` plus the fstab line `/mnt/<VOLUME> /workspace none bind,nofail,x-systemd.requires-mounts-for=/mnt/<VOLUME> 0 0` (then `systemctl daemon-reload`). With a symlink every canonical path — `pwd -P`, Claude Code's project keys, the sandbox allowlist, `lsof` — reads `/mnt/<VOLUME>/...`, so `~/.claude/projects` grows a second `-mnt-HC-Volume-...` key for the same repo and the sandbox `allowWrite` entry for `/workspace` never matches. `project-hub doctor` flags the symlink form.

### Research projects: one hub per project, hot on the fast disk, bulk on the volume

`~/projects/<name>/` is the unit — the same path on the Mac, a Hetzner box and a RunPod pod — and `project-hub` (`custom_bins/`) creates and maintains it:

```
~/projects/<name>/
├── code/  paper/  poster/     git repos, .venv inside      fast disk (NVMe)
├── data/                      inputs, weights at rest       volume
├── runs/                      eval logs, run outputs        volume
├── external/                  upstream clones               volume
└── archive/                   retired material              volume
```

- **Hetzner / bare-metal:** `~/projects` is a real dir on the root NVMe; the four bulk dirs are real under `$STORAGE_VOLUME/projects/<name>/` and the hub holds symlinks to them. Interpreter start-up, git and pytest stay on local IOPS; eval logs and weights sit on the big disk.
- **RunPod / Vast (ephemeral root):** `~/projects -> /workspace/projects`, everything real on the volume; `project-hub new` then makes plain dirs.
- **Mac:** no volume, plain dirs. `project-hub` reads `config/storage.conf` and decides per machine.
- **Inside a repo, bulk subdirs link relatively** — `code/logs -> ../runs/logs`, `code/data -> ../data` — so the checkout works unchanged on every box. `project-hub tier <name>/code logs data` makes the link after checking the dir is gitignored, has **no tracked files** (an `out/` that git ignores as a directory can still carry committed artifacts — that one stays in the repo) and had no writes in the last 15 minutes.
- **No `hub` symlink inside repos.** With the siblings in one directory `..` is the hub; Claude Code loads the hub's `CLAUDE.md` from the parent. A tracked absolute `hub -> /Users/...` link is a committed cross-machine bug.
- **Adopting existing repos:** `project-hub adopt <name> code=~/code/x paper=~/writing/y` renames on the same filesystem (never a cross-fs copy), runs `git worktree repair` for `.claude/worktrees/*`, renames `~/.claude/projects` and `~/.remember` encodings (leaving a compat symlink so `--resume` and old job records keep working), re-allows direnv and rebuilds the venv, whose console-script shebangs carry the absolute path.
- **Friction check:** `project-hub doctor` times interpreter start-up and the project import per repo and flags a venv on the volume; when it flags, point uv at a local env (`UV_PROJECT_ENVIRONMENT`) or move the repo to the fast disk rather than living with it.
- The forward link `/workspace/code -> ~/code` stays for path parity; the old `/workspace/projects -> ~/projects` direction is replaced by the hub layout above.

### Relocate-with-symlink-back (the core move)
```bash
mv  <src>           <dest-on-volume>
ln -s <dest-on-volume> <src>
```
Apps keep using their default path (`~/.cache/inspect_ai`, `~/.bun/install`); the symlink transparently redirects both old and new I/O to the volume. **No config edits, no env changes.** Store a relocated repo at `/workspace/<name>` (not under `/workspace/code`) so it doesn't form a loop with the `/workspace/code -> ~/code` link.

### Persistence
- The **volume** must be in `/etc/fstab` (cloud providers usually add it; confirm). Look for the `by-id` mount line; `nofail` is good practice so a missing volume doesn't block boot.
- **Symlinks** at `$HOME`/`/` persist inherently (they live on the root fs). `chown` on the volume persists (stored in the volume's own fs). So once fstab has the volume, nothing else needs persisting.

### Forward env vars (optional, for *future* growth only)
Set in the shell profile so new downloads land on the volume; needs a fresh shell to take effect. Not required for any relocation above.
```bash
export HF_HOME=/workspace/hf
export TORCH_HOME=/workspace/torch
# Leave UV_CACHE_DIR / PIP_CACHE_DIR at local defaults — they're latency-sensitive and may host live venvs.
```

**Already in dotfiles:** `config/aliases/storage.sh` (sourced by zshrc on every interactive shell) does this automatically when the volume exists — no manual profile edit needed. It deliberately **skips the export when the default cache path is already a symlink onto the volume** (a relocated `~/.cache/huggingface` redirects transparently; re-pointing `HF_HOME` would orphan the moved cache and force re-downloads), so an unset `HF_HOME` on a tiered box is correct, not a gap. The same file prints a one-line warning on shell start when root runs low. Scope boundary: zshrc-sourced env reaches interactive shells only — pueue daemons, cron and systemd services won't see it.

**The mount point and the warning threshold are per-machine**, not hardcoded — boxes differ (`/workspace` on RunPod, `/mnt/<volume>` elsewhere, nothing on a laptop). They come from `config/storage.conf` (gitignored; `config/storage.conf.example` documents both keys):

| Key | Default | Meaning |
|---|---|---|
| `STORAGE_VOLUME` | `/workspace` | Volume mount point; every export is skipped when the path is absent |
| `STORAGE_ROOT_WARN_GB` | `20` | Warn under this many GB free on `/`; `0` disables the warning |

Write it with **`storage-setup`** (`custom_bins/`, on PATH), which `./deploy.sh --only storage` also runs on every Linux box:

```bash
storage-setup                     # detect the volume, write config/storage.conf if absent
storage-setup --show              # what the shell fragment will actually use
storage-setup --volume /mnt/data --threshold-gb 50 --force
```

Detection prefers an existing `/workspace`, else the mounted block-device filesystem with the most free space, requiring at least 2x root's free space and at least 50G — so a second small disk or `/boot` never wins. It writes config only, never touching data, is idempotent (an existing config is left alone without `--force`), and treats "no volume here" as success.

---

## Pillar B — Latency-aware placement (tier by access pattern)

An attached/network volume is **slower than local NVMe** — Hetzner Ceph is roughly ~10× slower in IOPS than local SSD; RunPod network volumes run ~200–400 MB/s vs local NVMe's GB/s. Both *persist*, so on persistent-root boxes (Hetzner, bare-metal) the move is purely a **capacity + latency** decision. On RunPod the container disk is *ephemeral*, so persistence is the forcing function instead — but the placement table is the same.

| Keep on **local NVMe** (hot / latency-sensitive) | Move to **volume** (cold / sequential / at-rest) |
|---|---|
| Active code + working trees | Eval logs, run outputs, archived data |
| Live venvs / running interpreters (`uv`, `conda`) | Model weights & datasets **at rest** |
| Small hot tool caches (uv, pip, ruff) | Checkpoints, regenerable caches not in active use |
| **Random-access hot dataloader** | Cold/sequential write-once data |

**The staging rule (don't get this wrong):** symlink-in-place over the volume is correct *only for cold/sequential data*. A **hot random-access dataloader** symlinked to the volume bottlenecks on every read crossing the network. For those, **stage to local NVMe for the run** (`cp` the active shard local, train, delete the copy after) — keep the at-rest copy on the volume.

---

## Procedure

1. **Detect** disks and mounts: `df -hT`, `lsblk`, `cat /etc/fstab`.
2. **Measure** biggest consumers: `du -xh -d1 ~ | sort -rh | head` (the `-x` keeps it on one fs).
3. **Identify live/hot dirs and EXCLUDE them** — [Live-writer gate](#the-live-writer-gate) below.
4. **Expose `/workspace`** + create layout (Pillar A).
5. **Relocate biggest-cold-first**, one at a time, verifying each (Pillar A move + Pillar B tiering).
6. **Verify** (checklist below).

### The live-writer gate

**A directory with a live writer cannot be safely symlink-swapped.** Replacing a directory with a symlink is not atomic; if a process writes to it during the swap, you lose the race — new files reappear, `rmdir` fails, and a stray nested symlink gets created inside. Worse, a cross-filesystem `mv` changes inodes, so any process whose **cwd** is inside the dir, or which holds an **open file handle**, breaks.

Check immediately before each move — and know the check goes **stale in minutes**:
```bash
ps -ef | rg -i '<job-name>'                          # what's running
lsof 2>/dev/null | rg -F "$dir"                       # cwd or open handles under it (fast)
fd -t f --changed-within 15min . "$dir" | head        # recent writes
```
Rules of thumb:
- **Any open handle or cwd, or recent writes → do NOT move it.** Leave it local; revisit when idle.
- A clean snapshot (0 handles, 0 recent writes) is necessary but **not a guarantee** — re-check right before the move, and if the one-shot `mv` doesn't complete cleanly the first time (rmdir-not-empty, stray nested symlink), the dir is hot: **stop and leave it local.** Don't retry into a race.
- Common live dirs to exclude on an ML box: the running launcher's interpreter (`~/.local/share/uv`), live MCP/tool venvs (`~/.cache/uv`), any repo with an active editor/agent session or running eval (writes to `~/.cache/<tool>`, `~/.local/share/<tool>`).

### Interrupted-move recovery

A cross-fs `mv` killed mid-copy (e.g. a tool timeout) is **safe**: GNU `mv` copies the whole tree first and unlinks the source only after, so the source stays 100% intact and the dest holds a partial copy. Resume idempotently instead of restarting:
```bash
rsync -a --remove-source-files "$src/" "$dest/"      # skips already-copied, unlinks source per-file after transfer
fd -t d . "$src" | sort -r | xargs -r rmdir          # remove now-empty dirs deepest-first (children sort after parents)
rmdir "$src" && ln -s "$dest" "$src"                 # if rmdir fails "not empty", a writer is active → it's hot (see gate)
```
For dirs known to hold **many small files**, skip the foreground `mv` entirely and run the `rsync` in the background from the start — small-file copies over a network volume are slow and will blow a foreground timeout.

---

## Verification checklist

- `df -h /` shows space freed; `df -h /workspace` shows the volume carrying it.
- Each relocation resolves: `readlink -f <src>` points into the volume, `ls <src>` is readable.
- Live jobs untouched: the launcher PID is still alive; no moved path lies under a live dir.
- Tools still work through the symlinks (e.g. `bun --version`, read an eval log).
- Excluded hot dirs are still **real local dirs**, not symlinks: `[ -L <dir> ] && echo SYMLINK || echo local`.
- Reboot persistence: volume in `/etc/fstab`; symlinks persist inherently.

## Outcome shape (what "done" looks like)

Freed root by relocating cold data to the volume; left a symlink at every original path so apps need no reconfiguration; left every live/hot dir local and untouched. Anything not safely movable now (live writers) is documented for a later pass when those sessions are idle.
