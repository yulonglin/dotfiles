# Security Fixes: slack-mcp-server

## Implementation Plan

### 1. CRITICAL: Fix `tape.txt` symlink vulnerability

**File:** `pkg/provider/edge/edge.go:67-86`

**Problem:** `NewWithClient()` unconditionally creates `tape.txt` in working directory - vulnerable to symlink attacks and leaks tokens.

**Fix:** Make tape opt-in with `nopTape{}` default (matching `NewWithInfo` pattern):

```go
func NewWithClient(workspaceName string, teamID string, token string, cl *http.Client, opt ...Option) (*Client, error) {
    if teamID == "" {
        return nil, ErrNoTeamID
    }
    if token == "" {
        return nil, ErrNoToken
    }
    c := &Client{
        cl:           cl,
        token:        token,
        teamID:       teamID,
        webclientAPI: fmt.Sprintf("https://%s.slack.com/api/", workspaceName),
        edgeAPI:      fmt.Sprintf("https://edgeapi.slack.com/cache/%s/", teamID),
        tape:         nopTape{},  // Safe default - opt-in via WithTape()
    }
    for _, o := range opt {
        o(c)
    }
    return c, nil
}
```

**Rationale:**
- `WithTape(io.WriteCloser)` already exists for opt-in
- Callers who need tape can create their own secure file: `os.CreateTemp("", "tape-*.txt")`
- Also fixes the "file handle leak" issue (nopTape needs no closing)

---

### 2. CRITICAL: Fix cache file permissions

**File:** `pkg/provider/api.go:529, 585`

**Fix:** Change `0644` to `0600` for cache files containing sensitive data.

---

### 3. HIGH: Restrict "demo" auth bypass to dev builds

**File:** `cmd/slack-mcp-server/main.go:135, 167`

**Fix:** Use build tags to restrict "demo" bypass to development builds only:
- Create `cmd/slack-mcp-server/demo_dev.go` with `//go:build dev` containing demo logic
- Create `cmd/slack-mcp-server/demo_prod.go` with `//go:build !dev` returning false
- Production builds (`go build`) won't include demo bypass
- Dev builds (`go build -tags dev`) will include it

---

### 4. HIGH: Validate cache paths against traversal

**File:** `pkg/provider/api.go:382-391`

**Fix:** Validate that resolved cache paths stay within intended directory.

---

### 5. HIGH: Restrict TLS skip to dev builds

**File:** `pkg/transport/transport.go:378-382`

**Fix:** Use build tags to restrict `SLACK_MCP_SERVER_CA_INSECURE` to dev builds:
- Create `pkg/transport/tls_dev.go` with `//go:build dev` allowing insecure mode
- Create `pkg/transport/tls_prod.go` with `//go:build !dev` ignoring the env var
- Production builds will always require valid TLS

---

### 6. MEDIUM: Update deprecated `ioutil`

**Files:** `pkg/provider/api.go`, `pkg/transport/transport.go`

**Fix:** Replace `ioutil.ReadAll` → `io.ReadAll`, `ioutil.WriteFile` → `os.WriteFile`

---

## Verification

1. Run existing tests: `go test ./...`
2. Manual test: Verify tape not created by default
3. Manual test: Verify cache files have 0600 permissions
4. Build and run MCP server to confirm functionality
