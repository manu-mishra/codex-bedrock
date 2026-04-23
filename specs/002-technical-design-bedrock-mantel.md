# Technical Design: Bedrock Mantel Integration for Codex CLI
# Date: 2026-04-19
# Status: DRAFT
# Parent Spec: specs/001-bedrock-mantel-integration.feature

## 1. Problem Statement

Codex CLI currently only supports `WireApi::Responses` (the OpenAI Responses API
at `/v1/responses`). Amazon Bedrock Mantel exposes ~38 open-weight models via
OpenAI-compatible endpoints, but only 4 GPT-OSS models support the Responses API.
The remaining ~34 models (DeepSeek, Mistral, Qwen, Gemma, etc.) only support
Chat Completions (`/v1/chat/completions`).

This means Codex CLI is effectively broken for the vast majority of Bedrock
Mantel models. Additionally, even for the GPT-OSS models that do support
Responses, there are known issues with auth header passthrough and unsupported
tool types (`web_search`).

## 2. Goals

1. Add Bedrock Mantel as a built-in provider (like OpenAI, Ollama, LMStudio)
2. Re-introduce Chat Completions wire API support for providers that need it
3. Implement proper Bearer token auth via `AWS_BEARER_TOKEN_BEDROCK`
4. Filter unsupported tool types for Bedrock Mantel
5. Support model discovery via `/v1/models`
6. Provide clear first-run UX and error messages

## 3. Non-Goals (for initial release)

- AWS SigV4 signing (can be added later; Bearer token covers the primary use case)
- Bedrock native Converse API support (out of scope — Mantel is OpenAI-compatible)
- Support for models NOT on Mantel (Claude, Nova, Llama — these require different endpoints)
- WebSocket transport for Bedrock Mantel (not supported by Mantel)

## 3.1 Privacy Requirement

All telemetry, analytics, crash reporting, and phone-home behavior is DISABLED
by default. See `specs/003-privacy-first-defaults.feature` and
`specs/004-technical-design-privacy.md` for the full privacy specification.
The tool must only contact the configured Bedrock Mantel endpoint.

## 4. Architecture Overview

### 4.1 User Journey

```
User installs codex-b
  → Creates Bedrock API key in AWS Console
  → Sets AWS_BEARER_TOKEN_BEDROCK env var
  → Adds to ~/.codexb/config.toml:
      model = "deepseek.v3.2"
  → Runs `codex-b`
  → CLI resolves built-in "bedrock-mantel" provider (the default)
  → CLI detects model requires Chat Completions wire API
  → CLI sends requests to https://bedrock-mantle.<region>.api.aws/v1/chat/completions
  → Streaming responses displayed in TUI
  → Tool calls (shell, apply_patch, etc.) work via function calling
```

### 4.2 Component Changes

```
┌─────────────────────────────────────────────────────────────────┐
│                        Config Layer                              │
│  config.toml → model_provider = "bedrock-mantel"                │
│                model = "deepseek.v3.2"                          │
│                bedrock_region = "us-east-1" (optional)          │
└──────────────────────┬──────────────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────────────┐
│              model-provider-info crate                           │
│  NEW: WireApi::Chat variant (re-introduced)                     │
│  NEW: built-in "bedrock-mantel" in built_in_model_providers()   │
│  NEW: region-aware base_url construction                        │
└──────────────────────┬──────────────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────────────┐
│              model-provider crate                                │
│  UNCHANGED: ModelProvider trait, BearerAuthProvider              │
│  Auth: env_key = "AWS_BEARER_TOKEN_BEDROCK" → Bearer header     │
└──────────────────────┬──────────────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────────────┐
│              codex-api crate                                     │
│  NEW: ChatCompletionsClient (parallel to ResponsesClient)       │
│  NEW: Chat Completions request/response types                   │
│  NEW: Chat Completions SSE streaming parser                     │
│  NEW: Responses↔Chat translation layer                          │
└──────────────────────┬──────────────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────────────┐
│              core crate (session layer)                          │
│  MODIFIED: Session dispatches to Chat or Responses based on     │
│            wire_api from provider config                         │
│  NEW: Tool type filtering for Bedrock Mantel                    │
└─────────────────────────────────────────────────────────────────┘
```

## 5. Detailed Design

