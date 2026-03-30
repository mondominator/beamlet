CREATE TABLE files (
    id TEXT PRIMARY KEY,
    sender_id TEXT NOT NULL REFERENCES users(id),
    recipient_id TEXT NOT NULL REFERENCES users(id),
    filename TEXT NOT NULL,
    file_path TEXT,
    thumbnail_path TEXT,
    file_type TEXT NOT NULL,
    file_size INTEGER NOT NULL DEFAULT 0,
    content_type TEXT NOT NULL DEFAULT 'file',
    text_content TEXT,
    message TEXT,
    read INTEGER NOT NULL DEFAULT 0,
    expires_at TIMESTAMP NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_files_recipient_id ON files(recipient_id);
CREATE INDEX idx_files_expires_at ON files(expires_at);
