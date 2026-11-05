# Mission Engine deployment contract

Mission is an optional server-side mirror of the one local `TripTask`. The
Broker is the App API boundary, PostgreSQL in the `mission` schema is the
source of truth, and the standalone `mission-worker` performs scheduled
Context V5 checks. Remote push is deliberately not part of this contract:
events are persisted with `deliveryState: not_sent` until a notification
transport is separately implemented.

The App keeps `ownerSecret` in Android Keystore or iOS Keychain through
`flutter_secure_storage`. Existing preferences values are migrated once; a
secure-store read or write failure refuses bootstrap instead of silently
rotating the device identity. The `device_bindings` table anchors the session
binding hash independently of the expiring installation registry.
Existing Mission owners without a database binding are refused access until an
operator backfills their verified binding from the private installation
registry. This prevents the first post-upgrade request from claiming an older
Mission. Session bootstrap must use HTTPS.

The database must use separate credentials. Run the role setup once as a
PostgreSQL administrator, replacing the placeholders outside source control:

```sql
CREATE ROLE mission_migrator LOGIN PASSWORD '<migration-password>';
CREATE ROLE mission_api LOGIN PASSWORD '<api-password>';
CREATE ROLE mission_worker LOGIN PASSWORD '<worker-password>';
GRANT CONNECT ON DATABASE lumanest TO mission_migrator, mission_api, mission_worker;
```

Run `node scripts/migrate-mission.mjs` with
`MISSION_MIGRATION_DATABASE_URL` using `mission_migrator`. After the migration
has completed, grant the long-running roles only the schema and table access
they need:

```sql
GRANT USAGE ON SCHEMA mission TO mission_api, mission_worker;
GRANT SELECT, INSERT, UPDATE ON mission.device_bindings TO mission_api;
GRANT SELECT, INSERT, UPDATE ON mission.missions TO mission_api, mission_worker;
GRANT SELECT, INSERT ON mission.mission_operations TO mission_api;
GRANT SELECT, INSERT ON mission.mission_events, mission.mission_checks TO mission_worker;
GRANT SELECT ON mission.mission_events TO mission_api;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA mission TO mission_worker;
```

The Broker receives `MISSION_DATABASE_URL` and the Worker receives
`MISSION_WORKER_DATABASE_URL`; neither receives the migration URL. The Worker
also needs `MISSION_WORKER_TOKEN`, which is accepted only on the private
`/internal/v1/mission/check` route. Enable the Compose `mission` profile after
the migration and role grants are complete:

```text
MISSION_DATABASE_URL=postgresql://mission_api:<api-password>@postgres/lumanest
MISSION_WORKER_DATABASE_URL=postgresql://mission_worker:<worker-password>@postgres/lumanest
MISSION_MIGRATION_DATABASE_URL=postgresql://mission_migrator:<migration-password>@postgres/lumanest
MISSION_WORKER_TOKEN=<random-private-token>
```

The database enforces one open Mission per device subject, optimistic version
checks, idempotent operations, leased checks, and event deduplication. A
cancelled or watch-disabled Mission is revalidated before a Worker commits any
event. If the database URL is absent, the App returns `mission_unconfigured`
and the default Compose profile does not start the Worker.
