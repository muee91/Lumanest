-- Expired Mission watches are auditable runtime state changes, not silent skips.
ALTER TABLE mission.watch_authorization_audit
  DROP CONSTRAINT IF EXISTS watch_authorization_audit_action_check;

ALTER TABLE mission.watch_authorization_audit
  ADD CONSTRAINT watch_authorization_audit_action_check CHECK (
    action IN ('legacy_suspended', 'authorized', 'disabled', 'device_revoked', 'expired')
  );
