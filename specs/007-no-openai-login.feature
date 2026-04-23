# Spec: Remove OpenAI Login Requirements
# Parent specification — Gherkin format
# Date: 2026-04-19
# Status: DRAFT
#
# Summary:
#   codexbedrock must NEVER require, prompt for, or attempt any form of
#   OpenAI/ChatGPT authentication. No login screen, no browser OAuth,
#   no device code flow, no token refresh, no cloud requirements fetch.
#   The only auth is the Bedrock API key via env var.
#
# Audit Findings — 8 OpenAI auth touchpoints:
#
#   1. TUI login screen — shown when requires_openai_auth = true
#   2. Browser OAuth flow — opens auth.openai.com in browser
#   3. Device code flow — polls auth.openai.com for device code
#   4. API key entry screen — prompts for OpenAI API key in TUI
#   5. Token refresh — contacts auth.openai.com/oauth/token
#   6. Token revocation — contacts auth.openai.com/oauth/revoke
#   7. enforce_login_restrictions() — called unconditionally in exec
#   8. Cloud requirements — fetches requirements.toml from chatgpt.com
#
# Additionally:
#   9. chatgpt_base_url defaults to "https://chatgpt.com/backend-api/"
#  10. to_api_provider() falls back to api.openai.com or chatgpt.com
#  11. OPENAI_API_KEY / CODEX_API_KEY env vars checked for auth

Feature: No OpenAI login required — Bedrock API key only

  As a codexbedrock user
  I want zero interaction with OpenAI authentication systems
  So that I can use the tool purely with my AWS Bedrock credentials

  Background:
    Given the user is running codexbedrock
    And the user has AWS_BEARER_TOKEN_BEDROCK set in the environment

  # ─────────────────────────────────────────────────────────────────
  # EPIC 1: No Login Screen
  # ─────────────────────────────────────────────────────────────────

  @no-login @tui
  Scenario: TUI never shows the login/sign-in screen
    When codexbedrock starts the TUI
    Then no login or sign-in screen is displayed
    And the user goes directly to the chat interface
    And no "Sign in with ChatGPT" option is shown

  @no-login @tui
  Scenario: Onboarding skips authentication step entirely
    When codexbedrock shows the onboarding flow
    Then the authentication step is not present
    And the onboarding only shows trust/project setup if needed

  @no-login @exec
  Scenario: codexbedrock exec does not check login restrictions
    When the user runs "codexbedrock exec"
    Then enforce_login_restrictions() is not called
    And no auth.json or keyring is read
    And the command proceeds directly to execution

  # ─────────────────────────────────────────────────────────────────
  # EPIC 2: No OpenAI OAuth Flows
  # ─────────────────────────────────────────────────────────────────

  @no-login @oauth
  Scenario: No browser is opened for authentication
    When codexbedrock runs any command
    Then no browser window is opened
    And no local OAuth callback server is started
    And no connection is made to auth.openai.com

  @no-login @oauth
  Scenario: No device code flow is initiated
    When codexbedrock runs any command
    Then no device code request is made
    And no polling for device code completion occurs

  @no-login @oauth
  Scenario: No token refresh is attempted
    When codexbedrock runs any command
    Then no request is made to auth.openai.com/oauth/token
    And no refresh token logic is executed

  @no-login @oauth
  Scenario: No token revocation is attempted
    When codexbedrock runs any command
    Then no request is made to auth.openai.com/oauth/revoke

  # ─────────────────────────────────────────────────────────────────
  # EPIC 3: No Cloud Requirements Fetch
  # ─────────────────────────────────────────────────────────────────

  @no-login @cloud
  Scenario: Cloud requirements are not fetched
    When codexbedrock loads configuration
    Then no request is made to chatgpt.com/backend-api/
    And the CloudRequirementsLoader is disabled
    And local config.toml is the only config source

  # ─────────────────────────────────────────────────────────────────
  # EPIC 4: No OpenAI Fallback URLs
  # ─────────────────────────────────────────────────────────────────

  @no-login @urls
  Scenario: No fallback to api.openai.com
    Given the bedrock-mantel provider has a base_url configured
    When codexbedrock resolves the API provider
    Then the base_url is the Bedrock Mantel endpoint
    And "api.openai.com" is never used as a fallback
    And "chatgpt.com" is never used as a fallback

  @no-login @urls
  Scenario: chatgpt_base_url is not used
    When codexbedrock loads configuration
    Then chatgpt_base_url is irrelevant
    And no requests are made to any chatgpt.com endpoint

  # ─────────────────────────────────────────────────────────────────
  # EPIC 5: No OpenAI API Key Env Vars
  # ─────────────────────────────────────────────────────────────────

  @no-login @env
  Scenario: OPENAI_API_KEY is not read or used
    Given the user has OPENAI_API_KEY set in the environment
    When codexbedrock starts
    Then OPENAI_API_KEY is ignored
    And the Bedrock API key from AWS_BEARER_TOKEN_BEDROCK is used instead

  @no-login @env
  Scenario: CODEX_API_KEY is not read or used
    Given the user has CODEX_API_KEY set in the environment
    When codexbedrock starts
    Then CODEX_API_KEY is ignored
    And no OpenAI auth flow is triggered

  # ─────────────────────────────────────────────────────────────────
  # EPIC 6: Auth Storage Not Used
  # ─────────────────────────────────────────────────────────────────

  @no-login @storage
  Scenario: auth.json is not read or written
    When codexbedrock runs any command
    Then ~/.codexbedrock/auth.json is not read
    And ~/.codexbedrock/auth.json is not written
    And no keyring operations are performed

  @no-login @storage
  Scenario: No ChatGPT account ID is stored or sent
    When codexbedrock makes API requests
    Then no "ChatGPT-Account-ID" header is sent
    And no account ID is stored locally