### 5.1 Re-introduce WireApi::Chat (model-provider-info crate)

The `WireApi` enum currently only has `Responses`. Chat was explicitly removed
with an error message pointing to a GitHub discussion. We need to re-add it:

```
enum WireApi {
    Responses,  // existing — /v1/responses
    Chat,       // NEW — /v1/chat/completions
}
```

The deserialization error for `"chat"` should be removed, and `"chat"` should
deserialize to `WireApi::Chat`.

Impact: `model-provider-info` crate only. All downstream code that matches on
`WireApi` will need to handle the new variant (exhaustive match enforcement).

### 5.2 Built-in Bedrock Mantel Provider (model-provider-info crate)

Add a new built-in provider to `built_in_model_providers()`:

```
("bedrock-mantel", ModelProviderInfo {
    name: "Bedrock Mantel",
    base_url: Some(format!("https://bedrock-mantle.{region}.api.aws/v1")),
    env_key: Some("AWS_BEARER_TOKEN_BEDROCK"),
    env_key_instructions: Some("Create a Bedrock API key at https://console.aws.amazon.com/bedrock/..."),
    wire_api: WireApi::Chat,  // default to Chat since most models need it
    requires_openai_auth: false,
    supports_websockets: false,
    ...
})
```

Additionally, change the default `model_provider_id` from `"openai"` to
`"bedrock-mantel"` in `core/src/config/mod.rs`:
```rust
let model_provider_id = model_provider
    .or(config_profile.model_provider)
    .or(cfg.model_provider)
    .unwrap_or_else(|| "bedrock-mantel".to_string());
```

Region resolution order:
1. `bedrock_region` in config.toml (new field)
2. `CODEXB_REGION` env var
3. `AWS_REGION` or `AWS_DEFAULT_REGION` env var
4. Default: "us-east-1"

### 5.3 Chat Completions Client (codex-api crate — NEW module)

Create a new `ChatCompletionsClient` that mirrors `ResponsesClient` but targets
`/v1/chat/completions`:

Key responsibilities:
- Build Chat Completions request body (`messages`, `tools`, `model`, `stream`)
- Parse SSE streaming chunks (different format from Responses API)
- Translate tool calls from Chat Completions format to internal format
- Manage conversation history client-side (Chat Completions is stateless)

#### Request Translation (Responses → Chat Completions)

The core session layer currently builds `ResponsesApiRequest`. For Chat
Completions, we need a translation layer:

| Responses API field       | Chat Completions equivalent        |
|---------------------------|------------------------------------|
| `input` (array of items)  | `messages` (array of messages)     |
| `tools` (with types)      | `tools` (function type only)       |
| `model`                   | `model`                            |
| `stream: true`            | `stream: true`                     |
| `previous_response_id`    | N/A — full history in `messages`   |
| `store`                   | N/A                                |
| `reasoning`               | Provider-specific (if supported)   |

#### Response Translation (Chat Completions → ResponseEvent)

The TUI and session layer consume `ResponseEvent` (from the Responses API SSE
stream). The Chat Completions SSE stream has a different format. We need a
translation layer:

| Chat Completions SSE chunk          | ResponseEvent equivalent              |
|-------------------------------------|---------------------------------------|
| `choices[0].delta.content`          | `response.output_text.delta`          |
| `choices[0].delta.tool_calls`       | `response.function_call_arguments.*`  |
| `choices[0].finish_reason = "stop"` | `response.completed`                  |
| `choices[0].finish_reason = "tool_calls"` | `response.completed` (after tool events) |

This translation layer is the most complex piece. It should live in a new
module within `codex-api` (e.g., `codex-api/src/endpoint/chat_completions.rs`
and `codex-api/src/sse/chat_completions.rs`).

### 5.4 Session Dispatch (core crate)

The session layer (in `core/src/session/`) currently always uses
`ResponsesClient`. It needs to dispatch based on `wire_api`:

```
match provider.info().wire_api {
    WireApi::Responses => {
        // existing flow — use ResponsesClient
    }
    WireApi::Chat => {
        // new flow — use ChatCompletionsClient
        // translate ResponsesApiRequest → ChatCompletionsRequest
        // translate ChatCompletions SSE → ResponseEvent stream
    }
}
```

