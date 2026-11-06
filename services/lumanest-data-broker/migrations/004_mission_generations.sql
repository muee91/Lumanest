ALTER TABLE mission.missions
  ADD COLUMN IF NOT EXISTS watch_intent_revision BIGINT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS watch_authorization_epoch BIGINT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS lease_epoch BIGINT NOT NULL DEFAULT 0;

UPDATE mission.missions
   SET lease_owner = NULL, lease_until = NULL
 WHERE lease_owner IS NOT NULL OR lease_until IS NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'mission_lease_epoch_nonnegative'
  ) THEN
    ALTER TABLE mission.missions
      ADD CONSTRAINT mission_lease_epoch_nonnegative CHECK (lease_epoch >= 0);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'mission_watch_revision_json_safe'
  ) THEN
    ALTER TABLE mission.missions
      ADD CONSTRAINT mission_watch_revision_json_safe CHECK (
        watch_intent_revision <= 9007199254740991 AND
        watch_authorization_epoch <= 9007199254740991
      );
  END IF;
END $$;
