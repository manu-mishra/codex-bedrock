# Spec: Bedrock Mantel Integration for Codex CLI
# Parent specification — Gherkin format
# Date: 2026-04-19
# Author: codex-bedrock fork
#
# Summary:
#   Enable Codex CLI to work with Amazon Bedrock Mantel endpoints,
#   giving users access to ~38 open-weight models (DeepSeek, Mistral,
#   Qwen, Gemma, GPT-OSS, etc.) via OpenAI-compatible APIs on AWS.
#
# Context:
#   Bedrock Mantel exposes OpenAI-compatible endpoints at
#   https://bedrock-mantle.<region>.api.aws/v1 supporting:
#     - /v1/responses  (only 4 GPT-OSS models)
#     - /v1/chat/completions (all ~38 models)
#     - /v1/models
#   Auth: Bearer token via Bedrock API Key (env: AWS_BEARER_TOKEN_BEDROCK)
#   or AWS SigV4 signing.
#
#   Current Codex CLI limitation: only WireApi::Responses is supported.
#   Chat Completions was removed. This means only 4 GPT-OSS models
#   work today, and even those have known auth/tool-type issues.
#   This spec covers the full integration path.
#
# Related Specs:
#   - specs/003-privacy-first-defaults.feature (privacy requirements)
#   - specs/004-technical-design-privacy.md (privacy technical design)
#   - specs/005-rebranding-codexbedrock.feature (side-by-side naming)
#   - specs/006-technical-design-rebranding.md (rebranding technical design)
#   - specs/007-no-openai-login.feature (remove OpenAI login)
#   - specs/008-technical-design-no-login.md (login removal technical design)

