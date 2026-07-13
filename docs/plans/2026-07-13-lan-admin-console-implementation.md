# LumaNest LAN Admin Console Implementation Plan

> **For implementer:** Use TDD throughout. Write failing test first. Watch it fail. Then implement.

**Goal:** Add a password-protected, LAN-only Web console on port `8788` that securely manages encrypted runtime configuration for the existing LumaNest broker on port `8787`.

**Architecture:** Keep the public App API and admin surface on separate HTTP listeners. A runtime configuration service merges encrypted persisted overrides with existing environment defaults and publishes immutable snapshots to new requests. Admin authentication uses Argon2id, persistent opaque sessions, CSRF tokens and direct-socket LAN checks; the static admin UI consumes only masked configuration data.

**Tech Stack:** Node.js 22 ESM, `node:http`, `node:crypto` AES-256-GCM, `@node-rs/argon2` 2.0.2, static HTML/CSS/JavaScript, Docker Compose, Node test runner.

---

### Task 1: Define bounded runtime settings

**Files:**
- Create: `services/lumanest-data-broker/src/admin/runtime-settings.mjs`
- Create: `services/lumanest-data-broker/test/runtime-settings.test.mjs`

**Step 1: Write the failing tests**

Cover one behavior per test:

```js
test('accepts values inside every documented range', () => {
  const value = validateRuntimeSettings({
    aiEnabled: true,
    aiTimeoutMs: 8000,
    wildlifeRadiusKm: 20,
    wildlifeCacheTtlMinutes: 60,
    elevationCacheTtlMinutes: 1440,
    elevationMaximumSamples: 64,
    upstreamTimeoutMs: 10000,
    minimumOpportunityConfidence: 0.55,
    debugLogging: false,
  });
  assert.equal(value.elevationMaximumSamples, 64);
});

test('rejects settings outside server-side ranges', () => {
  assert.throws(() => validateRuntimeSettings({ wildlifeRadiusKm: 500 }));
});
```

Also test unknown fields, non-finite numbers, missing booleans and default values.

**Step 2: Run test — confirm it fails**

```bash
cd services/lumanest-data-broker
node --test test/runtime-settings.test.mjs
```

Expected: FAIL because `runtime-settings.mjs` does not exist.

**Step 3: Implement minimal validation**

Export immutable defaults and `validateRuntimeSettings(input, { partial })`. Use these ranges:

- AI timeout: 2–30 seconds
- Wildlife radius: 5–50 km
- Wildlife cache: 5–1440 minutes
- Elevation cache: 60–10080 minutes
- Elevation samples: 2–64
- Upstream timeout: 2–30 seconds
- Opportunity confidence: 0–1

Reject unknown fields; never silently clamp admin input.

**Step 4: Run test — confirm it passes**

Run the Task 1 command. Expected: PASS.

**Step 5: Commit only Task 1 files**

```bash
git add services/lumanest-data-broker/src/admin/runtime-settings.mjs services/lumanest-data-broker/test/runtime-settings.test.mjs
git commit -m "feat: validate broker runtime settings"
```

### Task 2: Add encrypted atomic configuration storage

**Files:**
- Create: `services/lumanest-data-broker/src/admin/config-store.mjs`
- Create: `services/lumanest-data-broker/test/config-store.test.mjs`

**Step 1: Write failing tests**

Test:

- a 32-byte base64 master key is required;
- sensitive fields are absent from persisted plaintext;
- AES-GCM round-trip restores values;
- corrupted authentication tag is rejected;
- save writes a temporary file then atomically renames it;
- a failed rename leaves the previous configuration readable;
- two queued saves produce one valid final document;
- restart with the same key restores overrides.

Use a temporary directory and inject filesystem operations for the failed-rename test.

**Step 2: Verify RED**

```bash
node --test test/config-store.test.mjs
```

Expected: FAIL because `EncryptedConfigStore` is missing.

**Step 3: Implement minimal store**

Persist versioned JSON containing IV, authentication tag and ciphertext. Encrypt one normalized configuration object with AES-256-GCM; write mode `0600`; serialize writes through a promise queue; call `fsync` before rename. Expose `read()`, `write(value)` and `masked(value)`. Masked output contains booleans and last four characters only, never ciphertext or full values.

**Step 4: Verify GREEN and commit**

```bash
node --test test/config-store.test.mjs
git add services/lumanest-data-broker/src/admin/config-store.mjs services/lumanest-data-broker/test/config-store.test.mjs
git commit -m "feat: persist encrypted broker configuration"
```

