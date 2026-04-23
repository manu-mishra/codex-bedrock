# Technical Design: Remove OpenAI Login Requirements
# Date: 2026-04-19
# Status: DRAFT
# Parent Spec: specs/007-no-openai-login.feature

## 1. Problem Statement

Upstream Codex CLI has deep integration with OpenAI/ChatGPT authentication:
browser OAuth, device code flow, token refresh, cloud requirements fetching,
and a TUI login screen. Even when `requires_openai_auth = false` (which the
bedrock-mantel provider sets), residual code paths still reference OpenAI
endpoints and can be triggered. codex-b must have zero OpenAI auth
surface.

## 2. Audit — All OpenAI Auth Touchpoints

| # | Touchpoint | Code Location | Contacts | Action |
|---|-----------|---------------|----------|--------|
| 1 | TUI login screen | `tui/src/lib.rs` → `should_show_login_screen()` | N/A (UI) | Already skipped when `requires_openai_auth = false` ✓ |
| 2 | Browser OAuth | `login/src/server.rs` | `auth.openai.com` | Dead code — never reached |
| 3 | Device code flow | `login/src/device_code_auth.rs` | `auth.openai.com` | Dead code — never reached |
| 4 | API key entry | `tui/src/onboarding/auth.rs` | N/A (UI) | Dead code — never reached |
| 5 | Token refresh | `login/src/auth/manager.rs` | `auth.openai.com/oauth/token` | Called by AuthManager — must not be created |
| 6 | Token revocation | `login/src/auth/revoke.rs` | `auth.openai.com/oauth/revoke` | Called by AuthManager — must not be created |
| 7 | `enforce_login_restrictions()` | `exec/src/lib.rs`, `tui/src/lib.rs` | Reads `auth.json` | Called unconditionally — must skip |
| 8 | Cloud requirements | `cloud-requirements/src/lib.rs` | `chatgpt.com/backend-api/` | Loader passed to ConfigBuilder — must disable |
| 9 | `chatgpt_base_url` default | `core/src/config/mod.rs` | `chatgpt.com` | Default URL — must not be used |
| 10 | `to_api_provider()` fallback | `model-provider-info/src/lib.rs` | `api.openai.com` or `chatgpt.com` | Fallback when `base_url` is None — bedrock-mantel always has base_url ✓ |
| 11 | `OPENAI_API_KEY` / `CODEX_API_KEY` | `login/src/auth/manager.rs` | N/A (env read) | Must not trigger auth flows |

## 3. Changes Required

### 3.1 Skip enforce_login_restrictions() for non-OpenAI providers

The `enforce_login_restrictions()` call in `exec/src/lib.rs` and
`tui/src/lib.rs` is unconditional. It reads `auth.json` and can force logout.
For codex-b, it should be skipped entirely.

**Approach:** Guard the call with `requires_openai_auth`:

File: `codex-rs/exec/src/lib.rs`
```rust
// Before:
if let Err(err) = enforce_login_restrictions(&AuthConfig { ... }) {

// After:
if config.model_provider.requires_openai_auth {
    if let Err(err) = enforce_login_restrictions(&AuthConfig { ... }) {
        eprintln!("{err}");
        std::process::exit(1);
    }
}
```

File: `codex-rs/tui/src/lib.rs` — same pattern (already partially guarded
but `enforce_login_restrictions` is called separately).

### 3.2 Disable Cloud Requirements Loader

The `CloudRequirementsLoader` is passed to `ConfigBuilder` and can fetch
from `chatgpt.com`. For codex-b, it should always be the default
(no-op) loader.

**Approach:** In the CLI entry point (`cli/src/main.rs`), when the provider
is not OpenAI, pass `CloudRequirementsLoader::default()` (which is a no-op).

This is already the default behavior — the cloud requirements loader is only
constructed with real credentials for ChatGPT auth users. But to be safe,
ensure the codex-b fork never constructs a non-default loader.

File: `codex-rs/cli/src/main.rs` — ensure `cloud_requirements` is always
`CloudRequirementsLoader::default()` when provider is bedrock-mantel.

### 3.3 No AuthManager Creation for Bedrock Mantel

The `AuthManager` is what drives token refresh, revocation, and auth.json
access. For bedrock-mantel, no `AuthManager` should be created.

