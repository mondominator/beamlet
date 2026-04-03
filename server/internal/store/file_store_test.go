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

func TestFileStore_GetByID_NotFound(t *testing.T) {
	env := setupFileTest(t)

	_, err := env.fileStore.GetByID("nonexistent-id")
	if err == nil {
		t.Fatal("expected error for non-existent file")
	}
}

func TestFileStore_GetByID_NullableFields(t *testing.T) {
	env := setupFileTest(t)

	f := &model.File{
		SenderID:    env.alice.ID,
		RecipientID: env.bob.ID,
		Filename:    "msg",
		FileType:    "text/plain",
		ContentType: "text",
		TextContent: "hello world",
		Message:     "a note",
		ExpiresAt:   time.Now().Add(24 * time.Hour).UTC(),
	}

	created, err := env.fileStore.Create(f)
	if err != nil {
		t.Fatalf("create: %v", err)
	}

	got, err := env.fileStore.GetByID(created.ID)
	if err != nil {
		t.Fatalf("get by id: %v", err)
	}
	if got.TextContent != "hello world" {
		t.Fatalf("expected text_content 'hello world', got %q", got.TextContent)
	}
	if got.Message != "a note" {
		t.Fatalf("expected message 'a note', got %q", got.Message)
	}
	if got.FilePath != "" {
		t.Fatalf("expected empty file_path, got %q", got.FilePath)
	}
	if got.ThumbnailPath != "" {
		t.Fatalf("expected empty thumbnail_path, got %q", got.ThumbnailPath)
	}
}

func TestFileStore_GetByID_WithThumbnail(t *testing.T) {
	env := setupFileTest(t)

	f := &model.File{
		SenderID:      env.alice.ID,
		RecipientID:   env.bob.ID,
		Filename:      "photo.jpg",
		FilePath:      "/uploads/photo.jpg",
		ThumbnailPath: "/uploads/thumbs/photo.jpg",
		FileType:      "image/jpeg",
		FileSize:      5000,
		ContentType:   "file",
		ExpiresAt:     time.Now().Add(24 * time.Hour).UTC(),
	}

	created, err := env.fileStore.Create(f)
	if err != nil {
		t.Fatalf("create: %v", err)
	}

	got, err := env.fileStore.GetByID(created.ID)
	if err != nil {
		t.Fatalf("get: %v", err)
	}
	if got.ThumbnailPath != "/uploads/thumbs/photo.jpg" {
		t.Fatalf("expected thumbnail path, got %q", got.ThumbnailPath)
	}
}

func TestFileStore_ListForSender(t *testing.T) {
	env := setupFileTest(t)

	for i := 0; i < 3; i++ {
		f := &model.File{
			SenderID:    env.alice.ID,
			RecipientID: env.bob.ID,
			Filename:    "sent.txt",
			FilePath:    "/uploads/sent.txt",
			FileType:    "document",
			FileSize:    100,
			ContentType: "file",
			ExpiresAt:   time.Now().Add(24 * time.Hour).UTC(),
		}
		if _, err := env.fileStore.Create(f); err != nil {
			t.Fatalf("create file %d: %v", i, err)
		}
	}

	files, err := env.fileStore.ListForSender(env.alice.ID, 10, 0)
	if err != nil {
		t.Fatalf("list for sender: %v", err)
	}
	if len(files) != 3 {
		t.Fatalf("expected 3 files, got %d", len(files))
	}
	if files[0].RecipientName != "Bob" {
		t.Fatalf("expected recipient_name Bob, got %s", files[0].RecipientName)
	}
}

func TestFileStore_ListForSender_Empty(t *testing.T) {
	env := setupFileTest(t)

	files, err := env.fileStore.ListForSender(env.alice.ID, 10, 0)
	if err != nil {
		t.Fatalf("list for sender: %v", err)
	}
	if len(files) != 0 {
		t.Fatalf("expected 0 files, got %d", len(files))
	}
}

func TestFileStore_ListForSender_Pagination(t *testing.T) {
	env := setupFileTest(t)

	for i := 0; i < 5; i++ {
		f := &model.File{
			SenderID:    env.alice.ID,
			RecipientID: env.bob.ID,
			Filename:    "file.txt",
			FileType:    "document",
			FileSize:    100,
			ContentType: "file",
			ExpiresAt:   time.Now().Add(24 * time.Hour).UTC(),
		}
		env.fileStore.Create(f)
	}

	page1, _ := env.fileStore.ListForSender(env.alice.ID, 2, 0)
	if len(page1) != 2 {
		t.Fatalf("expected 2 files on page 1, got %d", len(page1))
	}

	page2, _ := env.fileStore.ListForSender(env.alice.ID, 2, 2)
	if len(page2) != 2 {
		t.Fatalf("expected 2 files on page 2, got %d", len(page2))
	}

	page3, _ := env.fileStore.ListForSender(env.alice.ID, 2, 4)
	if len(page3) != 1 {
		t.Fatalf("expected 1 file on page 3, got %d", len(page3))
	}
}

