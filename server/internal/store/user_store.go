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

var ErrAuthFailed = errors.New("authentication failed")

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

	now := time.Now().UTC()
	_, err = s.db.Exec(
		"INSERT INTO users (id, name, token_hash, created_at) VALUES (?, ?, ?, ?)",
		id, name, string(hash), now,
	)
	if err != nil {
		return nil, "", fmt.Errorf("insert user: %w", err)
	}

	user := &model.User{
		ID:        id,
		Name:      name,
		TokenHash: string(hash),
		CreatedAt: now,
	}
	return user, token, nil
}

func (s *UserStore) GetByID(id string) (*model.User, error) {
	var u model.User
	err := s.db.QueryRow(
		"SELECT id, name, token_hash, created_at FROM users WHERE id = ?", id,
	).Scan(&u.ID, &u.Name, &u.TokenHash, &u.CreatedAt)
	if err != nil {
		return nil, fmt.Errorf("get user: %w", err)
	}
	return &u, nil
}

func (s *UserStore) Authenticate(token string) (*model.User, error) {
	rows, err := s.db.Query("SELECT id, name, token_hash, created_at FROM users")
	if err != nil {
		return nil, fmt.Errorf("query users: %w", err)
	}
	defer rows.Close()

	for rows.Next() {
		var u model.User
		if err := rows.Scan(&u.ID, &u.Name, &u.TokenHash, &u.CreatedAt); err != nil {
			return nil, fmt.Errorf("scan user: %w", err)
		}
		if bcrypt.CompareHashAndPassword([]byte(u.TokenHash), []byte(token)) == nil {
			return &u, nil
		}
	}
	return nil, ErrAuthFailed
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
	return users, nil
}

func (s *UserStore) RevokeToken(userID string) (string, error) {
	token := generateToken()
	hash, err := bcrypt.GenerateFromPassword([]byte(token), bcrypt.DefaultCost)
	if err != nil {
		return "", fmt.Errorf("hash token: %w", err)
	}

	result, err := s.db.Exec("UPDATE users SET token_hash = ? WHERE id = ?", string(hash), userID)
	if err != nil {
		return "", fmt.Errorf("update token: %w", err)
	}
	rows, _ := result.RowsAffected()
	if rows == 0 {
		return "", fmt.Errorf("user not found: %s", userID)
	}
	return token, nil
}

func generateToken() string {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		panic("crypto/rand failed: " + err.Error())
	}
	return hex.EncodeToString(b)
}
