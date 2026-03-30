package model

import (
	"database/sql"
	"time"
)

type Invite struct {
	ID            string         `json:"id"`
	TokenHash     string         `json:"-"`
	CreatorID     string         `json:"creator_id"`
	CreatedUserID sql.NullString `json:"-"`
	RedeemedBy    sql.NullString `json:"-"`
	ExpiresAt     time.Time      `json:"expires_at"`
	RedeemedAt    sql.NullTime   `json:"-"`
	CreatedAt     time.Time      `json:"created_at"`
}

func (i *Invite) IsExpired() bool {
	return time.Now().UTC().After(i.ExpiresAt)
}

func (i *Invite) IsRedeemed() bool {
	return i.RedeemedAt.Valid
}
