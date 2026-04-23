# Technical Design: Rebrand to "codex-b" for Side-by-Side Deployment
# Date: 2026-04-19
# Status: DRAFT
# Parent Spec: specs/005-rebranding-codex-b.feature

## 1. Problem Statement

If a user installs both upstream OpenAI Codex CLI and this Bedrock fork, they
collide on: binary name (`codex`), config directory (`~/.codex/`), environment
variables (`CODEX_*`), and in-repo config (`.codex/`). The fork must use
distinct names so both can coexist.

## 2. Naming Scheme

| Aspect          | Upstream (OpenAI)         | Fork (this project)              |
|-----------------|---------------------------|----------------------------------|
| Main binary     | `codex`                   | `codex-b`                   |
| Helper binaries | `codex-exec`, etc.        | `codex-b-exec`, etc.        |
| Home dir        | `~/.codex/`               | `~/.codexb/`               |
| Home env var    | `CODEX_HOME`              | `CODEXB_HOME`              |
| All env vars    | `CODEX_*`                 | `CODEXB_*`                 |
| In-repo config  | `.codex/`                 | `.codexb/`                 |
| Plugin manifest | `.codex-plugin/`          | `.codexb-plugin/`          |
| npm package     | `@openai/codex`           | `codex-b` (or scoped)       |
| Clap bin_name   | `codex`                   | `codex-b`                   |
| Originator      | `codex_cli_rs`            | `codex-b_cli_rs`            |

**What stays the same:**
- Internal Rust crate names (`codex-core`, `codex-tui`, etc.) — no user impact
- Internal lib names (`codex_core`, `codex_tui`) — no user impact
- `AGENTS.md` / `AGENTS.override.md` — shared project doc convention
- Wire protocol compatibility with OpenAI Responses API

## 3. Implementation Strategy

The rename touches many files but is mechanical. We use a two-tier approach:

### Tier 1: User-Facing Names (MUST change)

These are what users see and type. Conflicts here break side-by-side.

### Tier 2: Internal Crate Names (DO NOT change)

Renaming 80+ crates would be a massive diff with zero user benefit and would
make upstream merges nearly impossible. Internal names stay as `codex-*`.

## 4. Detailed Changes

### 4.1 Binary Names (Cargo.toml `[[bin]]` sections)

| File | Field | Old | New |
|------|-------|-----|-----|
| `codex-rs/cli/Cargo.toml` | `[[bin]] name` | `"codex"` | `"codex-b"` |
| `codex-rs/exec/Cargo.toml` | `[[bin]] name` | `"codex-exec"` | `"codex-b-exec"` |
| `codex-rs/app-server/Cargo.toml` | `[[bin]] name` | `"codex-app-server"` | `"codex-b-app-server"` |
| `codex-rs/mcp-server/Cargo.toml` | `[[bin]] name` | `"codex-mcp-server"` | `"codex-b-mcp-server"` |
| `codex-rs/linux-sandbox/Cargo.toml` | `[[bin]] name` | `"codex-linux-sandbox"` | `"codex-b-linux-sandbox"` |
| `codex-rs/responses-api-proxy/Cargo.toml` | `[[bin]] name` | `"codex-responses-api-proxy"` | `"codex-b-responses-api-proxy"` |
| `codex-rs/stdio-to-uds/Cargo.toml` | `[[bin]] name` | `"codex-stdio-to-uds"` | `"codex-b-stdio-to-uds"` |
| `codex-rs/execpolicy/Cargo.toml` | `[[bin]] name` | `"codex-execpolicy"` | `"codex-b-execpolicy"` |
| `codex-rs/windows-sandbox-rs/Cargo.toml` | `[[bin]] name` (3 bins) | `"codex-windows-*"` | `"codex-b-windows-*"` |

### 4.2 Clap CLI bin_name

File: `codex-rs/cli/src/main.rs`
```
bin_name = "codex"  →  bin_name = "codex-b"
```

### 4.3 Home Directory

File: `codex-rs/utils/home-dir/src/lib.rs`
```rust
// Env var name
std::env::var("CODEX_HOME")  →  std::env::var("CODEXB_HOME")

// Default path
p.push(".codex")  →  p.push(".codex-b")
```

### 4.4 In-Repo Config Directory

File: `codex-rs/core/src/config_loader/mod.rs`
```rust
dir.join(".codex")  →  dir.join(".codex-b")
```

Also in tests and other files that reference `.codex/` as the in-repo dir.

### 4.5 Plugin Manifest Directory

File: `codex-rs/utils/plugins/src/plugin_namespace.rs`
```rust
".codex-plugin/plugin.json"  →  ".codexb-plugin/plugin.json"
```

### 4.6 Environment Variables

All `CODEX_` prefixed env var constants need renaming to `CODEXB_`:

