package model

import "time"

type User struct {
	ID              string    `json:"id"`
	Name            string    `json:"name"`
	TokenHash       string    `json:"-"`
	Discoverability string    `json:"discoverability"`
	CreatedAt       time.Time `json:"created_at"`
}

// Valid discoverability values.
const (
	DiscoverabilityOff          = "off"
	DiscoverabilityContactsOnly = "contactsOnly"
	DiscoverabilityEveryone     = "everyone"
)

// IsValidDiscoverability checks whether a discoverability value is recognized.
func IsValidDiscoverability(v string) bool {
	return v == DiscoverabilityOff || v == DiscoverabilityContactsOnly || v == DiscoverabilityEveryone
}

type Device struct {
	ID        string    `json:"id"`
	UserID    string    `json:"user_id"`
	APNsToken string    `json:"apns_token"`
	Platform  string    `json:"platform"`
	Active    bool      `json:"active"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}