func TestFileStore_TogglePin(t *testing.T) {
	env := setupFileTest(t)

	f := &model.File{
		SenderID:    env.alice.ID,
		RecipientID: env.bob.ID,
		Filename:    "pin-me.txt",
		FilePath:    "/uploads/pin-me.txt",
		FileType:    "document",
		FileSize:    100,
		ContentType: "file",
		ExpiresAt:   time.Now().Add(24 * time.Hour).UTC(),
	}

	created, err := env.fileStore.Create(f)
	if err != nil {
		t.Fatalf("create file: %v", err)
	}

	// Initially not pinned, toggle should make it pinned
	pinned, err := env.fileStore.TogglePin(created.ID)
	if err != nil {
		t.Fatalf("toggle pin: %v", err)
	}
	if !pinned {
		t.Fatal("expected file to be pinned after first toggle")
	}

	// Toggle again should unpin
	pinned, err = env.fileStore.TogglePin(created.ID)
	if err != nil {
		t.Fatalf("toggle pin again: %v", err)
	}
	if pinned {
		t.Fatal("expected file to be unpinned after second toggle")
	}

	// Verify via GetByID
	got, _ := env.fileStore.GetByID(created.ID)
	if got.Pinned {
		t.Fatal("expected file to be unpinned in database")
	}
}

func TestFileStore_TogglePin_NonExistent(t *testing.T) {
	env := setupFileTest(t)

	_, err := env.fileStore.TogglePin("nonexistent-id")
	if err == nil {
		t.Fatal("expected error toggling pin on non-existent file")
	}
}

func TestFileStore_GetUserStats(t *testing.T) {
	env := setupFileTest(t)

	// Alice sends 2 files to Bob
	for i := 0; i < 2; i++ {
		env.fileStore.Create(&model.File{
			SenderID:    env.alice.ID,
			RecipientID: env.bob.ID,
			Filename:    "sent.txt",
			FileType:    "document",
			FileSize:    500,
			ContentType: "file",
			ExpiresAt:   time.Now().Add(24 * time.Hour).UTC(),
		})
	}

	// Bob sends 1 file to Alice
	env.fileStore.Create(&model.File{
		SenderID:    env.bob.ID,
		RecipientID: env.alice.ID,
		Filename:    "reply.txt",
		FileType:    "document",
		FileSize:    300,
		ContentType: "file",
		ExpiresAt:   time.Now().Add(24 * time.Hour).UTC(),
	})

	// Alice's stats: sent 2, received 1, storage = 500+500 = 1000 (only sent files)
	stats, err := env.fileStore.GetUserStats(env.alice.ID)
	if err != nil {
		t.Fatalf("get stats: %v", err)
	}
	if stats.FilesSent != 2 {
		t.Fatalf("expected 2 files sent, got %d", stats.FilesSent)
	}
	if stats.FilesReceived != 1 {
		t.Fatalf("expected 1 file received, got %d", stats.FilesReceived)
	}
	if stats.StorageUsed != 1000 {
		t.Fatalf("expected 1000 storage (sent only), got %d", stats.StorageUsed)
	}

	// Bob's stats: sent 1, received 2, storage = 300 (only sent files)
	bobStats, err := env.fileStore.GetUserStats(env.bob.ID)
	if err != nil {
		t.Fatalf("get bob stats: %v", err)
	}
	if bobStats.FilesSent != 1 {
		t.Fatalf("expected 1 file sent for Bob, got %d", bobStats.FilesSent)
	}
	if bobStats.FilesReceived != 2 {
		t.Fatalf("expected 2 files received for Bob, got %d", bobStats.FilesReceived)
	}
	if bobStats.StorageUsed != 300 {
		t.Fatalf("expected 300 storage (sent only) for Bob, got %d", bobStats.StorageUsed)
	}
}

func TestFileStore_GetUserStats_Empty(t *testing.T) {
	env := setupFileTest(t)

	stats, err := env.fileStore.GetUserStats(env.alice.ID)
	if err != nil {
		t.Fatalf("get stats: %v", err)
	}
	if stats.FilesSent != 0 {
		t.Fatalf("expected 0 files sent, got %d", stats.FilesSent)
	}
	if stats.FilesReceived != 0 {
		t.Fatalf("expected 0 files received, got %d", stats.FilesReceived)
	}
	if stats.StorageUsed != 0 {
		t.Fatalf("expected 0 storage, got %d", stats.StorageUsed)
	}
}

