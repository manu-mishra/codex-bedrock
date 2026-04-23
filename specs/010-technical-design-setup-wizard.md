# Technical Design: Bedrock Setup Wizard
# Date: 2026-04-19
# Status: DRAFT
# Parent Spec: specs/009-bedrock-setup-wizard.feature

## 1. Overview

A step-by-step TUI wizard that runs on first launch (or via `/setup`).
Each step validates before advancing. Results are persisted to keychain
(API key) and config.toml (region, model). Model list is cached locally.

## 2. Architecture

New module: `codex-rs/tui/src/bedrock_setup/`

```
bedrock_setup/
├── mod.rs              — public API: should_show_wizard(), run_wizard()
├── wizard_screen.rs    — step state machine, render, key handling
├── auth_step.rs        — API key entry with masked input
├── region_step.rs      — region picker list
├── model_step.rs       — model picker from live discovery
├── validation.rs       — HTTP calls to verify connection + fetch models
└── keychain.rs         — keychain read/write for API key
```

## 3. Step State Machine

```rust
enum WizardStep {
    AuthMethod,     // Pick: API Key vs AWS Profile (coming soon)
    ApiKeyEntry,    // Paste key, masked input
    RegionSelect,   // Pick from known list
    Validating,     // Spinner: GET /v1/models to verify connection
    ModelSelect,    // Pick from discovered models
    Summary,        // Show config, press Enter to start
}
```

Transitions:
```
AuthMethod → ApiKeyEntry → RegionSelect → Validating
    ↓ (on success)          ↑ (on failure, retry)
ModelSelect → Summary → [exit wizard, start chat]
```

## 4. Detailed Design

### 4.1 Wizard Trigger

File: `codex-rs/tui/src/lib.rs`

Replace the current early API key validation (the `eprintln` + `exit(1)`)
with a wizard trigger:

```rust
let needs_setup = !has_bedrock_api_key(&config) && !has_keychain_key();
if needs_setup || config.model.is_none() {
    let setup_result = bedrock_setup::run_wizard(&mut tui, &config).await?;
    // reload config after wizard writes to config.toml
    config = reload_config(...);
}
```

`has_bedrock_api_key()` checks `AWS_BEARER_TOKEN_BEDROCK` env var.
`has_keychain_key()` checks the keychain for a stored key.

### 4.2 Keychain Storage

File: `codex-rs/tui/src/bedrock_setup/keychain.rs`

```rust
use codex_keyring_store::DefaultKeyringStore;
use codex_keyring_store::KeyringStore;

const KEYRING_SERVICE: &str = "codex-b";
const KEYRING_ACCOUNT: &str = "bedrock-api-key";

pub fn save_api_key(key: &str) -> Result<(), String> {
    let store = DefaultKeyringStore;
    store.save(KEYRING_SERVICE, KEYRING_ACCOUNT, key)
        .map_err(|e| format!("Failed to save to keychain: {e}"))
}

pub fn load_api_key() -> Option<String> {
    let store = DefaultKeyringStore;
    store.load(KEYRING_SERVICE, KEYRING_ACCOUNT).ok().flatten()
}
```

### 4.3 Connection Validation + Model Discovery

File: `codex-rs/tui/src/bedrock_setup/validation.rs`

```rust
pub struct ValidationResult {
    pub models: Vec<String>,
}

pub async fn validate_and_discover(
    api_key: &str,
    region: &str,
) -> Result<ValidationResult, String> {
    let url = format!(
        "https://bedrock-mantle.{region}.api.aws/v1/models"
    );
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(10))
        .build()
        .map_err(|e| format!("HTTP client error: {e}"))?;

    let resp = client.get(&url)
        .header("Authorization", format!("Bearer {api_key}"))
        .send()
        .await
        .map_err(|e| format!("Connection failed: {e}"))?;

    if resp.status() == 401 {
        return Err("Invalid API key. Check your key and try again.".into());
    }
    if !resp.status().is_success() {
        return Err(format!("Bedrock returned HTTP {}", resp.status()));
    }

    let body: serde_json::Value = resp.json().await
        .map_err(|e| format!("Invalid response: {e}"))?;

    let models = body.get("data")
        .and_then(|d| d.as_array())
        .map(|arr| arr.iter()
            .filter_map(|m| m.get("id").and_then(|id| id.as_str()))
            .map(String::from)
            .collect::<Vec<_>>())
        .unwrap_or_default();

    if models.is_empty() {
        return Err("No models available in this region.".into());
    }

    Ok(ValidationResult { models })
}
```

