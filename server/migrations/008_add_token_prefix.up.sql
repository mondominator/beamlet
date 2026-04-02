ALTER TABLE users ADD COLUMN token_prefix TEXT;
CREATE INDEX idx_users_token_prefix ON users(token_prefix);

ALTER TABLE invites ADD COLUMN token_prefix TEXT;
CREATE INDEX idx_invites_token_prefix ON invites(token_prefix);
