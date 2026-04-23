use codex_keyring_store::DefaultKeyringStore;
use codex_keyring_store::KeyringStore;

const KEYRING_SERVICE: &str = "codexb";
const KEYRING_ACCOUNT: &str = "bedrock-api-key";

pub fn save_api_key(key: &str) -> Result<(), String> {
    let store = DefaultKeyringStore;
    store
        .save(KEYRING_SERVICE, KEYRING_ACCOUNT, key)
        .map_err(|e| format!("Failed to save to keychain: {e}"))
}

pub fn load_api_key() -> Option<String> {
    let store = DefaultKeyringStore;
    store.load(KEYRING_SERVICE, KEYRING_ACCOUNT).ok().flatten()
}
