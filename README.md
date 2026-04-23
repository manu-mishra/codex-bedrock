# codex-b

A privacy-first AI coding agent that runs locally, powered by Amazon Bedrock Mantel. Fork of [OpenAI Codex CLI](https://github.com/openai/codex).

## Quickstart

### 1. Get a Bedrock API Key

Go to the [Amazon Bedrock console](https://console.aws.amazon.com/bedrock/) → API keys → Create key.

### 2. Run

```shell
codex-b
```

On first run, a setup wizard guides you through:
- Pasting your API key (stored securely in macOS Keychain / Windows Credential Manager)
- Selecting your AWS region
- Picking a model from live discovery

No environment variables or config files needed. Just run it.

### Alternative: Environment Variable

If you prefer, you can skip the wizard by setting the key as an env var:

```shell
export AWS_BEARER_TOKEN_BEDROCK=<your-key>
codex-b
```

## Default Model

codex-b uses `deepseek.v3.2` by default. Change it anytime:

- **In the TUI**: type `/model` to open the model picker (fetches live from Bedrock)
- **CLI flag**: `codex-b -m mistral.mistral-large-3-675b-instruct`
- **Config file**: `~/.codexb/config.toml`

```toml
model = "qwen.qwen3-235b-a22b-2507"
```

## Available Models

All ~38 open-weight models on [Bedrock Mantel](https://docs.aws.amazon.com/bedrock/latest/userguide/bedrock-mantle.html), including:

| Model | ID |
|-------|----|
| DeepSeek V3.2 | `deepseek.v3.2` |
| Mistral Large 3 | `mistral.mistral-large-3-675b-instruct` |
| Qwen3 235B | `qwen.qwen3-235b-a22b-2507` |
| Qwen3 Coder | `qwen.qwen3-coder-next` |
| GPT-OSS 120B | `openai.gpt-oss-120b` |
| Moonshot Kimi K2.5 | `moonshotai.kimi-k2.5` |
| Google Gemma 3 27B | `google.gemma-3-27b-it` |
| NVIDIA Nemotron | `nvidia.nemotron-nano-12b-v2` |
| Mistral Ministral 8B | `mistral.ministral-3-8b-instruct` |
| Qwen3 Coder 30B | `qwen.qwen3-coder-30b-a3b-instruct` |

Use `/model` in the TUI to see the full list for your region, or:

```shell
curl -s -H "Authorization: Bearer $AWS_BEARER_TOKEN_BEDROCK" \
  https://bedrock-mantle.us-east-1.api.aws/v1/models | jq '.data[].id'
```

## Region

Default region is `us-east-1`. Override with:

```shell
export CODEXB_REGION=eu-west-1
```

Or in `~/.codexb/config.toml`:

```toml
bedrock_region = "eu-west-1"
```

Available regions: us-east-1, us-east-2, us-west-2, eu-west-1, eu-west-2, eu-central-1, eu-north-1, eu-south-1, ap-northeast-1, ap-south-1, ap-southeast-3, sa-east-1.

## What's Different from Upstream Codex

This fork makes the following changes to the [upstream OpenAI Codex CLI](https://github.com/openai/codex):

### Bedrock Mantel Integration
- **Built-in provider**: Bedrock Mantel is the default provider (not OpenAI)
- **Chat Completions API**: Re-introduced support for `/v1/chat/completions` so all ~38 Mantel models work (upstream only supports the Responses API, which only 4 GPT-OSS models on Mantel support)
- **Model discovery**: `/model` command fetches live model list from Bedrock Mantel
- **Region-aware**: Endpoint URL constructed from configured region
- **Default model**: `deepseek.v3.2` out of the box

### First-Run Setup Wizard
- Interactive TUI wizard on first launch
- API key entry with masked input
- Region selection from known Bedrock regions
- Live connection validation before proceeding
- Model selection from discovered models
- API key stored in OS keychain (never written to disk as plaintext)

### Privacy-First Defaults
All telemetry and phone-home behavior is **disabled by default**:

| What | Upstream Default | codex-b Default |
|------|-----------------|-----------------|
| Analytics events (to chatgpt.com) | ON | **OFF** |
| OTEL metrics (to Statsig) | ON | **OFF** |
| Sentry crash reports | ON | **OFF** |
| Update checker (GitHub/Homebrew) | ON | **OFF** |
| Conversation history | Saved to disk | **Not saved** |
| Memories (cross-session context) | ON | **OFF** |

The only outbound connection is to your configured Bedrock Mantel endpoint.

All features can be re-enabled in `~/.codexb/config.toml` if desired.

### No OpenAI Login Required
- No login screen, no browser OAuth, no device code flow
- No connection to `auth.openai.com`, `chatgpt.com`, or `api.openai.com`
- `codex login` / `codex logout` / `codex app` subcommands removed
- Authentication is purely via Bedrock API key (env var or keychain)

### Side-by-Side Deployment
Renamed to avoid conflicts with upstream Codex CLI:

| What | Upstream | codex-b |
|------|----------|---------|
| Binary | `codex` | `codex-b` |
| Home dir | `~/.codex/` | `~/.codexb/` |
| Env vars | `CODEX_*` | `CODEXB_*` |
| In-repo config | `.codex/` | `.codexb/` |
| Keychain service | — | `codexb` |

Internal crate names (`codex-core`, etc.) are unchanged to preserve upstream mergeability.

### Tool Compatibility
- `web_search` tool type auto-disabled (not supported by Bedrock Mantel)
- Function tools and MCP tools work via Chat Completions function calling
- `/apps` command hidden (ChatGPT-specific)

## Configuration

Config file: `~/.codexb/config.toml`

```toml
# Model (optional — defaults to deepseek.v3.2)
model = "mistral.mistral-large-3-675b-instruct"

# Region (optional — defaults to us-east-1)
bedrock_region = "eu-west-1"

# Re-enable features if desired:
# [analytics]
# enabled = true
#
# [feedback]
# enabled = true
#
# check_for_update_on_startup = true
#
# [history]
# persistence = "save-all"
#
# [memories]
# generate_memories = true
# use_memories = true
```

## API Key Storage

| Method | How | Where Stored |
|--------|-----|-------------|
| Setup wizard (default) | Paste in TUI on first run | OS Keychain (encrypted) |
| Environment variable | `export AWS_BEARER_TOKEN_BEDROCK=...` | Shell session only |
| Config file | `experimental_bearer_token = "..."` | Disk (not recommended) |

Priority: env var → keychain. The wizard is the default path.

## Building from Source

```shell
git clone <this-repo>
cd codex-bedrock/codex-rs
cargo build --release -p codex-cli
./target/release/codex-b
```

## License

[Apache-2.0](LICENSE)
