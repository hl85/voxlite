# Remote Model Configuration Redesign

## TL;DR

> **Quick Summary**: Redesign VoxLite's remote model configuration to provide a LiteLLM-like unified experience — dropdown menus for provider/model selection, provider presets with auto-filled endpoints, Keychain-secured API keys, and an in-house OpenAI-compatible HTTP client.
> 
> **Deliverables**:
> - Provider registry enum with presets for Deepseek, Groq, SiliconFlow + Custom
> - Lightweight OpenAI-compatible HTTP client (URLSession, zero deps)
> - Keychain wrapper for API key storage
> - Remote `SpeechTranscribing` implementation (Whisper API)
> - Remote `PromptGenerating` implementation (Chat Completions API)
> - Redesigned settings UI with dropdown menus and connection validation
> - Pipeline wiring to select local vs remote based on settings
> 
> **Estimated Effort**: Large
> **Parallel Execution**: YES — 3 waves
> **Critical Path**: Task 1 (types) → Task 3 (HTTP client) → Task 6 (remote STT) → Task 9 (pipeline wiring) → Task 10 (settings UI) → F1-F4

---

## Context

### Original Request
Redesign remote model configuration to be LiteLLM-like: dropdown menus for both STT and LLM model selection, default to local model, mainstream cloud providers as presets with auto-filled endpoints, user only configures API key.

### Interview Summary
**Key Discussions**:
- **Providers**: Deepseek, Groq, SiliconFlow (硅基流动), Custom (OpenAI-compatible). User explicitly excluded OpenAI and Anthropic.
- **API format**: OpenAI-compatible only (`/v1/chat/completions` + `/v1/audio/transcriptions`). Single HTTP client adapter.
- **Validation**: Validate API connection before saving config (test request to `/v1/models`).
- **Tests**: No unit tests — QA scenarios only for verification.
- **No third-party libs**: Everything built in-house using Swift standard library + system frameworks.

**Research Findings**:
- Current `ModelSetting` is just `{localEnabled, remoteProvider: String, remoteEndpoint: String}` — no structured data
- No HTTP networking or Keychain code exists in the project
- Pipeline uses protocol injection (`SpeechTranscribing`, `PromptGenerating`) — remote impls just conform
- Production macOS apps (Ayna, GPTalks, swift-ai) use enum-based provider registries — reference patterns studied
- All target providers support OpenAI-compatible Chat Completions; STT support varies by provider

### Metis Review
**Identified Gaps** (addressed):
- **Provider STT capability varies**: Added capability flags (`.supportsSTT`, `.supportsLLM`) to provider enum — only providers that support Whisper appear in STT dropdown
- **Fallback behavior**: Fail fast with error message — no silent fallback to local (user must be aware)
- **Model lists**: Hardcoded presets per provider — no API-based model discovery (simpler, works offline)
- **Custom provider scope**: Endpoint + API key + model name only — no custom headers/timeouts
- **Keychain security**: `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` (no iCloud sync)
- **Error granularity**: Specific error codes for 401 (InvalidAPIKey), 429 (RateLimited), generic for others
- **UI state**: Remember last-used model per provider (persist per-provider selections)
- **Privacy**: Metadata-only logging (endpoint, status code, latency) — no full request/response bodies

---

## Work Objectives

### Core Objective
Replace VoxLite's free-text remote model configuration with a structured provider registry system featuring dropdown menus, auto-filled endpoints, Keychain API key storage, and working remote STT/LLM integration.

### Concrete Deliverables
- `Sources/VoxLiteDomain/RemoteProviderTypes.swift` — Provider enum, capability flags, model presets
- `Sources/VoxLiteDomain/PrototypeModels.swift` — Redesigned `ModelSetting` struct
- `Sources/VoxLiteSystem/KeychainStorage.swift` — Keychain wrapper for API keys
- `Sources/VoxLiteCore/OpenAIClient.swift` — OpenAI-compatible HTTP client (Chat Completions + Whisper)
- `Sources/VoxLiteCore/RemoteSpeechTranscriber.swift` — Remote `SpeechTranscribing` implementation
- `Sources/VoxLiteCore/RemoteLLMGenerator.swift` — Remote `PromptGenerating` implementation
- `Sources/VoxLiteCore/ConnectionValidator.swift` — Pre-save connection validation logic
- `Sources/VoxLiteApp/ModelSettingsView.swift` — Redesigned settings UI with dropdowns
- `Sources/VoxLiteFeature/AppViewModel.swift` — Updated for remote model wiring

### Definition of Done
- [ ] Settings dropdown shows: 本地模型, Deepseek, Groq, SiliconFlow, 自定义 for both STT and LLM
- [ ] Selecting a provider auto-fills endpoint URL, shows API key field
- [ ] API key stored in Keychain, not in plain text settings file
- [ ] Connection validation blocks saving invalid configs (tests `/v1/models`)
- [ ] Remote STT transcription works via Whisper API
- [ ] Remote LLM text generation works via Chat Completions API
- [ ] Local model remains default; remote is opt-in
- [ ] `swift build --disable-sandbox` succeeds
- [ ] `swift run --disable-sandbox VoxLiteSelfCheck` outputs SELF_CHECK_OK

### Must Have
- Provider presets with auto-filled endpoints for Deepseek, Groq, SiliconFlow
- Custom (OpenAI-compatible) option with free-text endpoint
- Dropdown menus (SwiftUI `Picker`) for provider and model selection
- Keychain-secured API key storage (Security framework)
- Connection validation before saving (test request to `/v1/models`)
- Remote `SpeechTranscribing` conformance (Whisper API)
- Remote `PromptGenerating` conformance (Chat Completions API)
- Capability flags per provider (not all support STT)
- Error codes in `CoreResult`: InvalidAPIKey (401), RateLimited (429), NetworkError, RemoteAPIError
- HTTPS enforcement (reject HTTP endpoints in validation)
- Request cancellation support via `URLSessionTask.cancel()`
- latencyMs measurement in all remote operations

### Must NOT Have (Guardrails)
- No streaming support (request/response only)
- No response caching (every request fresh)
- No automatic retry logic (fail fast, user retries manually)
- No usage analytics / API call counting
- No model fine-tuning UI
- No multi-key rotation per provider (single key)
- No request queue persistence (in-memory only)
- No custom timeout UI (hardcoded 30s)
- No proxy configuration
- No third-party libraries
- No silent fallback to local on remote failure (explicit error required)
- No logging of full request/response bodies (metadata only)
- No iCloud sync of API keys (device-only Keychain)
- No Anthropic native API support (`/v1/messages`) — OpenAI-compatible only

---

## Verification Strategy

> **ZERO HUMAN INTERVENTION** — ALL verification is agent-executed. No exceptions.

### Test Decision
- **Infrastructure exists**: YES (VoxLiteSelfCheck exists as integration test)
- **Automated tests**: None (user chose QA scenarios only)
- **Framework**: VoxLiteSelfCheck for build/integration verification
- **QA Policy**: Every task MUST include agent-executed QA scenarios

### QA Policy
Every task MUST include agent-executed QA scenarios.
Evidence saved to `.sisyphus/evidence/task-{N}-{scenario-slug}.{ext}`.

- **Frontend/UI**: Use Playwright (playwright skill) — Navigate, interact, assert DOM, screenshot
- **API/Backend**: Use Bash (curl) — Send requests, assert status + response fields
- **Library/Module**: Use Bash (swift REPL / build / run) — Import, call functions, compare output
- **Keychain**: Use Bash (`security` CLI) — Verify stored/retrieved/deleted keys

---

## Execution Strategy

### Parallel Execution Waves

```
Wave 1 (Start Immediately — types + infrastructure, 5 parallel tasks):
├── Task 1: Provider registry types (RemoteProviderTypes.swift) [quick]
├── Task 2: Redesign ModelSetting struct (PrototypeModels.swift) [quick]
├── Task 3: Keychain storage wrapper (KeychainStorage.swift) [quick]
├── Task 4: OpenAI-compatible HTTP client (OpenAIClient.swift) [deep]
├── Task 5: Error code extensions (Models.swift) [quick]

Wave 2 (After Wave 1 — protocol implementations + validation, 4 parallel tasks):
├── Task 6: Remote Whisper transcriber (depends: 1, 4) [unspecified-high]
├── Task 7: Remote LLM generator (depends: 1, 4) [unspecified-high]
├── Task 8: Connection validator (depends: 1, 4) [unspecified-high]
├── Task 9: Pipeline + Bootstrap wiring (depends: 1, 2, 3, 6, 7) [deep]

Wave 3 (After Wave 2 — UI + integration, 2 tasks):
├── Task 10: Settings UI redesign with dropdowns (depends: 1, 2, 3, 8) [visual-engineering]
├── Task 11: End-to-end integration + AppViewModel update (depends: 9, 10) [deep]

Wave FINAL (After ALL tasks — 4 parallel reviews, then user okay):
├── Task F1: Plan compliance audit (oracle)
├── Task F2: Code quality review (unspecified-high)
├── Task F3: Real manual QA (unspecified-high)
└── Task F4: Scope fidelity check (deep)
-> Present results -> Get explicit user okay
```

**Critical Path**: Task 1 → Task 4 → Task 6/7 → Task 9 → Task 10 → Task 11 → F1-F4 → user okay
**Parallel Speedup**: ~60% faster than sequential
**Max Concurrent**: 5 (Wave 1)

### Dependency Matrix

| Task | Depends On | Blocks | Wave |
|------|-----------|--------|------|
| 1 | — | 2, 6, 7, 8, 9, 10 | 1 |
| 2 | — | 9, 10, 11 | 1 |
| 3 | — | 9, 10 | 1 |
| 4 | — | 6, 7, 8 | 1 |
| 5 | — | 6, 7 | 1 |
| 6 | 1, 4, 5 | 9 | 2 |
| 7 | 1, 4, 5 | 9 | 2 |
| 8 | 1, 4 | 10 | 2 |
| 9 | 1, 2, 3, 6, 7 | 11 | 2 |
| 10 | 1, 2, 3, 8 | 11 | 3 |
| 11 | 9, 10 | F1-F4 | 3 |

### Agent Dispatch Summary

- **Wave 1**: **5 tasks** — T1 → `quick`, T2 → `quick`, T3 → `quick`, T4 → `deep`, T5 → `quick`
- **Wave 2**: **4 tasks** — T6 → `unspecified-high`, T7 → `unspecified-high`, T8 → `unspecified-high`, T9 → `deep`
- **Wave 3**: **2 tasks** — T10 → `visual-engineering`, T11 → `deep`
- **FINAL**: **4 tasks** — F1 → `oracle`, F2 → `unspecified-high`, F3 → `unspecified-high`, F4 → `deep`