**Approach:** The `create_model_provider()` function in
`model-provider/src/provider.rs` already handles this — when
`provider.auth` is `None` and no base `auth_manager` is passed, the
`ConfiguredModelProvider` has `auth_manager: None`. The bedrock-mantel
provider has `requires_openai_auth: false` and `auth: None`, so no
`AuthManager` is created. ✓ Already correct.

### 3.4 Ensure bedrock-mantel Provider Always Has base_url

The `to_api_provider()` method falls back to `api.openai.com` or
`chatgpt.com` when `base_url` is `None`. The bedrock-mantel built-in
provider must always have a `base_url` set.

**Approach:** Already handled in spec 002 — the built-in bedrock-mantel
provider always constructs a region-specific base_url. ✓

### 3.5 Ignore OPENAI_API_KEY and CODEX_API_KEY

The `read_openai_api_key_from_env()` function checks `OPENAI_API_KEY` and
`CODEX_API_KEY`. For bedrock-mantel, these should not be used.

**Approach:** The bedrock-mantel provider uses `env_key = "AWS_BEARER_TOKEN_BEDROCK"`,
not `OPENAI_API_KEY`. The `requires_openai_auth = false` flag prevents the
login flow from checking these vars. ✓ Already correct.

### 3.6 No auth.json Read/Write

When `requires_openai_auth = false` and no `AuthManager` is created, no
`auth.json` is read or written. ✓ Already correct for the happy path.

The only risk is `enforce_login_restrictions()` (addressed in 3.1) which
reads `auth.json` unconditionally.

### 3.7 No ChatGPT-Account-ID Header

The `BearerAuthProvider` sends `ChatGPT-Account-ID` when `account_id` is
set. For bedrock-mantel, `account_id` is always `None` because no
`AuthManager` provides ChatGPT auth. ✓ Already correct.

## 4. Summary of Required Code Changes

| # | Change | File | Effort |
|---|--------|------|--------|
| 1 | Guard `enforce_login_restrictions()` with `requires_openai_auth` | `exec/src/lib.rs` | 3 lines |
| 2 | Guard `enforce_login_restrictions()` with `requires_openai_auth` | `tui/src/lib.rs` | 3 lines |
| 3 | Ensure cloud requirements loader is no-op for non-OpenAI | `cli/src/main.rs` | Verify only |
| 4 | Remove `Login` subcommand from CLI | `cli/src/main.rs` | Remove enum variant + match arm |
| 5 | Remove `Logout` subcommand from CLI | `cli/src/main.rs` | Remove enum variant + match arm |
| 6 | Remove `App` subcommand from CLI | `cli/src/main.rs` | Remove enum variant + match arm |

Items 4-6: The `codex login`, `codex logout`, and `codex app` subcommands are
OpenAI-specific. They should be removed from the CLI enum in
`cli/src/main.rs`. The `login.rs` module can remain in the codebase (dead code)
but the subcommands should not be exposed to users. MCP subcommands stay —
they are provider-agnostic.

## 5. Defense in Depth — What Prevents Accidental OpenAI Contact

Multiple layers ensure no OpenAI endpoints are contacted:

1. **Provider level:** `requires_openai_auth: false` → no login screen, no auth checks
2. **Provider level:** `base_url` always set → no fallback to `api.openai.com`
3. **Auth level:** No `AuthManager` created → no token refresh/revoke
4. **Config level:** Cloud requirements loader is no-op → no `chatgpt.com` fetch
5. **Exec level:** `enforce_login_restrictions()` skipped → no `auth.json` read
6. **Privacy spec (004):** Analytics disabled → no `chatgpt.com/analytics` calls
7. **Privacy spec (004):** OTEL disabled → no `ab.chatgpt.com` calls
8. **Privacy spec (004):** Feedback disabled → no `sentry.io` calls
9. **Privacy spec (004):** Update checker disabled → no `github.com` calls

The net result: the only outbound HTTPS connection is to
`bedrock-mantle.<region>.api.aws`.

## 6. What the User Sees

```
$ codex-b
  ┌─────────────────────────────────────────┐
  │  codex-b                           │
  │  Model: deepseek.v3.2                   │
  │  Provider: Bedrock Mantel (us-east-1)   │
  │                                         │
  │  >                                      │
  └─────────────────────────────────────────┘
```

No login screen. No "Sign in with ChatGPT". No API key prompt.
Just straight to the chat interface.
