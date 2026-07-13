# LumaNest Multi-provider LLM Implementation Plan

> **For implementer:** Use TDD throughout. Write failing test first. Watch it fail. Then implement.

**Goal:** Replace the single Qwen-oriented AI slot with an explicit, empty-by-default, multi-provider profile and optional fallback system.

**Architecture:** Server-owned provider presets create validated `LLMProfile` values. Protocol adapters normalize OpenAI-compatible, Anthropic and Gemini requests behind one router; encrypted runtime configuration publishes immutable profile/routing snapshots to each request. The admin API and static UI manage masked profiles without ever returning raw credentials.

**Tech Stack:** Node.js 22 ESM, node:test, existing AES-256-GCM store and runtime snapshots, static HTML/CSS/JavaScript, Docker Compose.

---

### Task 1: Provider catalog and profile validation

**Files:**
- Create: `services/lumanest-data-broker/src/llm/provider-catalog.mjs`
- Create: `services/lumanest-data-broker/src/llm/profile.mjs`
- Create: `services/lumanest-data-broker/test/llm-profile.test.mjs`

**Step 1:** Write failing tests proving the catalog contains the eleven approved templates, no template is active/default, custom OpenAI-compatible endpoints are supported, profile IDs/URLs/models/timeouts are bounded, unknown providers/protocols/fields are rejected, and API keys may be omitted only when updating an existing profile.

**Step 2:** Run `node --test test/llm-profile.test.mjs`. Expected: module-not-found failure.

**Step 3:** Implement immutable `providerCatalog`, `publicProviderCatalog()` and `validateLLMProfile(input, { existing })`. Provider templates define protocol, official base URL, suggested models and whether endpoint override is allowed. Do not include credentials or active-profile state.

**Step 4:** Run the target test and `npm test`. Expected: all pass.

**Step 5:** Commit `feat: define LLM provider profiles`.

### Task 2: Multi-profile encrypted runtime configuration

**Files:**
- Modify: `services/lumanest-data-broker/src/admin/runtime-config.mjs`
- Modify: `services/lumanest-data-broker/src/admin/config-store.mjs`
- Modify: `services/lumanest-data-broker/src/server.mjs`
- Modify: `services/lumanest-data-broker/test/runtime-config.test.mjs`
- Create: `services/lumanest-data-broker/test/llm-runtime-config.test.mjs`

**Step 1:** Write failing tests for empty-by-default `llmProfiles`, explicit `primaryProfileId`, disabled fallback, immutable snapshots, secret-preserving partial updates, profile deletion reference checks, and no migration when legacy `AI_API_KEY` is empty.

**Step 2:** Verify RED with `node --test test/llm-runtime-config.test.mjs`.

**Step 3:** Add `llmProfiles` and `llmRouting` to encrypted overrides. Remove Qwen branded defaults from environment parsing. Keep read compatibility for old non-empty legacy AI configuration but expose it only as an unimported migration candidate; never create a profile automatically.

**Step 4:** Verify target and full tests, then commit `feat: persist multiple LLM profiles`.

### Task 3: Protocol adapters

**Files:**
- Create: `services/lumanest-data-broker/src/llm/adapters/openai-compatible.mjs`
- Create: `services/lumanest-data-broker/src/llm/adapters/anthropic.mjs`
- Create: `services/lumanest-data-broker/src/llm/adapters/gemini.mjs`
- Create: `services/lumanest-data-broker/src/llm/adapters/index.mjs`
- Create: `services/lumanest-data-broker/test/llm-adapters.test.mjs`

**Step 1:** Write failing tests that inspect exact URL, authentication header, bounded request body and extracted text for all three protocols. Include OpenRouter optional attribution headers, Ollama no-key behavior, Anthropic version header and Gemini query-key handling without logging URLs.

**Step 2:** Verify RED.

**Step 3:** Implement `requestNarrative({ profile, prompt, fetcher, timeoutMs })` returning normalized `{ ok, text }` or stable failure categories: `authentication_failed`, `rate_limited`, `model_not_found`, `timeout`, `upstream_unavailable`, `invalid_response`.

**Step 4:** Verify tests and commit `feat: add native LLM protocol adapters`.

### Task 4: Primary and fallback routing