---

## TODOs

- [x] 1. Provider Registry Types — RemoteProviderTypes.swift

  **What to do**:
  - Create `Sources/VoxLiteDomain/RemoteProviderTypes.swift`
  - Define `RemoteProvider` enum: `.deepseek`, `.groq`, `.siliconFlow`, `.custom` — each with `Codable`, `CaseIterable`, `Sendable`
  - Add computed properties: `displayName` (中文: "Deepseek 深度求索", "Groq", "硅基流动 SiliconFlow", "自定义 OpenAI 兼容"), `defaultEndpoint: URL`, `apiKeyHelpURL: URL?`
  - Add capability flags: `supportsSTT: Bool`, `supportsLLM: Bool` — Groq supports both, Deepseek LLM-only (no Whisper), SiliconFlow both, Custom both (assumed)
  - Add hardcoded model presets per provider:
    - Deepseek LLM: `["deepseek-chat", "deepseek-reasoner"]`
    - Groq STT: `["whisper-large-v3", "whisper-large-v3-turbo"]`, LLM: `["llama-3.3-70b-versatile", "llama-3.1-8b-instant", "mixtral-8x7b-32768"]`
    - SiliconFlow STT: `["FunAudioLLM/SenseVoiceSmall"]`, LLM: `["deepseek-ai/DeepSeek-V3", "Qwen/Qwen2.5-72B-Instruct"]`
    - Custom: empty arrays (user enters model name manually)
  - Add `localOption` static property returning a display-only "本地模型" representation

  **Must NOT do**:
  - Do NOT fetch models from API (hardcoded only)
  - Do NOT add streaming-related types
  - Do NOT add Anthropic provider

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Single file creation with well-defined enum structure, no complex logic
  - **Skills**: []
  - **Skills Evaluated but Omitted**:
    - `playwright`: No UI work in this task

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 2, 3, 4, 5)
  - **Blocks**: Tasks 2, 6, 7, 8, 9, 10
  - **Blocked By**: None (can start immediately)

  **References**:

  **Pattern References**:
  - `Sources/VoxLiteDomain/Models.swift:1-50` — Follow existing domain type patterns (Codable, Sendable, public access)
  - `Sources/VoxLiteDomain/PrototypeModels.swift:125-167` — Current `ModelSetting` struct for context on what's being replaced

  **API/Type References**:
  - `Sources/VoxLiteDomain/Protocols.swift:1-30` — Protocol patterns used across the domain layer

  **External References**:
  - Deepseek API docs: `https://api-docs.deepseek.com/` — Endpoint: `https://api.deepseek.com/v1`, models: deepseek-chat, deepseek-reasoner
  - Groq API docs: `https://console.groq.com/docs/api-reference` — Endpoint: `https://api.groq.com/openai/v1`, has Whisper + Chat
  - SiliconFlow API docs: `https://docs.siliconflow.cn/` — Endpoint: `https://api.siliconflow.cn/v1`, has STT + Chat

  **WHY Each Reference Matters**:
  - `Models.swift` shows the domain type conventions (public struct, Codable+Sendable, documentation comments)
  - `PrototypeModels.swift` shows the current ModelSetting that downstream tasks will redesign to reference this new enum
  - Provider API docs confirm exact endpoint URLs and model identifiers to hardcode

  **Acceptance Criteria**:

  **QA Scenarios (MANDATORY):**

  ```
  Scenario: Provider enum has all required cases and compiles
    Tool: Bash (swift build)
    Preconditions: File created at Sources/VoxLiteDomain/RemoteProviderTypes.swift
    Steps:
      1. Run: swift build --disable-sandbox 2>&1
      2. Verify exit code 0 and output contains "Build complete!"
      3. Grep new file for "case deepseek", "case groq", "case siliconFlow", "case custom"
    Expected Result: Build succeeds, all 4 enum cases present
    Failure Indicators: Compilation error, missing enum case
    Evidence: .sisyphus/evidence/task-1-build-success.txt

  Scenario: Default endpoints return correct URLs
    Tool: Bash (swift REPL or test script)
    Preconditions: Build succeeds
    Steps:
      1. Write a small Swift snippet that prints RemoteProvider.deepseek.defaultEndpoint
      2. Verify output is "https://api.deepseek.com/v1"
      3. Verify RemoteProvider.groq.defaultEndpoint is "https://api.groq.com/openai/v1"
      4. Verify RemoteProvider.siliconFlow.defaultEndpoint is "https://api.siliconflow.cn/v1"
    Expected Result: All 3 preset endpoints match expected URLs exactly
    Failure Indicators: Wrong URL, missing /v1 suffix, HTTP instead of HTTPS
    Evidence: .sisyphus/evidence/task-1-endpoints.txt

  Scenario: Capability flags correctly reflect provider support
    Tool: Bash (grep file contents)
    Preconditions: File created
    Steps:
      1. Verify RemoteProvider.deepseek.supportsSTT returns false
      2. Verify RemoteProvider.groq.supportsSTT returns true
      3. Verify all providers return true for supportsLLM
    Expected Result: Deepseek STT=false, all others STT=true, all LLM=true
    Failure Indicators: Deepseek incorrectly marked as supporting STT
    Evidence: .sisyphus/evidence/task-1-capabilities.txt
  ```

  **Commit**: YES
  - Message: `feat(domain): add remote provider registry types and capability flags`
  - Files: `Sources/VoxLiteDomain/RemoteProviderTypes.swift`
  - Pre-commit: `swift build --disable-sandbox`

- [x] 2. Redesign ModelSetting Struct — PrototypeModels.swift

  **What to do**:
  - Modify `Sources/VoxLiteDomain/PrototypeModels.swift`
  - Replace current `ModelSetting` struct with structured version:
    ```swift
    public struct ModelSetting: Codable, Equatable, Sendable {
        public var useRemote: Bool = false
        public var provider: RemoteProvider = .deepseek
        public var customEndpoint: String = ""
        public var selectedSTTModel: String = ""
        public var selectedLLMModel: String = ""
        // API key NOT stored here — stored in Keychain
    }
    ```
  - Add computed property `effectiveEndpoint: URL?` — returns `customEndpoint` URL if provider is `.custom`, otherwise `provider.defaultEndpoint`
  - Update `AppSettings` default values to use new `ModelSetting` shape
  - Ensure backward compatibility: if old JSON is loaded, gracefully default to new structure (custom `init(from decoder:)` with try/catch for missing keys)

  **Must NOT do**:
  - Do NOT store API keys in this struct (Keychain only)
  - Do NOT add networking logic here
  - Do NOT remove non-model-related fields from `AppSettings`

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Single file modification, well-defined data model change
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 1, 3, 4, 5)
  - **Blocks**: Tasks 9, 10, 11
  - **Blocked By**: None (can start immediately, but Task 1 provides RemoteProvider type — if building fails, can use String placeholder and fix after)

  **References**:

  **Pattern References**:
  - `Sources/VoxLiteDomain/PrototypeModels.swift:125-167` — Current `ModelSetting` struct being replaced
  - `Sources/VoxLiteDomain/PrototypeModels.swift:1-124` — Other model types in same file for conventions

  **API/Type References**:
  - `Sources/VoxLiteDomain/RemoteProviderTypes.swift` (from Task 1) — `RemoteProvider` enum used in new `ModelSetting`

  **WHY Each Reference Matters**:
  - Current `ModelSetting` shows existing field names and usages that must be migrated
  - `RemoteProvider` enum is the key dependency — new struct references it

  **Acceptance Criteria**:

  **QA Scenarios (MANDATORY):**

  ```
  Scenario: New ModelSetting compiles with all fields
    Tool: Bash (swift build)
    Preconditions: Task 1 completed (RemoteProvider exists)
    Steps:
      1. Run: swift build --disable-sandbox 2>&1
      2. Verify build succeeds
      3. Grep PrototypeModels.swift for "useRemote", "provider", "customEndpoint", "selectedSTTModel", "selectedLLMModel"
    Expected Result: Build succeeds, all 5 fields present
    Failure Indicators: Compilation error due to type mismatch or missing RemoteProvider
    Evidence: .sisyphus/evidence/task-2-build.txt

  Scenario: Backward-compatible JSON decoding
    Tool: Bash (swift script)
    Preconditions: Build succeeds
    Steps:
      1. Create JSON string with OLD format: {"localEnabled": true, "remoteProvider": "openai", "remoteEndpoint": "https://api.openai.com/v1"}
      2. Attempt to decode as new ModelSetting
      3. Verify no crash — defaults applied for missing fields
    Expected Result: Decoding succeeds with defaults (useRemote=false, provider=.deepseek)
    Failure Indicators: DecodingError thrown, crash
    Evidence: .sisyphus/evidence/task-2-compat.txt
  ```

  **Commit**: YES
  - Message: `refactor(domain): redesign ModelSetting for structured provider selection`
  - Files: `Sources/VoxLiteDomain/PrototypeModels.swift`
  - Pre-commit: `swift build --disable-sandbox`

