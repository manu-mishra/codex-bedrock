# Spec: Bedrock Setup Wizard
# Parent specification — Gherkin format
# Date: 2026-04-19
# Status: DRAFT

Feature: First-run setup wizard for Bedrock Mantel

  As a new codexbedrock user
  I want a guided setup that validates each step
  So that I have a working configuration before I start coding

  Background:
    Given the user has installed codexbedrock
    And ~/.codexbedrock/config.toml does not exist or has no bedrock config

  # ─────────────────────────────────────────────────────────────────
  # EPIC 1: Wizard Trigger
  # ─────────────────────────────────────────────────────────────────

  @wizard @trigger
  Scenario: Wizard runs on first launch
    Given no API key is configured (env var or keychain)
    When the user runs codexbedrock
    Then the setup wizard is displayed in the TUI
    And the user cannot proceed to chat until setup is complete

  @wizard @trigger
  Scenario: Wizard is skipped when already configured
    Given AWS_BEARER_TOKEN_BEDROCK is set in the environment
    And ~/.codexbedrock/config.toml has a model configured
    When the user runs codexbedrock
    Then the wizard is skipped
    And the user goes directly to the chat interface

  @wizard @trigger
  Scenario: Wizard can be re-run from settings
    Given the user is in the chat interface
    When the user types /setup
    Then the setup wizard is displayed again
    And the user can change auth, region, or model

  # ─────────────────────────────────────────────────────────────────
  # EPIC 2: Step 1 — Authentication Method
  # ─────────────────────────────────────────────────────────────────

  @wizard @auth
  Scenario: User selects API Key authentication
    Given the wizard is on the auth method step
    When the user selects "Bedrock API Key"
    Then the wizard advances to the API key entry screen

  @wizard @auth
  Scenario: AWS Profile option shows coming soon
    Given the wizard is on the auth method step
    Then "AWS Profile (coming soon)" is visible but not selectable

  # ─────────────────────────────────────────────────────────────────
  # EPIC 3: Step 2 — API Key Entry + Keychain Storage
  # ─────────────────────────────────────────────────────────────────

  @wizard @key
  Scenario: User enters API key and it is stored in keychain
    Given the wizard is on the API key entry step
    When the user pastes their Bedrock API key
    And presses Enter
    Then the key is stored in the OS keychain (macOS Keychain / Windows Credential Manager)
    And the key is NOT written to config.toml or any file on disk
    And the wizard advances to region selection

  @wizard @key
  Scenario: API key input is masked
    Given the wizard is on the API key entry step
    When the user types characters
    Then each character is displayed as a bullet (•) not plaintext

  @wizard @key
  Scenario: Existing env var key is detected
    Given AWS_BEARER_TOKEN_BEDROCK is set in the environment
    When the wizard reaches the API key step
    Then the wizard shows "API key detected from environment"
    And the user can press Enter to use it or paste a different one

  # ─────────────────────────────────────────────────────────────────
  # EPIC 4: Step 3 — Region Selection + Validation
  # ─────────────────────────────────────────────────────────────────

  @wizard @region
  Scenario: User selects a region from the list
    Given the wizard is on the region selection step
    Then the following regions are listed:
      | Region         | Label                    |
      | us-east-1      | US East (N. Virginia)    |
      | us-east-2      | US East (Ohio)           |
      | us-west-2      | US West (Oregon)         |
      | eu-west-1      | Europe (Ireland)         |
      | eu-west-2      | Europe (London)          |
      | eu-central-1   | Europe (Frankfurt)       |
      | eu-north-1     | Europe (Stockholm)       |
      | eu-south-1     | Europe (Milan)           |
      | ap-northeast-1 | Asia Pacific (Tokyo)     |
      | ap-south-1     | Asia Pacific (Mumbai)    |
      | ap-southeast-3 | Asia Pacific (Jakarta)   |
      | sa-east-1      | South America (São Paulo)|
    And us-east-1 is highlighted as the default

  @wizard @region @validation
  Scenario: Connection is validated after region selection
    Given the user selects a region
    When the wizard validates the connection
    Then it sends GET /v1/models to bedrock-mantle.<region>.api.aws
    And on success shows "✓ Connected to Bedrock Mantel (<region>)"
    And advances to model selection

  @wizard @region @validation
  Scenario: Connection validation fails
    Given the user selects a region
    When the connection validation fails (401, timeout, etc.)
    Then the wizard shows an error: "Could not connect. Check your API key and region."
    And the user stays on the region step to try again

  # ─────────────────────────────────────────────────────────────────
  # EPIC 5: Step 4 — Model Selection + Cache
  # ─────────────────────────────────────────────────────────────────

  @wizard @model
  Scenario: Models are listed from live discovery
    Given the connection was validated successfully
    When the wizard shows the model selection step
    Then models are populated from the /v1/models response
    And deepseek.v3.2 is highlighted as the recommended default

  @wizard @model @cache
  Scenario: Model list is cached locally
    Given the user selects a model
    Then the full model list is saved to ~/.codexbedrock/models.json
    And the cache includes a timestamp
    And during normal usage the cached list is used instead of querying Bedrock

  @wizard @model @cache
  Scenario: Model cache is refreshed when stale
    Given the model cache is older than 24 hours
    When codexbedrock starts
    Then the model list is refreshed in the background
    And the cached list is updated

  # ─────────────────────────────────────────────────────────────────
  # EPIC 6: Step 5 — Save and Launch
  # ─────────────────────────────────────────────────────────────────

  @wizard @save
  Scenario: Configuration is persisted
    Given the user has completed all wizard steps
    Then ~/.codexbedrock/config.toml is written with:
      | Key            | Value                |
      | model          | <selected model>     |
      | bedrock_region | <selected region>    |
    And the API key is in the OS keychain (not in config.toml)
    And the model cache is in ~/.codexbedrock/models.json

  @wizard @save
  Scenario: User proceeds to chat after setup
    Given configuration is saved
    When the user presses Enter on the summary screen
    Then the wizard closes
    And the chat interface starts with the configured model and region

  # ─────────────────────────────────────────────────────────────────
  # EPIC 7: Runtime Key Resolution
  # ─────────────────────────────────────────────────────────────────

  @runtime @key
  Scenario: API key is resolved from keychain at runtime
    Given the user stored their key via the setup wizard
    And AWS_BEARER_TOKEN_BEDROCK is NOT set in the environment
    When codexbedrock makes an API request
    Then the key is loaded from the OS keychain
    And used as "Authorization: Bearer <key>"

  @runtime @key
  Scenario: Environment variable takes precedence over keychain
    Given the user has a key in the keychain
    And AWS_BEARER_TOKEN_BEDROCK IS set in the environment
    When codexbedrock makes an API request
    Then the environment variable value is used
    And the keychain value is ignored