**Files:**
- Create: `services/lumanest-data-broker/src/llm/router.mjs`
- Create: `services/lumanest-data-broker/test/llm-router.test.mjs`
- Modify: `services/lumanest-data-broker/src/server.mjs`
- Modify: `services/lumanest-data-broker/test/server.test.mjs`

**Step 1:** Write failing tests proving no profile means `ai_unconfigured`; primary success stops routing; fallback is off by default; only timeout/rate-limit/network/5xx failures fall through; authentication/model/request failures stop; order is preserved; and attempts never exceed three.

**Step 2:** Verify RED.

**Step 3:** Route `/v1/narrative` through an injected `LLMRouter`. Keep the existing final structured-output and allowed-event validation outside adapters. Return local-template-compatible failure when all attempts fail and never expose provider response bodies.

**Step 4:** Verify target/full tests and commit `feat: route narratives across LLM profiles`.

### Task 5: Profile-specific connection testing and admin API

**Files:**
- Modify: `services/lumanest-data-broker/src/admin/admin-server.mjs`
- Modify: `services/lumanest-data-broker/src/admin/connection-tester.mjs`
- Modify: `services/lumanest-data-broker/test/admin-server.test.mjs`
- Modify: `services/lumanest-data-broker/test/connection-tester.test.mjs`

**Step 1:** Write failing tests for `GET /admin-api/llm/providers`, profile CRUD, explicit primary selection, routing update, per-profile connection test, masked keys, blank-key preservation, delete confirmation semantics and no raw upstream errors.

**Step 2:** Verify RED.

**Step 3:** Implement APIs using the runtime configuration service. Audit only profile IDs, provider IDs, changed field names and stable result categories. Never record model prompts, keys or upstream bodies.

**Step 4:** Verify tests and commit `feat: manage LLM profiles through admin API`.

### Task 6: Professional model service console

**Files:**
- Modify: `services/lumanest-data-broker/src/admin/public/index.html`
- Modify: `services/lumanest-data-broker/src/admin/public/styles.css`
- Modify: `services/lumanest-data-broker/src/admin/public/app.js`
- Modify: `services/lumanest-data-broker/test/admin-static.test.mjs`

**Step 1:** Write failing static/security tests for an empty state, provider dialog, profile list/detail workspace, primary/fallback status, masked keys, accessible labels/status, explicit destructive confirmations, no inline scripts/styles, no HTML injection and no browser-persisted secrets.

**Step 2:** Verify RED.

**Step 3:** Replace the single AI fields with the professional model service console. Use restrained operational typography, compact status chips, provider/protocol metadata, ordered fallback controls and stable error translations. Templates populate fields only after an explicit user selection.

**Step 4:** Verify static/full tests and commit `feat: add professional LLM service console`.

### Task 7: Environment, documentation and compatibility cleanup

**Files:**
- Modify: `services/lumanest-data-broker/compose.yaml`
- Modify: `services/lumanest-data-broker/README.md`
- Modify: `services/lumanest-data-broker/src/server.mjs`
- Modify: `services/lumanest-data-broker/test/server.test.mjs`

**Step 1:** Write failing tests proving empty legacy AI variables produce no profile and no provider-specific defaults; non-empty legacy values remain an opt-in import candidate only.

**Step 2:** Verify RED.

**Step 3:** Remove `qwen-plus` and DashScope defaults from runtime/Compose. Document all presets, native protocols, fallback cost warning, Ollama LAN endpoint considerations and explicit empty-state behavior.

**Step 4:** Run `npm test` and `docker compose config`, then commit `docs: document multi-provider LLM configuration`.

### Task 8: Full regression and NAS deployment

**Files:**
- Modify only files proven defective by a failing integration check.

**Step 1:** Run `npm test`, `flutter analyze lib test`, `flutter test`, environment-aware debug APK build and `git diff --check`.

**Step 2:** Scan tracked files and admin responses for raw keys and provider response bodies.

**Step 3:** Deploy to `/vol2/docker/lumanest/qweather-token-broker`, preserving encrypted config and sessions. Build with cached base image if the NAS registry proxy remains unavailable.

**Step 4:** Verify empty LLM state, create/delete a non-secret test profile if possible, connection classification, public `/admin` 404, LAN console 200, QWeather/elevation regression, container restart persistence and healthy status.

**Step 5:** Report impact scope, verification evidence and residual risks including provider API drift, fallback cost and local Ollama network exposure.