### 4.4 Model Cache

File: `codex-rs/tui/src/bedrock_setup/mod.rs`

```rust
#[derive(Serialize, Deserialize)]
struct ModelCache {
    models: Vec<String>,
    region: String,
    cached_at: i64,  // unix timestamp
}

const MODELS_CACHE_FILE: &str = "models.json";
const CACHE_TTL_HOURS: i64 = 24;
```

Written to `~/.codexb/models.json` after successful discovery.
Read at startup to avoid re-querying Bedrock.

### 4.5 Config Persistence

After wizard completes, write to `~/.codexb/config.toml`:

```rust
use codex_core::config::edit::{ConfigEdit, ConfigEditsBuilder};
use toml_edit::value;

let edits = [
    ConfigEdit::SetPath {
        segments: vec!["model".into()],
        value: value(&selected_model),
    },
    ConfigEdit::SetPath {
        segments: vec!["bedrock_region".into()],
        value: value(&selected_region),
    },
];

ConfigEditsBuilder::new(&codex_home)
    .with_edits(edits)
    .apply_blocking()?;
```

The API key is NOT written to config.toml — it's in the keychain.

### 4.6 Runtime Key Resolution

File: `codex-rs/model-provider-info/src/lib.rs`

The `api_key()` method on `ModelProviderInfo` checks `env_key`. We need to
also check the keychain as a fallback. Add to the bedrock-mantel provider's
key resolution:

```rust
pub fn api_key(&self) -> CodexResult<Option<String>> {
    // 1. Check env var first
    if let Some(env_key) = &self.env_key {
        if let Ok(val) = std::env::var(env_key) {
            if !val.trim().is_empty() {
                return Ok(Some(val));
            }
        }
    }
    // 2. Fall back to keychain (for bedrock-mantel)
    // This is handled by the caller — see below
    ...
}
```

Actually, the cleaner approach: in the `BearerAuthProvider` construction
path for bedrock-mantel, check keychain if env var is empty. This happens
in `model-provider/src/auth.rs` → `bearer_auth_provider_from_auth()`.

The simplest integration point: modify `api_key()` on `ModelProviderInfo`
to accept an optional keychain fallback, or have the bedrock-mantel
provider set `experimental_bearer_token` from the keychain at startup.

**Recommended approach**: At TUI startup, before creating the provider,
check if the env var is set. If not, load from keychain and set
`experimental_bearer_token` on the provider info. This requires no changes
to the auth plumbing — it just uses the existing `experimental_bearer_token`
field which already feeds into `BearerAuthProvider`.

### 4.7 /setup Slash Command

File: `codex-rs/tui/src/slash_command.rs` (or equivalent)

Register `/setup` as a slash command that re-triggers the wizard.

## 5. What Gets Stored Where

| Data | Storage | Why |
|------|---------|-----|
| API key | OS Keychain (`codex-b` / `bedrock-api-key`) | Encrypted at rest, never on disk as plaintext |
| Region | `~/.codexb/config.toml` (`bedrock_region`) | Not sensitive |
| Model | `~/.codexb/config.toml` (`model`) | Not sensitive |
| Model list | `~/.codexb/models.json` | Cache, avoids re-querying Bedrock |

## 6. Implementation Order

1. Create `bedrock_setup/` module with keychain.rs and validation.rs
2. Build the wizard screen (state machine + rendering)
3. Wire wizard trigger into TUI startup
4. Add keychain fallback for API key at runtime
5. Add model cache read/write
6. Add /setup slash command
7. Run `just fmt`, `cargo test -p codex-tui`
