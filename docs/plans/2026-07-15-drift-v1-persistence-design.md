# LumaNest V1 Drift persistence design

## Decision

Use one local Drift database as the durable store for user-owned structured data and offline caches. Migrate one state flow at a time so each change remains testable and reversible.

The implementation order is:

1. Database foundation, saved places, and the most recent route destination.
2. Profile and accessibility preferences.
3. Planned-route cache.
4. Context snapshot cache.

SharedPreferences remains appropriate for small consent flags and one-time migration markers. It must not remain the primary store for favorites, preferences, routes, or environment caches.

## Database boundary

`AppDatabase` owns the SQLite connection and is provided once through Riverpod. Production uses the application support directory; tests use an in-memory executor. Store interfaces stay unchanged so controllers and pages do not depend on Drift.

V1 tables use explicit columns for queryable user data:

- `saved_places`: stable ID, name, category, WGS84 latitude and longitude.
- `recent_route_destination`: singleton row, name, WGS84 destination, and travel mode.
- `profile_preferences`: singleton row with accessibility, ambient, AI, and recommendation fields.
- `route_cache`: request identity, route payload, source metadata, and expiry timestamps.
- `context_cache`: snapshot version, observed/expiry times, and validated snapshot payload.

Schema changes use Drift migrations and bump `schemaVersion`. Generated files are committed so normal Android builds do not require code generation.

## Compatibility and failure behavior

Each replacement store checks Drift first. If the new tables are empty, it reads the existing versioned SharedPreferences payload, validates it with the current decoder, writes it to Drift transactionally, and removes the legacy key only after the transaction succeeds. Malformed legacy data is ignored without crashing.

Writes are transactional. Controllers keep their existing public contracts. A failed database write must surface to the caller and must not delete the old migration source. No precise location history is added: only user-selected places, the latest destination, and bounded cache entries are stored.

## Verification

Each phase requires in-memory database round-trip tests, legacy-import tests, malformed-input tests, controller regression tests, formatting, `flutter analyze`, and the relevant Flutter test groups. Android database open/reopen and data-clearing behavior are verified on the wireless Mi 10 Pro before release.
