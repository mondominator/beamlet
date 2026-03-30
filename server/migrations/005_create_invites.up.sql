CREATE TABLE invites (
    id TEXT PRIMARY KEY,
    token_hash TEXT NOT NULL,
    creator_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_user_id TEXT REFERENCES users(id) ON DELETE SET NULL,
    redeemed_by TEXT REFERENCES users(id) ON DELETE SET NULL,
    expires_at TIMESTAMP NOT NULL,
    redeemed_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_invites_creator_id ON invites(creator_id);
CREATE INDEX idx_invites_expires_at ON invites(expires_at);
