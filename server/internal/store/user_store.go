package store

import (
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/mondominator/beamlet/server/internal/model"
	"golang.org/x/crypto/bcrypt"
)

var errAuthFailed = errors.New("authentication failed")

type UserStore struct {
	db *sql.DB
}

func NewUserStore(db *sql.DB) *UserStore {
	return &UserStore{db: db}
}

func (s *UserStore) Create(name string) (*model.User, string, error) {
	id := uuid.New().String()
	token := generateToken()
	hash, err := bcrypt.GenerateFromPassword([]byte(token), bcrypt.DefaultCost)
	if err != nil {
		return nil, "", fmt.Errorf("hash token: %w", err)
	}

	prefix := token[:8]
	now := time.Now().UTC()
	_, err = s.db.Exec(
		"INSERT INTO users (id, name, token_hash, token_prefix, discoverability, created_at) VALUES (?, ?, ?, ?, ?, ?)",
		id, name, string(hash), prefix, model.DiscoverabilityContactsOnly, now,
	)
	if err != nil {
		return nil, "", fmt.Errorf("insert user: %w", err)
	}

	user := &model.User{
		ID:              id,
		Name:            name,
		TokenHash:       string(hash),
		Discoverability: model.DiscoverabilityContactsOnly,
		CreatedAt:       now,
	}
	return user, token, nil
}

func (s *UserStore) GetByID(id string) (*model.User, error) {
	var u model.User
	err := s.db.QueryRow(
		"SELECT id, name, token_hash, COALESCE(discoverability, 'contactsOnly'), created_at FROM users WHERE id = ?", id,
	).Scan(&u.ID, &u.Name, &u.TokenHash, &u.Discoverability, &u.CreatedAt)
	if err != nil {
		return nil, fmt.Errorf("get user: %w", err)
	}
	return &u, nil
}

func (s *UserStore) Authenticate(token string) (*model.User, error) {
	if len(token) < 8 {
		return nil, errAuthFailed
	}
	prefix := token[:8]

	// Fast path: lookup by prefix (handles collisions by iterating all matches)
	rows, err := s.db.Query(
		"SELECT id, name, token_hash, COALESCE(discoverability, 'contactsOnly'), created_at FROM users WHERE token_prefix = ?", prefix,
	)
	if err == nil {
		for rows.Next() {
			var u model.User
			if err := rows.Scan(&u.ID, &u.Name, &u.TokenHash, &u.Discoverability, &u.CreatedAt); err != nil {
				continue
			}
			if bcrypt.CompareHashAndPassword([]byte(u.TokenHash), []byte(token)) == nil {
				rows.Close()
				return &u, nil
			}
		}
		if err := rows.Err(); err != nil {
			rows.Close()
			return nil, errAuthFailed
		}
		rows.Close()
	}

	// Fallback: scan for users without token_prefix (pre-migration rows)
	rows, err = s.db.Query(
		"SELECT id, name, token_hash, COALESCE(discoverability, 'contactsOnly'), created_at FROM users WHERE token_prefix IS NULL",
	)
	if err != nil {
		return nil, errAuthFailed
	}
	defer rows.Close()
	for rows.Next() {
		var candidate model.User
		if err := rows.Scan(&candidate.ID, &candidate.Name, &candidate.TokenHash, &candidate.Discoverability, &candidate.CreatedAt); err != nil {
			continue
		}
		if bcrypt.CompareHashAndPassword([]byte(candidate.TokenHash), []byte(token)) == nil {
			// Backfill the prefix for future fast lookups
			s.db.Exec("UPDATE users SET token_prefix = ? WHERE id = ?", prefix, candidate.ID)
			return &candidate, nil
		}
	}
	return nil, errAuthFailed
}

