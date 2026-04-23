mod keychain;
mod validation;
mod wizard_screen;

use std::path::Path;

use crate::legacy_core::config::Config;
use crate::legacy_core::config::edit::ConfigEdit;
use crate::legacy_core::config::edit::ConfigEditsBuilder;
use serde::Deserialize;
use serde::Serialize;

pub use wizard_screen::run_wizard;

/// Result of a completed wizard run.
pub struct WizardResult {
    pub api_key: String,
    pub region: String,
    pub model: String,
    pub discovered_models: Vec<String>,
}

/// Returns true if the wizard should be shown (no API key available anywhere).
pub fn should_show_wizard(config: &Config) -> bool {
    let has_env_key = std::env::var("AWS_BEARER_TOKEN_BEDROCK")
        .ok()
        .filter(|v| !v.trim().is_empty())
        .is_some();
    let has_provider_token = config
        .model_provider
        .experimental_bearer_token
        .as_ref()
        .is_some_and(|v| !v.trim().is_empty());
    let has_keychain_key = keychain::load_api_key().is_some();

    !has_env_key && !has_provider_token && !has_keychain_key
}

/// Load API key from the OS keychain.
pub fn load_api_key_from_keychain() -> Option<String> {
    keychain::load_api_key()
}

/// Persist wizard results: API key to keychain, region+model to config.toml.
pub fn save_wizard_result(codex_home: &Path, result: &WizardResult) -> anyhow::Result<()> {
    keychain::save_api_key(&result.api_key).map_err(|e| anyhow::anyhow!(e))?;

    ConfigEditsBuilder::new(codex_home)
        .with_edits([
            ConfigEdit::SetPath {
                segments: vec!["model".into()],
                value: result.model.clone().into(),
            },
            ConfigEdit::SetPath {
                segments: vec!["bedrock_region".into()],
                value: result.region.clone().into(),
            },
        ])
        .apply_blocking()?;

    write_model_cache(codex_home, &result.region, &result.discovered_models)?;
    Ok(())
}

// --- Model cache ---

#[derive(Serialize, Deserialize)]
struct ModelCache {
    models: Vec<String>,
    region: String,
    cached_at: i64,
}

fn write_model_cache(codex_home: &Path, region: &str, models: &[String]) -> anyhow::Result<()> {
    let cache = ModelCache {
        models: models.to_vec(),
        region: region.to_string(),
        cached_at: chrono::Utc::now().timestamp(),
    };
    let path = codex_home.join("models.json");
    let json = serde_json::to_string_pretty(&cache)?;
    std::fs::write(path, json)?;
    Ok(())
}
