package storage

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/google/uuid"
)

type DiskStorage struct {
	baseDir string
}

func NewDiskStorage(baseDir string) *DiskStorage {
	return &DiskStorage{baseDir: baseDir}
}

func (s *DiskStorage) Save(filename, mimeType string, r io.Reader) (string, error) {
	now := time.Now().UTC()
	dir := filepath.Join(s.baseDir, fmt.Sprintf("%d", now.Year()), fmt.Sprintf("%02d", now.Month()))
	if err := os.MkdirAll(dir, 0755); err != nil {
		return "", fmt.Errorf("create directory: %w", err)
	}

	ext := filepath.Ext(filename)
	storedName := uuid.New().String() + ext
	fullPath := filepath.Join(dir, storedName)

	f, err := os.Create(fullPath)
	if err != nil {
		return "", fmt.Errorf("create file: %w", err)
	}
	defer f.Close()

	if _, err := io.Copy(f, r); err != nil {
		os.Remove(fullPath)
		return "", fmt.Errorf("write file: %w", err)
	}

	return fullPath, nil
}

func (s *DiskStorage) Read(path string) (io.ReadCloser, error) {
	clean := filepath.Clean(path)
	if !strings.HasPrefix(clean, s.baseDir) {
		return nil, fmt.Errorf("path outside base directory")
	}
	f, err := os.Open(clean)
	if err != nil {
		return nil, fmt.Errorf("open file: %w", err)
	}
	return f, nil
}

func (s *DiskStorage) Delete(path string) error {
	clean := filepath.Clean(path)
	if !strings.HasPrefix(clean, s.baseDir) {
		return fmt.Errorf("path outside base directory")
	}
	if err := os.Remove(clean); err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("delete file: %w", err)
	}
	return nil
}
