package store_test

import (
	"database/sql"
	"testing"
	"time"

	"github.com/mondominator/beamlet/server/internal/model"
	"github.com/mondominator/beamlet/server/internal/store"
	"github.com/mondominator/beamlet/server/testutil"
)

type fileTestEnv struct {
	db        *sql.DB
	userStore *store.UserStore
	fileStore *store.FileStore
	alice     *model.User
	bob       *model.User
}

func setupFileTest(t *testing.T) *fileTestEnv {
	t.Helper()
	database := testutil.TestDB(t)
	db := database.SQL()

	us := store.NewUserStore(db)
	fs := store.NewFileStore(db)

	alice, _, err := us.Create("Alice")
	if err != nil {
		t.Fatalf("create alice: %v", err)
	}
	bob, _, err := us.Create("Bob")
	if err != nil {
		t.Fatalf("create bob: %v", err)
	}

	return &fileTestEnv{
		db:        db,
		userStore: us,
		fileStore: fs,
		alice:     alice,
		bob:       bob,
	}
}

func TestFileStore_CreateAndGet(t *testing.T) {
	env := setupFileTest(t)

	f := &model.File{
		SenderID:    env.alice.ID,
		RecipientID: env.bob.ID,
		Filename:    "test.txt",
		FilePath:    "/uploads/test.txt",
		FileType:    "document",
		FileSize:    1024,
		ContentType: "file",
		ExpiresAt:   time.Now().Add(24 * time.Hour).UTC(),
	}

	created, err := env.fileStore.Create(f)
	if err != nil {
		t.Fatalf("create file: %v", err)
	}
	if created.ID == "" {
		t.Fatal("expected non-empty ID")
	}

	got, err := env.fileStore.GetByID(created.ID)
	if err != nil {
		t.Fatalf("get file: %v", err)
	}
	if got.Filename != "test.txt" {
		t.Fatalf("expected filename test.txt, got %s", got.Filename)
	}
	if got.SenderID != env.alice.ID {
		t.Fatalf("expected sender %s, got %s", env.alice.ID, got.SenderID)
	}
	if got.RecipientID != env.bob.ID {
		t.Fatalf("expected recipient %s, got %s", env.bob.ID, got.RecipientID)
	}
}

func TestFileStore_ListForRecipient(t *testing.T) {
	env := setupFileTest(t)

	for i := 0; i < 3; i++ {
		f := &model.File{
			SenderID:    env.alice.ID,
			RecipientID: env.bob.ID,
			Filename:    "file.txt",
			FilePath:    "/uploads/file.txt",
			FileType:    "document",
			FileSize:    100,
			ContentType: "file",
			ExpiresAt:   time.Now().Add(24 * time.Hour).UTC(),
		}
		if _, err := env.fileStore.Create(f); err != nil {
			t.Fatalf("create file %d: %v", i, err)
		}
	}

	files, err := env.fileStore.ListForRecipient(env.bob.ID, 10, 0)
	if err != nil {
		t.Fatalf("list files: %v", err)
	}
	if len(files) != 3 {
		t.Fatalf("expected 3 files, got %d", len(files))
	}
	if files[0].SenderName != "Alice" {
		t.Fatalf("expected sender_name Alice, got %s", files[0].SenderName)
	}
}

func TestFileStore_MarkRead(t *testing.T) {
	env := setupFileTest(t)

	f := &model.File{
		SenderID:    env.alice.ID,
		RecipientID: env.bob.ID,
		Filename:    "test.txt",
		FilePath:    "/uploads/test.txt",
		FileType:    "document",
		FileSize:    100,
		ContentType: "file",
		ExpiresAt:   time.Now().Add(24 * time.Hour).UTC(),
	}

	created, err := env.fileStore.Create(f)
	if err != nil {
		t.Fatalf("create file: %v", err)
	}

	if err := env.fileStore.MarkRead(created.ID); err != nil {
		t.Fatalf("mark read: %v", err)
	}

	got, err := env.fileStore.GetByID(created.ID)
	if err != nil {
		t.Fatalf("get file: %v", err)
	}
	if !got.Read {
		t.Fatal("expected file to be marked as read")
	}
}

func TestFileStore_Delete(t *testing.T) {
	env := setupFileTest(t)

	f := &model.File{
		SenderID:    env.alice.ID,
		RecipientID: env.bob.ID,
		Filename:    "test.txt",
		FilePath:    "/uploads/test.txt",
		FileType:    "document",
		FileSize:    100,
		ContentType: "file",
		ExpiresAt:   time.Now().Add(24 * time.Hour).UTC(),
	}

	created, err := env.fileStore.Create(f)
	if err != nil {
		t.Fatalf("create file: %v", err)
	}

	if err := env.fileStore.Delete(created.ID); err != nil {
		t.Fatalf("delete file: %v", err)
	}

	_, err = env.fileStore.GetByID(created.ID)
	if err == nil {
		t.Fatal("expected error after delete")
	}
}

func TestFileStore_ListExpired(t *testing.T) {
	env := setupFileTest(t)

	expired := &model.File{
		SenderID:    env.alice.ID,
		RecipientID: env.bob.ID,
		Filename:    "expired.txt",
		FilePath:    "/uploads/expired.txt",
		FileType:    "document",
		FileSize:    100,
		ContentType: "file",
		ExpiresAt:   time.Now().Add(-1 * time.Hour).UTC(),
	}
	if _, err := env.fileStore.Create(expired); err != nil {
		t.Fatalf("create expired file: %v", err)
	}

	valid := &model.File{
		SenderID:    env.alice.ID,
		RecipientID: env.bob.ID,
		Filename:    "valid.txt",
		FilePath:    "/uploads/valid.txt",
		FileType:    "document",
		FileSize:    100,
		ContentType: "file",
		ExpiresAt:   time.Now().Add(24 * time.Hour).UTC(),
	}
	if _, err := env.fileStore.Create(valid); err != nil {
		t.Fatalf("create valid file: %v", err)
	}

	files, err := env.fileStore.ListExpired()
	if err != nil {
		t.Fatalf("list expired: %v", err)
	}
	if len(files) != 1 {
		t.Fatalf("expected 1 expired file, got %d", len(files))
	}
	if files[0].FilePath != "/uploads/expired.txt" {
		t.Fatalf("expected expired.txt path, got %s", files[0].FilePath)
	}
}
