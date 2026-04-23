# Technical Design: Privacy-First Defaults
# Date: 2026-04-19
# Status: DRAFT
# Parent Spec: specs/003-privacy-first-defaults.feature

## 1. Problem Statement

The upstream Codex CLI has 10 identified data collection points that phone home
to OpenAI, Statsig, Sentry, GitHub, and Homebrew servers by default. For a fork
targeting Bedrock Mantel users who want complete privacy, every one of these
must be disabled out of the box. The tool should only ever contact the
user-configured model provider endpoint.

## 2. Audit Summary

| # | What                        | Where it sends                                      | Default | Target |
|---|-----------------------------|-----------------------------------------------------|---------|--------|
| 1 | Analytics events            | chatgpt.com/backend-api/codex/analytics-events      | ON      | OFF    |
| 2 | OTEL metrics (Statsig)      | ab.chatgpt.com/otlp/v1/metrics                      | ON      | OFF    |
| 3 | OTEL traces                 | None                                                 | OFF     | OFF ✓  |
| 4 | OTEL logs                   | None                                                 | OFF     | OFF ✓  |
| 5 | Sentry crash reports        | o33249.ingest.us.sentry.io                           | ON      | OFF    |
| 6 | Update checker              | api.github.com + formulae.brew.sh                    | ON      | OFF    |
| 7 | User-Agent fingerprint      | Model provider endpoint                              | Verbose | Minimal|
| 8 | Version/Org/Project headers | Model provider endpoint                              | ON      | OFF    |
| 9 | History persistence         | ~/.codex/history.jsonl                               | save-all| none   |
|10 | Memories                    | ~/.codex/memories/                                   | ON      | OFF    |

Items 3 and 4 are already OFF — no changes needed.

## 3. Changes Required

### 3.1 Analytics — DEFAULT_ANALYTICS_ENABLED → false

Files to change:
- `codex-rs/tui/src/lib.rs` — change `/*default_analytics_enabled*/ true` → `false`
- `codex-rs/exec/src/lib.rs` — change `DEFAULT_ANALYTICS_ENABLED: bool = true` → `false`
- `codex-rs/mcp-server/src/lib.rs` — change `DEFAULT_ANALYTICS_ENABLED: bool = true` → `false`
- `codex-rs/app-server-test-client/src/lib.rs` — change `DEFAULT_ANALYTICS_ENABLED: bool = true` → `false`

Additionally, in `codex-rs/core/src/config/mod.rs`, change the default for
`analytics_enabled` from `None` (which falls through to `default_analytics_enabled`)
to `Some(false)`.

### 3.2 OTEL Metrics Exporter — Statsig → None

File to change:
- `codex-rs/config/src/types.rs` — change `OtelConfig::default()`:
  ```
  metrics_exporter: OtelExporterKind::Statsig  →  OtelExporterKind::None
  ```

This single change ensures no metrics are sent to `ab.chatgpt.com` unless the
user explicitly configures an exporter.

### 3.3 Sentry/Feedback — feedback_enabled → false

File to change:
- `codex-rs/core/src/config/mod.rs` — change the feedback_enabled default:
  ```
  feedback_enabled: cfg.feedback.as_ref()
      .and_then(|feedback| feedback.enabled)
      .unwrap_or(true)    →    .unwrap_or(false)
  ```

### 3.4 Update Checker — check_for_update_on_startup → false

File to change:
- `codex-rs/core/src/config/mod.rs` — change the default:
  ```
  check_for_update_on_startup: cfg.check_for_update_on_startup.unwrap_or(true)
      →  .unwrap_or(false)
  ```

### 3.5 User-Agent Header — Minimal for codex-b

The User-Agent is constructed in `codex-login/src/auth/default_client.rs`
(`get_codex_user_agent()`). It currently includes OS type, OS version,
architecture, and terminal program info.

For the fork, simplify to: `codex-b/<version>` without OS, arch, or
terminal details. This change coordinates with spec 006 which renames the
originator to `codex-b_cli_rs`.

File to change:
- `codex-rs/login/src/auth/default_client.rs` — simplify `get_codex_user_agent()`
  to return `"codex-b/<CARGO_PKG_VERSION>"` only.

The bedrock-mantel built-in provider does NOT include `version`,
`OpenAI-Organization`, or `OpenAI-Project` headers (those are only on the
OpenAI provider definition). No change needed for those — they're absent
by construction.

### 3.6 Request Telemetry Headers — Strip for non-OpenAI providers

The `traceparent`, `tracestate`, `session_id`, and `x-openai-subagent` headers
are added in `codex-api/src/requests/headers.rs` and
`codex-api/src/endpoint/responses.rs`. These should be conditionally included
only when OTEL is explicitly enabled.

Approach: In the session/endpoint layer, check if the provider is OpenAI
(or if OTEL is enabled) before attaching trace context headers. For
bedrock-mantel, skip them.

### 3.7 History Persistence — Default to none

File to change:
- `codex-rs/config/src/types.rs` — change `HistoryPersistence::default()`:
  ```
  #[default]
  SaveAll    →    None
  ```

### 3.8 Memories — Default to disabled

File to change:
- `codex-rs/config/src/types.rs` — in `impl Default for MemoriesConfig` (line ~226):
  ```
  generate_memories: true   →   generate_memories: false
  use_memories: true        →   use_memories: false
  ```

### 3.9 Auth Environment Telemetry — Skip collection

The `collect_auth_env_telemetry()` function in `codex-rs/login/src/auth_env_telemetry.rs`
collects which env vars are present. Since OTEL is disabled by default, this
data has nowhere to go. No code change strictly needed, but for defense in
depth, the collection can be gated on OTEL being enabled.

## 4. Implementation Order

All changes are config-default flips — minimal code, high impact:

1. **Batch 1 — Config defaults** (all in one commit):
   - `DEFAULT_ANALYTICS_ENABLED` → `false` (4 files)
   - `OtelConfig::default().metrics_exporter` → `None` (1 file)
   - `feedback_enabled` default → `false` (1 file)
   - `check_for_update_on_startup` default → `false` (1 file)
   - `HistoryPersistence::default()` → `None` (1 file)
   - `memories` defaults → disabled (1 file)

2. **Batch 2 — Headers** (separate commit):
   - Minimal User-Agent for fork
   - Strip OpenAI-specific headers from bedrock-mantel provider
   - Conditional trace context headers

3. **Batch 3 — Verification**:
   - Integration test that starts a session with bedrock-mantel provider
     and asserts zero outbound connections to non-provider hosts

## 5. What Users Can Still Opt Into

All features remain available — just not on by default:

```toml
# config.toml — opt-in to any telemetry feature
[analytics]
enabled = true

[feedback]
enabled = true

check_for_update_on_startup = true

[history]
persistence = "save-all"

[memories]
generate_memories = true
use_memories = true

[otel]
metrics_exporter = "statsig"
```

## 6. Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Upstream merge conflicts on default values | Low | Changes are isolated to default constants |
| Tests that assert analytics_enabled = true | Medium | Update test assertions to match new defaults |
| Missing a phone-home path | Medium | Network isolation integration test catches it |
| User confusion about missing update prompts | Low | Document in README that updates are manual |
