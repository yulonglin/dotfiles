# Plan: Handle Gatsby Build Warnings

## Investigation Summary

Three categories of warnings appear during builds:

### 1. baseline-browser-mapping (~22 warnings/build)
```
warn [baseline-browser-mapping] The data in this module is over two months old.
```

**Root Cause:**
- Package v2.9.19 explicitly listed in devDependencies
- Package emits warning when bundled data >2 months old
- This is intentional by maintainers to encourage updates

**Dependency Chain:**
```
yulonglin-portfolio (devDependencies)
├── baseline-browser-mapping@2.9.19 (directly installed)
└── gatsby@5.16.0
    └── browserslist@4.28.0
        └── baseline-browser-mapping@2.8.29 (transitive)
```

### 2. punycode Deprecation (~3 warnings/build)
```
DeprecationWarning: The `punycode` module is deprecated.
```

**Root Cause:**
- Node.js v25.5.0 deprecated built-in punycode module
- Multiple packages still use it:
  - `whatwg-url@5.0.0` (via gatsby → node-fetch)
  - `uri-js@4.4.1` (via eslint → ajv)
  - `tr46` (dependency of whatwg-url)

### 3. addKeyword Deprecation
```
warn these parameters are deprecated, see docs for addKeyword
```

**Root Cause:**
- `ajv-keywords@3.5.2` using deprecated function signature
- Currently NOT appearing in builds (not triggered)

---

## Solution Options (Ranked by Feasibility)

### Option A: Suppress Warnings (Immediate, No Risk)

**What it does:** Hide warnings without changing dependencies

**Implementation:**
1. Add environment variable to package.json scripts:
```json
"scripts": {
  "dev": "NODE_NO_DEPRECATION=1 gatsby develop 2>&1 | grep -v 'baseline-browser-mapping'",
  "build": "NODE_NO_DEPRECATION=1 gatsby build 2>&1 | grep -v 'baseline-browser-mapping'"
}
```

**Pros:**
- ✅ Immediate effect
- ✅ Zero risk of breaking build
- ✅ Works for all warnings

**Cons:**
- ❌ Warnings still exist (just hidden)
- ❌ May hide legitimate deprecation notices
- ❌ Not a "real" fix

---

### Option B: Remove baseline-browser-mapping devDependency (Low Risk)

**What it does:** Let transitive dependency (via browserslist) provide the package instead

**Implementation:**
```bash
# 1. Remove explicit devDependency
bun remove baseline-browser-mapping

# 2. Reinstall
bun install
```

**Why this works:**
- Gatsby → browserslist already brings in baseline-browser-mapping@2.8.29
- No need for explicit devDependency
- The transitive version might be newer or emit fewer warnings

**Pros:**
- ✅ Low risk
- ✅ Simplifies dependency tree
- ✅ May reduce warnings (transitive version might be newer)

**Cons:**
- ❌ If explicitly added for a reason, removing might cause issues
- ❌ Warnings may still appear from transitive dependency

---

### Option C: Wait for Gatsby/Dependencies to Update (No Action)

**What it does:** Continue using current setup, run upgrade script monthly

**Implementation:**
```bash
# Monthly maintenance
./scripts/upgrade-deps.sh --gatsby
```

**Why this works:**
- Gatsby will eventually update node-fetch → whatwg-url to v14+ (no punycode)
- eslint will eventually update ajv → uri-js to newer version
- baseline-browser-mapping maintainers will release updates with fresh data

**Pros:**
- ✅ Zero effort
- ✅ Zero risk
- ✅ Site works perfectly despite warnings

**Cons:**
- ❌ Warnings persist until upstream fixes
- ❌ May take months

---

### Option D: Targeted Bun Resolutions (Medium Risk - EXPERIMENTAL)

**What it does:** Use Bun's `resolutions` (different from npm `overrides`) to target specific packages

**Implementation:**
```json
// package.json
"resolutions": {
  "whatwg-url": "^14.0.0",    // For punycode fix in gatsby chain
  "eslint/ajv/uri-js": "^4.4.2"  // For punycode fix in eslint chain
}
```

**Why this might work better than overrides:**
- Bun's resolutions are more granular (can target specific paths)
- Won't force global ajv@8 like npm overrides did

**Pros:**
- ✅ Addresses root cause
- ✅ More targeted than npm overrides

**Cons:**
- ❌ Experimental - may break build
- ❌ Bun resolutions syntax is less documented
- ❌ Needs careful testing

---

## Chosen Approach

**User Decision: Try Option D first, fallback to B+C if it fails**

### Implementation Plan

**Phase 1: Try Option D (Bun Resolutions)**

1. Add Bun resolutions to package.json:
```json
"resolutions": {
  "whatwg-url": "^14.0.0"
}
```

2. Reinstall dependencies:
```bash
bun install
```

3. Test build:
```bash
bun dev          # Should start without crashing
bun run build    # Should complete without errors
```

4. Check warnings:
   - Count punycode warnings (should be 0 if successful)
   - baseline-browser-mapping warnings will still appear (addressed in Phase 2)

**Phase 2: If Option D Works**
- Proceed to Option B (remove baseline-browser-mapping devDependency)
- Final test to ensure all warnings reduced

**Phase 3: If Option D Fails (Build Crashes)**
- Remove resolutions from package.json
- Run `bun install` to restore
- Proceed directly to Option B + Option C (accept warnings, maintain dependencies)

---

## Why NOT Aggressive Fixes

**Learned from previous attempts:**
- npm overrides (`ajv@8.17.1`) broke babel-loader/schema-utils/ajv-keywords
- Forcing major version bumps breaks compatibility
- Gatsby's build chain has complex interdependencies

**The warnings are harmless:**
- Site builds successfully
- Site runs perfectly
- No security vulnerabilities
- Just noise in terminal output

---

## Verification

After implementing any option:

```bash
# Test dev server
bun dev
# Should start without crashes

# Test production build
bun run build
# Should complete successfully

# Test production serve
bun run preview
# Should serve on localhost
```

---

## Critical Files

- `/Users/yulong/writing/yulonglin.github.io/package.json` - Dependencies
- `/Users/yulong/writing/yulonglin.github.io/gatsby-config.js` - Gatsby config
- `/Users/yulong/writing/yulonglin.github.io/scripts/upgrade-deps.sh` - Upgrade script (fixed)
