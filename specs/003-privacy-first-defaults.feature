# Spec: Privacy-First Defaults for codex-bedrock Fork
# Parent specification — Gherkin format
# Date: 2026-04-19
# Status: DRAFT
#
# Summary:
#   All telemetry, analytics, tracking, crash reporting, and
#   phone-home behavior must be DISABLED by default in this fork.
#   The tool should only communicate with the configured model
#   provider endpoint (Bedrock Mantel) and nothing else.
#
# Audit Findings — 10 data collection points identified:
#
#   1. Analytics Events → chatgpt.com/backend-api/codex/analytics-events/events
#   2. OpenTelemetry Metrics → ab.chatgpt.com/otlp/v1/metrics (Statsig)
#   3. Sentry Crash Reports → o33249.ingest.us.sentry.io
#   4. Update Checker → api.github.com + formulae.brew.sh
#   5. User-Agent Header → OS, arch, terminal, version fingerprint
#   6. Version Header → CARGO_PKG_VERSION to OpenAI
#   7. Request Telemetry Headers → traceparent, tracestate, session_id
#   8. Auth Env Telemetry → which env vars are present
#   9. History persistence → ~/.codex/history.jsonl
#  10. Memories → ~/.codex/memories/ cross-session context

Feature: Privacy-first defaults — all telemetry disabled out of the box

  As a privacy-conscious developer using codex-bedrock
  I want zero data sent to any third party other than my model provider
  So that my code, prompts, and usage patterns remain completely private

  Background:
    Given the user is running the codex-bedrock fork
    And the user has not modified any telemetry settings

  # ─────────────────────────────────────────────────────────────────
  # EPIC 1: Analytics Events — DISABLED
  # ─────────────────────────────────────────────────────────────────

  @privacy @analytics
  Scenario: Analytics events are disabled by default
    Given the user has not set analytics.enabled in config.toml
    When Codex CLI initializes
    Then analytics_enabled defaults to false
    And no events are sent to chatgpt.com/backend-api/codex/analytics-events/events
    And no skill invocation, thread init, or turn events are tracked

  @privacy @analytics
  Scenario: DEFAULT_ANALYTICS_ENABLED constant is false
    Given the codex-bedrock fork source code
    When the TUI, exec, or mcp-server initializes the OTEL provider
    Then the default_analytics_enabled parameter is false
    And the analytics queue is not created unless explicitly enabled

  # ─────────────────────────────────────────────────────────────────
  # EPIC 2: OpenTelemetry Metrics — DISABLED
  # ─────────────────────────────────────────────────────────────────

  @privacy @otel
  Scenario: OTEL metrics exporter defaults to None
    Given the user has not configured otel.metrics_exporter in config.toml
    When Codex CLI initializes the OTEL provider
    Then the metrics_exporter defaults to OtelExporterKind::None
    And no metrics are sent to ab.chatgpt.com/otlp/v1/metrics
    And the Statsig API key is not used

  @privacy @otel
  Scenario: OTEL trace exporter defaults to None
    Given the user has not configured otel.trace_exporter in config.toml
    When Codex CLI initializes
    Then the trace_exporter defaults to OtelExporterKind::None
    And no traces are exported

  @privacy @otel
  Scenario: OTEL log exporter defaults to None
    Given the user has not configured otel.exporter in config.toml
    When Codex CLI initializes
    Then the exporter defaults to OtelExporterKind::None

  # ─────────────────────────────────────────────────────────────────
  # EPIC 3: Sentry/Feedback Crash Reports — DISABLED
  # ─────────────────────────────────────────────────────────────────

  @privacy @feedback
  Scenario: Feedback/Sentry crash reporting is disabled by default
    Given the user has not set feedback.enabled in config.toml
    When Codex CLI initializes
    Then feedback_enabled defaults to false
    And no crash reports are sent to Sentry (o33249.ingest.us.sentry.io)
    And no diagnostic data is collected or uploaded

  # ─────────────────────────────────────────────────────────────────
  # EPIC 4: Update Checker — DISABLED
  # ─────────────────────────────────────────────────────────────────

  @privacy @updates
  Scenario: Update checker is disabled by default
    Given the user has not set check_for_update_on_startup in config.toml
    When Codex CLI starts
    Then check_for_update_on_startup defaults to false
    And no requests are made to api.github.com
    And no requests are made to formulae.brew.sh

  # ─────────────────────────────────────────────────────────────────
  # EPIC 5: Request Headers — Minimal Fingerprint
  # ─────────────────────────────────────────────────────────────────

  @privacy @headers
  Scenario: User-Agent header is minimal for Bedrock Mantel
    Given the user is using the bedrock-mantel provider
    When Codex CLI makes a request to the model endpoint
    Then the User-Agent header does not include OS version details
    And the User-Agent header does not include terminal program info
    And the User-Agent is a generic identifier like "codex-bedrock/1.0"

  @privacy @headers
  Scenario: No version header is sent to Bedrock Mantel
    Given the user is using the bedrock-mantel provider
    When Codex CLI makes a request
    Then no "version" header containing CARGO_PKG_VERSION is sent
    And no "OpenAI-Organization" header is sent
    And no "OpenAI-Project" header is sent

  @privacy @headers
  Scenario: W3C trace context headers are not sent by default
    Given the user has not enabled OTEL tracing
    When Codex CLI makes a request to the model endpoint
    Then no "traceparent" header is sent
    And no "tracestate" header is sent

  # ─────────────────────────────────────────────────────────────────
  # EPIC 6: Local Data Persistence — Opt-in
  # ─────────────────────────────────────────────────────────────────

  @privacy @history
  Scenario: Conversation history is not persisted by default
    Given the user has not configured history.persistence in config.toml
    When the user completes a conversation
    Then no data is written to ~/.codexbedrock/history.jsonl
    And history.persistence defaults to "none"

  @privacy @memories
  Scenario: Memories are disabled by default
    Given the user has not configured memories in config.toml
    When the user completes a conversation
    Then no memory files are written to ~/.codexbedrock/memories/
    And memories.generate_memories defaults to false
    And memories.use_memories defaults to false

  # ─────────────────────────────────────────────────────────────────
  # EPIC 7: Auth Environment Telemetry — DISABLED
  # ─────────────────────────────────────────────────────────────────

  @privacy @auth-telemetry
  Scenario: Auth environment telemetry is not collected
    Given the user is using the bedrock-mantel provider
    When Codex CLI initializes authentication
    Then no telemetry about which env vars are present is collected
    And no auth environment metadata is sent via OTEL

  # ─────────────────────────────────────────────────────────────────
  # EPIC 8: Network Isolation — Only Model Provider
  # ─────────────────────────────────────────────────────────────────

  @privacy @network
  Scenario: Only the model provider endpoint is contacted
    Given the user is using the bedrock-mantel provider
    And all privacy defaults are in effect
    When Codex CLI runs a complete session
    Then the only outbound HTTPS connections are to bedrock-mantle.<region>.api.aws
    And no connections are made to chatgpt.com
    And no connections are made to api.openai.com
    And no connections are made to ab.chatgpt.com
    And no connections are made to sentry.io
    And no connections are made to api.github.com
    And no connections are made to formulae.brew.sh

  # ─────────────────────────────────────────────────────────────────
  # EPIC 9: User Can Opt-In to Telemetry
  # ─────────────────────────────────────────────────────────────────

  @privacy @opt-in
  Scenario: User explicitly enables analytics
    Given the user sets analytics.enabled = true in config.toml
    When Codex CLI initializes
    Then analytics events are sent as normal
    And the user made an informed choice

  @privacy @opt-in
  Scenario: User explicitly enables feedback
    Given the user sets feedback.enabled = true in config.toml
    When Codex CLI initializes
    Then Sentry crash reporting is enabled
    And the user made an informed choice

  @privacy @opt-in
  Scenario: User explicitly enables history
    Given the user sets history.persistence = "save-all" in config.toml
    When the user completes a conversation
    Then conversation history is written to ~/.codex/history.jsonl

  @privacy @opt-in
  Scenario: User explicitly enables update checks
    Given the user sets check_for_update_on_startup = true in config.toml
    When Codex CLI starts
    Then the update checker runs as normal
