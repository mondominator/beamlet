DROP INDEX IF EXISTS idx_users_token_prefix;
DROP INDEX IF EXISTS idx_invites_token_prefix;
ALTER TABLE users DROP COLUMN token_prefix;
ALTER TABLE invites DROP COLUMN token_prefix;
