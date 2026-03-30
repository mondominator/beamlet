package storage_test

import (
	"bytes"
	"io"
	"os"
	"path/filepath"
	"testing"

	"github.com/mondominator/beamlet/server/internal/storage"
)

func TestDiskStorage_SaveAndRead(t *testing.T) {
	dir := t.TempDir()
	s := storage.NewDiskStorage(dir)

	content := []byte("hello world")
	path, err := s.Save("test.txt", "text/plain", bytes.NewReader(content))
	if err != nil {
		t.Fatalf("save: %v", err)
	}

	if !filepath.IsAbs(path) {
		t.Fatalf("expected absolute path, got %s", path)
	}

	reader, err := s.Read(path)
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	defer reader.Close()

	got, err := io.ReadAll(reader)
	if err != nil {
		t.Fatalf("read all: %v", err)
	}
	if !bytes.Equal(got, content) {
		t.Fatalf("expected %q, got %q", content, got)
	}
}

func TestDiskStorage_Delete(t *testing.T) {
	dir := t.TempDir()
	s := storage.NewDiskStorage(dir)

	content := []byte("hello")
	path, _ := s.Save("test.txt", "text/plain", bytes.NewReader(content))

	if err := s.Delete(path); err != nil {
		t.Fatalf("delete: %v", err)
	}

	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatal("expected file to be deleted")
	}
}
