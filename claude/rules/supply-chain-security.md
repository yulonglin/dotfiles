# Supply Chain Security

## When Adding Dependencies

Before installing ANY new package (npm, pip, bun, uv), state:
1. Package name and exact version
2. Weekly downloads (check npm/PyPI)
3. Package age and maintainer count
4. Whether it has postinstall/lifecycle scripts

Flag packages with <1,000 weekly downloads or <6 months old as potential risks.

## min-release-age Quarantine (IMPORTANT)

All package managers are configured with a **7-day quarantine** (`min-release-age`). Packages published less than 7 days ago will fail to install. This is intentional — it blocks supply chain attacks that are typically caught within days.

**When install fails due to min-release-age:**
1. This is NOT a bug — it's working as intended
2. Tell the user: "Package X@Y was published less than 7 days ago. The 7-day quarantine is blocking it."
3. Suggest alternatives:
   - Wait for the quarantine to expire (safest)
   - Use a known-good older version: `npm install package@<previous-version>`
   - Override for this install only (user must confirm): `npm install --min-release-age=0 package`
4. **Never** silently bypass the quarantine or suggest disabling it globally

**Per-manager override syntax:**
- npm: `npm install --min-release-age=0 <pkg>`
- bun: `bun add --minimumReleaseAge=0 <pkg>` (or remove from bunfig.toml temporarily)
- pnpm: `pnpm add --minimum-release-age=0 <pkg>` (or set to 0 in global rc temporarily)
- uv: `UV_EXCLUDE_NEWER= uv pip install <pkg>` (unset the env var for this command)

## Python Dependencies

- Use `uv pip compile --generate-hashes` to produce hash-pinned requirements
- Use `uv pip install --require-hashes -r requirements.txt` when installing
- For `uv add`: verify package on PyPI before adding

## JavaScript/TypeScript Dependencies

- Global `~/.npmrc` has `ignore-scripts=true` — do not override without user approval
- bun ignores lifecycle scripts by default (trustedDependencies allowlist)
- After adding dependencies: run `socket report` if socket CLI is available
- If lockfile changes, note added/removed/updated packages in commit message

## Never Do

- Install packages from arbitrary URLs or git repos without user approval
- Run `npm install --ignore-scripts=false` without explicit user confirmation
- Add packages to bun's `trustedDependencies` without stating why
- Skip hash verification for production Python dependencies
- Bypass min-release-age quarantine without explicit user approval

## Secrets Awareness

- API keys are scoped per-project via direnv `.envrc`, NOT globally exported
- If a project needs an API key, use `setup-envrc` to set up the repo `.envrc`
- Never hardcode secrets; verify `.envrc` is in `.gitignore`
