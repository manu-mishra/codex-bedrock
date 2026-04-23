# codex-b — Specification Index

## Overview

This folder contains the complete specification for forking OpenAI's Codex CLI
into **codex-b** — a privacy-first, side-by-side-deployable CLI that works
with Amazon Bedrock Mantel models.

## Execution Order

Specs have dependencies. An agent must execute them in this order:

```
Phase 1 (can run in parallel — no code dependencies between them):
  ├── 005/006 — Rebranding (binary names, paths, env vars)
  ├── 003/004 — Privacy defaults (flip config defaults)
  └── 007/008 — Remove OpenAI login (guard 2 functions)

Phase 2 (depends on Phase 1 — needs renamed binary + privacy defaults):
  └── 001/002 — Bedrock Mantel integration (provider, Chat Completions, tools)
```

Phase 1 specs are independent of each other and can be done in any order or
in parallel. Phase 2 depends on Phase 1 because the Bedrock Mantel provider
definition references the renamed env vars and assumes privacy defaults.

## Spec Pairs

Each feature has a Gherkin spec (WHAT) and a technical design (HOW):

| # | Gherkin Spec (WHAT) | Technical Design (HOW) | Summary |
|---|--------------------|-----------------------|---------|
| 1 | `001-bedrock-mantel-integration.feature` | `002-technical-design-bedrock-mantel.md` | Add Bedrock Mantel as built-in provider, re-introduce Chat Completions API |
| 2 | `003-privacy-first-defaults.feature` | `004-technical-design-privacy.md` | Disable all 10 telemetry/tracking points by default |
| 3 | `005-rebranding-codex-b.feature` | `006-technical-design-rebranding.md` | Rename binaries, paths, env vars for side-by-side install |
| 4 | `007-no-openai-login.feature` | `008-technical-design-no-login.md` | Remove all OpenAI/ChatGPT login requirements |

## Key Decisions (resolved)

These decisions were open questions in earlier drafts. They are now resolved:

1. **WireApi::Chat available to all providers** — Yes. Users may have other
   Chat Completions providers beyond Bedrock Mantel.

2. **Auto-detect wire API for Bedrock Mantel** — Yes. Models matching
   `openai.gpt-oss-*` use Responses API; all others use Chat Completions.

3. **Compaction with Chat Completions** — Client-side compaction of the
   messages array. The existing context management already tracks history
   internally; for Chat Completions it serializes to `messages[]` on each
   request instead of using `previous_response_id`.

4. **Bedrock Mantel Projects API** — Not in initial release.

5. **Region env var name** — `CODEXB_REGION` (follows the
   `CODEXB_` prefix convention from spec 005, not `BEDROCK_MANTEL_REGION`).

6. **`codex login` / `codex logout` / `codex app` subcommands** — Remove from
   the CLI. These are OpenAI-specific. The `codex-b` binary should not
   expose login/logout/app subcommands. MCP subcommands stay (they're
   provider-agnostic).

7. **CODEX_CI env var** — Do NOT rename. This is used in CI test infrastructure
   and is not a user-facing config variable. Same for any env vars that are
   purely internal test fixtures.

8. **Memories default** — Confirmed: `generate_memories: true` and
   `use_memories: true` in `MemoriesConfig::default()` at
   `codex-rs/config/src/types.rs:226`. Must change both to `false`.

## Naming Convention

| What | Value |
|------|-------|
| Main binary | `codex-b` |
| Helper binaries | `codex-b-exec`, `codex-b-linux-sandbox`, etc. |
| Home directory | `~/.codexb/` |
| Home env var | `CODEXB_HOME` |
| All user-facing env vars | `CODEXB_*` prefix |
| In-repo config dir | `.codexb/` |
| Plugin manifest dir | `.codexb-plugin/` |
| Originator | `codex-b_cli_rs` |
| Region env var | `CODEXB_REGION` |
| Bedrock API key env var | `AWS_BEARER_TOKEN_BEDROCK` (AWS standard, not renamed) |
| Internal crate names | `codex-*` (UNCHANGED) |
| AGENTS.md | `AGENTS.md` (UNCHANGED — shared convention) |

## Change Size Estimates

| Spec | Files Changed | Effort | Risk |
|------|--------------|--------|------|
| 003/004 Privacy | ~8 files, single-line default flips | Small | Low |
| 007/008 No Login | ~3 files, 2 guard conditions + subcommand removal | Small | Low |
| 005/006 Rebranding | ~30+ files, mechanical rename | Medium | Medium |
| 001/002 Bedrock Mantel | ~15+ new/modified files, new crate | Large | High |

## Agent Instructions

When assigning specs to sub-agents:

- **Give each agent the Gherkin spec AND the technical design together** — the
  Gherkin defines acceptance criteria, the technical design gives exact files
  and code patterns.

- **Phase 1 agents need no cross-spec context** — each is self-contained.

- **Phase 2 agent (001/002) needs to know** that the binary is now
  `codex-b`, the home dir is `~/.codexb/`, env vars use
  `CODEXB_` prefix, and all telemetry is off by default. Give it
  this README as context.

- **Every agent should run `just fmt` and the relevant `cargo test -p` after
  making changes** per the project's AGENTS.md conventions.
