package store

import (
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/mondominator/beamlet/server/internal/model"
	"golang.org/x/crypto/bcrypt"
)

type InviteStore struct {
	db *sql.DB
}

func NewInviteStore(db *sql.DB) *InviteStore {
	return &InviteStore{db: db}
}

func (s *InviteStore) Create(creatorID, createdUserID string, ttl time.Duration) (*model.Invite, string, error) {
	tokenBytes := make([]byte, 16)
	if _, err := rand.Read(tokenBytes); err != nil {
		return nil, "", fmt.Errorf("generate token: %w", err)
	}
	token := hex.EncodeToString(tokenBytes)

	hash, err := bcrypt.GenerateFromPassword([]byte(token), bcrypt.DefaultCost)
	if err != nil {
		return nil, "", fmt.Errorf("hash token: %w", err)
	}

	invite := &model.Invite{
		ID:        uuid.New().String(),
		TokenHash: string(hash),
		CreatorID: creatorID,
		ExpiresAt: time.Now().UTC().Add(ttl),
		CreatedAt: time.Now().UTC(),
	}

	if createdUserID != "" {
		invite.CreatedUserID = sql.NullString{String: createdUserID, Valid: true}
	}

	_, err = s.db.Exec(
		`INSERT INTO invites (id, token_hash, creator_id, created_user_id, expires_at, created_at)
		 VALUES (?, ?, ?, ?, ?, ?)`,
		invite.ID, invite.TokenHash, invite.CreatorID,
		invite.CreatedUserID, invite.ExpiresAt, invite.CreatedAt,
	)
	if err != nil {
		return nil, "", fmt.Errorf("insert invite: %w", err)
	}

	return invite, token, nil
}

func (s *InviteStore) FindByToken(token string) (*model.Invite, error) {
	rows, err := s.db.Query(
		`SELECT id, token_hash, creator_id, created_user_id, redeemed_by, expires_at, redeemed_at, created_at
		 FROM invites
		 WHERE redeemed_at IS NULL AND expires_at > ?`,
		time.Now().UTC(),
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	for rows.Next() {
		var inv model.Invite
		if err := rows.Scan(
			&inv.ID, &inv.TokenHash, &inv.CreatorID, &inv.CreatedUserID,
			&inv.RedeemedBy, &inv.ExpiresAt, &inv.RedeemedAt, &inv.CreatedAt,
		); err != nil {
			return nil, err
		}
		if bcrypt.CompareHashAndPassword([]byte(inv.TokenHash), []byte(token)) == nil {
			return &inv, nil
		}
	}

	return nil, fmt.Errorf("invite not found or expired")
}

func (s *InviteStore) Redeem(inviteID, redeemedByID string) error {
	_, err := s.db.Exec(
		`UPDATE invites SET redeemed_by = ?, redeemed_at = ? WHERE id = ?`,
		redeemedByID, time.Now().UTC(), inviteID,
	)
	return err
}