### Task 3: Implement administrator authentication and sessions

**Files:**
- Modify: `services/lumanest-data-broker/package.json`
- Create: `services/lumanest-data-broker/src/admin/auth.mjs`
- Create: `services/lumanest-data-broker/test/admin-auth.test.mjs`

**Step 1: Add dependency**

Add `@node-rs/argon2` `^2.0.2`, run `npm install`, and commit the generated lockfile with this task.

**Step 2: Write failing tests**

Test:

- bootstrap password becomes Argon2id hash and plaintext is never persisted;
- correct and incorrect password verification;
- five failures in fifteen minutes trigger a fifteen-minute IP lock;
- successful login clears that IP failure counter;
- session token is random, only its SHA-256 digest is stored;
- session expires after 30 days;
- Cookie contains `HttpOnly`, `SameSite=Strict`, `Path=/` and `Max-Age=2592000`;
- CSRF mismatch rejects state-changing requests;
- password change invalidates all sessions.

Inject `now()` and random byte generation for deterministic tests.

**Step 3: Verify RED, implement, verify GREEN**

```bash
node --test test/admin-auth.test.mjs
```

Implement `AdminAuthService` backed by an atomic versioned JSON file in `/var/lib/lumanest`. Do not log password, token, Cookie or CSRF values.

**Step 4: Commit exact files**

```bash
git add services/lumanest-data-broker/package.json services/lumanest-data-broker/package-lock.json services/lumanest-data-broker/src/admin/auth.mjs services/lumanest-data-broker/test/admin-auth.test.mjs
git commit -m "feat: authenticate LAN admin sessions"
```

### Task 4: Introduce immutable runtime configuration snapshots

**Files:**
- Create: `services/lumanest-data-broker/src/admin/runtime-config.mjs`
- Modify: `services/lumanest-data-broker/src/server.mjs`
- Modify: `services/lumanest-data-broker/test/server.test.mjs`
- Create: `services/lumanest-data-broker/test/runtime-config.test.mjs`

**Step 1: Write failing tests**

Prove:

- persisted values override matching environment values;
- missing persisted fields fall back to environment values;
- snapshots are frozen and an in-flight request retains its original snapshot;
- a successful replace affects the next request without server restart;
- failed validation/store writes retain the previous snapshot;
- QWeather private PEM can be parsed from either existing file fallback or encrypted override;
- AI-disabled snapshot returns `ai_unconfigured` without upstream traffic.

**Step 2: Verify RED**

```bash
node --test test/runtime-config.test.mjs test/server.test.mjs
```

**Step 3: Implement and refactor**

Create `RuntimeConfigService` with `snapshot()` and serialized `replace(patch)`. Refactor broker request handlers to obtain one snapshot at request start instead of closing over fixed keys. Pass snapshot settings into wildlife/elevation cache expiry and upstream timeout calculations. Keep existing `createTokenBrokerServer` test constructor compatible through an adapter.

**Step 4: Verify GREEN and full broker regression**

```bash
npm test
```

Expected: all old and new tests pass.

**Step 5: Commit exact runtime files**

### Task 5: Build the isolated admin HTTP server and API

**Files:**
- Create: `services/lumanest-data-broker/src/admin/admin-server.mjs`
- Create: `services/lumanest-data-broker/src/admin/lan-address.mjs`
- Create: `services/lumanest-data-broker/src/admin/audit-log.mjs`
- Create: `services/lumanest-data-broker/test/admin-server.test.mjs`
- Create: `services/lumanest-data-broker/test/lan-address.test.mjs`

**Step 1: Write failing network-boundary tests**

Test IPv4 loopback/private ranges, IPv4-mapped IPv6, IPv6 loopback/ULA and rejection of public/unspecified addresses. Explicitly ignore `X-Forwarded-For`.

Test admin endpoints:

- `POST /admin-api/login`
- `GET /admin-api/session`
- `POST /admin-api/logout`
- `GET /admin-api/config`
- `PUT /admin-api/config`
- `POST /admin-api/test-connection`
- `POST /admin-api/change-password`
- `GET /admin-api/audit`
- `POST /admin-api/clear-cache`
- `POST /admin-api/restart`

Prove LAN check happens before authentication, unauthenticated responses reveal no config, mutation requires CSRF, responses use `Cache-Control: no-store`, and bodies larger than 16 KiB are rejected.

**Step 2: Verify RED, then implement**

The admin server listens separately and is never mounted on the App API server. Connection tests return only stable categories: `ok`, `authentication_failed`, `timeout`, `upstream_unavailable`, `invalid_response`.

