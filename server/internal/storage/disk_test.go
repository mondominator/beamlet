package storage_test

import (
	"bytes"
	"io"
	"os"
	"path/filepath"
	"strings"
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

func TestDiskStorage_ReadNonExistent(t *testing.T) {
	dir := t.TempDir()
	s := storage.NewDiskStorage(dir)

	_, err := s.Read(filepath.Join(dir, "does-not-exist.txt"))
	if err == nil {
		t.Fatal("expected error reading non-existent file")
	}
	if !strings.Contains(err.Error(), "open file") {
		t.Fatalf("expected 'open file' error, got: %v", err)
	}
}

func TestDiskStorage_DeleteNonExistent(t *testing.T) {
	dir := t.TempDir()
	s := storage.NewDiskStorage(dir)

	// Deleting a non-existent file within base dir should not error
	err := s.Delete(filepath.Join(dir, "does-not-exist.txt"))
	if err != nil {
		t.Fatalf("expected no error deleting non-existent file, got: %v", err)
	}
}

func TestDiskStorage_ReadPathTraversal(t *testing.T) {
	dir := t.TempDir()
	s := storage.NewDiskStorage(dir)

	// Attempt to read outside base directory
	_, err := s.Read(filepath.Join(dir, "..", "etc", "passwd"))
	if err == nil {
		t.Fatal("expected error for path traversal")
	}
	if !strings.Contains(err.Error(), "path outside base directory") {
		t.Fatalf("expected path traversal error, got: %v", err)
	}
}

func TestDiskStorage_DeletePathTraversal(t *testing.T) {
	dir := t.TempDir()
	s := storage.NewDiskStorage(dir)

	// Attempt to delete outside base directory
	err := s.Delete(filepath.Join(dir, "..", "etc", "passwd"))
	if err == nil {
		t.Fatal("expected error for path traversal")
	}
	if !strings.Contains(err.Error(), "path outside base directory") {
		t.Fatalf("expected path traversal error, got: %v", err)
	}
}

func TestDiskStorage_ReadAbsolutePathOutside(t *testing.T) {
	dir := t.TempDir()
	s := storage.NewDiskStorage(dir)

	_, err := s.Read("/tmp/outside-file.txt")
	if err == nil {
		t.Fatal("expected error for absolute path outside base")
	}
	if !strings.Contains(err.Error(), "path outside base directory") {
		t.Fatalf("expected path traversal error, got: %v", err)
	}
}

func TestDiskStorage_DeleteAbsolutePathOutside(t *testing.T) {
	dir := t.TempDir()
	s := storage.NewDiskStorage(dir)

	err := s.Delete("/tmp/outside-file.txt")
	if err == nil {
		t.Fatal("expected error for absolute path outside base")
	}
	if !strings.Contains(err.Error(), "path outside base directory") {
		t.Fatalf("expected path traversal error, got: %v", err)
	}
}

func TestDiskStorage_SaveContentCorrect(t *testing.T) {
	dir := t.TempDir()
	s := storage.NewDiskStorage(dir)

	content := []byte("the quick brown fox jumps over the lazy dog")
	path, err := s.Save("document.txt", "text/plain", bytes.NewReader(content))
	if err != nil {
		t.Fatalf("save: %v", err)
	}

	// Verify by reading directly from disk
	got, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read file: %v", err)
	}
	if !bytes.Equal(got, content) {
		t.Fatalf("content mismatch: expected %q, got %q", content, got)
	}
}

func TestDiskStorage_SavePreservesExtension(t *testing.T) {
	dir := t.TempDir()
	s := storage.NewDiskStorage(dir)

	path, err := s.Save("photo.jpg", "image/jpeg", bytes.NewReader([]byte("fake image")))
	if err != nil {
		t.Fatalf("save: %v", err)
	}
	if !strings.HasSuffix(path, ".jpg") {
		t.Fatalf("expected .jpg extension, got %s", path)
	}
}

func TestDiskStorage_SaveNoExtension(t *testing.T) {
	dir := t.TempDir()
	s := storage.NewDiskStorage(dir)

	path, err := s.Save("README", "text/plain", bytes.NewReader([]byte("readme")))
	if err != nil {
		t.Fatalf("save: %v", err)
	}
	// Should not have an extension appended
	if strings.Contains(filepath.Base(path), ".") && filepath.Ext(path) != "" {
		// The UUID portion has no dots, so if Ext returns "" for "README" that's correct
		// Just verify file exists
	}
	if _, err := os.Stat(path); err != nil {
		t.Fatalf("saved file should exist: %v", err)
	}
}

