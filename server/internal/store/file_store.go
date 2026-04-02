package store

import (
	"database/sql"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/mondominator/beamlet/server/internal/model"
)

type FileStore struct {
	db *sql.DB
}

func NewFileStore(db *sql.DB) *FileStore {
	return &FileStore{db: db}
}

func (s *FileStore) Create(f *model.File) (*model.File, error) {
	f.ID = uuid.New().String()
	f.CreatedAt = time.Now().UTC()

	_, err := s.db.Exec(
		`INSERT INTO files (id, sender_id, recipient_id, filename, file_path, thumbnail_path,
			file_type, file_size, content_type, text_content, message, read, expires_at, created_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		f.ID, f.SenderID, f.RecipientID, f.Filename, f.FilePath, f.ThumbnailPath,
		f.FileType, f.FileSize, f.ContentType, f.TextContent, f.Message, f.Read, f.ExpiresAt, f.CreatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("insert file: %w", err)
	}
	return f, nil
}

func (s *FileStore) GetByID(id string) (*model.File, error) {
	var f model.File
	var filePath, thumbnailPath, textContent, message sql.NullString

	err := s.db.QueryRow(
		`SELECT id, sender_id, recipient_id, filename, file_path, thumbnail_path,
			file_type, file_size, content_type, text_content, message, read, pinned, expires_at, created_at
		FROM files WHERE id = ?`, id,
	).Scan(&f.ID, &f.SenderID, &f.RecipientID, &f.Filename, &filePath, &thumbnailPath,
		&f.FileType, &f.FileSize, &f.ContentType, &textContent, &message, &f.Read, &f.Pinned, &f.ExpiresAt, &f.CreatedAt)
	if err != nil {
		return nil, fmt.Errorf("get file: %w", err)
	}

	f.FilePath = filePath.String
	f.ThumbnailPath = thumbnailPath.String
	f.TextContent = textContent.String
	f.Message = message.String
	return &f, nil
}

func (s *FileStore) ListForRecipient(recipientID string, limit, offset int) ([]model.File, error) {
	rows, err := s.db.Query(
		`SELECT f.id, f.sender_id, f.recipient_id, f.filename, f.file_path, f.thumbnail_path,
			f.file_type, f.file_size, f.content_type, f.text_content, f.message, f.read, f.pinned, f.expires_at, f.created_at,
			u.name AS sender_name
		FROM files f
		JOIN users u ON u.id = f.sender_id
		WHERE f.recipient_id = ?
		ORDER BY f.pinned DESC, f.created_at DESC
		LIMIT ? OFFSET ?`,
		recipientID, limit, offset,
	)
	if err != nil {
		return nil, fmt.Errorf("query files: %w", err)
	}
	defer rows.Close()

	var files []model.File
	for rows.Next() {
		var f model.File
		var filePath, thumbnailPath, textContent, message sql.NullString

		if err := rows.Scan(&f.ID, &f.SenderID, &f.RecipientID, &f.Filename, &filePath, &thumbnailPath,
			&f.FileType, &f.FileSize, &f.ContentType, &textContent, &message, &f.Read, &f.Pinned, &f.ExpiresAt, &f.CreatedAt,
			&f.SenderName); err != nil {
			return nil, fmt.Errorf("scan file: %w", err)
		}

		f.FilePath = filePath.String
		f.ThumbnailPath = thumbnailPath.String
		f.TextContent = textContent.String
		f.Message = message.String
		files = append(files, f)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return files, nil
}

func (s *FileStore) ListForSender(senderID string, limit, offset int) ([]model.File, error) {
	rows, err := s.db.Query(
		`SELECT f.id, f.sender_id, f.recipient_id, f.filename, f.file_path, f.thumbnail_path,
			f.file_type, f.file_size, f.content_type, f.text_content, f.message, f.read, f.pinned, f.expires_at, f.created_at,
			u.name AS sender_name
		FROM files f
		JOIN users u ON u.id = f.recipient_id
		WHERE f.sender_id = ?
		ORDER BY f.created_at DESC
		LIMIT ? OFFSET ?`,
		senderID, limit, offset,
	)
	if err != nil {
		return nil, fmt.Errorf("query sent files: %w", err)
	}
	defer rows.Close()

	var files []model.File
	for rows.Next() {
		var f model.File
		var filePath, thumbnailPath, textContent, message sql.NullString

		if err := rows.Scan(&f.ID, &f.SenderID, &f.RecipientID, &f.Filename, &filePath, &thumbnailPath,
			&f.FileType, &f.FileSize, &f.ContentType, &textContent, &message, &f.Read, &f.Pinned, &f.ExpiresAt, &f.CreatedAt,
			&f.SenderName); err != nil {
			return nil, fmt.Errorf("scan sent file: %w", err)
		}

		f.FilePath = filePath.String
		f.ThumbnailPath = thumbnailPath.String
		f.TextContent = textContent.String
		f.Message = message.String
		files = append(files, f)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return files, nil
}

func (s *FileStore) TogglePin(id string) (bool, error) {
	result, err := s.db.Exec("UPDATE files SET pinned = CASE WHEN pinned = 1 THEN 0 ELSE 1 END WHERE id = ?", id)
	if err != nil {
		return false, err
	}
	rows, _ := result.RowsAffected()
	if rows == 0 {
		return false, fmt.Errorf("file not found")
	}
	var pinned bool
	s.db.QueryRow("SELECT pinned FROM files WHERE id = ?", id).Scan(&pinned)
	return pinned, nil
}

func (s *FileStore) MarkRead(id string) error {
	result, err := s.db.Exec("UPDATE files SET read = 1 WHERE id = ?", id)
	if err != nil {
		return fmt.Errorf("mark read: %w", err)
	}
	rows, _ := result.RowsAffected()
	if rows == 0 {
		return fmt.Errorf("file not found: %s", id)
	}
	return nil
}

func (s *FileStore) Delete(id string) error {
	result, err := s.db.Exec("DELETE FROM files WHERE id = ?", id)
	if err != nil {
		return fmt.Errorf("delete file: %w", err)
	}
	rows, _ := result.RowsAffected()
	if rows == 0 {
		return fmt.Errorf("file not found: %s", id)
	}
	return nil
}

func (s *FileStore) ListExpired() ([]model.File, error) {
	rows, err := s.db.Query(
		`SELECT id, file_path, thumbnail_path FROM files WHERE expires_at < ?`,
		time.Now().UTC(),
	)
	if err != nil {
		return nil, fmt.Errorf("query expired: %w", err)
	}
	defer rows.Close()

	var files []model.File
	for rows.Next() {
		var f model.File
		var filePath, thumbnailPath sql.NullString
		if err := rows.Scan(&f.ID, &filePath, &thumbnailPath); err != nil {
			return nil, fmt.Errorf("scan expired: %w", err)
		}
		f.FilePath = filePath.String
		f.ThumbnailPath = thumbnailPath.String
		files = append(files, f)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return files, nil
}

type UserStats struct {
	FilesSent     int   `json:"files_sent"`
	FilesReceived int   `json:"files_received"`
	StorageUsed   int64 `json:"storage_used"`
}

func (s *FileStore) GetUserStats(userID string) (UserStats, error) {
	var stats UserStats

	if err := s.db.QueryRow(
		"SELECT COUNT(*) FROM files WHERE sender_id = ?", userID,
	).Scan(&stats.FilesSent); err != nil {
		return stats, fmt.Errorf("count sent: %w", err)
	}

	if err := s.db.QueryRow(
		"SELECT COUNT(*) FROM files WHERE recipient_id = ?", userID,
	).Scan(&stats.FilesReceived); err != nil {
		return stats, fmt.Errorf("count received: %w", err)
	}

	if err := s.db.QueryRow(
		"SELECT COALESCE(SUM(file_size), 0) FROM files WHERE sender_id = ? OR recipient_id = ?", userID, userID,
	).Scan(&stats.StorageUsed); err != nil {
		return stats, fmt.Errorf("sum storage: %w", err)
	}

	return stats, nil
}
