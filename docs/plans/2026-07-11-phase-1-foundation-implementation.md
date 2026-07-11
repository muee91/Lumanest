# 栖光 Phase 1 Foundation Implementation Plan

> **For implementer:** Use TDD throughout. Write failing test first. Watch it fail. Then implement.

**Goal:** 建立可运行的「栖光」Flutter Android 首版骨架，具备稳定五导航、统一情境状态、按需动态槽位、设计令牌、环境背景基线和本地偏好设置。

**Architecture:** 客户端采用 feature-first 目录和单向状态流。`ContextSnapshot` 是页面动态内容的唯一事实输入，`UiManifest` 决定页面出现哪些组件；Flutter 页面不自行推断天气或场景。Phase 1 只使用本地 fixture，真实地图和天气放在 Phase 2。

**Tech Stack:** Flutter 3.44、Dart 3.12、Riverpod、go_router、Drift、flutter_test。

---

## Ownership and integration

- Root/Codex owns project scaffold, dependencies, context domain, UI manifest, router, navigation shell, integration and final review.
- Qoder CLI CN owns only `lib/src/design/**`, `lib/src/shared/widgets/ambient/**` and corresponding tests. It must not edit routing, domain models, generated platform files or `pubspec.yaml`.
- CodeBuddy owns only `lib/src/features/profile/**` and corresponding tests. It must not edit routing, design tokens, domain models, generated platform files or `pubspec.yaml`.
- Both delegated branches start from the scaffold commit and are integrated by cherry-pick only after tests and diff review.

## Task 1: Scaffold the Flutter application

**Files:**
- Generate: Flutter application files in repository root
- Preserve: `docs/plans/**`
- Modify: `pubspec.yaml`

**Step 1: Generate boilerplate**

Generated boilerplate is the explicit TDD exception. Run:

```bash
flutter create --project-name luma_nest --org com.muee --platforms android,ios .
```

Expected: Android application id is `com.muee.lumanest`; existing `docs/` remains intact.

**Step 2: Add foundation dependencies**

```bash
flutter pub add flutter_riverpod go_router drift sqlite3 path_provider path
flutter pub add --dev build_runner drift_dev
```

`sqlite3` 3.x uses Native Assets. Do not add the EOL `sqlite3_flutter_libs` package.

**Step 3: Verify generated baseline**

```bash
flutter test
flutter analyze
```

Expected: both commands pass before custom code starts.

**Step 4: Commit**

```bash
git add .
git commit -m "build: scaffold luma_nest flutter app"
```

## Task 2: Establish brand identity and app entry point

**Files:**
- Create: `lib/src/app/luma_nest_app.dart`
- Modify: `lib/main.dart`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Test: `test/app/luma_nest_app_test.dart`

**Step 1: Write the failing widget test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:luma_nest/src/app/luma_nest_app.dart';