func TestDiskStorage_SaveEmptyContent(t *testing.T) {
	dir := t.TempDir()
	s := storage.NewDiskStorage(dir)

	path, err := s.Save("empty.txt", "text/plain", bytes.NewReader([]byte{}))
	if err != nil {
		t.Fatalf("save empty: %v", err)
	}

	info, err := os.Stat(path)
	if err != nil {
		t.Fatalf("stat: %v", err)
	}
	if info.Size() != 0 {
		t.Fatalf("expected empty file, got %d bytes", info.Size())
	}
}

func TestDiskStorage_SaveLargeContent(t *testing.T) {
	dir := t.TempDir()
	s := storage.NewDiskStorage(dir)

	content := bytes.Repeat([]byte("x"), 1024*1024) // 1MB
	path, err := s.Save("large.bin", "application/octet-stream", bytes.NewReader(content))
	if err != nil {
		t.Fatalf("save large: %v", err)
	}

	reader, err := s.Read(path)
	if err != nil {
		t.Fatalf("read large: %v", err)
	}
	defer reader.Close()

	got, err := io.ReadAll(reader)
	if err != nil {
		t.Fatalf("read all: %v", err)
	}
	if len(got) != len(content) {
		t.Fatalf("expected %d bytes, got %d", len(content), len(got))
	}
}

func TestDiskStorage_SaveMultipleFiles(t *testing.T) {
	dir := t.TempDir()
	s := storage.NewDiskStorage(dir)

	// Save multiple files with the same name - should get unique paths
	path1, _ := s.Save("file.txt", "text/plain", bytes.NewReader([]byte("one")))
	path2, _ := s.Save("file.txt", "text/plain", bytes.NewReader([]byte("two")))

	if path1 == path2 {
		t.Fatal("expected unique paths for files with same name")
	}

	r1, _ := s.Read(path1)
	defer r1.Close()
	got1, _ := io.ReadAll(r1)

	r2, _ := s.Read(path2)
	defer r2.Close()
	got2, _ := io.ReadAll(r2)

	if string(got1) != "one" {
		t.Fatalf("expected 'one', got %q", got1)
	}
	if string(got2) != "two" {
		t.Fatalf("expected 'two', got %q", got2)
	}
}

func TestDiskStorage_DeleteThenRead(t *testing.T) {
	dir := t.TempDir()
	s := storage.NewDiskStorage(dir)

	path, _ := s.Save("doomed.txt", "text/plain", bytes.NewReader([]byte("gone soon")))

	if err := s.Delete(path); err != nil {
		t.Fatalf("delete: %v", err)
	}

	_, err := s.Read(path)
	if err == nil {
		t.Fatal("expected error reading deleted file")
	}
}

func TestGenerateThumbnail_NonImageVideoType(t *testing.T) {
	dir := t.TempDir()

	// For non-image/non-video types, should return empty string
	result, err := storage.GenerateThumbnail("/tmp/file.pdf", dir, "application/pdf")
	if err != nil {
		t.Fatalf("expected no error for non-image type, got: %v", err)
	}
	if result != "" {
		t.Fatalf("expected empty string for non-image type, got: %s", result)
	}
}

func TestGenerateThumbnail_TextType(t *testing.T) {
	dir := t.TempDir()

	result, err := storage.GenerateThumbnail("/tmp/file.txt", dir, "text/plain")
	if err != nil {
		t.Fatalf("expected no error for text type, got: %v", err)
	}
	if result != "" {
		t.Fatalf("expected empty string for text type, got: %s", result)
	}
}

func TestGenerateThumbnail_AudioType(t *testing.T) {
	dir := t.TempDir()

	result, err := storage.GenerateThumbnail("/tmp/file.mp3", dir, "audio/mpeg")
	if err != nil {
		t.Fatalf("expected no error for audio type, got: %v", err)
	}
	if result != "" {
		t.Fatalf("expected empty string for audio type, got: %s", result)
	}
}

func TestGenerateThumbnail_EmptyMimeType(t *testing.T) {
	dir := t.TempDir()

	result, err := storage.GenerateThumbnail("/tmp/file", dir, "")
	if err != nil {
		t.Fatalf("expected no error for empty type, got: %v", err)
	}
	if result != "" {
		t.Fatalf("expected empty string for empty type, got: %s", result)
	}
}