- [x] 4. OpenAI-Compatible HTTP Client — OpenAIClient.swift

  **What to do**:
  - Create `Sources/VoxLiteCore/OpenAIClient.swift`
  - Define `OpenAIClient` class with:
    - `init(baseURL: URL, apiKey: String)` — configurable endpoint + auth
    - `func chatCompletion(model: String, messages: [ChatMessage]) async throws -> ChatCompletionResponse` — POST to `/chat/completions`
    - `func transcribeAudio(model: String, audioFileURL: URL) async throws -> TranscriptionResponse` — POST multipart/form-data to `/audio/transcriptions`
    - `func listModels() async throws -> ModelsListResponse` — GET `/models` (for connection validation)
  - Define request/response DTOs (all `Codable`):
    - `ChatMessage { role: String, content: String }`
    - `ChatCompletionRequest { model: String, messages: [ChatMessage], temperature: Double? }`
    - `ChatCompletionResponse { choices: [Choice] }` where `Choice { message: ChatMessage }`
    - `TranscriptionResponse { text: String }`
    - `ModelsListResponse { data: [ModelInfo] }` where `ModelInfo { id: String }`
  - Use `URLSession.shared` for all requests
  - Set `Authorization: Bearer {apiKey}` header
  - Set `Content-Type: application/json` for chat, `multipart/form-data` for audio
  - Hardcoded timeout: 30 seconds via `URLRequest.timeoutInterval`
  - Map HTTP errors: 401 → `OpenAIClientError.invalidAPIKey`, 429 → `.rateLimited`, 4xx/5xx → `.apiError(statusCode, body)`
  - Support request cancellation via returned `URLSessionTask` or Swift structured concurrency (`Task.checkCancellation()`)
  - Measure latency: `CFAbsoluteTimeGetCurrent()` before/after request, return as `latencyMs: Int`
  - Log metadata only: endpoint, status code, latency (NO full request/response bodies)

  **Must NOT do**:
  - Do NOT add streaming support (no SSE/chunked responses)
  - Do NOT add retry logic
  - Do NOT add response caching
  - Do NOT import any third-party HTTP libraries
  - Do NOT log full request/response bodies

  **Recommended Agent Profile**:
  - **Category**: `deep`
    - Reason: Complex networking logic — multipart form-data upload, error mapping, structured concurrency, latency measurement
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 1, 2, 3, 5)
  - **Blocks**: Tasks 6, 7, 8
  - **Blocked By**: None (can start immediately — uses URL/String for baseURL, not RemoteProvider)

  **References**:

  **Pattern References**:
  - `Sources/VoxLiteCore/SpeechTranscriber.swift:72-145` — Existing async transcription pattern (error handling, result wrapping)
  - `Sources/VoxLiteDomain/Models.swift:1-50` — `CoreResult` pattern with success/errorCode/latencyMs

  **External References**:
  - OpenAI Chat Completions API: `https://platform.openai.com/docs/api-reference/chat/create` — Request/response JSON schema
  - OpenAI Whisper API: `https://platform.openai.com/docs/api-reference/audio/createTranscription` — Multipart form-data format
  - OpenAI List Models API: `https://platform.openai.com/docs/api-reference/models/list` — GET /v1/models response format
  - `swift-llm-chat-openai` (kevinhermawan): `https://github.com/kevinhermawan/swift-llm-chat-openai` — Reference for lightweight OpenAI-compatible client implementation patterns (study, don't import)

  **WHY Each Reference Matters**:
  - `SpeechTranscriber.swift` shows how the project handles async operations with error recovery
  - `Models.swift` shows the result type pattern that downstream tasks will use to wrap HTTP responses
  - OpenAI API docs define the exact JSON schema this client must implement
  - swift-llm-chat-openai shows a minimal production-quality implementation to reference for architecture decisions

  **Acceptance Criteria**:

  **QA Scenarios (MANDATORY):**

  ```
  Scenario: Chat completion request to Groq API
    Tool: Bash (swift script or curl comparison)
    Preconditions: Valid Groq API key available
    Steps:
      1. Create OpenAIClient(baseURL: URL(string: "https://api.groq.com/openai/v1")!, apiKey: GROQ_KEY)
      2. Call chatCompletion(model: "llama-3.1-8b-instant", messages: [ChatMessage(role: "user", content: "Say hello")])
      3. Verify response.choices is non-empty
      4. Verify response.choices[0].message.content is non-empty string
      5. Verify latencyMs > 0
    Expected Result: Non-empty response text, latency measured
    Failure Indicators: Network error, empty choices array, latency = 0
    Evidence: .sisyphus/evidence/task-4-chat-completion.txt

  Scenario: Audio transcription via Whisper API on Groq
    Tool: Bash (swift script)
    Preconditions: Valid Groq API key, test audio file (create 1s silent WAV or use existing)
    Steps:
      1. Create OpenAIClient with Groq endpoint
      2. Call transcribeAudio(model: "whisper-large-v3-turbo", audioFileURL: testAudioURL)
      3. Verify response.text is a String (may be empty for silent audio)
      4. Verify no error thrown
    Expected Result: TranscriptionResponse returned without error
    Failure Indicators: Multipart encoding error, 400 Bad Request, timeout
    Evidence: .sisyphus/evidence/task-4-whisper.txt

  Scenario: Invalid API key returns 401 error
    Tool: Bash (swift script)
    Preconditions: None
    Steps:
      1. Create OpenAIClient(baseURL: groqURL, apiKey: "invalid-key-12345")
      2. Call listModels()
      3. Verify throws OpenAIClientError.invalidAPIKey
    Expected Result: Error thrown with invalidAPIKey case
    Failure Indicators: Different error type, no error thrown, crash
    Evidence: .sisyphus/evidence/task-4-auth-error.txt

  Scenario: List models for connection validation
    Tool: Bash (swift script)
    Preconditions: Valid API key
    Steps:
      1. Create OpenAIClient with valid Groq key
      2. Call listModels()
      3. Verify response.data is non-empty array
      4. Verify at least one model.id is non-empty string
    Expected Result: Models list returned with valid model IDs
    Failure Indicators: Empty list, decoding error
    Evidence: .sisyphus/evidence/task-4-list-models.txt
  ```

  **Commit**: YES
  - Message: `feat(core): add OpenAI-compatible HTTP client for chat and whisper APIs`
  - Files: `Sources/VoxLiteCore/OpenAIClient.swift`
  - Pre-commit: `swift build --disable-sandbox`

- [x] 5. Remote API Error Codes — Models.swift

  **What to do**:
  - Modify `Sources/VoxLiteDomain/Models.swift`
  - Add new error cases to `VoxErrorCode` (or equivalent error enum):
    - `.remoteAPIError` — Generic remote API failure
    - `.invalidAPIKey` — HTTP 401 from provider
    - `.rateLimited` — HTTP 429 from provider
    - `.networkError` — No connection, timeout, DNS failure
    - `.invalidResponse` — HTTP 200 but malformed JSON body
    - `.remoteProviderUnavailable` — Provider endpoint unreachable
    - `.httpsRequired` — User attempted to use HTTP endpoint (must be HTTPS)
  - Ensure new cases follow existing pattern (Codable, Equatable, Sendable)
  - Update any switch statements that use `VoxErrorCode` to handle new cases (use `lsp_find_references` first)

  **Must NOT do**:
  - Do NOT change existing error codes or their raw values
  - Do NOT add error codes for features not being built (streaming, caching, etc.)

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Small addition to existing enum, straightforward
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 1, 2, 3, 4)
  - **Blocks**: Tasks 6, 7
  - **Blocked By**: None

  **References**:

  **Pattern References**:
  - `Sources/VoxLiteDomain/Models.swift` — Existing `VoxErrorCode` enum definition and conventions

  **WHY Each Reference Matters**:
  - Must follow exact naming and coding conventions of existing error codes

  **Acceptance Criteria**:

  **QA Scenarios (MANDATORY):**

  ```
  Scenario: New error codes compile and are exhaustive
    Tool: Bash (swift build)
    Preconditions: None
    Steps:
      1. Run: swift build --disable-sandbox
      2. Verify no "switch must be exhaustive" compiler errors
      3. Grep Models.swift for all 7 new error cases
    Expected Result: Build succeeds, all new cases present
    Failure Indicators: Compilation error from non-exhaustive switch
    Evidence: .sisyphus/evidence/task-5-error-codes.txt
  ```

  **Commit**: YES
  - Message: `feat(domain): add remote API error codes to VoxErrorCode`
  - Files: `Sources/VoxLiteDomain/Models.swift`
  - Pre-commit: `swift build --disable-sandbox`

- [x] 3. Keychain Storage Wrapper — KeychainStorage.swift

  **What to do**:
  - Create `Sources/VoxLiteSystem/KeychainStorage.swift`
  - Define `KeychainStoring` protocol in `VoxLiteDomain/Protocols.swift`:
    ```swift
    public protocol KeychainStoring: Sendable {
        func store(_ value: String, forKey key: String) throws
        func retrieve(forKey key: String) throws -> String?
        func delete(forKey key: String) throws
    }
    ```
  - Implement `KeychainStorage: KeychainStoring` in VoxLiteSystem using Security framework:
    - Service identifier: `"ai.holoo.voxlite.apikeys"`
    - Access level: `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
    - Operations: store (delete old + add new), retrieve (query + return), delete
    - Error handling: Map `OSStatus` to descriptive errors
  - Add convenience methods: `storeAPIKey(for provider: RemoteProvider, key: String)`, `retrieveAPIKey(for provider: RemoteProvider) -> String?`, `deleteAPIKey(for provider: RemoteProvider)`

  **Must NOT do**:
  - Do NOT use UserDefaults for API keys
  - Do NOT log API key values
  - Do NOT enable iCloud Keychain sync
  - Do NOT import third-party Keychain libraries

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Well-understood pattern, Security framework API is straightforward
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 1, 2, 4, 5)
  - **Blocks**: Tasks 9, 10
  - **Blocked By**: None

  **References**:

  **Pattern References**:
  - `Sources/VoxLiteSystem/LocalStores.swift:197-229` — Existing persistence pattern (FileAppSettingsStore) — follow same code style
  - `Sources/VoxLiteDomain/Protocols.swift:1-60` — Where to add `KeychainStoring` protocol

  **External References**:
  - Apple Security framework: `https://developer.apple.com/documentation/security/keychain_services` — SecItemAdd, SecItemCopyMatching, SecItemDelete APIs
  - Ayna AIService Keychain pattern (reference only): `https://github.com/sozercan/ayna/blob/main/Sources/Ayna/Services/AIService.swift` — Production Keychain usage

  **WHY Each Reference Matters**:
  - `LocalStores.swift` shows the project's persistence coding style (error handling, access patterns, protocol conformance)
  - `Protocols.swift` is where the new `KeychainStoring` protocol must be added (cross-layer communication via domain protocols)
  - Apple docs provide the exact Security framework API signatures needed

  **Acceptance Criteria**:

  **QA Scenarios (MANDATORY):**

  ```
  Scenario: Store and retrieve API key via Keychain
    Tool: Bash (security CLI + swift build)
    Preconditions: Build succeeds, app is sandboxed or has Keychain access
    Steps:
      1. Run: swift build --disable-sandbox
      2. Write a test script that calls KeychainStorage().store("test-key-abc123", forKey: "ai.holoo.voxlite.apikeys.deepseek")
      3. Run: security find-generic-password -s "ai.holoo.voxlite.apikeys" -a "deepseek" -w 2>&1
      4. Verify output is "test-key-abc123"
    Expected Result: Key stored and retrievable via both Swift API and security CLI
    Failure Indicators: errSecAuthFailed, key not found, wrong value
    Evidence: .sisyphus/evidence/task-3-keychain-store.txt

  Scenario: Delete API key from Keychain
    Tool: Bash (security CLI)
    Preconditions: Key stored from previous scenario
    Steps:
      1. Call KeychainStorage().delete(forKey: "deepseek")
      2. Run: security find-generic-password -s "ai.holoo.voxlite.apikeys" -a "deepseek" -w 2>&1
      3. Verify error output (key not found)
    Expected Result: Key deleted, subsequent retrieval returns nil/error
    Failure Indicators: Key still exists after deletion
    Evidence: .sisyphus/evidence/task-3-keychain-delete.txt

  Scenario: Retrieve nonexistent key returns nil (not crash)
    Tool: Bash (swift script)
    Preconditions: No key stored for "nonexistent-provider"
    Steps:
      1. Call KeychainStorage().retrieve(forKey: "nonexistent-provider")
      2. Verify returns nil without throwing
    Expected Result: nil returned, no error thrown
    Failure Indicators: Crash, thrown error, non-nil return
    Evidence: .sisyphus/evidence/task-3-keychain-missing.txt
  ```

  **Commit**: YES
  - Message: `feat(system): add Keychain storage wrapper for API keys`
  - Files: `Sources/VoxLiteSystem/KeychainStorage.swift`, `Sources/VoxLiteDomain/Protocols.swift`
  - Pre-commit: `swift build --disable-sandbox`

