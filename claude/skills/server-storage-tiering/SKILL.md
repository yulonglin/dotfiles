---
name: server-storage-tiering
description: >
  Relieve a full root disk and organize storage on a server/cloud box (Hetzner, RunPod,
  bare-metal GPU) that has an attached volume. Use when `/` is near 100%, when you need to
  expose a volume at `/workspace`, or when deciding what lives on fast local NVMe vs. a slower
  attached/network volume. Covers the conventions (volume at `/workspace`, standard layout,
  relocate-with-symlink-back, env vars, fstab) AND latency-aware placement (tier by access
  pattern: cold/sequential → volume, hot random-access → local). Move data, never `rm`.
---

# Server Storage Tiering

Two jobs, often at once: **(A) organize storage with portable conventions**, and **(B) place
each thing where its access pattern wants it.** The forcing function differs by platform but the
method is the same: measure, exclude what's live, relocate cold data to the volume with a
symlink left behind, verify.

## Cardinal rules

- **Never `rm` user data.** Relocate with `mv` (or `rsync --remove-source-files`), leave a
  symlink at the original path, archive with `mv` to `/workspace/archive/`. `rmdir` (empty dirs
  only) and `unlink` (a single symlink you created) are the only deletions allowed.
- **Exclude live/hot directories first** — see [Live-writer gate](#the-live-writer-gate). This is
  the rule that prevents the worst failures.
- **Verify every relocation** before the next: the symlink resolves, the target is readable, the
  live job is still alive, `df` moved the right way.

---

## Pillar A — Conventions (portable layout)

Goal: the same paths resolve on every box, so projects and configs don't care which machine
they're on.

### Expose the volume at `/workspace`
```bash
sudo chown "$USER:$USER" /mnt/<VOLUME>          # cloud volumes mount root:root — you can't write until this
sudo ln -s /mnt/<VOLUME> /workspace             # reversible; no fstab edit needed for the symlink itself
mkdir -p /workspace/{cache,share,outputs,archive,hf,torch,bun,projects-data}
```
`/workspace` is the RunPod convention; adopting it everywhere gives path parity.

### Code/projects parity (direction flips by platform)
- **Hetzner / bare-metal (root persists):** real dirs live in `$HOME`, add forward links for parity:
  `ln -s ~/code /workspace/code`, `ln -s ~/projects /workspace/projects`.
- **RunPod (container disk is ephemeral, `/workspace` persists):** real dirs live under
  `/workspace`, and `~/code` → `/workspace/code`. The direction is reversed but **both paths
  resolve in both environments.**

### Relocate-with-symlink-back (the core move)
```bash
mv  <src>           <dest-on-volume>
ln -s <dest-on-volume> <src>
```
Apps keep using their default path (`~/.cache/inspect_ai`, `~/.bun/install`); the symlink
transparently redirects both old and new I/O to the volume. **No config edits, no env changes.**
Store a relocated repo at `/workspace/<name>` (not under `/workspace/code`) so it doesn't form a
loop with the `/workspace/code -> ~/code` link.

### Persistence
- The **volume** must be in `/etc/fstab` (cloud providers usually add it; confirm). Look for the
  `by-id` mount line; `nofail` is good practice so a missing volume doesn't block boot.
- **Symlinks** at `$HOME`/`/` persist inherently (they live on the root fs). `chown` on the
  volume persists (stored in the volume's own fs). So once fstab has the volume, nothing else
  needs persisting.

### Forward env vars (optional, for *future* growth only)
Set in the shell profile so new downloads land on the volume; needs a fresh shell to take effect.
Not required for any relocation above.
```bash
export HF_HOME=/workspace/hf
export TORCH_HOME=/workspace/torch
# Leave UV_CACHE_DIR / PIP_CACHE_DIR at local defaults — they're latency-sensitive and may host live venvs.
```

---

## Pillar B — Latency-aware placement (tier by access pattern)

An attached/network volume is **slower than local NVMe** — Hetzner Ceph is roughly ~10× slower
in IOPS than local SSD; RunPod network volumes run ~200–400 MB/s vs local NVMe's GB/s. Both
*persist*, so on persistent-root boxes (Hetzner, bare-metal) the move is purely a **capacity +
latency** decision. On RunPod the container disk is *ephemeral*, so persistence is the forcing
function instead — but the placement table is the same.

| Keep on **local NVMe** (hot / latency-sensitive) | Move to **volume** (cold / sequential / at-rest) |
|---|---|
| Active code + working trees | Eval logs, run outputs, archived data |
| Live venvs / running interpreters (`uv`, `conda`) | Model weights & datasets **at rest** |
| Small hot tool caches (uv, pip, ruff) | Checkpoints, regenerable caches not in active use |
| **Random-access hot dataloader** | Cold/sequential write-once data |

**The staging rule (don't get this wrong):** symlink-in-place over the volume is correct *only
for cold/sequential data*. A **hot random-access dataloader** symlinked to the volume bottlenecks
on every read crossing the network. For those, **stage to local NVMe for the run** (`cp` the
active shard local, train, delete the copy after) — keep the at-rest copy on the volume.

---

## Procedure

1. **Detect** disks and mounts: `df -hT`, `lsblk`, `cat /etc/fstab`.
2. **Measure** biggest consumers: `du -xh -d1 ~ | sort -rh | head` (the `-x` keeps it on one fs).
3. **Identify live/hot dirs and EXCLUDE them** — [Live-writer gate](#the-live-writer-gate) below.
4. **Expose `/workspace`** + create layout (Pillar A).
5. **Relocate biggest-cold-first**, one at a time, verifying each (Pillar A move + Pillar B tiering).
6. **Verify** (checklist below).

### The live-writer gate

**A directory with a live writer cannot be safely symlink-swapped.** Replacing a directory with a
symlink is not atomic; if a process writes to it during the swap, you lose the race — new files
reappear, `rmdir` fails, and a stray nested symlink gets created inside. Worse, a cross-filesystem
`mv` changes inodes, so any process whose **cwd** is inside the dir, or which holds an **open file
handle**, breaks.

Check immediately before each move — and know the check goes **stale in minutes**:
```bash
ps -ef | rg -i '<job-name>'                          # what's running
lsof 2>/dev/null | rg -F "$dir"                       # cwd or open handles under it (fast)
fd -t f --changed-within 15min . "$dir" | head        # recent writes
```
Rules of thumb:
- **Any open handle or cwd, or recent writes → do NOT move it.** Leave it local; revisit when idle.
- A clean snapshot (0 handles, 0 recent writes) is necessary but **not a guarantee** — re-check
  right before the move, and if the one-shot `mv` doesn't complete cleanly the first time
  (rmdir-not-empty, stray nested symlink), the dir is hot: **stop and leave it local.** Don't
  retry into a race.
- Common live dirs to exclude on an ML box: the running launcher's interpreter
  (`~/.local/share/uv`), live MCP/tool venvs (`~/.cache/uv`), any repo with an active editor/agent
  session or running eval (writes to `~/.cache/<tool>`, `~/.local/share/<tool>`).

### Interrupted-move recovery

A cross-fs `mv` killed mid-copy (e.g. a tool timeout) is **safe**: GNU `mv` copies the whole tree
first and unlinks the source only after, so the source stays 100% intact and the dest holds a
partial copy. Resume idempotently instead of restarting:
```bash
rsync -a --remove-source-files "$src/" "$dest/"      # skips already-copied, unlinks source per-file after transfer
fd -t d . "$src" | sort -r | xargs -r rmdir          # remove now-empty dirs deepest-first (children sort after parents)
rmdir "$src" && ln -s "$dest" "$src"                 # if rmdir fails "not empty", a writer is active → it's hot (see gate)
```
For dirs known to hold **many small files**, skip the foreground `mv` entirely and run the
`rsync` in the background from the start — small-file copies over a network volume are slow and
will blow a foreground timeout.

---

## Verification checklist

- `df -h /` shows space freed; `df -h /workspace` shows the volume carrying it.
- Each relocation resolves: `readlink -f <src>` points into the volume, `ls <src>` is readable.
- Live jobs untouched: the launcher PID is still alive; no moved path lies under a live dir.
- Tools still work through the symlinks (e.g. `bun --version`, read an eval log).
- Excluded hot dirs are still **real local dirs**, not symlinks: `[ -L <dir> ] && echo SYMLINK || echo local`.
- Reboot persistence: volume in `/etc/fstab`; symlinks persist inherently.

## Outcome shape (what "done" looks like)

Freed root by relocating cold data to the volume; left a symlink at every original path so apps
need no reconfiguration; left every live/hot dir local and untouched. Anything not safely movable
now (live writers) is documented for a later pass when those sessions are idle.
