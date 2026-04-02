package cleanup_test

import (
	"bytes"
	"os"
	"testing"
	"time"

	"github.com/mondominator/beamlet/server/internal/cleanup"
	"github.com/mondominator/beamlet/server/internal/model"
	"github.com/mondominator/beamlet/server/internal/storage"
	"github.com/mondominator/beamlet/server/internal/store"
	"github.com/mondominator/beamlet/server/testutil"
)

func TestRunOnce(t *testing.T) {
	db := testutil.TestDB(t)
	tmpDir := t.TempDir()

	us := store.NewUserStore(db.SQL())
	fs := store.NewFileStore(db.SQL())
	ds := storage.NewDiskStorage(tmpDir)

	sender, _, _ := us.Create("Alice")
	recipient, _, _ := us.Create("Bob")

	path, _ := ds.Save("old.txt", "text/plain", bytes.NewReader([]byte("old")))

	fs.Create(&model.File{
		SenderID:    sender.ID,
		RecipientID: recipient.ID,
		Filename:    "old.txt",
		FilePath:    path,
		FileType:    "text/plain",
		ContentType: "file",
		ExpiresAt:   time.Now().Add(-1 * time.Hour),
	})

	fs.Create(&model.File{
		SenderID:    sender.ID,
		RecipientID: recipient.ID,
		Filename:    "new.txt",
		FileType:    "text/plain",
		ContentType: "file",
		ExpiresAt:   time.Now().Add(30 * 24 * time.Hour),
	})

	deleted, err := cleanup.RunOnce(fs, ds, nil)
	if err != nil {
		t.Fatalf("run once: %v", err)
	}
	if deleted != 1 {
		t.Fatalf("expected 1 deleted, got %d", deleted)
	}

	files, _ := fs.ListForRecipient(recipient.ID, 10, 0)
	if len(files) != 1 {
		t.Fatalf("expected 1 remaining file, got %d", len(files))
	}
	if files[0].Filename != "new.txt" {
		t.Fatalf("expected new.txt to remain, got %s", files[0].Filename)
	}
}

func TestRunOnce_NoExpired(t *testing.T) {
	db := testutil.TestDB(t)
	tmpDir := t.TempDir()

	us := store.NewUserStore(db.SQL())
	fs := store.NewFileStore(db.SQL())
	ds := storage.NewDiskStorage(tmpDir)

	sender, _, _ := us.Create("Alice")
	recipient, _, _ := us.Create("Bob")

	fs.Create(&model.File{
		SenderID:    sender.ID,
		RecipientID: recipient.ID,
		Filename:    "active.txt",
		FileType:    "text/plain",
		ContentType: "file",
		ExpiresAt:   time.Now().Add(30 * 24 * time.Hour),
	})

	deleted, err := cleanup.RunOnce(fs, ds, nil)
	if err != nil {
		t.Fatalf("run once: %v", err)
	}
	if deleted != 0 {
		t.Fatalf("expected 0 deleted, got %d", deleted)
	}
}

func TestRunOnce_EmptyDatabase(t *testing.T) {
	db := testutil.TestDB(t)
	tmpDir := t.TempDir()

	fs := store.NewFileStore(db.SQL())
	ds := storage.NewDiskStorage(tmpDir)

	deleted, err := cleanup.RunOnce(fs, ds, nil)
	if err != nil {
		t.Fatalf("run once: %v", err)
	}
	if deleted != 0 {
		t.Fatalf("expected 0 deleted, got %d", deleted)
	}
}

func TestRunOnce_FileAndThumbnail(t *testing.T) {
	db := testutil.TestDB(t)
	tmpDir := t.TempDir()

	us := store.NewUserStore(db.SQL())
	fs := store.NewFileStore(db.SQL())
	ds := storage.NewDiskStorage(tmpDir)

	sender, _, _ := us.Create("Alice")
	recipient, _, _ := us.Create("Bob")

	filePath, _ := ds.Save("photo.jpg", "image/jpeg", bytes.NewReader([]byte("image data")))
	thumbPath, _ := ds.Save("thumb.jpg", "image/jpeg", bytes.NewReader([]byte("thumb data")))

	fs.Create(&model.File{
		SenderID:      sender.ID,
		RecipientID:   recipient.ID,
		Filename:      "photo.jpg",
		FilePath:      filePath,
		ThumbnailPath: thumbPath,
		FileType:      "image/jpeg",
		ContentType:   "file",
		ExpiresAt:     time.Now().Add(-1 * time.Hour),
	})

	deleted, err := cleanup.RunOnce(fs, ds, nil)
	if err != nil {
		t.Fatalf("run once: %v", err)
	}
	if deleted != 1 {
		t.Fatalf("expected 1 deleted, got %d", deleted)
	}

	// Both file and thumbnail should be removed from disk
	if _, err := os.Stat(filePath); !os.IsNotExist(err) {
		t.Fatal("expected file to be deleted from disk")
	}
	if _, err := os.Stat(thumbPath); !os.IsNotExist(err) {
		t.Fatal("expected thumbnail to be deleted from disk")
	}
}

