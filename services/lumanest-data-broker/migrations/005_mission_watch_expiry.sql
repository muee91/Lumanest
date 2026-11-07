-- Expired Mission watches are auditable runtime state changes, not silent skips.
ALTER TABLE mission.watch_authorization_audit
  DROP CONSTRAINT IF EXISTS watch_authorization_audit_action_check;

ALTER TABLE mission.watch_authorization_audit
  ADD CONSTRAINT watch_authorization_audit_action_check CHECK (
    action IN ('legacy_suspended', 'authorized', 'disabled', 'device_revoked', 'expired')
  );

-- A pre-005 authorized watch with no deadline must not survive the upgrade as
-- an unbounded background job. Stop it atomically and leave an audit trail.
WITH legacy_watches AS (
  UPDATE mission.missions
     SET watch_enabled = FALSE,
         watch_consent_version = NULL,
         watch_consented_at = NULL,
         next_check_at = NULL,
         lease_owner = NULL,
         lease_until = NULL,
         version = version + 1,
         updated_at = clock_timestamp()
   WHERE state IN ('planning', 'enRoute', 'field')
     AND watch_enabled = TRUE
     AND ends_at IS NULL
   RETURNING id, updated_at
)
INSERT INTO mission.watch_authorization_audit (id, mission_id, action, created_at)
SELECT 'expire-legacy-' || id, id, 'expired', updated_at
  FROM legacy_watches
ON CONFLICT (id) DO NOTHING;
