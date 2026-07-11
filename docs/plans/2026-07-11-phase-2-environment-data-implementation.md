# LumaNest Phase 2 Environment Data Implementation Plan

> **For implementer:** Use TDD throughout. Write failing test first. Watch it fail. Then implement.

**Goal:** Replace Phase 1 fixtures in normal runtime with real current-location, weather, solar-phase and map data while preserving explicit privacy consent, deterministic tests, offline fallback and the no-placeholder UI rule.

**Architecture:** WGS84 remains the canonical domain coordinate. `geolocator` provides current WGS84 readings, QWeather consumes those coordinates through a repository, and `nrel_spa` calculates solar phases locally. A Riverpod environment controller builds `ContextSnapshot`; UI consumes only the resulting async snapshot and `UiManifest`. `amap_map` is isolated behind the Explore feature and uses its native GCJ-02 location callback only for map presentation, never overwriting WGS84 domain data.

**Tech Stack:** Flutter 3.44, Dart 3.12, Riverpod 3, Dio, geolocator, nrel_spa, amap_map, Drift, flutter_test.

---

## Configuration and secret policy

- `AMAP_ANDROID_KEY`: injected with `--dart-define`; never committed.
- `QWEATHER_API_HOST`: the per-project API Host from QWeather Console; injected with `--dart-define`.
- `QWEATHER_TOKEN_ENDPOINT` and `LUMANEST_SERVICE_TOKEN`: injected with `--dart-define`; used only to obtain a short-lived JWT from the NAS broker; never logged or committed.
- Missing configuration is a typed `EnvironmentConfigMissing` state, not a crash.
- AMap SDK is not initialized until the user accepts the AMap/privacy disclosure.
- Current user permission and privacy consent are distinct: privacy consent first, OS location permission second.

## Delegated ownership

- Root/Codex owns dependencies, domain contracts, repositories, QWeather parsing, geolocation, solar calculation, orchestration, cache integration and final review.
- Qoder CLI CN owns only the visual async states, ambient visual mapping and Explore map/consent presentation files assigned below.
- CodeBuddy owns only environment diagnostics/settings presentation and cache-status presentation files assigned below.
- Delegated work uses manual Git worktrees; no Paseo.

## Task 1: Add Phase 2 dependencies and typed runtime configuration

**Files:**
- Modify: `pubspec.yaml`
- Create: `lib/src/core/config/environment_config.dart`
- Test: `test/core/config/environment_config_test.dart`

**RED:** Verify absent defines produce `isAmapConfigured == false` and `isQWeatherConfigured == false`; supplied constructor values trim trailing host slashes and report configured.

**GREEN:** Add `amap_map`, `geolocator`, `dio`, and `nrel_spa`. Implement an immutable config with `fromEnvironment()` reading `String.fromEnvironment`; do not expose secrets in `toString`.

**Verify:**

```bash
flutter test test/core/config/environment_config_test.dart
flutter analyze
```

**Commit:** `build: add environment data dependencies`

## Task 2: Define canonical location and weather contracts

**Files:**
- Create: `lib/src/core/location/geo_point.dart`
- Create: `lib/src/core/location/location_reading.dart`
- Create: `lib/src/core/location/location_repository.dart`
- Create: `lib/src/core/weather/weather_observation.dart`
- Create: `lib/src/core/weather/weather_repository.dart`
- Test: `test/core/location/geo_point_test.dart`
- Test: `test/core/weather/weather_observation_test.dart`

**RED:** Test coordinate range validation, WGS84 coordinate-system tagging, immutable timestamps, weather-code mapping and precipitation/wind/cloud fields.

**GREEN:** Keep repositories interface-only. `WeatherObservation` contains observed time, temperature, condition code, cloud cover when available, wind speed/direction/gust, visibility, precipitation and thunder flag. Unknown optional source fields remain nullable rather than fabricated.

**Verify:** `flutter test test/core/location test/core/weather`

**Commit:** `feat: add location and weather domain contracts`

## Task 3: Calculate local solar phase

**Files:**
- Create: `lib/src/core/solar/solar_service.dart`
- Create: `lib/src/infrastructure/solar/nrel_solar_service.dart`
- Test: `test/infrastructure/solar/nrel_solar_service_test.dart`

**RED:** Use fixed Shanghai and western-China coordinates/dates. Assert sunrise precedes sunset, solar azimuth is within 0–360, and `DayPhase` changes between dawn/day/sunset/night without network access.

**GREEN:** Wrap `nrel_spa` behind `SolarService`. Return solar elevation, azimuth, sunrise, sunset and derived Phase 1 `DayPhase`. Tests use tolerances and never assert a single exact floating-point degree.

**Verify:** `flutter test test/infrastructure/solar`

**Commit:** `feat: add deterministic solar phase calculation`

## Task 4: Implement QWeather current-condition adapter

**Files:**
- Create: `lib/src/infrastructure/weather/qweather_client.dart`
- Create: `lib/src/infrastructure/weather/qweather_repository.dart`
- Test: `test/infrastructure/weather/qweather_repository_test.dart`

**RED:** With Dio `MockAdapter` or a minimal fake transport, verify broker JWT request, weather request path `/v7/weather/now`, `location=longitude,latitude`, `Authorization: Bearer` header, successful parsing, API-code failure, malformed body and timeout mapping.

**GREEN:** Never log headers or complete request URLs. Obtain a short-lived JWT from the NAS broker before calling QWeather, then map QWeather `now` fields to `WeatherObservation`; missing cloud/gust fields remain null. Throw typed repository failures carrying safe user-readable categories, not raw credentials or response bodies.

**Verify:** `flutter test test/infrastructure/weather`

**Commit:** `feat: add qweather current conditions adapter`

## Task 5: Implement current-location adapter and permissions