void main() {
  testWidgets('shows the LumaNest brand and five destinations', (tester) async {
    await tester.pumpWidget(const LumaNestApp());

    expect(find.text('栖光'), findsOneWidget);
    expect(find.text('今日'), findsOneWidget);
    expect(find.text('探索'), findsOneWidget);
    expect(find.text('路线'), findsOneWidget);
    expect(find.text('灵感'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
  });
}
```

**Step 2: Verify RED**

```bash
flutter test test/app/luma_nest_app_test.dart
```

Expected: FAIL because `LumaNestApp` does not exist.

**Step 3: Implement the minimum app shell**

Create a temporary `MaterialApp` with an `AppBar(title: Text('栖光'))` and a five-item `NavigationBar`. Do not add page-specific functionality yet. Set Android `android:label` to `栖光`.

**Step 4: Verify GREEN**

```bash
flutter test test/app/luma_nest_app_test.dart
flutter test
```

Expected: PASS.

**Step 5: Commit**

```bash
git add lib android/app/src/main/AndroidManifest.xml test/app
git commit -m "feat: add luma_nest app identity and navigation shell"
```

## Task 3: Define the context domain and deterministic fixtures

**Files:**
- Create: `lib/src/core/context/context_snapshot.dart`
- Create: `lib/src/core/context/context_fixture.dart`
- Test: `test/core/context/context_snapshot_test.dart`

**Step 1: Write failing domain tests**

Tests must prove:

```dart
expect(ContextSnapshot.quietCity().primaryScene, SceneType.city);
expect(ContextSnapshot.quietCity().activeRoute, isFalse);
expect(ContextSnapshot.lakeSunset().opportunityIds, contains('reflection'));
expect(ContextSnapshot.mountainDawn().opportunityIds, contains('alpenglow'));
```

Each fixture is immutable and includes `id`, `observedAt`, `expiresAt`, `primaryScene`, `dayPhase`, `weather`, `activeRoute`, `opportunityIds`, `safetyEventIds`, and `wildlifeEventIds`.

**Step 2: Verify RED**

```bash
flutter test test/core/context/context_snapshot_test.dart
```

Expected: FAIL because the context types do not exist.

**Step 3: Implement minimal immutable value types**

Use Dart enums and `final` fields only. Do not add JSON serialization or API concerns in Phase 1.

**Step 4: Verify GREEN and commit**

```bash
flutter test test/core/context/context_snapshot_test.dart
flutter test
git add lib/src/core/context test/core/context
git commit -m "feat: add deterministic context snapshots"
```

## Task 4: Define the UI manifest and no-placeholder policy

**Files:**
- Create: `lib/src/core/manifest/ui_manifest.dart`
- Create: `lib/src/core/manifest/manifest_policy.dart`
- Test: `test/core/manifest/manifest_policy_test.dart`

**Step 1: Write failing policy tests**

Cover one behavior per test:

- Quiet city returns a summary and no dynamic opportunity cards.
- Lake sunset returns reflection as primary and at most two secondary cards.
- Mountain dawn returns alpenglow only when the fixture contains that opportunity.
- Safety events are emitted separately from creative cards.
- Empty dynamic lists remain empty; no placeholder component is emitted.

**Step 2: Verify RED**

```bash
flutter test test/core/manifest/manifest_policy_test.dart
```

Expected: FAIL because `ManifestPolicy` does not exist.

**Step 3: Implement minimal policy**

`ManifestPolicy.build(ContextSnapshot)` returns immutable `UiManifest` with `layoutMode`, `summary`, optional `primary`, `secondary`, `safety`, and `inspirationPreview`. Limit secondary items to two. Do not include networking, AI or rendering logic.

**Step 4: Verify GREEN and commit**

```bash
flutter test test/core/manifest/manifest_policy_test.dart
flutter test
git add lib/src/core/manifest test/core/manifest
git commit -m "feat: add context driven ui manifest policy"
```

## Task 5: Build the design foundation and ambient baseline — Qoder CLI CN

**Files:**
- Create: `lib/src/design/luma_nest_colors.dart`
- Create: `lib/src/design/luma_nest_spacing.dart`
- Create: `lib/src/design/luma_nest_theme.dart`
- Create: `lib/src/shared/widgets/ambient/ambient_canvas.dart`
- Test: `test/design/luma_nest_theme_test.dart`
- Test: `test/shared/widgets/ambient/ambient_canvas_test.dart`

**Step 1: Write failing tests**

Tests verify:

- Theme exposes readable light and dark color schemes.
- Primary foreground/background contrast is represented by distinct colors.
- `AmbientCanvas` renders a static, non-interactive environment color layer.
- `reduceMotion: true` produces no continuously ticking animation.

**Step 2: Verify RED, implement, and verify GREEN**

Use only Flutter SDK primitives. Phase 1 ambient output is a low-motion layered gradient, not a shader or weather animation. It must not intercept pointer events.

```bash
flutter test test/design test/shared/widgets/ambient
flutter analyze lib/src/design lib/src/shared/widgets/ambient
```

Expected: PASS.

**Step 3: Commit**

```bash
git add lib/src/design lib/src/shared/widgets/ambient test/design test/shared/widgets/ambient
git commit -m "feat: add luma_nest design foundation"
```

## Task 6: Build local profile preferences — CodeBuddy

**Files:**
- Create: `lib/src/features/profile/domain/profile_preferences.dart`
- Create: `lib/src/features/profile/application/profile_preferences_controller.dart`
- Create: `lib/src/features/profile/presentation/profile_page.dart`
- Test: `test/features/profile/profile_preferences_controller_test.dart`
- Test: `test/features/profile/profile_page_test.dart`

**Step 1: Write failing tests**

Tests verify:

- Defaults enable ambient background and disable reduced motion and reduced flashing.
- Toggling each accessibility preference returns an immutable new state.
- Profile page exposes switches for dynamic background, reduce motion, and reduce flashing.
- No empty groups for unavailable collections, routes or devices are rendered.

**Step 2: Verify RED, implement, and verify GREEN**

Use Riverpod `Notifier` with in-memory state only. Persistence is deferred until the Drift task in a later phase. Do not add fake collections or placeholder counts.

```bash
flutter test test/features/profile
flutter analyze lib/src/features/profile
```

Expected: PASS.

**Step 3: Commit**

```bash
git add lib/src/features/profile test/features/profile
git commit -m "feat: add local accessibility preferences"
```

## Task 7: Integrate the five-page router and dynamic Today page

**Files:**
- Create: `lib/src/app/router.dart`
- Create: `lib/src/app/app_shell.dart`
- Create: `lib/src/features/today/presentation/today_page.dart`
- Create: `lib/src/features/explore/presentation/explore_page.dart`
- Create: `lib/src/features/route/presentation/route_page.dart`
- Create: `lib/src/features/inspiration/presentation/inspiration_page.dart`
- Modify: `lib/src/app/luma_nest_app.dart`
- Test: `test/app/navigation_test.dart`
- Test: `test/features/today/today_page_test.dart`

**Step 1: Write failing navigation tests**

Verify every navigation item changes the visible page while the navigation bar remains mounted. Back navigation must preserve the active tab shell.

**Step 2: Write failing Today policy tests**

Verify:

- Quiet context renders summary and actions without dynamic card placeholders.
- Lake sunset renders one primary opportunity.
- Safety content uses a separate semantic region.
- Inspiration preview is compact and never contains safety text.

**Step 3: Verify RED**

```bash
flutter test test/app/navigation_test.dart test/features/today/today_page_test.dart
```

**Step 4: Implement minimal routed pages**

Use go_router `StatefulShellRoute.indexedStack`. Explore, Route and Inspiration pages are intentional Phase 1 shells with a title and one primary action only; do not add fake maps, fake route data or decorative cards. Profile uses the delegated real settings page.

**Step 5: Verify GREEN and commit**

```bash
flutter test
flutter analyze
git add lib test
git commit -m "feat: integrate context driven app shell"
```

## Task 8: Quality gate and Android build

**Files:**
- Modify only files required by verified failures

**Step 1: Run formatting check**

```bash
dart format --output=none --set-exit-if-changed lib test
```

Expected: exit 0.

**Step 2: Run all static and automated checks**

```bash
flutter analyze
flutter test
```

Expected: no analyzer issues; all tests pass.

**Step 3: Build Android debug APK**

```bash
flutter build apk --debug
```

Expected: `build/app/outputs/flutter-apk/app-debug.apk` exists.

**Step 4: Inspect repository scope**

```bash
git status --short
git diff main...HEAD --stat
```

Expected: only Phase 1 foundation, design docs and generated Flutter platform files are changed. No API keys, credentials, map SDK integration or fake production data.

**Step 5: Commit verified fixes if needed**

```bash
git add <verified-files>
git commit -m "test: verify phase one foundation"
```

## Phase 1 acceptance criteria

- Android debug APK builds with display name `栖光` and application id `com.muee.lumanest`.
- Five navigation destinations work and preserve shell state.
- Context fixtures deterministically produce UI manifests.
- Dynamic opportunity slots disappear without placeholder height when empty.
- Safety content is structurally separate from inspiration content.
- Design tokens and low-motion ambient baseline are reusable.
- Reduce-motion and reduce-flashing controls are testable.
- No real map, weather, wildlife or model integration is falsely represented in the UI.