func (s *UserStore) List() ([]model.User, error) {
	rows, err := s.db.Query("SELECT id, name, created_at FROM users ORDER BY name")
	if err != nil {
		return nil, fmt.Errorf("query users: %w", err)
	}
	defer rows.Close()

	var users []model.User
	for rows.Next() {
		var u model.User
		if err := rows.Scan(&u.ID, &u.Name, &u.CreatedAt); err != nil {
			return nil, fmt.Errorf("scan user: %w", err)
		}
		users = append(users, u)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate users: %w", err)
	}
	return users, nil
}

func (s *UserStore) Delete(userID string) error {
	result, err := s.db.Exec("DELETE FROM users WHERE id = ?", userID)
	if err != nil {
		return fmt.Errorf("delete user: %w", err)
	}
	rows, _ := result.RowsAffected()
	if rows == 0 {
		return fmt.Errorf("user not found: %s", userID)
	}
	return nil
}

func (s *UserStore) RevokeToken(userID string) (string, error) {
	token := generateToken()
	hash, err := bcrypt.GenerateFromPassword([]byte(token), bcrypt.DefaultCost)
	if err != nil {
		return "", fmt.Errorf("hash token: %w", err)
	}

	prefix := token[:8]
	result, err := s.db.Exec("UPDATE users SET token_hash = ?, token_prefix = ? WHERE id = ?", string(hash), prefix, userID)
	if err != nil {
		return "", fmt.Errorf("update token: %w", err)
	}
	rows, _ := result.RowsAffected()
	if rows == 0 {
		return "", fmt.Errorf("user not found: %s", userID)
	}
	return token, nil
}

func (s *UserStore) GetDiscoverability(userID string) (string, error) {
	var disc string
	err := s.db.QueryRow(
		"SELECT COALESCE(discoverability, 'contactsOnly') FROM users WHERE id = ?", userID,
	).Scan(&disc)
	if err != nil {
		return "", fmt.Errorf("get discoverability: %w", err)
	}
	return disc, nil
}

func (s *UserStore) UpdateDiscoverability(userID, value string) error {
	result, err := s.db.Exec("UPDATE users SET discoverability = ? WHERE id = ?", value, userID)
	if err != nil {
		return fmt.Errorf("update discoverability: %w", err)
	}
	rows, _ := result.RowsAffected()
	if rows == 0 {
		return fmt.Errorf("user not found: %s", userID)
	}
	return nil
}

func (s *UserStore) RegisterDevice(userID, apnsToken, platform string) error {
	id := uuid.New().String()
	now := time.Now().UTC()

	_, err := s.db.Exec(
		`INSERT INTO devices (id, user_id, apns_token, platform, active, created_at, updated_at)
		 VALUES (?, ?, ?, ?, 1, ?, ?)
		 ON CONFLICT(user_id, apns_token) DO UPDATE SET active = 1, updated_at = ?`,
		id, userID, apnsToken, platform, now, now, now,
	)
	return err
}

func (s *UserStore) GetActiveDevices(userID string) ([]model.Device, error) {
	rows, err := s.db.Query(
		"SELECT id, user_id, apns_token, platform, active, created_at, updated_at FROM devices WHERE user_id = ? AND active = 1",
		userID,
	)
	if err != nil {
		return nil, fmt.Errorf("query devices: %w", err)
	}
	defer rows.Close()

	var devices []model.Device
	for rows.Next() {
		var d model.Device
		if err := rows.Scan(&d.ID, &d.UserID, &d.APNsToken, &d.Platform, &d.Active, &d.CreatedAt, &d.UpdatedAt); err != nil {
			return nil, fmt.Errorf("scan device: %w", err)
		}
		devices = append(devices, d)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate devices: %w", err)
	}
	return devices, nil
}

func (s *UserStore) DeactivateDevice(apnsToken string) error {
	_, err := s.db.Exec("UPDATE devices SET active = 0, updated_at = ? WHERE apns_token = ?", time.Now().UTC(), apnsToken)
	return err
}

func generateToken() string {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		panic("crypto/rand failed: " + err.Error())
	}
	return hex.EncodeToString(b)
}