**Files:**
- Create: `lib/src/infrastructure/location/geolocator_repository.dart`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `ios/Runner/Info.plist`
- Test: `test/infrastructure/location/geolocator_repository_test.dart`

**RED:** Through an injected platform gateway, test service-disabled, permission-denied, permission-denied-forever and successful WGS84 reading. No test invokes the real platform channel.

**GREEN:** Request foreground location only; do not add background-location permission. Add Android coarse/fine permissions and a clear iOS when-in-use explanation. Convert platform exceptions into typed location failures.

**Verify:** `flutter test test/infrastructure/location`

**Commit:** `feat: add foreground location repository`

## Task 6: Build the environment orchestrator and offline cache

**Files:**
- Create: `lib/src/core/context/environment_controller.dart`
- Create: `lib/src/core/context/environment_providers.dart`
- Create: `lib/src/core/context/context_snapshot_builder.dart`
- Create: `lib/src/core/context/context_cache.dart`
- Test: `test/core/context/context_snapshot_builder_test.dart`
- Test: `test/core/context/environment_controller_test.dart`

**RED:** Test the sequence location → weather + solar → snapshot, refresh deduplication, missing-config state, retry, partial weather failure, and cached snapshot fallback with stale timestamp retained.

**GREEN:** Implement an `AsyncNotifier<ContextSnapshot>`. Do not call the network on every rebuild. Cache the latest successful snapshot through a narrow `ContextCache` interface; use an in-memory implementation in Phase 2 unless a Drift table is required by an acceptance test. A fallback snapshot is marked stale and cannot generate high-confidence weather opportunities.

**Verify:** `flutter test test/core/context`

**Commit:** `feat: orchestrate live environment snapshots`

## Task 7: Connect Today and ambient visuals to async environment state — Qoder CLI CN

**Files:**
- Modify: `lib/src/features/today/presentation/today_page.dart`
- Modify: `lib/src/shared/widgets/ambient/ambient_canvas.dart`
- Create: `lib/src/shared/widgets/ambient/ambient_visual_mapper.dart`
- Test: `test/features/today/today_page_test.dart`
- Test: `test/shared/widgets/ambient/ambient_visual_mapper_test.dart`

**RED:** Test loading, permission/config error, stale-cache label, live manifest, retry action and weather-to-visual mapping for clear/cloud/rain/thunder. Ensure empty opportunities still occupy no height.

**GREEN:** Today consumes an injected `AsyncValue<ContextSnapshot>`/manifest provider. Ambient mapping changes palette and motion parameters deterministically; no rain particles or shader in this task. Safety content remains independent.

**Verify:** `flutter test test/features/today test/shared/widgets/ambient`

**Commit:** `feat: connect live environment presentation`

## Task 8: Add AMap privacy gate and Explore map — Qoder CLI CN

**Files:**
- Create: `lib/src/features/explore/application/map_consent_controller.dart`
- Create: `lib/src/features/explore/infrastructure/amap_initializer.dart`
- Modify: `lib/src/features/explore/presentation/explore_page.dart`
- Test: `test/features/explore/map_consent_controller_test.dart`
- Test: `test/features/explore/explore_page_test.dart`

**RED:** Test that no `AMapWidget` is built before explicit consent, missing key shows a configuration state, consent initializes privacy flags before SDK initialization, and accepted/configured state builds the map.

**GREEN:** Use `AMapInitializer.updatePrivacyAgree` before `AMapInitializer.init`. Keep API key in `EnvironmentConfig`. The map uses the plugin's native location display/callback for GCJ-02 presentation only. Do not convert or persist it into WGS84 domain state.

**Verify:** `flutter test test/features/explore`

**Commit:** `feat: add consent gated amap explore page`

## Task 9: Add environment diagnostics and user recovery — CodeBuddy

**Files:**
- Create: `lib/src/features/profile/presentation/environment_diagnostics.dart`
- Modify: `lib/src/features/profile/presentation/profile_page.dart`
- Test: `test/features/profile/environment_diagnostics_test.dart`
- Test: `test/features/profile/profile_page_test.dart`

**RED:** Test concise states for missing AMap config, missing QWeather config, denied permission, stale cache and fully operational environment. Never render a key value.

**GREEN:** Diagnostics appear only when a problem or stale fallback exists; a healthy system does not reserve space. Actions route to retry, OS settings or privacy consent as appropriate.

**Verify:** `flutter test test/features/profile`

**Commit:** `feat: add environment recovery diagnostics`

## Task 10: Integration, credential reminder and live verification

**Files:**
- Modify only verified integration failures
- Create: `docs/setup/environment-credentials.md`

**Steps:**

1. Document how to create the AMap Android key for package `com.muee.lumanest` and the debug SHA1, plus QWeather API Host/API Key.
2. Verify no secret patterns are tracked with `git grep`.
3. Without keys: test config-missing UI, fixture-independent tests, analyze and APK build.
4. Ask the user for keys only at this point. Provide commands using `--dart-define`, never request that keys be pasted into a tracked file.
5. With keys: run on an Android device/emulator, grant consent and location, verify real location, weather observation time, solar phase and map rendering.

**Verify:**

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug
```

**Commit:** `test: verify phase two environment data`

## Phase 2 acceptance criteria

- Normal runtime no longer depends on `ContextFixtures`; fixtures remain test-only.
- Missing keys, denied permission, disabled location, network errors and stale cache each have distinct recoverable UI states.
- WGS84 domain coordinates are never overwritten by GCJ-02 map coordinates.
- QWeather secrets never appear in logs, exceptions, source, tests or Git history.
- AMap is never initialized before explicit privacy consent.
- Today and ambient visuals respond to real weather/solar data without introducing empty placeholders.
- Android APK builds without keys and can perform live verification when keys are injected.
