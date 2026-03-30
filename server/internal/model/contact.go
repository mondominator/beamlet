package model

import "time"

type Contact struct {
	UserID    string    `json:"user_id"`
	ContactID string    `json:"contact_id"`
	CreatedAt time.Time `json:"created_at"`
}

type ContactUser struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	CreatedAt time.Time `json:"created_at"`
}
