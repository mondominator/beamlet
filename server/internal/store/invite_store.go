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

	prefix := token[:8]
	_, err = s.db.Exec(
		`INSERT INTO invites (id, token_hash, token_prefix, creator_id, created_user_id, expires_at, created_at)
		 VALUES (?, ?, ?, ?, ?, ?, ?)`,
		invite.ID, invite.TokenHash, prefix, invite.CreatorID,
		invite.CreatedUserID, invite.ExpiresAt, invite.CreatedAt,
	)
	if err != nil {
		return nil, "", fmt.Errorf("insert invite: %w", err)
	}

	return invite, token, nil
}

func (s *InviteStore) FindByToken(token string) (*model.Invite, error) {
	if len(token) < 8 {
		return nil, fmt.Errorf("invite not found or expired")
	}
	prefix := token[:8]
	now := time.Now().UTC()

	// Fast path: lookup by prefix (handles collisions by iterating all matches)
	rows, err := s.db.Query(
		`SELECT id, token_hash, creator_id, created_user_id, redeemed_by, expires_at, redeemed_at, created_at
		 FROM invites
		 WHERE token_prefix = ? AND redeemed_at IS NULL AND expires_at > ?`,
		prefix, now,
	)
	if err == nil {
		for rows.Next() {
			var inv model.Invite
			if err := rows.Scan(
				&inv.ID, &inv.TokenHash, &inv.CreatorID, &inv.CreatedUserID,
				&inv.RedeemedBy, &inv.ExpiresAt, &inv.RedeemedAt, &inv.CreatedAt,
			); err != nil {
				continue
			}
			if bcrypt.CompareHashAndPassword([]byte(inv.TokenHash), []byte(token)) == nil {
				rows.Close()
				return &inv, nil
			}
		}
		rows.Close()
	}

	// Fallback: scan invites without prefix (pre-migration rows)
	rows, err = s.db.Query(
		`SELECT id, token_hash, creator_id, created_user_id, redeemed_by, expires_at, redeemed_at, created_at
		 FROM invites
		 WHERE token_prefix IS NULL AND redeemed_at IS NULL AND expires_at > ?`,
		now,
	)
	if err != nil {
		return nil, fmt.Errorf("invite not found or expired")
	}
	defer rows.Close()
	for rows.Next() {
		var candidate model.Invite
		if err := rows.Scan(
			&candidate.ID, &candidate.TokenHash, &candidate.CreatorID, &candidate.CreatedUserID,
			&candidate.RedeemedBy, &candidate.ExpiresAt, &candidate.RedeemedAt, &candidate.CreatedAt,
		); err != nil {
			continue
		}
		if bcrypt.CompareHashAndPassword([]byte(candidate.TokenHash), []byte(token)) == nil {
			// Backfill prefix
			s.db.Exec("UPDATE invites SET token_prefix = ? WHERE id = ?", prefix, candidate.ID)
			return &candidate, nil
		}
	}
	return nil, fmt.Errorf("invite not found or expired")
}

func (s *InviteStore) DeleteExpired() (int, error) {
	result, err := s.db.Exec(
		`DELETE FROM invites WHERE (redeemed_at IS NOT NULL AND redeemed_at < ?) OR (expires_at < ?)`,
		time.Now().UTC().Add(-7*24*time.Hour),
		time.Now().UTC().Add(-7*24*time.Hour),
	)
	if err != nil {
		return 0, err
	}
	n, _ := result.RowsAffected()
	return int(n), nil
}

func (s *InviteStore) Redeem(inviteID, redeemedByID string) error {
	_, err := s.db.Exec(
		`UPDATE invites SET redeemed_by = ?, redeemed_at = ? WHERE id = ?`,
		redeemedByID, time.Now().UTC(), inviteID,
	)
	return err
}
