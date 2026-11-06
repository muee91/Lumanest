ALTER TABLE mission.missions
  ADD COLUMN IF NOT EXISTS watch_consent_version SMALLINT,
  ADD COLUMN IF NOT EXISTS watch_consented_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS mission.watch_authorization_audit (
  id TEXT PRIMARY KEY,
  mission_id TEXT NOT NULL REFERENCES mission.missions(id) ON DELETE CASCADE,
  action TEXT NOT NULL CHECK (action IN ('legacy_suspended', 'authorized', 'disabled', 'device_revoked')),
  created_at TIMESTAMPTZ NOT NULL
);

INSERT INTO mission.watch_authorization_audit (id, mission_id, action, created_at)
SELECT 'legacy-' || id, id, 'legacy_suspended', clock_timestamp()
  FROM mission.missions WHERE watch_enabled = TRUE
ON CONFLICT (id) DO NOTHING;

UPDATE mission.missions
   SET watch_enabled = FALSE, next_check_at = NULL, lease_owner = NULL,
       lease_until = NULL, version = version + 1, updated_at = clock_timestamp()
 WHERE watch_enabled = TRUE;

ALTER TABLE mission.missions
  ADD CONSTRAINT mission_watch_requires_consent CHECK (
    NOT watch_enabled OR ((watch_consent_version = 1) IS TRUE AND watch_consented_at IS NOT NULL)
  );