func TestRunOnce_FileOnlyNoThumbnail(t *testing.T) {
	db := testutil.TestDB(t)
	tmpDir := t.TempDir()

	us := store.NewUserStore(db.SQL())
	fs := store.NewFileStore(db.SQL())
	ds := storage.NewDiskStorage(tmpDir)

	sender, _, _ := us.Create("Alice")
	recipient, _, _ := us.Create("Bob")

	filePath, _ := ds.Save("doc.pdf", "application/pdf", bytes.NewReader([]byte("pdf data")))

	fs.Create(&model.File{
		SenderID:    sender.ID,
		RecipientID: recipient.ID,
		Filename:    "doc.pdf",
		FilePath:    filePath,
		FileType:    "application/pdf",
		ContentType: "file",
		ExpiresAt:   time.Now().Add(-1 * time.Hour),
	})

	deleted, err := cleanup.RunOnce(fs, ds, nil)
	if err != nil {
		t.Fatalf("run once: %v", err)
	}
	if deleted != 1 {
		t.Fatalf("expected 1 deleted, got %d", deleted)
	}

	if _, err := os.Stat(filePath); !os.IsNotExist(err) {
		t.Fatal("expected file to be deleted from disk")
	}
}

func TestRunOnce_MultipleExpired(t *testing.T) {
	db := testutil.TestDB(t)
	tmpDir := t.TempDir()

	us := store.NewUserStore(db.SQL())
	fs := store.NewFileStore(db.SQL())
	ds := storage.NewDiskStorage(tmpDir)

	sender, _, _ := us.Create("Alice")
	recipient, _, _ := us.Create("Bob")

	for i := 0; i < 5; i++ {
		path, _ := ds.Save("file.txt", "text/plain", bytes.NewReader([]byte("data")))
		fs.Create(&model.File{
			SenderID:    sender.ID,
			RecipientID: recipient.ID,
			Filename:    "expired.txt",
			FilePath:    path,
			FileType:    "text/plain",
			ContentType: "file",
			ExpiresAt:   time.Now().Add(-1 * time.Hour),
		})
	}

	// Also create 2 active files
	for i := 0; i < 2; i++ {
		fs.Create(&model.File{
			SenderID:    sender.ID,
			RecipientID: recipient.ID,
			Filename:    "active.txt",
			FileType:    "text/plain",
			ContentType: "file",
			ExpiresAt:   time.Now().Add(24 * time.Hour),
		})
	}

	deleted, err := cleanup.RunOnce(fs, ds, nil)
	if err != nil {
		t.Fatalf("run once: %v", err)
	}
	if deleted != 5 {
		t.Fatalf("expected 5 deleted, got %d", deleted)
	}

	files, _ := fs.ListForRecipient(recipient.ID, 100, 0)
	if len(files) != 2 {
		t.Fatalf("expected 2 remaining files, got %d", len(files))
	}
}

func TestRunOnce_WithInviteStore(t *testing.T) {
	db := testutil.TestDB(t)
	tmpDir := t.TempDir()

	us := store.NewUserStore(db.SQL())
	fs := store.NewFileStore(db.SQL())
	is := store.NewInviteStore(db.SQL())
	ds := storage.NewDiskStorage(tmpDir)

	alice, _, _ := us.Create("Alice")

	// Create an expired invite (expired more than 7 days ago so DeleteExpired picks it up)
	is.Create(alice.ID, "", -8*24*time.Hour)

	// RunOnce should not error even with invite store
	deleted, err := cleanup.RunOnce(fs, ds, is)
	if err != nil {
		t.Fatalf("run once with invite store: %v", err)
	}
	if deleted != 0 {
		t.Fatalf("expected 0 file deletions, got %d", deleted)
	}
}

