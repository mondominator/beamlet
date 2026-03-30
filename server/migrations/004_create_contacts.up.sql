CREATE TABLE contacts (
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    contact_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, contact_id)
);

CREATE INDEX idx_contacts_user_id ON contacts(user_id);

-- Migrate existing users: create contacts between all pairs
INSERT INTO contacts (user_id, contact_id)
SELECT a.id, b.id FROM users a, users b WHERE a.id != b.id;
