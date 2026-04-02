package cleanup_test

import (
	"bytes"
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
