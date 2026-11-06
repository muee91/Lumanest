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
CREATE SCHEMA IF NOT EXISTS mission AUTHORIZATION mission_migrator;
```

Run `node scripts/migrate-mission.mjs` with
`MISSION_MIGRATION_DATABASE_URL` using `mission_migrator`. After the migration
has completed, grant the long-running roles only the schema and table access
they need:

The migrator records applied versions in `mission.schema_migrations` and runs
under an advisory transaction lock. Upgrade an existing database with the same
command after backing it up. Operations recorded before the request-fingerprint
migration have no verifiable request body and are rejected on replay; clients
can query `GET /v1/mission-operations` with the device session and the original
`Idempotency-Key` to find the associated Mission, then read its current state.
The result is only evidence of the operation's historical association; it does
not authenticate the original request body. If the Mission or its destination
cannot be matched safely, the client leaves the operation unresolved.
Do not enable the Mission Worker for legacy watches until their consent has
been reviewed and the server-side authorization migration is available.

```sql
GRANT USAGE ON SCHEMA mission TO mission_api, mission_worker;
GRANT SELECT, INSERT, UPDATE ON mission.device_bindings TO mission_api;
GRANT SELECT, INSERT, UPDATE ON mission.missions TO mission_api, mission_worker;
GRANT SELECT, INSERT ON mission.mission_operations TO mission_api;
GRANT SELECT, INSERT ON mission.watch_authorization_audit TO mission_api;
GRANT SELECT, INSERT ON mission.mission_events, mission.mission_checks TO mission_worker;
GRANT SELECT ON mission.mission_events TO mission_api;
GRANT SELECT ON mission.schema_migrations TO mission_api, mission_worker;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA mission TO mission_worker;
```

The Broker receives `MISSION_DATABASE_URL` and the Worker receives
`MISSION_WORKER_DATABASE_URL`; neither receives the migration URL. The Worker
also needs `MISSION_WORKER_TOKEN`, which is accepted only on the private
`/internal/v1/mission/check` route. After the migration and role grants are
complete, set the three runtime values below. `scripts/nas-deploy.sh` detects
that complete set on Ubuntu/NAS and automatically enables the Compose
`mission` profile for the release and rollback source (including the rollback
script). If any value is absent,
the profile remains disabled and no Worker is started. For a manual Compose
operation, pass `--profile mission` explicitly:

```text
MISSION_DATABASE_URL=postgresql://mission_api:<api-password>@postgres/lumanest
MISSION_WORKER_DATABASE_URL=postgresql://mission_worker:<worker-password>@postgres/lumanest
MISSION_MIGRATION_DATABASE_URL=postgresql://mission_migrator:<migration-password>@postgres/lumanest
MISSION_WORKER_TOKEN=<random-private-token>
```

```sh
docker compose --profile mission up -d --build
```

The Ubuntu/NAS deployment script runs a read-only preflight inside the built
Broker and Worker images before stopping the old stack. It checks that all four
migration ledger entries are present and that each restricted runtime role has
the table privileges listed above. A failed preflight aborts the deployment;
credentials alone do not enable the Worker.

The database enforces one open Mission per device subject, optimistic version
checks, idempotent operations, leased checks, and event deduplication. A
cancelled or watch-disabled Mission is revalidated before a Worker commits any
event. If the database URL is absent, the App returns `mission_unconfigured`
and the default Compose profile does not start the Worker.

Device revocation is a two-part operation. The admin API blocks the local
installation immediately, then revokes the persistent `device_bindings` row and
disables open Missions in one Mission transaction. If that transaction fails,
the local registry stores a `mission_revocation_pending` obligation in
`session-installations.json`; the Broker retries it at startup and on a timer.
The admin response remains `503` until PostgreSQL confirms the revoke, and the
Worker continues to use the database binding as its final execution gate.