Audit records contain timestamp, direct remote address, operation, field names and result. No values or secret suffixes.

**Step 3: Verify GREEN**

```bash
node --test test/lan-address.test.mjs test/admin-server.test.mjs
npm test
```

**Step 4: Commit Task 5 files**

### Task 6: Build the static admin Web UI

**Files:**
- Create: `services/lumanest-data-broker/src/admin/public/index.html`
- Create: `services/lumanest-data-broker/src/admin/public/styles.css`
- Create: `services/lumanest-data-broker/src/admin/public/app.js`
- Create: `services/lumanest-data-broker/test/admin-static.test.mjs`

**Step 1: Write failing static security tests**

Assert:

- `/admin` serves the login/app shell only on the admin listener;
- scripts and styles are external files;
- CSP blocks inline script, external origins, frames and form submission outside self;
- HTML has password labels, accessible status regions and no secret placeholders;
- JavaScript uses `textContent`, never `innerHTML` or `document.write`;
- UI never stores session token, password or Key in localStorage;
- CSRF token is held in memory/sessionStorage only.

**Step 2: Verify RED, implement minimal four-page UI**

Build responsive navigation for 概览, 密钥与服务, 运行设置, 安全与维护. Render masked status only. Key fields start blank with “留空表示不修改”. Require an explicit checkbox before force-saving a failed connection test. Do not add a frontend framework or build pipeline.

**Step 3: Verify GREEN and commit**

```bash
node --test test/admin-static.test.mjs
npm test
```

### Task 7: Add bootstrap/reset CLI and Docker persistence

**Files:**
- Create: `services/lumanest-data-broker/src/admin/admin-cli.mjs`
- Modify: `services/lumanest-data-broker/src/server.mjs`
- Modify: `services/lumanest-data-broker/Dockerfile`
- Modify: `services/lumanest-data-broker/compose.yaml`
- Modify: `services/lumanest-data-broker/README.md`
- Create: `services/lumanest-data-broker/test/admin-cli.test.mjs`

**Step 1: Write failing tests**

Test bootstrap validation and password reset without printing a password hash or configuration. Test both HTTP listeners start with injected ports and closing one does not route admin requests through the other.

**Step 2: Implement**

Required deployment variables:

- `LUMANEST_CONFIG_MASTER_KEY`: base64 32-byte key
- `LUMANEST_ADMIN_PASSWORD`: used only when no password hash exists
- `ADMIN_PORT`: default `8788`
- `LUMANEST_DATA_DIR`: default `/var/lib/lumanest`

Compose changes:

- expose `8787:8787` and `8788:8788` separately;
- mount named/bind volume at `/var/lib/lumanest`;
- preserve read-only root filesystem and `no-new-privileges`;
- never mount Docker socket;
- add health checks for App API and admin listener.

Document generation commands without echoing secrets into shell history where avoidable. Document local reset command and router rule: only 8787 may be reverse-proxied.

**Step 3: Verify GREEN and commit**

```bash
npm test
sudo docker compose config
```

### Task 8: Security regression, NAS deployment and live verification

**Files:**
- Modify as required only when a failing integration test proves a defect.

**Step 1: Run complete local gates**

```bash
cd services/lumanest-data-broker && npm test
cd ../.. && flutter analyze lib test
flutter test
tool/flutter_with_environment.sh build apk --debug
git diff --check
```

Expected: every command passes; existing App API behavior remains unchanged.

**Step 2: Generate deployment-only secrets**

Generate the 32-byte configuration key and a strong initial admin password. Store them only in the ignored NAS deployment environment file; do not print them in logs, tests, commits or chat.

**Step 3: Deploy to NAS**

Copy the broker directory to `/vol2/docker/lumanest/qweather-token-broker`, then run:

```bash
sudo docker compose --env-file qweather-token-broker.env up -d --build
```

**Step 4: Verify live boundaries**

- `http://192.168.100.151:8787/healthz` returns 200.
- `http://192.168.100.151:8787/admin` returns 404.
- `http://192.168.100.151:8788/admin` loads only from LAN.
- Login Cookie and CSRF behavior match tests.
- Existing QWeather token and elevation endpoints remain 200.
- Saving a harmless runtime setting takes effect without restart.
- Restart container and confirm settings/session persistence.
- Confirm the public reverse-proxy domain has no route to port 8788.

**Step 5: Final review**

Review changed files for secret leakage, run `rg` for known test secrets and verify no raw Key is returned by any admin response. Report impact scope, verification commands and residual risks.