- [ ] 6. Remote Whisper Speech Transcriber — RemoteSpeechTranscriber.swift

  **What to do**:
  - Create `Sources/VoxLiteCore/RemoteSpeechTranscriber.swift`
  - Implement `RemoteSpeechTranscriber` conforming to `SpeechTranscribing` protocol (defined in `VoxLiteDomain/Protocols.swift:14-16`)
  - Class must be `@MainActor public final class RemoteSpeechTranscriber: SpeechTranscribing`
  - Constructor: `init(client: OpenAIClient, model: String, logger: LoggerServing)`
    - `client` is the `OpenAIClient` from Task 4 (already initialized with baseURL + apiKey)
    - `model` is the Whisper model name (e.g. `"whisper-large-v3-turbo"`)
    - `logger` for metadata-only logging
  - Implement `func transcribe(audioFileURL: URL, elapsedMs: Int?) async throws -> SpeechTranscription`:
    1. Verify file exists at `audioFileURL` — if not, throw `SpeechTranscriptionError.noResult`
    2. Measure latency: record `CFAbsoluteTimeGetCurrent()` before request
    3. Call `client.transcribeAudio(model: model, audioFileURL: audioFileURL)` — this sends multipart/form-data to `/v1/audio/transcriptions`
    4. On success: return `SpeechTranscription(text: response.text, latencyMs: elapsed, usedOnDevice: false)`
    5. On error: map `OpenAIClientError` → `SpeechTranscriptionError` or `VoxErrorCode`:
       - `.invalidAPIKey` → throw `VoxErrorCode.invalidAPIKey`
       - `.rateLimited` → throw `VoxErrorCode.rateLimited`
       - `.apiError(statusCode, _)` → throw `VoxErrorCode.remoteAPIError`
       - `.networkError` → throw `VoxErrorCode.remoteNetworkError`
    6. Log metadata: endpoint used, status code, latencyMs, audio file size — NOT the transcribed text
  - Return type must match existing `SpeechTranscription(text:, latencyMs:, usedOnDevice:)` exactly

  **Must NOT do**:
  - Do NOT add retry logic (pipeline handles retries)
  - Do NOT add fallback to on-device if remote fails (fail fast)
  - Do NOT add streaming/progressive transcription
  - Do NOT log the transcribed text content (privacy rule)
  - Do NOT import third-party libraries

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Moderate complexity — needs careful protocol conformance, error mapping, and latency measurement. Not as complex as the HTTP client (Task 4) but more than a simple wrapper.
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 7, 8, 9)
  - **Blocks**: Task 11
  - **Blocked By**: Task 4 (OpenAIClient), Task 5 (error codes)

  **References**:

  **Pattern References**:
  - `Sources/VoxLiteCore/SpeechTranscriber.swift:72-139` — `OnDeviceSpeechTranscriber` class — follow exact same coding style: init pattern (line 78-88), `transcribe()` method structure (line 90-139), error handling approach, latency measurement using `Date()` and `elapsed()` helper, log format conventions (`logger.info("transcriber ...")`)
  - `Sources/VoxLiteDomain/Protocols.swift:13-16` — `SpeechTranscribing` protocol signature that must be conformed to: `@MainActor`, `func transcribe(audioFileURL: URL, elapsedMs: Int?) async throws -> SpeechTranscription`
  - `Sources/VoxLiteDomain/Models.swift:127-137` — `SpeechTranscription` struct with exact init signature: `(text: String, latencyMs: Int, usedOnDevice: Bool)` — remote must pass `usedOnDevice: false`
  - `Sources/VoxLiteDomain/Models.swift:139-144` — `SpeechTranscriptionError` enum — reuse existing cases where applicable

  **API/Type References**:
  - `Sources/VoxLiteCore/OpenAIClient.swift` (from Task 4) — `transcribeAudio(model:audioFileURL:)` method and `TranscriptionResponse { text: String }` type
  - `Sources/VoxLiteDomain/Models.swift:13-30` — `VoxErrorCode` enum with new remote error cases from Task 5

  **External References**:
  - OpenAI Whisper API: `https://platform.openai.com/docs/api-reference/audio/createTranscription` — Response format reference
  - Groq Whisper: `https://console.groq.com/docs/speech-text` — Provider-specific compatibility notes

  **WHY Each Reference Matters**:
  - `OnDeviceSpeechTranscriber` is the template — copy its structure, naming, logging, and error handling exactly. The remote version is simpler (no locale check, no authorization check, no fallback) but must match the project's code style.
  - `SpeechTranscription` return type must be constructed identically — `usedOnDevice: false` is the only difference from on-device path.
  - `OpenAIClient` from Task 4 handles the actual HTTP call — this class is a thin adapter between the protocol and the client.

  **Acceptance Criteria**:

  **QA Scenarios (MANDATORY):**

  ```
  Scenario: Remote transcription via Groq Whisper API
    Tool: Bash (swift script)
    Preconditions: Valid Groq API key, test audio file (create 1s WAV with `afconvert` or use existing test asset)
    Steps:
      1. Create OpenAIClient(baseURL: URL(string: "https://api.groq.com/openai/v1")!, apiKey: GROQ_KEY)
      2. Create RemoteSpeechTranscriber(client: client, model: "whisper-large-v3-turbo", logger: ConsoleLogger())
      3. Call transcriber.transcribe(audioFileURL: testAudioURL, elapsedMs: nil)
      4. Verify result.text is a String (may be empty for silent audio)
      5. Verify result.usedOnDevice == false
      6. Verify result.latencyMs > 0
    Expected Result: SpeechTranscription returned with usedOnDevice=false and positive latency
    Failure Indicators: Error thrown, usedOnDevice=true, latencyMs=0
    Evidence: .sisyphus/evidence/task-6-remote-stt.txt

  Scenario: Missing audio file throws noResult error
    Tool: Bash (swift script)
    Preconditions: None
    Steps:
      1. Create RemoteSpeechTranscriber with valid client
      2. Call transcribe(audioFileURL: URL(fileURLWithPath: "/tmp/nonexistent-audio.wav"), elapsedMs: nil)
      3. Verify throws SpeechTranscriptionError.noResult
    Expected Result: Error thrown before any network call
    Failure Indicators: Network request sent, different error thrown, crash
    Evidence: .sisyphus/evidence/task-6-missing-file.txt

  Scenario: Invalid API key propagates correct error
    Tool: Bash (swift script)
    Preconditions: Test audio file exists
    Steps:
      1. Create OpenAIClient with apiKey: "invalid-key-xyz"
      2. Create RemoteSpeechTranscriber with that client
      3. Call transcribe(audioFileURL: validAudioURL, elapsedMs: nil)
      4. Verify throws VoxErrorCode.invalidAPIKey
    Expected Result: VoxErrorCode.invalidAPIKey thrown
    Failure Indicators: Generic error, different error code, crash
    Evidence: .sisyphus/evidence/task-6-auth-error.txt
  ```

  **Commit**: YES
  - Message: `feat(core): add remote Whisper speech transcriber`
  - Files: `Sources/VoxLiteCore/RemoteSpeechTranscriber.swift`
  - Pre-commit: `swift build --disable-sandbox`