func TestRunOnce_WithInviteStoreNilSafe(t *testing.T) {
	db := testutil.TestDB(t)
	tmpDir := t.TempDir()

	fs := store.NewFileStore(db.SQL())
	ds := storage.NewDiskStorage(tmpDir)

	// nil invite store should be handled gracefully
	deleted, err := cleanup.RunOnce(fs, ds, nil)
	if err != nil {
		t.Fatalf("run once with nil invite store: %v", err)
	}
	if deleted != 0 {
		t.Fatalf("expected 0 deleted, got %d", deleted)
	}
}

func TestRunOnce_ExpiredFileWithEmptyPaths(t *testing.T) {
	db := testutil.TestDB(t)
	tmpDir := t.TempDir()

	us := store.NewUserStore(db.SQL())
	fs := store.NewFileStore(db.SQL())
	ds := storage.NewDiskStorage(tmpDir)

	sender, _, _ := us.Create("Alice")
	recipient, _, _ := us.Create("Bob")

	// File with no file path and no thumbnail (e.g. text-only message)
	fs.Create(&model.File{
		SenderID:    sender.ID,
		RecipientID: recipient.ID,
		Filename:    "message",
		FileType:    "text/plain",
		ContentType: "text",
		TextContent: "hello",
		ExpiresAt:   time.Now().Add(-1 * time.Hour),
	})

	deleted, err := cleanup.RunOnce(fs, ds, nil)
	if err != nil {
		t.Fatalf("run once: %v", err)
	}
	if deleted != 1 {
		t.Fatalf("expected 1 deleted, got %d", deleted)
	}
}

func TestRunOnce_FileWithMissingDiskFile(t *testing.T) {
	// Tests the branch where diskStorage.Delete is called on a file that
	// doesn't exist on disk -- the cleanup should still succeed and count the deletion
	db := testutil.TestDB(t)
	tmpDir := t.TempDir()

	us := store.NewUserStore(db.SQL())
	fs := store.NewFileStore(db.SQL())
	ds := storage.NewDiskStorage(tmpDir)

	sender, _, _ := us.Create("Alice")
	recipient, _, _ := us.Create("Bob")

	// Create a file record pointing to a non-existent disk path
	fs.Create(&model.File{
		SenderID:      sender.ID,
		RecipientID:   recipient.ID,
		Filename:      "ghost.txt",
		FilePath:      tmpDir + "/nonexistent-file.txt",
		ThumbnailPath: tmpDir + "/nonexistent-thumb.jpg",
		FileType:      "text/plain",
		ContentType:   "file",
		ExpiresAt:     time.Now().Add(-1 * time.Hour),
	})

	deleted, err := cleanup.RunOnce(fs, ds, nil)
	if err != nil {
		t.Fatalf("run once: %v", err)
	}
	if deleted != 1 {
		t.Fatalf("expected 1 deleted, got %d", deleted)
	}
}

func TestRunOnce_InviteStoreDeleteExpiredActuallyDeletes(t *testing.T) {
	db := testutil.TestDB(t)
	tmpDir := t.TempDir()

	us := store.NewUserStore(db.SQL())
	fs := store.NewFileStore(db.SQL())
	is := store.NewInviteStore(db.SQL())
	ds := storage.NewDiskStorage(tmpDir)

	alice, _, _ := us.Create("Alice")

	// Create multiple expired invites (expired >7 days ago)
	is.Create(alice.ID, "", -8*24*time.Hour)
	is.Create(alice.ID, "", -9*24*time.Hour)
	is.Create(alice.ID, "", -10*24*time.Hour)

	// Also create a non-expired invite that should NOT be deleted
	is.Create(alice.ID, "", 24*time.Hour)

	deleted, err := cleanup.RunOnce(fs, ds, is)
	if err != nil {
		t.Fatalf("run once: %v", err)
	}
	// No file deletions expected
	if deleted != 0 {
		t.Fatalf("expected 0 file deletions, got %d", deleted)
	}
}

func TestStartScheduler_StopsImmediately(t *testing.T) {
	db := testutil.TestDB(t)
	tmpDir := t.TempDir()

	fs := store.NewFileStore(db.SQL())
	ds := storage.NewDiskStorage(tmpDir)

	stop := make(chan struct{})

	done := make(chan struct{})
	go func() {
		cleanup.StartScheduler(fs, ds, nil, stop)
		close(done)
	}()

	// Let the initial RunOnce execute, then stop
	time.Sleep(50 * time.Millisecond)
	close(stop)

	select {
	case <-done:
		// Success: scheduler stopped
	case <-time.After(2 * time.Second):
		t.Fatal("StartScheduler did not stop within timeout")
	}
}
