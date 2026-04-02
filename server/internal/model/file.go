package model

import "time"

type File struct {
	ID            string    `json:"id"`
	SenderID      string    `json:"sender_id"`
	RecipientID   string    `json:"recipient_id"`
	Filename      string    `json:"filename"`
	FilePath      string    `json:"-"`
	ThumbnailPath string    `json:"-"`
	FileType      string    `json:"file_type"`
	FileSize      int64     `json:"file_size"`
	ContentType   string    `json:"content_type"`
	TextContent   string    `json:"text_content,omitempty"`
	Message       string    `json:"message,omitempty"`
	Read          bool      `json:"read"`
	Pinned        bool      `json:"pinned"`
	ExpiresAt     time.Time `json:"expires_at"`
	CreatedAt     time.Time `json:"created_at"`
	SenderName    string    `json:"sender_name,omitempty"`
	RecipientName string    `json:"recipient_name,omitempty"`
}