- [ ] 7. Remote LLM Text Generator — RemoteLLMGenerator.swift

  **What to do**:
  - Create `Sources/VoxLiteCore/RemoteLLMGenerator.swift`
  - Implement `RemoteLLMGenerator` conforming to `PromptGenerating` protocol (defined in `VoxLiteCore/TextCleaner.swift:8-12`)
  - Class must be `@MainActor public final class RemoteLLMGenerator: PromptGenerating`
  - Constructor: `init(client: OpenAIClient, model: String, logger: LoggerServing)`
    - `client` is the `OpenAIClient` from Task 4
    - `model` is the LLM model name (e.g. `"deepseek-chat"`, `"llama-3.1-8b-instant"`)
    - `logger` for metadata-only logging
  - Implement `func generateText(from prompt: String) async throws -> String`:
    1. Create messages array: `[ChatMessage(role: "user", content: prompt)]`
    2. Call `client.chatCompletion(model: model, messages: messages)`
    3. Extract text: `response.choices.first?.message.content`
    4. Trim whitespace, verify non-empty — if empty, throw `PromptGenerationError.emptyResult`
    5. Return the cleaned text string
    6. On error: map `OpenAIClientError`:
       - `.invalidAPIKey` → throw `PromptGenerationError.unavailable` (or map to VoxErrorCode — align with Task 6 approach)
       - `.rateLimited` → throw `PromptGenerationError.unavailable`
       - Other errors → throw `PromptGenerationError.unavailable`
    7. Log metadata: model, status code, latency, response token count estimate — NOT the prompt or response text
  - Implement `func availabilityState() -> FoundationModelAvailabilityState`:
    - Return `.available` unconditionally — remote providers are always "available" if configured.
    - The actual availability check (API key present, connection valid) is handled at bootstrap time (Task 9) and UI validation time (Task 8).
  - NOTE: `FoundationModelAvailabilityState` is defined in `TextCleaner.swift:19-25`, NOT in FoundationModels. It's a custom enum already usable without any `#if canImport`.

  **Must NOT do**:
  - Do NOT add streaming support (no SSE)
  - Do NOT add system message injection (just pass user prompt)
  - Do NOT add temperature/max_tokens configuration (use API defaults)
  - Do NOT add conversation history (stateless single-prompt)
  - Do NOT log prompt content or response content (privacy)
  - Do NOT import third-party libraries

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Moderate complexity — protocol conformance, chat message construction, error mapping
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 6, 8, 9)
  - **Blocks**: Task 11
  - **Blocked By**: Task 4 (OpenAIClient), Task 5 (error codes)

  **References**:

  **Pattern References**:
  - `Sources/VoxLiteCore/TextCleaner.swift:32-76` — `FoundationModelPromptGenerator` class — this is the LOCAL equivalent. Copy exact same structure: simple init (line 33), `generateText(from:)` method (line 35-52), `availabilityState()` method (line 54-76), error handling with `PromptGenerationError`
  - `Sources/VoxLiteCore/TextCleaner.swift:8-12` — `PromptGenerating` protocol: `@MainActor`, two methods: `generateText(from: String) async throws -> String` and `availabilityState() -> FoundationModelAvailabilityState`
  - `Sources/VoxLiteCore/TextCleaner.swift:14-17` — `PromptGenerationError` enum: `.unavailable`, `.emptyResult` — reuse these for error cases
  - `Sources/VoxLiteCore/TextCleaner.swift:19-25` — `FoundationModelAvailabilityState` enum — return `.available` for remote

  **API/Type References**:
  - `Sources/VoxLiteCore/OpenAIClient.swift` (from Task 4) — `chatCompletion(model:messages:)` method, `ChatMessage { role, content }`, `ChatCompletionResponse { choices }` types
  - `Sources/VoxLiteCore/TextCleaner.swift:84-92` — `RuleBasedTextCleaner.init(generator:)` — this is where `RemoteLLMGenerator` gets injected, via the `generator: PromptGenerating` parameter

  **External References**:
  - OpenAI Chat Completions API: `https://platform.openai.com/docs/api-reference/chat/create` — Request/response format
  - Deepseek API: `https://api-docs.deepseek.com/` — Compatible with OpenAI format

  **WHY Each Reference Matters**:
  - `FoundationModelPromptGenerator` is the direct template — `RemoteLLMGenerator` replaces it for remote mode. Must match protocol signature exactly.
  - `PromptGenerationError` must be reused (not new error types) because `RuleBasedTextCleaner` catches these specific errors in its `generateText` call (TextCleaner.swift line 116).
  - The `availabilityState()` method is called by `RuleBasedTextCleaner.foundationModelAvailability()` (line 131-133) — returning `.available` ensures the UI shows remote LLM as ready.

  **Acceptance Criteria**:

  **QA Scenarios (MANDATORY):**

  ```
  Scenario: Remote LLM text generation via Groq API
    Tool: Bash (swift script)
    Preconditions: Valid Groq API key
    Steps:
      1. Create OpenAIClient(baseURL: URL(string: "https://api.groq.com/openai/v1")!, apiKey: GROQ_KEY)
      2. Create RemoteLLMGenerator(client: client, model: "llama-3.1-8b-instant", logger: ConsoleLogger())
      3. Call generator.generateText(from: "请将以下口语转为书面语：今天天气不错啊我觉得可以出去走走")
      4. Verify result is non-empty String
      5. Verify result.count > 0
    Expected Result: Non-empty cleaned text returned
    Failure Indicators: Empty result, error thrown, PromptGenerationError.emptyResult
    Evidence: .sisyphus/evidence/task-7-remote-llm.txt

  Scenario: availabilityState returns .available
    Tool: Bash (swift script)
    Preconditions: None
    Steps:
      1. Create RemoteLLMGenerator with any client and model
      2. Call generator.availabilityState()
      3. Verify returns FoundationModelAvailabilityState.available
    Expected Result: .available returned
    Failure Indicators: Any other state returned
    Evidence: .sisyphus/evidence/task-7-availability.txt

  Scenario: Empty LLM response throws emptyResult
    Tool: Bash (swift script)
    Preconditions: Valid API key, use a prompt designed to get minimal/empty response
    Steps:
      1. Create RemoteLLMGenerator
      2. Call generateText(from: "") — empty prompt
      3. If API returns empty choices or empty content, verify throws PromptGenerationError.emptyResult
    Expected Result: PromptGenerationError.emptyResult thrown for empty responses
    Failure Indicators: Empty string returned without error, different error type
    Evidence: .sisyphus/evidence/task-7-empty-response.txt
  ```

  **Commit**: YES
  - Message: `feat(core): add remote LLM text generator via chat completions`
  - Files: `Sources/VoxLiteCore/RemoteLLMGenerator.swift`
  - Pre-commit: `swift build --disable-sandbox`

 - [x] 8. Connection Validator — ConnectionValidator.swift

  **What to do**:
  - Create `Sources/VoxLiteCore/ConnectionValidator.swift`
  - Implement `ConnectionValidator` as a utility class (does NOT need a domain protocol — used only by Settings UI and bootstrap)
  - Class: `public final class ConnectionValidator: Sendable`
  - Constructor: `init()`
  - Implement `func validate(baseURL: URL, apiKey: String) async -> ConnectionValidationResult`:
    1. Create a temporary `OpenAIClient(baseURL: baseURL, apiKey: apiKey)`
    2. Call `client.listModels()` — this is a lightweight GET to `/v1/models`
    3. On success: return `.success(models: response.data.map(\.id))` — list of available model IDs
    4. On `OpenAIClientError.invalidAPIKey`: return `.failure(.invalidAPIKey)`
    5. On `OpenAIClientError.rateLimited`: return `.failure(.rateLimited)`
    6. On `OpenAIClientError.networkError(let error)`: return `.failure(.networkError(error.localizedDescription))`
    7. On `OpenAIClientError.apiError(let code, let body)`: return `.failure(.apiError(statusCode: code, message: body))`
    8. On any other error: return `.failure(.unknown(error.localizedDescription))`
    9. Hardcoded timeout: 10 seconds (shorter than normal 30s because this is just a connectivity check)
  - Define result type (in same file):
    ```swift
    public enum ConnectionValidationResult: Sendable {
        case success(models: [String])
        case failure(ConnectionValidationError)
    }
    public enum ConnectionValidationError: Error, Sendable {
        case invalidAPIKey
        case rateLimited
        case networkError(String)
        case apiError(statusCode: Int, message: String)
        case unknown(String)
    }
    ```
  - The Settings UI (Task 10) will call this before saving a remote config
  - Log validation attempt metadata: endpoint, success/failure, latency

  **Must NOT do**:
  - Do NOT add retry logic (single attempt only)
  - Do NOT cache validation results
  - Do NOT add full model discovery (just use model list to verify connectivity)
  - Do NOT add this to VoxLiteDomain protocols (it's a utility, not a cross-layer contract)

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Simple utility — creates a temporary OpenAIClient, makes one API call, maps result. Straightforward error handling.
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 6, 7, 9)
  - **Blocks**: Task 10
  - **Blocked By**: Task 4 (OpenAIClient)

  **References**:

  **Pattern References**:
  - `Sources/VoxLiteCore/OpenAIClient.swift` (from Task 4) — `listModels()` method, `OpenAIClientError` enum, `ModelsListResponse` type — this validator is a thin wrapper around `listModels()`
  - `Sources/VoxLiteCore/SpeechTranscriber.swift:90-96` — Error checking pattern (file exists check before proceeding)

  **API/Type References**:
  - `Sources/VoxLiteCore/OpenAIClient.swift` (from Task 4) — `OpenAIClient(baseURL:apiKey:)` constructor, `func listModels() async throws -> ModelsListResponse`
  - OpenAI List Models API: `https://platform.openai.com/docs/api-reference/models/list` — GET /v1/models response format

  **WHY Each Reference Matters**:
  - `OpenAIClient.listModels()` is the core dependency — understand its error types to map them correctly
  - The validator is intentionally simple: create client → call listModels → map result. No complex logic.

  **Acceptance Criteria**:

  **QA Scenarios (MANDATORY):**

  ```
  Scenario: Validate valid Groq connection
    Tool: Bash (swift script)
    Preconditions: Valid Groq API key
    Steps:
      1. Create ConnectionValidator()
      2. Call validate(baseURL: URL(string: "https://api.groq.com/openai/v1")!, apiKey: GROQ_KEY)
      3. Verify result is .success(models:) with non-empty models array
      4. Verify at least one model ID in the array (e.g. contains "llama")
    Expected Result: .success with model IDs
    Failure Indicators: .failure returned, empty models array
    Evidence: .sisyphus/evidence/task-8-validate-success.txt

  Scenario: Invalid API key returns invalidAPIKey error
    Tool: Bash (swift script)
    Preconditions: None
    Steps:
      1. Create ConnectionValidator()
      2. Call validate(baseURL: groqURL, apiKey: "invalid-key-000")
      3. Verify result is .failure(.invalidAPIKey)
    Expected Result: .failure(.invalidAPIKey)
    Failure Indicators: .success, different error, crash
    Evidence: .sisyphus/evidence/task-8-validate-badkey.txt

  Scenario: Invalid endpoint returns network error
    Tool: Bash (swift script)
    Preconditions: None
    Steps:
      1. Create ConnectionValidator()
      2. Call validate(baseURL: URL(string: "https://nonexistent.invalid.example.com/v1")!, apiKey: "any-key")
      3. Verify result is .failure(.networkError(...))
    Expected Result: .failure with network error description
    Failure Indicators: Hangs forever, crash, .success returned
    Evidence: .sisyphus/evidence/task-8-validate-badurl.txt
  ```

  **Commit**: YES
  - Message: `feat(core): add connection validator for provider configs`
  - Files: `Sources/VoxLiteCore/ConnectionValidator.swift`
  - Pre-commit: `swift build --disable-sandbox`

