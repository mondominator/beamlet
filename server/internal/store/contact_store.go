package store

import (
	"database/sql"

	"github.com/mondominator/beamlet/server/internal/model"
)

type ContactStore struct {
	db *sql.DB
}

func NewContactStore(db *sql.DB) *ContactStore {
	return &ContactStore{db: db}
}

func (s *ContactStore) Add(userID, contactID string) error {
	tx, err := s.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	_, err = tx.Exec(
		`INSERT OR IGNORE INTO contacts (user_id, contact_id) VALUES (?, ?)`,
		userID, contactID,
	)
	if err != nil {
		return err
	}

	_, err = tx.Exec(
		`INSERT OR IGNORE INTO contacts (user_id, contact_id) VALUES (?, ?)`,
		contactID, userID,
	)
	if err != nil {
		return err
	}

	return tx.Commit()
}

func (s *ContactStore) ListForUser(userID string) ([]model.ContactUser, error) {
	rows, err := s.db.Query(
		`SELECT u.id, u.name, c.created_at
		 FROM contacts c
		 JOIN users u ON u.id = c.contact_id
		 WHERE c.user_id = ?
		 ORDER BY u.name`,
		userID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var contacts []model.ContactUser
	for rows.Next() {
		var c model.ContactUser
		if err := rows.Scan(&c.ID, &c.Name, &c.CreatedAt); err != nil {
			return nil, err
		}
		contacts = append(contacts, c)
	}
	return contacts, rows.Err()
}

func (s *ContactStore) Delete(userID, contactID string) error {
	tx, err := s.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	_, err = tx.Exec(`DELETE FROM contacts WHERE user_id = ? AND contact_id = ?`, userID, contactID)
	if err != nil {
		return err
	}
	_, err = tx.Exec(`DELETE FROM contacts WHERE user_id = ? AND contact_id = ?`, contactID, userID)
	if err != nil {
		return err
	}

	return tx.Commit()
}

func (s *ContactStore) AreContacts(userID, contactID string) (bool, error) {
	var count int
	err := s.db.QueryRow(
		`SELECT COUNT(*) FROM contacts WHERE user_id = ? AND contact_id = ?`,
		userID, contactID,
	).Scan(&count)
	return count > 0, err
}
