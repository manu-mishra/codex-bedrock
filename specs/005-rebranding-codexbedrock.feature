# Spec: Rebrand to "codexbedrock" for Side-by-Side Deployment
# Parent specification — Gherkin format
# Date: 2026-04-19
# Status: DRAFT
#
# Summary:
#   Rename user-facing binaries, config paths, and environment variables
#   from "codex" to "codexbedrock" so this fork can be installed alongside
#   the upstream OpenAI Codex CLI without conflicts.
#
# Naming Convention:
#   Binary:     codexbedrock  (what users type)
#   Home dir:   ~/.codexbedrock/
#   Env prefix: CODEXBEDROCK_
#   In-repo:    .codexbedrock/
#   Crate names: unchanged internally (codex-*) — only user-facing names change
#
# What does NOT change:
#   - Internal Rust crate names (codex-core, codex-tui, etc.)
#   - Internal lib names (codex_core, codex_tui, etc.)
#   - AGENTS.md / AGENTS.override.md filenames (shared convention)
#   - Wire protocol / API compatibility

Feature: Side-by-side deployment as "codexbedrock"

  As a developer who uses both OpenAI Codex and this Bedrock fork
  I want them installed side by side without conflicts
  So that I can switch between providers without uninstalling either

  Background:
    Given the upstream OpenAI Codex CLI is installed as "codex"
    And it uses ~/.codex/ for configuration
    And it uses CODEX_HOME as its env var

  # ─────────────────────────────────────────────────────────────────
  # EPIC 1: Binary Names
  # ─────────────────────────────────────────────────────────────────

  @naming @binary
  Scenario: Main CLI binary is named "codexbedrock"
    When the user installs the codex-bedrock fork
    Then the main binary is named "codexbedrock"
    And the user runs it by typing "codexbedrock" in the terminal
    And it does not conflict with the upstream "codex" binary

  @naming @binary
  Scenario: Companion binaries are renamed
    When the user installs the codex-bedrock fork
    Then the following binaries are available:
      | Original                    | Renamed                          |
      | codex                       | codexbedrock                     |
      | codex-exec                  | codexbedrock-exec                |
      | codex-app-server            | codexbedrock-app-server          |
      | codex-mcp-server            | codexbedrock-mcp-server          |
      | codex-linux-sandbox         | codexbedrock-linux-sandbox       |
      | codex-responses-api-proxy   | codexbedrock-responses-api-proxy |
      | codex-stdio-to-uds          | codexbedrock-stdio-to-uds        |
      | codex-execpolicy            | codexbedrock-execpolicy          |
      | codex-execve-wrapper        | codexbedrock-execve-wrapper      |
      | codex-windows-sandbox       | codexbedrock-windows-sandbox     |
      | codex-windows-sandbox-setup | codexbedrock-windows-sandbox-setup|
      | codex-command-runner        | codexbedrock-command-runner       |
    And none of these conflict with upstream Codex binaries

  # ─────────────────────────────────────────────────────────────────
  # EPIC 2: Configuration Paths
  # ─────────────────────────────────────────────────────────────────

  @naming @config
  Scenario: Home directory is ~/.codexbedrock/
    Given the user has not set CODEXBEDROCK_HOME
    When codexbedrock starts
    Then it uses ~/.codexbedrock/ as the home directory
    And ~/.codex/ is not read or modified

  @naming @config
  Scenario: In-repo project config uses .codexbedrock/
    Given a project has a .codexbedrock/ directory
    When codexbedrock runs in that project
    Then it reads .codexbedrock/config.toml for project-level config
    And .codex/ is not read

  @naming @config
  Scenario: Plugin manifest uses .codexbedrock-plugin/
    Given a plugin has a .codexbedrock-plugin/plugin.json manifest
    When codexbedrock discovers plugins
    Then it reads .codexbedrock-plugin/plugin.json
    And .codex-plugin/ is not read

  @naming @config
  Scenario: Config files within home directory are unchanged
    Given codexbedrock uses ~/.codexbedrock/ as home
    Then the following files are at their expected paths:
      | File                              |
      | ~/.codexbedrock/config.toml       |
      | ~/.codexbedrock/auth.json         |
      | ~/.codexbedrock/history.jsonl     |
      | ~/.codexbedrock/memories/         |
      | ~/.codexbedrock/log/              |

  # ─────────────────────────────────────────────────────────────────
  # EPIC 3: Environment Variables
  # ─────────────────────────────────────────────────────────────────

  @naming @env
  Scenario: Environment variables use CODEXBEDROCK_ prefix
    When codexbedrock reads environment configuration
    Then it uses the following environment variables:
      | Original                          | Renamed                              |
      | CODEX_HOME                        | CODEXBEDROCK_HOME                    |
      | CODEX_SANDBOX                     | CODEXBEDROCK_SANDBOX                 |
      | CODEX_SANDBOX_NETWORK_DISABLED    | CODEXBEDROCK_SANDBOX_NETWORK_DISABLED|
      | CODEX_SQLITE_HOME                 | CODEXBEDROCK_SQLITE_HOME             |
      | CODEX_CA_CERTIFICATE              | CODEXBEDROCK_CA_CERTIFICATE          |
      | CODEX_API_KEY                     | CODEXBEDROCK_API_KEY                 |
      | CODEX_OSS_PORT                    | CODEXBEDROCK_OSS_PORT                |
      | CODEX_OSS_BASE_URL                | CODEXBEDROCK_OSS_BASE_URL            |
      | CODEX_THREAD_ID                   | CODEXBEDROCK_THREAD_ID               |
      | CODEX_EXEC_SERVER_URL             | CODEXBEDROCK_EXEC_SERVER_URL         |
      | CODEX_CONNECTORS_TOKEN            | CODEXBEDROCK_CONNECTORS_TOKEN        |
      | CODEX_REMOTE_AUTH_TOKEN           | CODEXBEDROCK_REMOTE_AUTH_TOKEN       |
      | CODEX_JS_REPL_NODE_MODULE_DIRS    | CODEXBEDROCK_JS_REPL_NODE_MODULE_DIRS|
      | CODEX_INTERNAL_ORIGINATOR_OVERRIDE| CODEXBEDROCK_INTERNAL_ORIGINATOR_OVERRIDE|
    And the CODEX_ prefixed variables are not read

  # ─────────────────────────────────────────────────────────────────
  # EPIC 4: CLI Help and Branding
  # ─────────────────────────────────────────────────────────────────

  @naming @ux
  Scenario: CLI help shows "codexbedrock" branding
    When the user runs "codexbedrock --help"
    Then the help text shows "codexbedrock" as the binary name
    And examples use "codexbedrock" not "codex"

  @naming @ux
  Scenario: Error messages reference "codexbedrock"
    When codexbedrock encounters a configuration error
    Then error messages reference "codexbedrock" and "~/.codexbedrock/"
    And they do not reference "codex" or "~/.codex/"

  # ─────────────────────────────────────────────────────────────────
  # EPIC 5: Side-by-Side Verification
  # ─────────────────────────────────────────────────────────────────

  @naming @side-by-side
  Scenario: Both tools coexist without interference
    Given upstream "codex" is installed with ~/.codex/config.toml
    And "codexbedrock" is installed with ~/.codexbedrock/config.toml
    When the user runs "codex" then "codexbedrock"
    Then each tool reads only its own config directory
    And each tool writes only to its own home directory
    And no data leaks between the two installations

  @naming @side-by-side
  Scenario: AGENTS.md is shared between both tools
    Given a project has an AGENTS.md file
    When the user runs "codex" or "codexbedrock" in that project
    Then both tools read the same AGENTS.md
    And this is intentional — project docs are tool-agnostic