- [ ] 9. Pipeline + Bootstrap Wiring — AppViewModel.swift Updates

  **What to do**:
  - Modify `Sources/VoxLiteFeature/AppViewModel.swift`
  - Update `VoxLiteFeatureBootstrap.makeDefaultViewModel()` (currently at line 549-587) to support local/remote switching:
    1. Read `AppSettings` from `FileAppSettingsStore.defaultSettings` (or loaded settings)
    2. Check `appSettings.speechModel.useRemote` and `appSettings.llmModel.useRemote` flags
    3. **For STT (Speech Transcriber)**:
       - If `speechModel.useRemote == true` AND `speechModel.provider.supportsSTT == true`:
         a. Retrieve API key from `KeychainStorage().retrieveAPIKey(for: speechModel.provider)`
         b. Guard API key is non-nil — if nil, fall back to on-device transcriber with a warning log
         c. Compute effective endpoint: `speechModel.effectiveEndpoint` (from Task 2's ModelSetting)
         d. Create `OpenAIClient(baseURL: endpoint, apiKey: apiKey)`
         e. Create `RemoteSpeechTranscriber(client: client, model: speechModel.selectedSTTModel, logger: logger)`
         f. Use this as the `transcriber` parameter for VoicePipeline
       - If local: keep existing `OnDeviceSpeechTranscriber(logger: logger)` path
    4. **For LLM (Prompt Generator)**:
       - If `llmModel.useRemote == true`:
         a. Retrieve API key from Keychain for `llmModel.provider`
         b. Guard API key non-nil — if nil, fall back to `FoundationModelPromptGenerator()` with warning
         c. Create `OpenAIClient(baseURL: endpoint, apiKey: apiKey)`
         d. Create `RemoteLLMGenerator(client: client, model: llmModel.selectedLLMModel, logger: logger)`
         e. Pass as `generator` parameter to `RuleBasedTextCleaner(generator: remoteLLM)`
       - If local: keep existing `RuleBasedTextCleaner()` (which defaults to `FoundationModelPromptGenerator`)
    5. Rest of pipeline construction stays identical (stateMachine, audio, resolver, injector, performanceSampler)
  - Add `import VoxLiteSystem` to AppViewModel.swift if not already present (needed for `KeychainStorage`)
  - The bootstrap must handle the dependency chain: settings → keychain → client → transcriber/generator → pipeline
  - Add a public method `AppViewModel.reconfigurePipeline()` that re-creates the pipeline with current settings (called after settings change in UI). This requires storing the non-pipeline dependencies (logger, metrics, etc.) as instance properties so they can be reused.
    - IMPORTANT: If `reconfigurePipeline()` is too invasive, an alternative is to simply require app restart after settings change. Decision: **require restart** (show alert "请重启应用以应用新配置" after save). This is simpler and avoids runtime pipeline swapping complexity.

  **Must NOT do**:
  - Do NOT add automatic fallback from remote to local on every request (fail fast — if remote is configured, use remote only)
  - Do NOT add lazy initialization or caching of OpenAIClient (create fresh at bootstrap)
  - Do NOT modify VoicePipeline.swift constructor or protocol (it already accepts any SpeechTranscribing)
  - Do NOT add connection validation at bootstrap time (validation happens in Settings UI via Task 8)
  - Do NOT modify any VoxLiteDomain protocols for this task

  **Recommended Agent Profile**:
  - **Category**: `deep`
    - Reason: Complex wiring logic — reads settings, accesses Keychain, creates conditional dependency graph, modifies bootstrap. High risk of breaking existing functionality if done incorrectly.
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES (but depends on most Wave 1 tasks)
  - **Parallel Group**: Wave 2 (with Tasks 6, 7, 8)
  - **Blocks**: Task 11
  - **Blocked By**: Task 1 (RemoteProvider types), Task 2 (ModelSetting redesign), Task 3 (KeychainStorage), Task 4 (OpenAIClient), Task 6 (RemoteSpeechTranscriber), Task 7 (RemoteLLMGenerator)

  **References**:

  **Pattern References**:
  - `Sources/VoxLiteFeature/AppViewModel.swift:549-587` — Current `VoxLiteFeatureBootstrap.makeDefaultViewModel()` — THIS is the exact code being modified. Read it carefully — understand every dependency created and the order.
  - `Sources/VoxLiteFeature/AppViewModel.swift:1-50` — `AppViewModel` class declaration, stored properties, init signature — understand what the ViewModel expects
  - `Sources/VoxLiteCore/VoicePipeline.swift:17-39` — `VoicePipeline.init(...)` — the constructor signature that bootstrap must satisfy. Note: `transcriber: SpeechTranscribing` accepts any conforming type.
  - `Sources/VoxLiteCore/TextCleaner.swift:84-92` — `RuleBasedTextCleaner.init(generator:)` — where `RemoteLLMGenerator` gets injected. Default is `FoundationModelPromptGenerator()`.

  **API/Type References**:
  - `Sources/VoxLiteDomain/PrototypeModels.swift:125-` — Redesigned `ModelSetting` (from Task 2) with `useRemote`, `provider`, `effectiveEndpoint`, `selectedSTTModel`, `selectedLLMModel`
  - `Sources/VoxLiteDomain/RemoteProviderTypes.swift` (from Task 1) — `RemoteProvider` enum with `supportsSTT`, `supportsLLM`
  - `Sources/VoxLiteSystem/KeychainStorage.swift` (from Task 3) — `KeychainStorage().retrieveAPIKey(for:)` method
  - `Sources/VoxLiteCore/OpenAIClient.swift` (from Task 4) — `OpenAIClient(baseURL:apiKey:)` constructor
  - `Sources/VoxLiteCore/RemoteSpeechTranscriber.swift` (from Task 6) — `RemoteSpeechTranscriber(client:model:logger:)`
  - `Sources/VoxLiteCore/RemoteLLMGenerator.swift` (from Task 7) — `RemoteLLMGenerator(client:model:logger:)`
  - `Sources/VoxLiteSystem/LocalStores.swift:197-229` — `FileAppSettingsStore` — how settings are loaded at bootstrap

  **WHY Each Reference Matters**:
  - `makeDefaultViewModel()` is the ONLY place where all dependencies are wired together. Any mistake here breaks the entire app.
  - `VoicePipeline.init` accepts `SpeechTranscribing` protocol — so `RemoteSpeechTranscriber` slots in without pipeline changes.
  - `RuleBasedTextCleaner.init(generator:)` accepts `PromptGenerating` — so `RemoteLLMGenerator` slots in without cleaner changes.
  - Settings must be read FIRST to determine which implementations to create.

  **Acceptance Criteria**:

  **QA Scenarios (MANDATORY):**

  ```
  Scenario: App builds and launches with local model (default)
    Tool: Bash (swift build + run)
    Preconditions: No remote settings configured
    Steps:
      1. Run: swift build --disable-sandbox
      2. Verify build succeeds
      3. Check that default AppSettings has speechModel.useRemote == false and llmModel.useRemote == false
      4. Run: swift run --disable-sandbox VoxLiteSelfCheck
      5. Verify SELF_CHECK_OK output (existing functionality preserved)
    Expected Result: Build succeeds, self-check passes, local model used by default
    Failure Indicators: Build failure, self-check failure, crash at launch
    Evidence: .sisyphus/evidence/task-9-local-default.txt

  Scenario: Bootstrap creates remote transcriber when settings configured
    Tool: Bash (swift script)
    Preconditions: AppSettings saved with speechModel.useRemote=true, provider=.groq, valid API key in Keychain
    Steps:
      1. Save test AppSettings with remote STT enabled for Groq
      2. Store API key via KeychainStorage
      3. Call VoxLiteFeatureBootstrap.makeDefaultViewModel()
      4. Verify pipeline uses RemoteSpeechTranscriber (log output should show "RemoteSpeechTranscriber" or remote-specific log)
    Expected Result: Remote transcriber created and wired into pipeline
    Failure Indicators: Still uses OnDeviceSpeechTranscriber, crash, nil API key fallback
    Evidence: .sisyphus/evidence/task-9-remote-bootstrap.txt

  Scenario: Missing API key falls back to local with warning
    Tool: Bash (swift script)
    Preconditions: AppSettings saved with remote enabled, but NO API key in Keychain
    Steps:
      1. Save test AppSettings with speechModel.useRemote=true
      2. Do NOT store API key
      3. Call makeDefaultViewModel()
      4. Verify falls back to OnDeviceSpeechTranscriber
      5. Verify warning logged about missing API key
    Expected Result: Graceful fallback to local, warning logged
    Failure Indicators: Crash, nil reference, no fallback
    Evidence: .sisyphus/evidence/task-9-missing-key-fallback.txt
  ```

  **Commit**: YES
  - Message: `feat(feature): wire remote providers into pipeline bootstrap`
  - Files: `Sources/VoxLiteFeature/AppViewModel.swift`
  - Pre-commit: `swift build --disable-sandbox && swift run --disable-sandbox VoxLiteSelfCheck`

- [ ] 10. Settings UI Redesign with Provider Dropdowns — ModelSettingsView.swift

  **What to do**:
  - Create `Sources/VoxLiteApp/ModelSettingsView.swift` as a new extracted view for the model settings section
  - Replace the current model settings section in `MainWindowView.swift` (lines 479-511) with a call to the new `ModelSettingsView()`
  - The new view replaces free-text TextFields with structured dropdowns:

  **UI Layout** (top to bottom):
  1. **语音识别模型 (STT)** section:
     - `Picker` (dropdown) with options: `本地模型（端侧）`, `Deepseek` (disabled — `.supportsSTT == false`), `Groq`, `硅基流动 (SiliconFlow)`, `自定义 (Custom)`
     - Default selection: `本地模型（端侧）`
     - When a remote provider is selected, show below it:
       a. **端点地址** (read-only for presets, editable for Custom): auto-filled from `RemoteProvider.defaultEndpoint`
       b. **模型选择** `Picker`: populated from `RemoteProvider.sttModelPresets` for the selected provider
       c. **API Key** `SecureField`: masked input, loaded from Keychain on appear, stored to Keychain on save
     - If provider `.supportsSTT == false`, show disabled message: "该服务商不支持语音识别"

  2. **LLM 模型** section:
     - `Picker` with options: `本地模型（端侧）`, `Deepseek`, `Groq`, `硅基流动 (SiliconFlow)`, `自定义 (Custom)`
     - Default selection: `本地模型（端侧）`
     - When remote selected, show same sub-fields as STT but with LLM model presets

  3. **Shared behaviors**:
     - API Key field shared per provider (if both STT and LLM use same provider, show one API key field OR share the same Keychain entry)
     - "验证连接" (Validate Connection) button — calls `ConnectionValidator.validate()`, shows inline status:
       - Loading spinner during validation
       - ✅ "连接成功" on success (green pill)
       - ❌ "API Key 无效" / "连接失败: {error}" on failure (red pill)
     - "保存配置" button — saves ModelSetting to AppSettings, API key to Keychain, shows restart alert
     - After save: show alert "配置已保存，请重启应用以应用新配置" (restart required — from Task 9 decision)

  **State management**:
  - Use `@EnvironmentObject private var model: AppViewModel` (existing pattern)
  - Local `@State` for: selected STT provider, selected LLM provider, API key text, validation status, is validating
  - On appear: load current ModelSetting from `model.appSettings`, load API key from KeychainStorage
  - Remember per-provider model selections: when switching between providers, restore previously selected model for that provider

  **Custom provider handling**:
  - When `自定义 (Custom)` is selected, endpoint becomes an editable TextField
  - Model name becomes an editable TextField (no preset dropdown)
  - API key still uses SecureField

  **SwiftUI implementation details**:
  - Use `Picker` with `.menu` style for dropdowns (standard macOS picker)
  - Use `SecureField` for API key (masks input)
  - Use existing `sectionCard(title:)`, `settingRow(_:content:)`, `statusPill(_:tone:)` helpers from MainWindowView
  - Match existing color palette: `palette.mutedText`, `palette.bodyText`, `palette.cardBorder`, etc.
  - Use `VoxPrimaryButtonStyle()` for save button (existing style)

  **Must NOT do**:
  - Do NOT add "获取 API Key" links to provider websites
  - Do NOT add import/export of settings
  - Do NOT add model search/filter functionality
  - Do NOT add real-time streaming preview
  - Do NOT use any third-party UI components
  - Do NOT change the overall MainWindowView layout or navigation

  **Recommended Agent Profile**:
  - **Category**: `visual-engineering`
    - Reason: Complex SwiftUI form with conditional visibility, dropdowns, secure fields, async validation state, inline status indicators. Needs careful attention to UX flow and visual consistency.
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 3
  - **Blocks**: Task 11
  - **Blocked By**: Task 1 (RemoteProvider), Task 2 (ModelSetting), Task 3 (KeychainStorage), Task 8 (ConnectionValidator)

  **References**:

  **Pattern References**:
  - `Sources/VoxLiteApp/MainWindowView.swift:479-511` — Current model settings section — THIS IS BEING REPLACED. Understand what it renders and how it binds to model.
  - `Sources/VoxLiteApp/MainWindowView.swift:518-527` — `settingRow(_:content:)` helper — reuse this exact pattern for form rows
  - `Sources/VoxLiteApp/MainWindowView.swift:529-548` — `permissionSettingRow(_:granted:action:)` — reference for status pill + action button pattern
  - `Sources/VoxLiteApp/MainWindowView.swift:550-560` — `statusRow(_:_:)` — reference for read-only status display
  - `Sources/VoxLiteApp/MainWindowView.swift:619-` — `sectionCard(title:content:)` — the container used for settings sections
  - `Sources/VoxLiteApp/MainWindowView.swift:7-22` — View struct with `@EnvironmentObject`, `@State` declarations — follow same pattern
  - `Sources/VoxLiteApp/MainWindowView.swift:1-6` — Import list — use same imports

  **API/Type References**:
  - `Sources/VoxLiteDomain/RemoteProviderTypes.swift` (from Task 1) — `RemoteProvider` enum: `.allCases`, `.displayName`, `.defaultEndpoint`, `.supportsSTT`, `.supportsLLM`, `.sttModelPresets`, `.llmModelPresets`
  - `Sources/VoxLiteDomain/PrototypeModels.swift` (from Task 2) — Redesigned `ModelSetting` with `useRemote`, `provider`, `customEndpoint`, `selectedSTTModel`, `selectedLLMModel`, `effectiveEndpoint`
  - `Sources/VoxLiteSystem/KeychainStorage.swift` (from Task 3) — `KeychainStorage().retrieveAPIKey(for:)`, `.storeAPIKey(for:key:)`
  - `Sources/VoxLiteCore/ConnectionValidator.swift` (from Task 8) — `ConnectionValidator().validate(baseURL:apiKey:)` → `ConnectionValidationResult`
  - `Sources/VoxLiteFeature/AppViewModel.swift:253-255` — `saveRemoteModelSettings()` — existing save method to call (or enhance)

  **External References**:
  - Ayna settings UI (reference only): `https://github.com/sozercan/ayna` — Production macOS AI settings pattern
  - GPTalks provider selection: `https://github.com/nicktgn/GPTalks` — SwiftUI provider dropdown pattern

  **WHY Each Reference Matters**:
  - Current `MainWindowView` lines 479-511 define exactly what exists now — the new view must fit into the same slot with improved UX
  - The `settingRow`/`sectionCard`/`statusPill` helpers ensure visual consistency with the rest of the settings page
  - `RemoteProvider` enum drives the dropdown options and auto-fill behavior — the UI is a direct reflection of this enum
  - `ConnectionValidator` powers the "验证连接" button async flow
  - `KeychainStorage` loads/saves API keys — must be called on appear and on save

  **Acceptance Criteria**:

  **QA Scenarios (MANDATORY):**

  ```
  Scenario: Default state shows local model selected for both STT and LLM
    Tool: Playwright (launch app, navigate to settings)
    Preconditions: App launched, no remote settings saved
    Steps:
      1. Navigate to Settings module (click 设置 in sidebar)
      2. Locate "模型设置" section card
      3. Verify STT dropdown shows "本地模型（端侧）"
      4. Verify LLM dropdown shows "本地模型（端侧）"
      5. Verify no API key field, no endpoint field visible (local mode hides them)
    Expected Result: Both dropdowns default to local, remote fields hidden
    Failure Indicators: Remote provider shown by default, fields visible in local mode
    Evidence: .sisyphus/evidence/task-10-default-state.png

  Scenario: Select Groq shows auto-filled endpoint and model presets
    Tool: Playwright (interact with UI)
    Preconditions: App settings page open
    Steps:
      1. Click STT dropdown, select "Groq"
      2. Verify endpoint field shows "https://api.groq.com/openai/v1" (read-only)
      3. Verify model dropdown appears with Groq STT presets (e.g. "whisper-large-v3-turbo")
      4. Verify API Key SecureField appears (empty)
      5. Verify "验证连接" button appears
    Expected Result: Endpoint auto-filled, model dropdown populated, API key field shown
    Failure Indicators: Empty endpoint, no model options, missing fields
    Evidence: .sisyphus/evidence/task-10-groq-selection.png

  Scenario: Deepseek disables STT with explanation
    Tool: Playwright
    Preconditions: App settings page open
    Steps:
      1. Click STT dropdown, select "Deepseek"
      2. Verify disabled message shown: "该服务商不支持语音识别"
      3. Verify no model dropdown or API key field for STT
    Expected Result: Clear message that Deepseek doesn't support STT
    Failure Indicators: Crash, API key field shown, no explanation
    Evidence: .sisyphus/evidence/task-10-deepseek-no-stt.png

  Scenario: Connection validation success flow
    Tool: Playwright + real API
    Preconditions: Valid Groq API key
    Steps:
      1. Select Groq for LLM
      2. Enter valid API key in SecureField
      3. Click "验证连接"
      4. Verify spinner/loading indicator appears
      5. Verify "连接成功" green status pill appears after validation completes
    Expected Result: Validation succeeds, green status shown
    Failure Indicators: Validation hangs, no status shown, crash
    Evidence: .sisyphus/evidence/task-10-validation-success.png

  Scenario: Connection validation failure with invalid key
    Tool: Playwright
    Preconditions: None
    Steps:
      1. Select Groq for LLM
      2. Enter "bad-key-12345" as API key
      3. Click "验证连接"
      4. Verify red error status: "API Key 无效"
    Expected Result: Red error indicator with clear message
    Failure Indicators: No error shown, generic error, crash
    Evidence: .sisyphus/evidence/task-10-validation-failure.png

  Scenario: Custom provider allows editable endpoint
    Tool: Playwright
    Preconditions: App settings page open
    Steps:
      1. Select "自定义 (Custom)" for LLM
      2. Verify endpoint field is editable TextField (not read-only)
      3. Enter "https://my-custom-api.example.com/v1"
      4. Verify model name field is editable TextField (not dropdown)
      5. Enter "my-model-name"
    Expected Result: Both endpoint and model name are free-text editable
    Failure Indicators: Fields read-only, dropdown instead of text, crash
    Evidence: .sisyphus/evidence/task-10-custom-provider.png
  ```

  **Commit**: YES
  - Message: `feat(app): redesign model settings UI with provider dropdowns`
  - Files: `Sources/VoxLiteApp/ModelSettingsView.swift`, `Sources/VoxLiteApp/MainWindowView.swift`
  - Pre-commit: `swift build --disable-sandbox`

- [ ] 11. End-to-End Integration and Final Wiring

  **What to do**:
  - This is the integration task that ensures all pieces work together as a complete feature
  - Verify and fix any cross-task integration issues:

  1. **Settings persistence round-trip**:
     - Verify that `ModelSettingsView` → save → `AppSettings` → `FileAppSettingsStore` → persist → reload → bootstrap correctly reads the saved config
     - Update `FileAppSettingsStore.defaultSettings` (in `LocalStores.swift:218`) if the new `ModelSetting` structure requires different defaults
     - Ensure `AppSettings.Codable` conformance still works with the new `ModelSetting` fields (provider enum, selectedSTTModel, selectedLLMModel)

  2. **End-to-end STT flow** (if remote enabled):
     - User speaks → AudioCaptureService records → VoicePipeline calls `transcriber.transcribe()` → `RemoteSpeechTranscriber` sends to Whisper API → returns `SpeechTranscription` → pipeline continues with clean/inject
     - Verify the audio file format from AudioCaptureService is compatible with Whisper API (must be WAV, MP3, or M4A — check AudioCaptureService output format)

  3. **End-to-end LLM flow** (if remote enabled):
     - Pipeline gets transcription → `RuleBasedTextCleaner.cleanText()` → calls `generator.generateText(from: prompt)` → `RemoteLLMGenerator` sends to Chat Completions API → returns cleaned text → pipeline injects
     - Verify the prompt template from `RuleBasedTextCleaner.buildPrompt()` works with remote LLMs (it was designed for Apple Foundation Model — verify remote LLMs understand the same prompts)

  4. **Restart notification flow**:
     - After settings save in `ModelSettingsView`, user sees restart alert
     - After restart, `VoxLiteFeatureBootstrap.makeDefaultViewModel()` reads new settings and creates correct remote/local pipeline

  5. **Error propagation**:
     - Remote API errors propagate through pipeline error handling correctly
     - `VoxErrorCode` remote cases are handled in `AppViewModel` state machine (verify `failed` state shows appropriate error message in UI)

  6. **Self-check compatibility**:
     - Run `VoxLiteSelfCheck` and verify it still passes — existing self-check tests local pipeline; it should not break
     - If self-check creates its own test fixtures, ensure new ModelSetting defaults don't break them

  **Must NOT do**:
  - Do NOT add new features beyond integration (no new API endpoints, no new UI views)
  - Do NOT modify the VoicePipeline processing logic (it's already protocol-based)
  - Do NOT add integration tests as code (QA scenarios are the verification method)
  - Do NOT change the self-check tests — if they fail, fix the production code to maintain compatibility

  **Recommended Agent Profile**:
  - **Category**: `deep`
    - Reason: End-to-end integration requires understanding the full pipeline flow, reading multiple files, verifying cross-module contracts, and potentially fixing subtle compatibility issues. Requires deep reasoning.
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 3 (after Task 10)
  - **Blocks**: Final Verification Wave
  - **Blocked By**: ALL previous tasks (1-10)

  **References**:

  **Pattern References**:
  - `Sources/VoxLiteCore/VoicePipeline.swift:41-244` — Full pipeline flow: `startRecording()` → `stopAndProcess()` — understand every step to verify remote impls integrate correctly
  - `Sources/VoxLiteCore/TextCleaner.swift:94-129` — `RuleBasedTextCleaner.cleanText()` — verify prompt template works with remote LLMs. Look at `buildPrompt()` method and what it produces.
  - `Sources/VoxLiteFeature/AppViewModel.swift:549-587` — Updated bootstrap from Task 9 — verify it correctly constructs the full dependency chain

  **API/Type References**:
  - `Sources/VoxLiteInput/AudioCaptureService.swift` — Check audio output format (file extension, encoding) — must be Whisper-compatible
  - `Sources/VoxLiteSystem/LocalStores.swift:197-239` — `FileAppSettingsStore` — verify Codable round-trip with new ModelSetting structure
  - `Sources/VoxLiteSelfCheck/` — All self-check files — verify no breakage

  **External References**:
  - OpenAI Whisper supported formats: `https://platform.openai.com/docs/api-reference/audio/createTranscription` — "file must be in one of these formats: flac, mp3, mp4, mpeg, mpga, m4a, ogg, wav, or webm"

  **WHY Each Reference Matters**:
  - `VoicePipeline` is the orchestrator — remote impls must satisfy its exact contract (async throws, return types, error types)
  - `RuleBasedTextCleaner.buildPrompt()` produces a specific prompt format — verify remote LLMs (Deepseek, Groq/Llama) handle it correctly
  - `AudioCaptureService` output format determines Whisper compatibility — if it outputs `.caf` or unsupported format, need to convert
  - `FileAppSettingsStore` must handle the new Codable structure — breaking migration could crash the app

  **Acceptance Criteria**:

  **QA Scenarios (MANDATORY):**

  ```
  Scenario: Full STT round-trip with Groq Whisper
    Tool: Bash (swift build + manual pipeline test) + Playwright (if UI needed)
    Preconditions: Groq API key configured, remote STT enabled in settings, app restarted
    Steps:
      1. Build: swift build --disable-sandbox
      2. Launch app
      3. Record a short voice clip (press Fn, say "你好世界", release Fn)
      4. Verify transcription appears (either in UI status or injected text)
      5. Verify log shows RemoteSpeechTranscriber was used (look for "remote" in logs)
      6. Verify latencyMs is reported
    Expected Result: Voice transcribed via remote Whisper, text injected into active app
    Failure Indicators: Local transcriber used instead, error thrown, no text injected
    Evidence: .sisyphus/evidence/task-11-e2e-stt.txt

  Scenario: Full LLM round-trip with remote text cleaning
    Tool: Bash + Playwright
    Preconditions: Remote LLM enabled, valid API key
    Steps:
      1. Record voice: "今天天气真不错我想出去走走"
      2. Verify transcription is cleaned/polished by remote LLM
      3. Verify cleaned text is injected into active text field
      4. Verify log shows remote LLM was used
    Expected Result: Text cleaned by remote LLM and injected
    Failure Indicators: Raw transcription injected (no cleaning), local Foundation Model used
    Evidence: .sisyphus/evidence/task-11-e2e-llm.txt

  Scenario: Self-check still passes with all changes
    Tool: Bash
    Preconditions: All tasks 1-10 complete
    Steps:
      1. Run: swift build --disable-sandbox
      2. Run: swift run --disable-sandbox VoxLiteSelfCheck
      3. Verify output contains "SELF_CHECK_OK"
    Expected Result: SELF_CHECK_OK — no regressions
    Failure Indicators: Any test failure, crash, build error
    Evidence: .sisyphus/evidence/task-11-selfcheck.txt

  Scenario: Settings persistence survives app restart
    Tool: Bash + Playwright
    Preconditions: Remote settings saved from Task 10
    Steps:
      1. Save remote config: Groq, LLM model "llama-3.1-8b-instant", API key stored
      2. Quit app completely
      3. Relaunch app
      4. Navigate to Settings
      5. Verify Groq is still selected, model is still "llama-3.1-8b-instant"
      6. Verify API key field shows masked content (loaded from Keychain)
    Expected Result: All settings preserved across restart
    Failure Indicators: Settings reset to default, crash on launch, API key lost
    Evidence: .sisyphus/evidence/task-11-persistence.txt

  Scenario: Remote API error shows error in UI
    Tool: Playwright
    Preconditions: Remote enabled with INVALID API key (expired/wrong)
    Steps:
      1. Record voice with invalid remote config
      2. Verify app shows error state (not crash)
      3. Verify error message mentions API key or connection issue
      4. Verify app can recover (retry or switch to local)
    Expected Result: Graceful error display, no crash
    Failure Indicators: Crash, silent failure, stuck state
    Evidence: .sisyphus/evidence/task-11-error-handling.png
  ```

  **Commit**: YES
  - Message: `feat(feature): end-to-end remote model integration`
  - Files: `Sources/VoxLiteFeature/AppViewModel.swift`, `Sources/VoxLiteSystem/LocalStores.swift` (if default settings update needed)
  - Pre-commit: `swift build --disable-sandbox && swift run --disable-sandbox VoxLiteSelfCheck`

---

## Final Verification Wave (MANDATORY — after ALL implementation tasks)

> 4 review agents run in PARALLEL. ALL must APPROVE. Present consolidated results to user and get explicit "okay" before completing.

- [ ] F1. **Plan Compliance Audit** — `oracle`
  Read the plan end-to-end. For each "Must Have": verify implementation exists (read file, curl endpoint, run command). For each "Must NOT Have": search codebase for forbidden patterns — reject with file:line if found. Check evidence files exist in .sisyphus/evidence/. Compare deliverables against plan.
  Output: `Must Have [N/N] | Must NOT Have [N/N] | Tasks [N/N] | VERDICT: APPROVE/REJECT`

- [ ] F2. **Code Quality Review** — `unspecified-high`
  Run `swift build --disable-sandbox`. Review all changed/new files for: `as! Any` force casts, empty catches, print() in prod code, commented-out code, unused imports. Check AI slop: excessive comments, over-abstraction, generic names (data/result/item/temp). Verify Swift 6 concurrency compliance (@Sendable, actor isolation).
  Output: `Build [PASS/FAIL] | SelfCheck [PASS/FAIL] | Files [N clean/N issues] | VERDICT`

- [ ] F3. **Real Manual QA** — `unspecified-high` (+ `playwright` skill if UI)
  Start from clean state. Execute EVERY QA scenario from EVERY task — follow exact steps, capture evidence. Test cross-task integration (provider selection → API key entry → validation → transcription). Test edge cases: empty API key, invalid endpoint, network timeout. Save to `.sisyphus/evidence/final-qa/`.
  Output: `Scenarios [N/N pass] | Integration [N/N] | Edge Cases [N tested] | VERDICT`

- [ ] F4. **Scope Fidelity Check** — `deep`
  For each task: read "What to do", read actual diff (git log/diff). Verify 1:1 — everything in spec was built (no missing), nothing beyond spec was built (no creep). Check "Must NOT do" compliance. Detect cross-task contamination: Task N touching Task M's files. Flag unaccounted changes.
  Output: `Tasks [N/N compliant] | Contamination [CLEAN/N issues] | Unaccounted [CLEAN/N files] | VERDICT`

---

## Commit Strategy

| Wave | Commit | Message | Files |
|------|--------|---------|-------|
| 1 | C1 | `feat(domain): add remote provider registry types and capability flags` | RemoteProviderTypes.swift |
| 1 | C2 | `refactor(domain): redesign ModelSetting for structured provider selection` | PrototypeModels.swift |
| 1 | C3 | `feat(system): add Keychain storage wrapper for API keys` | KeychainStorage.swift |
| 1 | C4 | `feat(core): add OpenAI-compatible HTTP client for chat and whisper APIs` | OpenAIClient.swift |
| 1 | C5 | `feat(domain): add remote API error codes to VoxErrorCode` | Models.swift |
| 2 | C6 | `feat(core): add remote Whisper speech transcriber` | RemoteSpeechTranscriber.swift |
| 2 | C7 | `feat(core): add remote LLM text generator via chat completions` | RemoteLLMGenerator.swift |
| 2 | C8 | `feat(core): add connection validator for provider configs` | ConnectionValidator.swift |
| 2 | C9 | `feat(feature): wire remote providers into pipeline bootstrap` | AppViewModel.swift, VoicePipeline changes |
| 3 | C10 | `feat(app): redesign model settings UI with provider dropdowns` | ModelSettingsView.swift, MainWindowView.swift |
| 3 | C11 | `feat(feature): end-to-end remote model integration` | AppViewModel.swift, LocalStores.swift |

---

## Success Criteria

### Verification Commands
```bash
swift build --disable-sandbox  # Expected: Build Succeeded
swift run --disable-sandbox VoxLiteSelfCheck  # Expected: SELF_CHECK_OK
```

### Final Checklist
- [ ] Settings dropdown shows 本地模型 + 4 remote options for both STT and LLM
- [ ] Selecting Deepseek auto-fills `https://api.deepseek.com/v1`
- [ ] Selecting Groq auto-fills `https://api.groq.com/openai/v1`
- [ ] Selecting SiliconFlow auto-fills `https://api.siliconflow.cn/v1`
- [ ] Custom option allows free-text endpoint entry
- [ ] API key stored in Keychain (verifiable via `security` CLI)
- [ ] Connection validation blocks invalid configs
- [ ] Remote STT transcription returns text with latencyMs
- [ ] Remote LLM generation returns cleaned text with latencyMs
- [ ] Local model works when remote is disabled
- [ ] All "Must NOT Have" items absent from codebase
- [ ] Zero third-party dependencies in Package.swift