| File | Constant | Old | New |
|------|----------|-----|-----|
| `core/src/spawn.rs` | `CODEX_SANDBOX_NETWORK_DISABLED_ENV_VAR` | `"CODEX_SANDBOX_NETWORK_DISABLED"` | `"CODEXB_SANDBOX_NETWORK_DISABLED"` |
| `core/src/spawn.rs` | `CODEX_SANDBOX_ENV_VAR` | `"CODEX_SANDBOX"` | `"CODEXB_SANDBOX"` |
| `login/src/auth/manager.rs` | `CODEX_API_KEY_ENV_VAR` | `"CODEX_API_KEY"` | `"CODEXB_API_KEY"` |
| `config/src/shell_environment.rs` | `CODEX_THREAD_ID_ENV_VAR` | `"CODEX_THREAD_ID"` | `"CODEXB_THREAD_ID"` |
| `exec-server/src/environment.rs` | `CODEX_EXEC_SERVER_URL_ENV_VAR` | `"CODEX_EXEC_SERVER_URL"` | `"CODEXB_EXEC_SERVER_URL"` |
| `codex-mcp/src/mcp/mod.rs` | `CODEX_CONNECTORS_TOKEN_ENV_VAR` | `"CODEX_CONNECTORS_TOKEN"` | `"CODEXB_CONNECTORS_TOKEN"` |
| `login/src/auth/default_client.rs` | `CODEX_INTERNAL_ORIGINATOR_OVERRIDE_ENV_VAR` | `"CODEX_INTERNAL_ORIGINATOR_OVERRIDE"` | `"CODEXB_INTERNAL_ORIGINATOR_OVERRIDE"` |
| `model-provider-info/src/lib.rs` | inline | `"CODEX_OSS_PORT"`, `"CODEX_OSS_BASE_URL"` | `"CODEXB_OSS_PORT"`, `"CODEXB_OSS_BASE_URL"` |
| `codex-client/tests/ca_env.rs` | inline | `"CODEX_CA_CERTIFICATE"` | `"CODEXB_CA_CERTIFICATE"` |
| `state/src/lib.rs` | `SQLITE_HOME_ENV` | `"CODEX_SQLITE_HOME"` | `"CODEXB_SQLITE_HOME"` |

### 4.7 Arg0 Constants

File: `codex-rs/arg0/src/lib.rs`
```rust
const EXECVE_WRAPPER_ARG0: &str = "codex-execve-wrapper"
    →  "codex-b-execve-wrapper"
```

File: `codex-rs/sandboxing/src/landlock/mod.rs` (or wherever `CODEX_LINUX_SANDBOX_ARG0` is)
```rust
"codex-linux-sandbox"  →  "codex-b-linux-sandbox"
```

### 4.8 Originator / User-Agent

File: `codex-rs/login/src/auth/default_client.rs`
```rust
pub const DEFAULT_ORIGINATOR: &str = "codex_cli_rs"
    →  "codex-b_cli_rs"
```

### 4.9 npm Package

File: `codex-cli/package.json`
```json
"name": "@openai/codex"  →  "codex-b"
"bin": { "codex": "bin/codex.js" }  →  { "codex-b": "bin/codex-b.js" }
```

### 4.10 cargo_bin() References in Tests

All test files that call `cargo_bin("codex")` need updating to
`cargo_bin("codex-b")`. Similarly for `cargo_bin("codex-exec")`, etc.

## 5. Implementation Approach

Rather than a manual find-and-replace across hundreds of files, use a
centralized constants approach:

### Option A: Global Constants Module (Recommended)

Create a new tiny crate `codex-rs/branding/` with:

```rust
pub const BINARY_NAME: &str = "codex-b";
pub const HOME_DIR_NAME: &str = ".codex-b";
pub const HOME_ENV_VAR: &str = "CODEXB_HOME";
pub const ENV_PREFIX: &str = "CODEXB_";
pub const REPO_CONFIG_DIR: &str = ".codex-b";
pub const PLUGIN_DIR: &str = ".codex-b-plugin";
pub const ORIGINATOR: &str = "codex-b_cli_rs";
```

Then replace hardcoded strings throughout the codebase with references to
these constants. This makes future renames trivial and keeps the diff
reviewable.

### Option B: Scripted Rename

Use `sed`/`rg --replace` for the mechanical rename. Faster to execute but
harder to maintain and verify.

**Recommendation: Option A for constants that appear in logic, Option B for
Cargo.toml binary names and test fixtures.**

## 6. What NOT to Rename

- **Internal crate names** (`codex-core`, `codex-tui`, etc.) — no user impact,
  massive diff, kills upstream mergeability
- **AGENTS.md** — shared convention, not tool-specific
- **Wire protocol fields** — must stay OpenAI-compatible
- **Rust module paths** (`codex_core::`, `codex_tui::`) — internal only
- **Test-only env vars** (`CODEX_CI`, `CODEX_RS_SSE_FIXTURE`, etc.) — internal
  test infrastructure, not user-facing. Renaming these adds churn with no benefit.

## 7. Implementation Order

1. Create `codex-rs/branding/` crate with all constants
2. Rename binary names in Cargo.toml files (12 files)
3. Update `find_codex_home()` to use new env var and path
4. Update in-repo config dir (`.codexb/`)
5. Update env var constants (10+ files)
6. Update arg0 constants
7. Update Clap bin_name
8. Update npm package
9. Update test fixtures referencing binary names
10. Run full test suite

## 8. Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Missing a hardcoded "codex" string | Medium | `grep -r '"codex"' codex-rs/` after rename |
| Upstream merge conflicts | High | Keep internal crate names unchanged; conflicts limited to user-facing strings |
| Tests break from binary name change | Medium | Batch update all `cargo_bin("codex")` calls |
| Users confused by new name | Low | Clear README, migration guide |