func TestFileStore_ListExpired_WithThumbnail(t *testing.T) {
	env := setupFileTest(t)

	f := &model.File{
		SenderID:      env.alice.ID,
		RecipientID:   env.bob.ID,
		Filename:      "photo.jpg",
		FilePath:      "/uploads/photo.jpg",
		ThumbnailPath: "/uploads/thumbs/photo.jpg",
		FileType:      "image/jpeg",
		FileSize:      5000,
		ContentType:   "file",
		ExpiresAt:     time.Now().Add(-1 * time.Hour).UTC(),
	}
	env.fileStore.Create(f)

	files, err := env.fileStore.ListExpired()
	if err != nil {
		t.Fatalf("list expired: %v", err)
	}
	if len(files) != 1 {
		t.Fatalf("expected 1 expired, got %d", len(files))
	}
	if files[0].ThumbnailPath != "/uploads/thumbs/photo.jpg" {
		t.Fatalf("expected thumbnail path, got %q", files[0].ThumbnailPath)
	}
}

func TestFileStore_ListExpired_None(t *testing.T) {
	env := setupFileTest(t)

	env.fileStore.Create(&model.File{
		SenderID:    env.alice.ID,
		RecipientID: env.bob.ID,
		Filename:    "active.txt",
		FileType:    "document",
		ContentType: "file",
		ExpiresAt:   time.Now().Add(24 * time.Hour).UTC(),
	})

	files, err := env.fileStore.ListExpired()
	if err != nil {
		t.Fatalf("list expired: %v", err)
	}
	if len(files) != 0 {
		t.Fatalf("expected 0 expired, got %d", len(files))
	}
}

func TestFileStore_MarkRead_NonExistent(t *testing.T) {
	env := setupFileTest(t)

	err := env.fileStore.MarkRead("nonexistent-id")
	if err == nil {
		t.Fatal("expected error marking non-existent file as read")
	}
}

func TestFileStore_MarkRead_Idempotent(t *testing.T) {
	env := setupFileTest(t)

	f := &model.File{
		SenderID:    env.alice.ID,
		RecipientID: env.bob.ID,
		Filename:    "test.txt",
		FileType:    "document",
		ContentType: "file",
		ExpiresAt:   time.Now().Add(24 * time.Hour).UTC(),
	}
	created, _ := env.fileStore.Create(f)

	// Mark read twice should not error
	if err := env.fileStore.MarkRead(created.ID); err != nil {
		t.Fatalf("first mark read: %v", err)
	}
	if err := env.fileStore.MarkRead(created.ID); err != nil {
		t.Fatalf("second mark read: %v", err)
	}

	got, _ := env.fileStore.GetByID(created.ID)
	if !got.Read {
		t.Fatal("expected file to be read")
	}
}

func TestFileStore_Delete_NonExistent(t *testing.T) {
	env := setupFileTest(t)

	err := env.fileStore.Delete("nonexistent-id")
	if err == nil {
		t.Fatal("expected error deleting non-existent file")
	}
}

func TestFileStore_ListForRecipient_Pagination(t *testing.T) {
	env := setupFileTest(t)

	for i := 0; i < 5; i++ {
		env.fileStore.Create(&model.File{
			SenderID:    env.alice.ID,
			RecipientID: env.bob.ID,
			Filename:    "file.txt",
			FileType:    "document",
			FileSize:    100,
			ContentType: "file",
			ExpiresAt:   time.Now().Add(24 * time.Hour).UTC(),
		})
	}

	page1, _ := env.fileStore.ListForRecipient(env.bob.ID, 2, 0)
	if len(page1) != 2 {
		t.Fatalf("expected 2 on page 1, got %d", len(page1))
	}

	page2, _ := env.fileStore.ListForRecipient(env.bob.ID, 2, 2)
	if len(page2) != 2 {
		t.Fatalf("expected 2 on page 2, got %d", len(page2))
	}

	page3, _ := env.fileStore.ListForRecipient(env.bob.ID, 2, 4)
	if len(page3) != 1 {
		t.Fatalf("expected 1 on page 3, got %d", len(page3))
	}
}

func TestFileStore_PinnedFilesFirst(t *testing.T) {
	env := setupFileTest(t)

	// Create 3 files
	f1, _ := env.fileStore.Create(&model.File{
		SenderID: env.alice.ID, RecipientID: env.bob.ID,
		Filename: "first.txt", FileType: "document", ContentType: "file",
		ExpiresAt: time.Now().Add(24 * time.Hour).UTC(),
	})
	env.fileStore.Create(&model.File{
		SenderID: env.alice.ID, RecipientID: env.bob.ID,
		Filename: "second.txt", FileType: "document", ContentType: "file",
		ExpiresAt: time.Now().Add(24 * time.Hour).UTC(),
	})

	// Pin the first file
	env.fileStore.TogglePin(f1.ID)

	files, _ := env.fileStore.ListForRecipient(env.bob.ID, 10, 0)
	if len(files) != 2 {
		t.Fatalf("expected 2 files, got %d", len(files))
	}
	// Pinned file should appear first
	if files[0].ID != f1.ID {
		t.Fatal("expected pinned file to be first")
	}
	if !files[0].Pinned {
		t.Fatal("expected first file to be pinned")
	}
}