The dispatch should happen at the point where the HTTP request is made, not
higher up. The rest of the session layer (tool execution, approval flow,
context management) should remain unchanged.

### 5.5 Conversation History Management

For Chat Completions, the server is stateless. The client must maintain and
send the full conversation history with each request. This is different from
the Responses API where `previous_response_id` handles state server-side.

The session layer already maintains conversation history internally (for
context management, compaction, etc.). For Chat Completions, this history
needs to be serialized into the `messages` array format on each request.

### 5.6 Tool Type Filtering

Bedrock Mantel only supports `function` and `mcp` tool types. The `web_search`
tool type causes errors. The tool list should be filtered before sending to
Bedrock Mantel:

- Filter location: in the Chat Completions request builder
- Filter logic: exclude tools where `type != "function"`
- No user-facing error for filtered tools (silent exclusion)

### 5.7 New Crate: codex-bedrock-mantel (optional, recommended)

Following the pattern of `codex-ollama` and `codex-lmstudio`, create a new
crate `codex-rs/bedrock-mantel/` that encapsulates Bedrock-specific logic:

- Region resolution
- Health check (probe `/v1/models` endpoint)
- Model discovery and caching
- Provider-specific error messages

This keeps Bedrock-specific code out of `codex-core` per the project guidelines.

## 6. Config Schema Changes

### 6.1 New config.toml fields

```toml
# Model to use (must be available on Mantel)
model = "deepseek.v3.2"

# Optional: override the default region (us-east-1)
# Can also be set via CODEXB_REGION env var
bedrock_region = "eu-west-1"
```

Note: `model_provider` defaults to `"bedrock-mantel"` in this fork (not
`"openai"` as in upstream). Users do not need to set it explicitly.

### 6.2 Custom provider override (existing mechanism)

Users can also override the built-in provider:

```toml
[model_providers.bedrock-mantel]
name = "Bedrock Mantel"
base_url = "https://bedrock-mantle.eu-west-1.api.aws/v1"
env_key = "AWS_BEARER_TOKEN_BEDROCK"
wire_api = "chat"
```

## 7. Implementation Phases

### Phase 1: Foundation (Estimated: 1-2 weeks)
1. Re-introduce `WireApi::Chat` in `model-provider-info`
2. Add built-in "bedrock-mantel" provider definition
3. Add `bedrock_region` config field
4. Run `just write-config-schema` to update JSON schema

### Phase 2: Chat Completions Client (Estimated: 2-3 weeks)
1. Create `ChatCompletionsClient` in `codex-api`
2. Implement Chat Completions request types
3. Implement Chat Completions SSE streaming parser
4. Implement Responses↔Chat translation layer
5. Add unit tests with mock server

### Phase 3: Session Integration (Estimated: 1-2 weeks)
1. Add wire_api dispatch in session layer
2. Implement conversation history serialization for Chat Completions
3. Implement tool type filtering for Bedrock Mantel
4. Integration tests

### Phase 4: UX and Polish (Estimated: 1 week)
1. First-run guidance messages
2. Error messages for auth failures, model not found, etc.
3. Model discovery command support
4. Documentation updates

### Phase 5: Optional Enhancements (Future)
1. AWS SigV4 signing support
2. `codex-bedrock-mantel` crate extraction
3. Auto-detect wire API based on model capabilities
4. Model catalog integration for Bedrock Mantel models

## 8. Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Chat Completions re-introduction breaks existing code | High | Exhaustive match on WireApi ensures all call sites are updated |
| Bedrock Mantel SSE format differs from OpenAI | Medium | Test against real Mantel endpoint; Mantel claims OpenAI compatibility |
| Tool call format differences between APIs | Medium | Translation layer with comprehensive test coverage |
| Conversation history grows unbounded in Chat mode | Medium | Leverage existing compaction/context management |
| Bedrock API key region mismatch | Low | Clear error messages; validate region in health check |

## 9. Testing Strategy

- Unit tests: Mock HTTP server for Chat Completions request/response
- Integration tests: End-to-end with wiremock simulating Bedrock Mantel
- Manual testing: Against real Bedrock Mantel endpoint with API key
- Snapshot tests: TUI rendering with Chat Completions streaming

## 10. Open Questions

All resolved — see `specs/README.md` "Key Decisions" section.