Feature: Bedrock Mantel as a built-in provider for Codex CLI

  As a developer using AWS Bedrock
  I want to use Codex CLI with models available on Bedrock Mantel
  So that I can leverage my AWS credits and infrastructure for AI-assisted coding

  # ─────────────────────────────────────────────────────────────────
  # EPIC 1: Built-in Bedrock Mantel Provider
  # ─────────────────────────────────────────────────────────────────

  @provider @config
  Scenario: User configures Bedrock Mantel as the model provider
    Given the user has a Bedrock API key stored in AWS_BEARER_TOKEN_BEDROCK
    And the user sets model_provider to "bedrock-mantel" in config.toml
    When Codex CLI starts
    Then the CLI resolves the built-in "bedrock-mantel" provider
    And the base_url is set to "https://bedrock-mantle.<region>.api.aws/v1"
    And the Authorization header uses "Bearer <API_KEY>"

  @provider @config
  Scenario: User configures Bedrock Mantel with a specific region
    Given the user sets bedrock_region to "eu-west-1" in config.toml
    When Codex CLI resolves the Bedrock Mantel provider
    Then the base_url is "https://bedrock-mantle.eu-west-1.api.aws/v1"

  @provider @config
  Scenario: User configures Bedrock Mantel via CLI override
    Given the user passes --model-provider bedrock-mantel on the command line
    And the user passes --model "deepseek.v3.2"
    When Codex CLI starts
    Then the CLI uses the Bedrock Mantel provider with the DeepSeek model

  @provider @config
  Scenario: User overrides Bedrock Mantel region via environment variable
    Given the environment variable CODEXBEDROCK_REGION is set to "us-west-2"
    When codexbedrock resolves the Bedrock Mantel provider
    Then the base_url uses the us-west-2 region endpoint

  # ─────────────────────────────────────────────────────────────────
  # EPIC 2: Authentication
  # ─────────────────────────────────────────────────────────────────

  @auth
  Scenario: Authentication via Bedrock API Key
    Given the user has AWS_BEARER_TOKEN_BEDROCK set in the environment
    When Codex CLI makes a request to Bedrock Mantel
    Then the request includes "Authorization: Bearer <key>" header
    And no SigV4 signing is applied

  # NOTE: SigV4 auth is a non-goal for initial release (see spec 002 section 3).
  # The scenario below is FUTURE scope only.

  @auth @error
  Scenario: Missing authentication credentials
    Given the user has not set AWS_BEARER_TOKEN_BEDROCK
    And the user has not configured AWS credentials
    When Codex CLI starts with model_provider "bedrock-mantel"
    Then the CLI displays a clear error message explaining authentication options
    And the error includes instructions for creating a Bedrock API key

  # ─────────────────────────────────────────────────────────────────
  # EPIC 3: Wire API — Chat Completions Support (Critical Path)
  # ─────────────────────────────────────────────────────────────────

  @wire-api @chat-completions
  Scenario: User selects a model that only supports Chat Completions
    Given the user configures model "deepseek.v3.2" on Bedrock Mantel
    And DeepSeek V3.2 only supports the Chat Completions API
    When Codex CLI starts a session
    Then the CLI uses the /v1/chat/completions endpoint
    And the request body uses the "messages" array format
    And streaming is enabled via "stream": true

  @wire-api @chat-completions
  Scenario: Chat Completions multi-turn conversation
    Given the user is in a Chat Completions session with "mistral.mistral-large-3-675b-instruct"
    When the user sends a follow-up message
    Then the CLI includes the full conversation history in the messages array
    And the previous assistant responses are included for context

  @wire-api @responses-api
  Scenario: User selects a GPT-OSS model that supports Responses API
    Given the user configures model "openai.gpt-oss-120b" on Bedrock Mantel
    And GPT-OSS 120B supports the Responses API
    When Codex CLI starts a session
    Then the CLI uses the /v1/responses endpoint
    And the existing Responses API flow works unchanged

  @wire-api @auto-detect
  Scenario: Wire API is auto-detected based on model capabilities
    Given the user configures model "qwen.qwen3-235b-a22b-2507" on Bedrock Mantel
    When Codex CLI resolves the wire API for this model
    Then the CLI determines that Chat Completions is required
    And the wire_api is set to "chat" for this session

  # ─────────────────────────────────────────────────────────────────
  # EPIC 4: Tool Use Compatibility
  # ─────────────────────────────────────────────────────────────────

  @tools
  Scenario: Function tools work via Chat Completions
    Given the user is in a Chat Completions session on Bedrock Mantel
    When the model requests a function tool call (e.g., shell command)
    Then the CLI translates the tool call to Chat Completions "tools" format
    And the tool result is sent back as a "tool" role message
    And the conversation continues

  @tools @filter
  Scenario: Unsupported tool types are filtered for Bedrock Mantel
    Given the user is in a session on Bedrock Mantel
    When the CLI prepares the tool list for the request
    Then only "function" and "mcp" tool types are included
    And "web_search" and other unsupported types are excluded
    And the user is not shown an error for filtered tools

  @tools
  Scenario: MCP tools work via Chat Completions on Bedrock Mantel
    Given the user has MCP servers configured
    And the user is in a Chat Completions session on Bedrock Mantel
    When the model invokes an MCP tool
    Then the MCP tool call is translated to the Chat Completions function format
    And the MCP tool result is returned to the model correctly

  # ─────────────────────────────────────────────────────────────────
  # EPIC 5: Model Discovery
  # ─────────────────────────────────────────────────────────────────

  @models
  Scenario: User lists available models on Bedrock Mantel
    Given the user has configured the Bedrock Mantel provider
    When the user requests the model list
    Then the CLI queries /v1/models on the Bedrock Mantel endpoint
    And displays the available models with their IDs

  @models
  Scenario: User selects a model not available on Mantel
    Given the user configures model "anthropic.claude-3-sonnet" on Bedrock Mantel
    When Codex CLI starts
    Then the CLI displays an error that the model is not available on Mantel
    And suggests checking available models via the models endpoint

  # ─────────────────────────────────────────────────────────────────
  # EPIC 6: Streaming and Error Handling
  # ─────────────────────────────────────────────────────────────────

  @streaming
  Scenario: Streaming responses via Chat Completions
    Given the user is in a Chat Completions session on Bedrock Mantel
    When the model generates a response
    Then the response is streamed incrementally via SSE
    And each chunk contains delta content
    And the TUI displays tokens as they arrive

  @error
  Scenario: Bedrock Mantel returns a 401 Unauthorized
    Given the user's Bedrock API key is expired or invalid
    When Codex CLI makes a request
    Then the CLI displays "Authentication failed with Bedrock Mantel"
    And suggests checking the API key and region

  @error
  Scenario: Bedrock Mantel returns a rate limit error
    Given the user exceeds the Bedrock Mantel rate limit
    When Codex CLI receives a 429 response
    Then the CLI retries with exponential backoff
    And respects the configured request_max_retries

  @error
  Scenario: Model not found on Bedrock Mantel
    Given the user configures a model ID that doesn't exist
    When Codex CLI makes a request
    Then the CLI displays a clear "model not found" error
    And suggests running model discovery

  # ─────────────────────────────────────────────────────────────────
  # EPIC 7: User Experience — First Run
  # ─────────────────────────────────────────────────────────────────

  @ux @first-run
  Scenario: First-time setup with Bedrock Mantel
    Given the user has never configured codexbedrock
    When the user runs "codexbedrock"
    And AWS_BEARER_TOKEN_BEDROCK is not set
    Then the CLI displays a guided setup message
    And the message explains how to create a Bedrock API key
    And the message shows the required environment variable
    And the message lists the available regions
