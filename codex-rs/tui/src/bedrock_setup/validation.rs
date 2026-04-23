use std::time::Duration;

pub struct DiscoveryResult {
    pub models: Vec<String>,
}

pub async fn validate_and_discover_models(
    api_key: &str,
    region: &str,
) -> Result<DiscoveryResult, String> {
    let url = format!("https://bedrock-mantle.{region}.api.aws/v1/models");
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(10))
        .build()
        .map_err(|e| format!("HTTP client error: {e}"))?;

    let resp = client
        .get(&url)
        .header("Authorization", format!("Bearer {api_key}"))
        .send()
        .await
        .map_err(|e| format!("Connection failed: {e}"))?;

    if resp.status() == reqwest::StatusCode::UNAUTHORIZED {
        return Err("Invalid API key. Check your key and try again.".into());
    }
    if !resp.status().is_success() {
        return Err(format!("Bedrock returned HTTP {}", resp.status()));
    }

    let body: serde_json::Value = resp
        .json()
        .await
        .map_err(|e| format!("Invalid response: {e}"))?;

    let models = body
        .get("data")
        .and_then(|d| d.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|m| m.get("id").and_then(|id| id.as_str()))
                .map(String::from)
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();

    if models.is_empty() {
        return Err("No models available in this region.".into());
    }

    Ok(DiscoveryResult { models })
}
