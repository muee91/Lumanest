-- Legacy records do not contain enough information to reconstruct a request.
-- Leave their fingerprints NULL and reject their replay rather than guessing.
ALTER TABLE mission.mission_operations
  ADD COLUMN IF NOT EXISTS request_fingerprint TEXT
  CHECK (request_fingerprint IS NULL OR request_fingerprint ~ '^[a-f0-9]{64}$');

ALTER TABLE mission.mission_operations
  ADD COLUMN IF NOT EXISTS request_fingerprint_version SMALLINT
  CHECK (request_fingerprint_version IS NULL OR request_fingerprint_version = 1);
