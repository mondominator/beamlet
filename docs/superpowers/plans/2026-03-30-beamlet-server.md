# Beamlet Server Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a self-hosted Go server that accepts file uploads, stores them, manages users via CLI, and sends push notifications to iOS devices via APNs.

**Architecture:** Single Go binary serving both the HTTP API and CLI commands. SQLite for metadata, local disk for file storage. Uses golang-migrate for schema migrations. Dockerized for deployment on Unraid behind nginx.

**Tech Stack:** Go 1.22+, SQLite (modernc.org/sqlite — pure Go, no CGO), golang-migrate, chi router, APNs (sideshow/apns2), bcrypt for token hashing, Docker

---

## File Structure

```
server/
├── main.go                         # Entrypoint — CLI commands via cobra
├── go.mod
├── go.sum
├── Dockerfile
├── docker-compose.yml
├── cmd/
│   ├── serve.go                    # "beamlet serve" command
│   ├── adduser.go                  # "beamlet add-user" command
│   ├── listusers.go                # "beamlet list-users" command
│   └── revoketoken.go              # "beamlet revoke-token" command
├── internal/
│   ├── config/
│   │   └── config.go               # Configuration from env vars
│   ├── db/
│   │   ├── db.go                   # Database connection + migration runner
│   │   └── db_test.go
│   ├── model/
│   │   ├── user.go                 # User + Device structs
│   │   └── file.go                 # File metadata struct
│   ├── store/
│   │   ├── user_store.go           # User/device CRUD operations
│   │   ├── user_store_test.go
│   │   ├── file_store.go           # File metadata CRUD operations
│   │   └── file_store_test.go
│   ├── storage/
│   │   ├── disk.go                 # File read/write to disk
│   │   ├── disk_test.go
│   │   └── thumbnail.go            # Thumbnail generation
│   ├── auth/
│   │   ├── middleware.go           # Bearer token auth middleware
│   │   └── middleware_test.go
│   ├── push/
│   │   ├── apns.go                 # APNs notification sender
│   │   └── apns_test.go
│   ├── cleanup/
│   │   ├── cleanup.go              # Expired file cleanup goroutine
│   │   └── cleanup_test.go
│   └── api/
│       ├── router.go               # Route definitions
│       ├── users_handler.go        # GET /api/users
│       ├── users_handler_test.go
│       ├── files_handler.go        # POST/GET/DELETE /api/files
│       ├── files_handler_test.go
│       ├── device_handler.go       # POST /api/auth/register-device
│       └── device_handler_test.go
├── migrations/
│   ├── 001_create_users.up.sql
│   ├── 001_create_users.down.sql
│   ├── 002_create_devices.up.sql
│   ├── 002_create_devices.down.sql
│   ├── 003_create_files.up.sql
│   └── 003_create_files.down.sql
└── testutil/
    └── testutil.go                 # Shared test helpers (temp DB, etc.)
```

---

### Task 1: Project Scaffolding and Database

**Files:**
- Create: `server/go.mod`
- Create: `server/main.go`
- Create: `server/internal/config/config.go`
- Create: `server/internal/db/db.go`
- Create: `server/internal/db/db_test.go`
- Create: `server/testutil/testutil.go`
- Create: `server/migrations/001_create_users.up.sql`
- Create: `server/migrations/001_create_users.down.sql`
- Create: `server/migrations/002_create_devices.up.sql`
- Create: `server/migrations/002_create_devices.down.sql`
- Create: `server/migrations/003_create_files.up.sql`
- Create: `server/migrations/003_create_files.down.sql`

- [ ] **Step 1: Initialize Go module**

```bash
mkdir -p server && cd server
go mod init github.com/mondominator/beamlet/server
```

- [ ] **Step 2: Create config**

Create `server/internal/config/config.go`:

```go
package config

import (
	"os"
	"strconv"
)

type Config struct {
	DBPath       string
	DataDir      string
	Port         string
	APNsKeyPath  string
	APNsKeyID    string
	APNsTeamID   string
	APNsBundleID string
	MaxFileSize  int64
	ExpiryDays   int
}

func Load() Config {
	maxSize, _ := strconv.ParseInt(getEnv("BEAMLET_MAX_FILE_SIZE", "524288000"), 10, 64)
	expiryDays, _ := strconv.Atoi(getEnv("BEAMLET_EXPIRY_DAYS", "30"))

	return Config{
		DBPath:       getEnv("BEAMLET_DB_PATH", "/data/beamlet.db"),
		DataDir:      getEnv("BEAMLET_DATA_DIR", "/data/files"),
		Port:         getEnv("BEAMLET_PORT", "8080"),
		APNsKeyPath:  getEnv("BEAMLET_APNS_KEY_PATH", ""),
		APNsKeyID:    getEnv("BEAMLET_APNS_KEY_ID", ""),
		APNsTeamID:   getEnv("BEAMLET_APNS_TEAM_ID", ""),
		APNsBundleID: getEnv("BEAMLET_APNS_BUNDLE_ID", ""),
		MaxFileSize:  maxSize,
		ExpiryDays:   expiryDays,
	}
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
```

- [ ] **Step 3: Create migration SQL files**

Create `server/migrations/001_create_users.up.sql`:

```sql
CREATE TABLE users (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    token_hash TEXT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
```

Create `server/migrations/001_create_users.down.sql`:

```sql
DROP TABLE users;
```

Create `server/migrations/002_create_devices.up.sql`:

```sql
CREATE TABLE devices (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    apns_token TEXT NOT NULL,
    platform TEXT NOT NULL DEFAULT 'ios',
    active INTEGER NOT NULL DEFAULT 1,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_devices_user_id ON devices(user_id);
```

Create `server/migrations/002_create_devices.down.sql`:

```sql
DROP TABLE devices;
```

Create `server/migrations/003_create_files.up.sql`:

```sql
CREATE TABLE files (
    id TEXT PRIMARY KEY,
    sender_id TEXT NOT NULL REFERENCES users(id),
    recipient_id TEXT NOT NULL REFERENCES users(id),
    filename TEXT NOT NULL,
    file_path TEXT,
    thumbnail_path TEXT,
    file_type TEXT NOT NULL,
    file_size INTEGER NOT NULL DEFAULT 0,
    content_type TEXT NOT NULL DEFAULT 'file',
    text_content TEXT,
    message TEXT,
    read INTEGER NOT NULL DEFAULT 0,
    expires_at TIMESTAMP NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_files_recipient_id ON files(recipient_id);
CREATE INDEX idx_files_expires_at ON files(expires_at);
```

Create `server/migrations/003_create_files.down.sql`:

```sql
DROP TABLE files;
```

- [ ] **Step 4: Create test helpers**

Create `server/testutil/testutil.go`:

```go
package testutil

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/mondominator/beamlet/server/internal/db"
)

func TestDB(t *testing.T) *db.DB {
	t.Helper()
	tmpDir := t.TempDir()
	dbPath := filepath.Join(tmpDir, "test.db")
	migrationsPath := findMigrationsDir(t)

	database, err := db.Open(dbPath, migrationsPath)
	if err != nil {
		t.Fatalf("failed to open test db: %v", err)
	}
	t.Cleanup(func() { database.Close() })
	return database
}

func findMigrationsDir(t *testing.T) string {
	t.Helper()
	// Walk up from the test's working directory to find migrations/
	dir, err := os.Getwd()
	if err != nil {
		t.Fatalf("failed to get working directory: %v", err)
	}
	for {
		candidate := filepath.Join(dir, "migrations")
		if info, err := os.Stat(candidate); err == nil && info.IsDir() {
			return candidate
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			t.Fatal("could not find migrations directory")
		}
		dir = parent
	}
}
```

- [ ] **Step 5: Write the failing test for database initialization**

Create `server/internal/db/db_test.go`:

```go
package db_test

import (
	"testing"

	"github.com/mondominator/beamlet/server/testutil"
)

func TestOpen_RunsMigrations(t *testing.T) {
	database := testutil.TestDB(t)

	// Verify all three tables exist by querying sqlite_master
	rows, err := database.SQL().Query(
		"SELECT name FROM sqlite_master WHERE type='table' AND name IN ('users', 'devices', 'files') ORDER BY name",
	)
	if err != nil {
		t.Fatalf("query failed: %v", err)
	}
	defer rows.Close()

	var tables []string
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err != nil {
			t.Fatalf("scan failed: %v", err)
		}
		tables = append(tables, name)
	}

	if len(tables) != 3 {
		t.Fatalf("expected 3 tables, got %d: %v", len(tables), tables)
	}
	if tables[0] != "devices" || tables[1] != "files" || tables[2] != "users" {
		t.Fatalf("unexpected tables: %v", tables)
	}
}
```

- [ ] **Step 6: Run test to verify it fails**

```bash
cd server && go test ./internal/db/ -v
```

Expected: Compilation error — `db.Open` and `db.DB` don't exist yet.

- [ ] **Step 7: Implement db package**

Create `server/internal/db/db.go`:

```go
package db

import (
	"database/sql"
	"fmt"

	"github.com/golang-migrate/migrate/v4"
	"github.com/golang-migrate/migrate/v4/database/sqlite"
	_ "github.com/golang-migrate/migrate/v4/source/file"
	_ "modernc.org/sqlite"
)

type DB struct {
	db *sql.DB
}

func Open(dbPath, migrationsPath string) (*DB, error) {
	sqlDB, err := sql.Open("sqlite", dbPath+"?_pragma=journal_mode(wal)&_pragma=foreign_keys(on)")
	if err != nil {
		return nil, fmt.Errorf("open database: %w", err)
	}

	if err := runMigrations(sqlDB, migrationsPath); err != nil {
		sqlDB.Close()
		return nil, fmt.Errorf("run migrations: %w", err)
	}

	return &DB{db: sqlDB}, nil
}

func (d *DB) SQL() *sql.DB {
	return d.db
}

func (d *DB) Close() error {
	return d.db.Close()
}

func runMigrations(sqlDB *sql.DB, migrationsPath string) error {
	driver, err := sqlite.WithInstance(sqlDB, &sqlite.Config{})
	if err != nil {
		return fmt.Errorf("create migration driver: %w", err)
	}

	m, err := migrate.NewWithDatabaseInstance(
		"file://"+migrationsPath,
		"sqlite",
		driver,
	)
	if err != nil {
		return fmt.Errorf("create migrator: %w", err)
	}

	if err := m.Up(); err != nil && err != migrate.ErrNoChange {
		return fmt.Errorf("apply migrations: %w", err)
	}

	return nil
}
```

- [ ] **Step 8: Install dependencies**

```bash
cd server && go mod tidy
```

- [ ] **Step 9: Run test to verify it passes**

```bash
cd server && go test ./internal/db/ -v
```

Expected: PASS

- [ ] **Step 10: Create main.go entrypoint stub**

Create `server/main.go`:

```go
package main

import (
	"fmt"
	"os"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: beamlet <command>")
		fmt.Fprintln(os.Stderr, "commands: serve, add-user, list-users, revoke-token")
		os.Exit(1)
	}
	fmt.Fprintln(os.Stderr, "command not yet implemented:", os.Args[1])
	os.Exit(1)
}
```

- [ ] **Step 11: Commit**

```bash
cd server
git add .
git commit -m "feat: project scaffolding with database migrations and config"
```

---

### Task 2: Models and User Store

**Files:**
- Create: `server/internal/model/user.go`
- Create: `server/internal/model/file.go`
- Create: `server/internal/store/user_store.go`
- Create: `server/internal/store/user_store_test.go`

- [ ] **Step 1: Create model types**

Create `server/internal/model/user.go`:

```go
package model

import "time"

type User struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	TokenHash string    `json:"-"`
	CreatedAt time.Time `json:"created_at"`
}

type Device struct {
	ID        string    `json:"id"`
	UserID    string    `json:"user_id"`
	APNsToken string    `json:"apns_token"`
	Platform  string    `json:"platform"`
	Active    bool      `json:"active"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}
```

Create `server/internal/model/file.go`:

```go
package model

import "time"

type File struct {
	ID            string    `json:"id"`
	SenderID      string    `json:"sender_id"`
	RecipientID   string    `json:"recipient_id"`
	Filename      string    `json:"filename"`
	FilePath      string    `json:"-"`
	ThumbnailPath string    `json:"-"`
	FileType      string    `json:"file_type"`
	FileSize      int64     `json:"file_size"`
	ContentType   string    `json:"content_type"`
	TextContent   string    `json:"text_content,omitempty"`
	Message       string    `json:"message,omitempty"`
	Read          bool      `json:"read"`
	ExpiresAt     time.Time `json:"expires_at"`
	CreatedAt     time.Time `json:"created_at"`
	SenderName    string    `json:"sender_name,omitempty"`
}
```

- [ ] **Step 2: Write failing tests for user store**

Create `server/internal/store/user_store_test.go`:

```go
package store_test

import (
	"testing"

	"github.com/mondominator/beamlet/server/internal/store"
	"github.com/mondominator/beamlet/server/testutil"
)

func TestUserStore_CreateAndGet(t *testing.T) {
	db := testutil.TestDB(t)
	s := store.NewUserStore(db.SQL())

	user, token, err := s.Create("Alice")
	if err != nil {
		t.Fatalf("create user: %v", err)
	}
	if user.Name != "Alice" {
		t.Fatalf("expected name Alice, got %s", user.Name)
	}
	if token == "" {
		t.Fatal("expected non-empty token")
	}
	if user.ID == "" {
		t.Fatal("expected non-empty ID")
	}

	got, err := s.GetByID(user.ID)
	if err != nil {
		t.Fatalf("get by id: %v", err)
	}
	if got.Name != "Alice" {
		t.Fatalf("expected Alice, got %s", got.Name)
	}
}

func TestUserStore_Authenticate(t *testing.T) {
	db := testutil.TestDB(t)
	s := store.NewUserStore(db.SQL())

	_, token, err := s.Create("Bob")
	if err != nil {
		t.Fatalf("create user: %v", err)
	}

	user, err := s.Authenticate(token)
	if err != nil {
		t.Fatalf("authenticate: %v", err)
	}
	if user.Name != "Bob" {
		t.Fatalf("expected Bob, got %s", user.Name)
	}

	_, err = s.Authenticate("wrong-token")
	if err == nil {
		t.Fatal("expected error for bad token")
	}
}

func TestUserStore_List(t *testing.T) {
	db := testutil.TestDB(t)
	s := store.NewUserStore(db.SQL())

	s.Create("Alice")
	s.Create("Bob")

	users, err := s.List()
	if err != nil {
		t.Fatalf("list: %v", err)
	}
	if len(users) != 2 {
		t.Fatalf("expected 2 users, got %d", len(users))
	}
}

func TestUserStore_RevokeToken(t *testing.T) {
	db := testutil.TestDB(t)
	s := store.NewUserStore(db.SQL())

	user, oldToken, _ := s.Create("Alice")

	newToken, err := s.RevokeToken(user.ID)
	if err != nil {
		t.Fatalf("revoke token: %v", err)
	}
	if newToken == oldToken {
		t.Fatal("expected new token to differ from old")
	}

	// Old token should fail
	_, err = s.Authenticate(oldToken)
	if err == nil {
		t.Fatal("old token should no longer work")
	}

	// New token should work
	_, err = s.Authenticate(newToken)
	if err != nil {
		t.Fatalf("new token should work: %v", err)
	}
}
```

- [ ] **Step 3: Run tests to verify they fail**

```bash
cd server && go test ./internal/store/ -v
```

Expected: Compilation error — `store.NewUserStore` doesn't exist.

- [ ] **Step 4: Implement user store**

Create `server/internal/store/user_store.go`:

```go
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
```

- [ ] **Step 5: Install dependencies and run tests**

```bash
cd server && go mod tidy && go test ./internal/store/ -v
```

Expected: PASS — all 4 tests pass.

- [ ] **Step 6: Commit**

```bash
cd server
git add .
git commit -m "feat: add models and user store with token auth"
```

---

### Task 3: File Store

**Files:**
- Create: `server/internal/store/file_store.go`
- Create: `server/internal/store/file_store_test.go`

- [ ] **Step 1: Write failing tests**

Create `server/internal/store/file_store_test.go`:

```go
package store_test

import (
	"testing"
	"time"

	"github.com/mondominator/beamlet/server/internal/model"
	"github.com/mondominator/beamlet/server/internal/store"
	"github.com/mondominator/beamlet/server/testutil"
)

func setupFileTest(t *testing.T) (*store.FileStore, *model.User, *model.User) {
	t.Helper()
	db := testutil.TestDB(t)
	us := store.NewUserStore(db.SQL())
	fs := store.NewFileStore(db.SQL())

	sender, _, _ := us.Create("Alice")
	recipient, _, _ := us.Create("Bob")
	return fs, sender, recipient
}

func TestFileStore_CreateAndGet(t *testing.T) {
	fs, sender, recipient := setupFileTest(t)

	f := &model.File{
		SenderID:    sender.ID,
		RecipientID: recipient.ID,
		Filename:    "photo.jpg",
		FilePath:    "/data/files/2026/03/abc.jpg",
		FileType:    "image/jpeg",
		FileSize:    12345,
		ContentType: "file",
		ExpiresAt:   time.Now().Add(30 * 24 * time.Hour),
	}

	created, err := fs.Create(f)
	if err != nil {
		t.Fatalf("create file: %v", err)
	}
	if created.ID == "" {
		t.Fatal("expected non-empty ID")
	}

	got, err := fs.GetByID(created.ID)
	if err != nil {
		t.Fatalf("get by id: %v", err)
	}
	if got.Filename != "photo.jpg" {
		t.Fatalf("expected photo.jpg, got %s", got.Filename)
	}
}

func TestFileStore_ListForRecipient(t *testing.T) {
	fs, sender, recipient := setupFileTest(t)

	for i := 0; i < 3; i++ {
		fs.Create(&model.File{
			SenderID:    sender.ID,
			RecipientID: recipient.ID,
			Filename:    "file.jpg",
			FileType:    "image/jpeg",
			ContentType: "file",
			ExpiresAt:   time.Now().Add(30 * 24 * time.Hour),
		})
	}

	files, err := fs.ListForRecipient(recipient.ID, 10, 0)
	if err != nil {
		t.Fatalf("list: %v", err)
	}
	if len(files) != 3 {
		t.Fatalf("expected 3 files, got %d", len(files))
	}
	// Should include sender name
	if files[0].SenderName != "Alice" {
		t.Fatalf("expected sender name Alice, got %s", files[0].SenderName)
	}
}

func TestFileStore_MarkRead(t *testing.T) {
	fs, sender, recipient := setupFileTest(t)

	f, _ := fs.Create(&model.File{
		SenderID:    sender.ID,
		RecipientID: recipient.ID,
		Filename:    "doc.pdf",
		FileType:    "application/pdf",
		ContentType: "file",
		ExpiresAt:   time.Now().Add(30 * 24 * time.Hour),
	})

	if err := fs.MarkRead(f.ID); err != nil {
		t.Fatalf("mark read: %v", err)
	}

	got, _ := fs.GetByID(f.ID)
	if !got.Read {
		t.Fatal("expected file to be marked as read")
	}
}

func TestFileStore_Delete(t *testing.T) {
	fs, sender, recipient := setupFileTest(t)

	f, _ := fs.Create(&model.File{
		SenderID:    sender.ID,
		RecipientID: recipient.ID,
		Filename:    "doc.pdf",
		FileType:    "application/pdf",
		ContentType: "file",
		ExpiresAt:   time.Now().Add(30 * 24 * time.Hour),
	})

	if err := fs.Delete(f.ID); err != nil {
		t.Fatalf("delete: %v", err)
	}

	_, err := fs.GetByID(f.ID)
	if err == nil {
		t.Fatal("expected error getting deleted file")
	}
}

func TestFileStore_ListExpired(t *testing.T) {
	fs, sender, recipient := setupFileTest(t)

	// Create an already-expired file
	fs.Create(&model.File{
		SenderID:    sender.ID,
		RecipientID: recipient.ID,
		Filename:    "old.jpg",
		FileType:    "image/jpeg",
		ContentType: "file",
		ExpiresAt:   time.Now().Add(-1 * time.Hour),
	})

	// Create a non-expired file
	fs.Create(&model.File{
		SenderID:    sender.ID,
		RecipientID: recipient.ID,
		Filename:    "new.jpg",
		FileType:    "image/jpeg",
		ContentType: "file",
		ExpiresAt:   time.Now().Add(30 * 24 * time.Hour),
	})

	expired, err := fs.ListExpired()
	if err != nil {
		t.Fatalf("list expired: %v", err)
	}
	if len(expired) != 1 {
		t.Fatalf("expected 1 expired file, got %d", len(expired))
	}
	if expired[0].Filename != "old.jpg" {
		t.Fatalf("expected old.jpg, got %s", expired[0].Filename)
	}
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd server && go test ./internal/store/ -v -run TestFileStore
```

Expected: Compilation error — `store.NewFileStore` doesn't exist.

- [ ] **Step 3: Implement file store**

Create `server/internal/store/file_store.go`:

```go
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
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?)`,
		f.ID, f.SenderID, f.RecipientID, f.Filename, f.FilePath, f.ThumbnailPath,
		f.FileType, f.FileSize, f.ContentType, f.TextContent, f.Message,
		f.ExpiresAt, f.CreatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("insert file: %w", err)
	}
	return f, nil
}

func (s *FileStore) GetByID(id string) (*model.File, error) {
	var f model.File
	var textContent, message, thumbnailPath, filePath sql.NullString
	err := s.db.QueryRow(
		`SELECT id, sender_id, recipient_id, filename, file_path, thumbnail_path,
		 file_type, file_size, content_type, text_content, message, read, expires_at, created_at
		 FROM files WHERE id = ?`, id,
	).Scan(
		&f.ID, &f.SenderID, &f.RecipientID, &f.Filename, &filePath, &thumbnailPath,
		&f.FileType, &f.FileSize, &f.ContentType, &textContent, &message,
		&f.Read, &f.ExpiresAt, &f.CreatedAt,
	)
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
		 f.file_type, f.file_size, f.content_type, f.text_content, f.message, f.read,
		 f.expires_at, f.created_at, u.name as sender_name
		 FROM files f JOIN users u ON f.sender_id = u.id
		 WHERE f.recipient_id = ?
		 ORDER BY f.created_at DESC
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
		var textContent, message, thumbnailPath, filePath sql.NullString
		if err := rows.Scan(
			&f.ID, &f.SenderID, &f.RecipientID, &f.Filename, &filePath, &thumbnailPath,
			&f.FileType, &f.FileSize, &f.ContentType, &textContent, &message,
			&f.Read, &f.ExpiresAt, &f.CreatedAt, &f.SenderName,
		); err != nil {
			return nil, fmt.Errorf("scan file: %w", err)
		}
		f.FilePath = filePath.String
		f.ThumbnailPath = thumbnailPath.String
		f.TextContent = textContent.String
		f.Message = message.String
		files = append(files, f)
	}
	return files, nil
}

func (s *FileStore) MarkRead(id string) error {
	_, err := s.db.Exec("UPDATE files SET read = 1 WHERE id = ?", id)
	return err
}

func (s *FileStore) Delete(id string) error {
	_, err := s.db.Exec("DELETE FROM files WHERE id = ?", id)
	return err
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
	return files, nil
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd server && go mod tidy && go test ./internal/store/ -v
```

Expected: PASS — all store tests pass.

- [ ] **Step 5: Commit**

```bash
cd server
git add .
git commit -m "feat: add file store with CRUD and expiry queries"
```

---

### Task 4: Disk Storage and Thumbnails

**Files:**
- Create: `server/internal/storage/disk.go`
- Create: `server/internal/storage/disk_test.go`
- Create: `server/internal/storage/thumbnail.go`

- [ ] **Step 1: Write failing tests for disk storage**

Create `server/internal/storage/disk_test.go`:

```go
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

	// Path should be under the data dir
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
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd server && go test ./internal/storage/ -v
```

Expected: Compilation error — `storage.NewDiskStorage` doesn't exist.

- [ ] **Step 3: Implement disk storage**

Create `server/internal/storage/disk.go`:

```go
package storage

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
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
	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("open file: %w", err)
	}
	return f, nil
}

func (s *DiskStorage) Delete(path string) error {
	if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("delete file: %w", err)
	}
	return nil
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd server && go test ./internal/storage/ -v
```

Expected: PASS

- [ ] **Step 5: Create thumbnail stub**

Create `server/internal/storage/thumbnail.go`:

```go
package storage

import (
	"fmt"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/google/uuid"
)

func GenerateThumbnail(srcPath, destDir, mimeType string) (string, error) {
	if !strings.HasPrefix(mimeType, "image/") && !strings.HasPrefix(mimeType, "video/") {
		return "", nil
	}

	thumbName := uuid.New().String() + ".jpg"
	thumbPath := filepath.Join(destDir, thumbName)

	if strings.HasPrefix(mimeType, "image/") {
		// Use ImageMagick convert to resize
		cmd := exec.Command("convert", srcPath, "-thumbnail", "200x200>", "-quality", "80", thumbPath)
		if err := cmd.Run(); err != nil {
			return "", fmt.Errorf("generate image thumbnail: %w", err)
		}
	} else if strings.HasPrefix(mimeType, "video/") {
		// Use ffmpeg to grab first frame
		cmd := exec.Command("ffmpeg", "-i", srcPath, "-vframes", "1", "-vf", "scale=200:-1", "-y", thumbPath)
		if err := cmd.Run(); err != nil {
			return "", fmt.Errorf("generate video thumbnail: %w", err)
		}
	}

	return thumbPath, nil
}
```

- [ ] **Step 6: Commit**

```bash
cd server
git add .
git commit -m "feat: add disk storage and thumbnail generation"
```

---

### Task 5: Auth Middleware

**Files:**
- Create: `server/internal/auth/middleware.go`
- Create: `server/internal/auth/middleware_test.go`

- [ ] **Step 1: Write failing tests**

Create `server/internal/auth/middleware_test.go`:

```go
package auth_test

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/mondominator/beamlet/server/internal/auth"
	"github.com/mondominator/beamlet/server/internal/store"
	"github.com/mondominator/beamlet/server/testutil"
)

func TestMiddleware_ValidToken(t *testing.T) {
	db := testutil.TestDB(t)
	us := store.NewUserStore(db.SQL())
	_, token, _ := us.Create("Alice")

	handler := auth.Middleware(us)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		user := auth.UserFromContext(r.Context())
		if user == nil {
			t.Fatal("expected user in context")
		}
		if user.Name != "Alice" {
			t.Fatalf("expected Alice, got %s", user.Name)
		}
		w.WriteHeader(http.StatusOK)
	}))

	req := httptest.NewRequest("GET", "/", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
}

func TestMiddleware_MissingToken(t *testing.T) {
	db := testutil.TestDB(t)
	us := store.NewUserStore(db.SQL())

	handler := auth.Middleware(us)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t.Fatal("handler should not be called")
	}))

	req := httptest.NewRequest("GET", "/", nil)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", rec.Code)
	}
}

func TestMiddleware_InvalidToken(t *testing.T) {
	db := testutil.TestDB(t)
	us := store.NewUserStore(db.SQL())

	handler := auth.Middleware(us)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t.Fatal("handler should not be called")
	}))

	req := httptest.NewRequest("GET", "/", nil)
	req.Header.Set("Authorization", "Bearer bad-token")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", rec.Code)
	}
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd server && go test ./internal/auth/ -v
```

Expected: Compilation error.

- [ ] **Step 3: Implement auth middleware**

Create `server/internal/auth/middleware.go`:

```go
package auth

import (
	"context"
	"net/http"
	"strings"

	"github.com/mondominator/beamlet/server/internal/model"
	"github.com/mondominator/beamlet/server/internal/store"
)

type contextKey string

const userContextKey contextKey = "user"

func Middleware(users *store.UserStore) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			header := r.Header.Get("Authorization")
			if header == "" || !strings.HasPrefix(header, "Bearer ") {
				http.Error(w, "unauthorized", http.StatusUnauthorized)
				return
			}

			token := strings.TrimPrefix(header, "Bearer ")
			user, err := users.Authenticate(token)
			if err != nil {
				http.Error(w, "unauthorized", http.StatusUnauthorized)
				return
			}

			ctx := context.WithValue(r.Context(), userContextKey, user)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

func UserFromContext(ctx context.Context) *model.User {
	user, _ := ctx.Value(userContextKey).(*model.User)
	return user
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd server && go test ./internal/auth/ -v
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd server
git add .
git commit -m "feat: add bearer token auth middleware"
```

---

### Task 6: API Handlers — Users and Devices

**Files:**
- Create: `server/internal/api/router.go`
- Create: `server/internal/api/users_handler.go`
- Create: `server/internal/api/users_handler_test.go`
- Create: `server/internal/api/device_handler.go`
- Create: `server/internal/api/device_handler_test.go`

- [ ] **Step 1: Create router**

Create `server/internal/api/router.go`:

```go
package api

import (
	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/mondominator/beamlet/server/internal/auth"
	"github.com/mondominator/beamlet/server/internal/config"
	"github.com/mondominator/beamlet/server/internal/push"
	"github.com/mondominator/beamlet/server/internal/storage"
	"github.com/mondominator/beamlet/server/internal/store"
)

type Server struct {
	UserStore   *store.UserStore
	FileStore   *store.FileStore
	Storage     *storage.DiskStorage
	Pusher      *push.APNsPusher
	Config      config.Config
}

func NewRouter(s *Server) *chi.Mux {
	r := chi.NewRouter()
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)

	r.Route("/api", func(r chi.Router) {
		r.Use(auth.Middleware(s.UserStore))

		r.Get("/users", s.ListUsers)
		r.Post("/auth/register-device", s.RegisterDevice)
		r.Post("/files", s.UploadFile)
		r.Get("/files", s.ListFiles)
		r.Get("/files/{id}", s.DownloadFile)
		r.Get("/files/{id}/thumbnail", s.DownloadThumbnail)
		r.Delete("/files/{id}", s.DeleteFile)
		r.Put("/files/{id}/read", s.MarkFileRead)
	})

	return r
}
```

- [ ] **Step 2: Write failing tests for users handler**

Create `server/internal/api/users_handler_test.go`:

```go
package api_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/mondominator/beamlet/server/internal/api"
	"github.com/mondominator/beamlet/server/internal/config"
	"github.com/mondominator/beamlet/server/internal/store"
	"github.com/mondominator/beamlet/server/internal/storage"
	"github.com/mondominator/beamlet/server/testutil"
)

func setupTestServer(t *testing.T) (*api.Server, string) {
	t.Helper()
	db := testutil.TestDB(t)
	tmpDir := t.TempDir()

	us := store.NewUserStore(db.SQL())
	fs := store.NewFileStore(db.SQL())
	ds := storage.NewDiskStorage(tmpDir)

	_, token, _ := us.Create("Alice")
	us.Create("Bob")

	srv := &api.Server{
		UserStore: us,
		FileStore: fs,
		Storage:   ds,
		Config:    config.Config{MaxFileSize: 524288000, ExpiryDays: 30, DataDir: tmpDir},
	}
	return srv, token
}

func TestListUsers(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	req := httptest.NewRequest("GET", "/api/users", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	var users []struct {
		Name string `json:"name"`
	}
	if err := json.NewDecoder(rec.Body).Decode(&users); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(users) != 2 {
		t.Fatalf("expected 2 users, got %d", len(users))
	}
}
```

- [ ] **Step 3: Run tests to verify they fail**

```bash
cd server && go test ./internal/api/ -v
```

Expected: Compilation error.

- [ ] **Step 4: Implement users handler**

Create `server/internal/api/users_handler.go`:

```go
package api

import (
	"encoding/json"
	"net/http"
)

func (s *Server) ListUsers(w http.ResponseWriter, r *http.Request) {
	users, err := s.UserStore.List()
	if err != nil {
		http.Error(w, "failed to list users", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(users)
}
```

- [ ] **Step 5: Write failing test for device registration**

Create `server/internal/api/device_handler_test.go`:

```go
package api_test

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/mondominator/beamlet/server/internal/api"
)

func TestRegisterDevice(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	body := `{"apns_token":"abc123","platform":"ios"}`
	req := httptest.NewRequest("POST", "/api/auth/register-device", strings.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
}
```

- [ ] **Step 6: Implement device handler**

Create `server/internal/api/device_handler.go`:

```go
package api

import (
	"encoding/json"
	"net/http"

	"github.com/mondominator/beamlet/server/internal/auth"
)

type registerDeviceRequest struct {
	APNsToken string `json:"apns_token"`
	Platform  string `json:"platform"`
}

func (s *Server) RegisterDevice(w http.ResponseWriter, r *http.Request) {
	var req registerDeviceRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid request body", http.StatusBadRequest)
		return
	}

	if req.APNsToken == "" {
		http.Error(w, "apns_token is required", http.StatusBadRequest)
		return
	}
	if req.Platform == "" {
		req.Platform = "ios"
	}

	user := auth.UserFromContext(r.Context())
	if err := s.UserStore.RegisterDevice(user.ID, req.APNsToken, req.Platform); err != nil {
		http.Error(w, "failed to register device", http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}
```

- [ ] **Step 7: Add RegisterDevice to user store**

Add to `server/internal/store/user_store.go`:

```go
func (s *UserStore) RegisterDevice(userID, apnsToken, platform string) error {
	id := uuid.New().String()
	now := time.Now().UTC()

	// Upsert: if this apns_token already exists for this user, update it
	_, err := s.db.Exec(
		`INSERT INTO devices (id, user_id, apns_token, platform, active, created_at, updated_at)
		 VALUES (?, ?, ?, ?, 1, ?, ?)
		 ON CONFLICT(apns_token, user_id) DO UPDATE SET active = 1, updated_at = ?`,
		id, userID, apnsToken, platform, now, now, now,
	)
	return err
}

func (s *UserStore) GetActiveDevices(userID string) ([]model.Device, error) {
	rows, err := s.db.Query(
		"SELECT id, user_id, apns_token, platform, active, created_at, updated_at FROM devices WHERE user_id = ? AND active = 1",
		userID,
	)
	if err != nil {
		return nil, fmt.Errorf("query devices: %w", err)
	}
	defer rows.Close()

	var devices []model.Device
	for rows.Next() {
		var d model.Device
		if err := rows.Scan(&d.ID, &d.UserID, &d.APNsToken, &d.Platform, &d.Active, &d.CreatedAt, &d.UpdatedAt); err != nil {
			return nil, fmt.Errorf("scan device: %w", err)
		}
		devices = append(devices, d)
	}
	return devices, nil
}

func (s *UserStore) DeactivateDevice(apnsToken string) error {
	_, err := s.db.Exec("UPDATE devices SET active = 0, updated_at = ? WHERE apns_token = ?", time.Now().UTC(), apnsToken)
	return err
}
```

**Note:** The `ON CONFLICT` requires a unique index. Add to migration `002_create_devices.up.sql` — append this line:

```sql
CREATE UNIQUE INDEX idx_devices_user_apns ON devices(user_id, apns_token);
```

- [ ] **Step 8: Run all tests**

```bash
cd server && go mod tidy && go test ./... -v
```

Expected: PASS

- [ ] **Step 9: Commit**

```bash
cd server
git add .
git commit -m "feat: add API router, users handler, and device registration"
```

---

### Task 7: API Handlers — Files

**Files:**
- Create: `server/internal/api/files_handler.go`
- Create: `server/internal/api/files_handler_test.go`

- [ ] **Step 1: Write failing tests for file upload and list**

Create `server/internal/api/files_handler_test.go`:

```go
package api_test

import (
	"bytes"
	"encoding/json"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/mondominator/beamlet/server/internal/api"
	"github.com/mondominator/beamlet/server/internal/model"
	"github.com/mondominator/beamlet/server/internal/store"
)

func TestUploadFile(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	// Get Bob's ID for recipient
	users, _ := srv.UserStore.List()
	var bobID string
	for _, u := range users {
		if u.Name == "Bob" {
			bobID = u.ID
		}
	}

	body := &bytes.Buffer{}
	writer := multipart.NewWriter(body)
	writer.WriteField("recipient_id", bobID)
	writer.WriteField("message", "check this out")
	part, _ := writer.CreateFormFile("file", "photo.jpg")
	part.Write([]byte("fake image data"))
	writer.Close()

	req := httptest.NewRequest("POST", "/api/files", body)
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", writer.FormDataContentType())
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d: %s", rec.Code, rec.Body.String())
	}

	var f model.File
	if err := json.NewDecoder(rec.Body).Decode(&f); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if f.Filename != "photo.jpg" {
		t.Fatalf("expected photo.jpg, got %s", f.Filename)
	}
}

func TestUploadText(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	users, _ := srv.UserStore.List()
	var bobID string
	for _, u := range users {
		if u.Name == "Bob" {
			bobID = u.ID
		}
	}

	body := &bytes.Buffer{}
	writer := multipart.NewWriter(body)
	writer.WriteField("recipient_id", bobID)
	writer.WriteField("content_type", "text")
	writer.WriteField("text_content", "Hello from Alice!")
	writer.Close()

	req := httptest.NewRequest("POST", "/api/files", body)
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", writer.FormDataContentType())
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestListFiles(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	// Get user IDs
	users, _ := srv.UserStore.List()
	var aliceID, bobID string
	for _, u := range users {
		if u.Name == "Alice" {
			aliceID = u.ID
		} else {
			bobID = u.ID
		}
	}

	// Create a file sent to Alice (so Alice can see it in her list)
	_, bobToken, _ := srv.UserStore.Create("Charlie")
	_ = bobToken
	srv.FileStore.Create(&model.File{
		SenderID:    bobID,
		RecipientID: aliceID,
		Filename:    "test.jpg",
		FileType:    "image/jpeg",
		ContentType: "file",
	})

	req := httptest.NewRequest("GET", "/api/files?limit=10&offset=0", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	var files []model.File
	json.NewDecoder(rec.Body).Decode(&files)
	if len(files) != 1 {
		t.Fatalf("expected 1 file, got %d", len(files))
	}
}

func TestDownloadFile(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	// Upload a file first
	users, _ := srv.UserStore.List()
	var aliceID, bobID string
	for _, u := range users {
		if u.Name == "Alice" {
			aliceID = u.ID
		} else if u.Name == "Bob" {
			bobID = u.ID
		}
	}

	// Save a file to disk
	fileContent := []byte("hello file content")
	path, _ := srv.Storage.Save("test.txt", "text/plain", bytes.NewReader(fileContent))

	f, _ := srv.FileStore.Create(&model.File{
		SenderID:    bobID,
		RecipientID: aliceID,
		Filename:    "test.txt",
		FilePath:    path,
		FileType:    "text/plain",
		FileSize:    int64(len(fileContent)),
		ContentType: "file",
	})

	req := httptest.NewRequest("GET", "/api/files/"+f.ID, nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	if rec.Body.String() != "hello file content" {
		t.Fatalf("unexpected body: %s", rec.Body.String())
	}
}

func TestDeleteFile(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	users, _ := srv.UserStore.List()
	var aliceID, bobID string
	for _, u := range users {
		if u.Name == "Alice" {
			aliceID = u.ID
		} else if u.Name == "Bob" {
			bobID = u.ID
		}
	}

	f, _ := srv.FileStore.Create(&model.File{
		SenderID:    bobID,
		RecipientID: aliceID,
		Filename:    "delete-me.txt",
		FileType:    "text/plain",
		ContentType: "file",
	})

	req := httptest.NewRequest("DELETE", "/api/files/"+f.ID, nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
}

func TestMarkFileRead(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	users, _ := srv.UserStore.List()
	var aliceID, bobID string
	for _, u := range users {
		if u.Name == "Alice" {
			aliceID = u.ID
		} else if u.Name == "Bob" {
			bobID = u.ID
		}
	}

	f, _ := srv.FileStore.Create(&model.File{
		SenderID:    bobID,
		RecipientID: aliceID,
		Filename:    "read-me.txt",
		FileType:    "text/plain",
		ContentType: "file",
	})

	req := httptest.NewRequest("PUT", "/api/files/"+f.ID+"/read", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}

	got, _ := srv.FileStore.GetByID(f.ID)
	if !got.Read {
		t.Fatal("expected file to be marked read")
	}
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd server && go test ./internal/api/ -v
```

Expected: Compilation error — file handler methods don't exist.

- [ ] **Step 3: Implement files handler**

Create `server/internal/api/files_handler.go`:

```go
package api

import (
	"encoding/json"
	"io"
	"net/http"
	"strconv"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/mondominator/beamlet/server/internal/auth"
	"github.com/mondominator/beamlet/server/internal/model"
	"github.com/mondominator/beamlet/server/internal/storage"
)

func (s *Server) UploadFile(w http.ResponseWriter, r *http.Request) {
	user := auth.UserFromContext(r.Context())

	if err := r.ParseMultipartForm(s.Config.MaxFileSize); err != nil {
		http.Error(w, "request too large", http.StatusRequestEntityTooLarge)
		return
	}

	recipientID := r.FormValue("recipient_id")
	if recipientID == "" {
		http.Error(w, "recipient_id is required", http.StatusBadRequest)
		return
	}

	contentType := r.FormValue("content_type")
	if contentType == "" {
		contentType = "file"
	}

	f := &model.File{
		SenderID:    user.ID,
		RecipientID: recipientID,
		ContentType: contentType,
		Message:     r.FormValue("message"),
		ExpiresAt:   time.Now().UTC().Add(time.Duration(s.Config.ExpiryDays) * 24 * time.Hour),
	}

	if contentType == "text" || contentType == "link" {
		f.TextContent = r.FormValue("text_content")
		f.Filename = contentType
		f.FileType = "text/plain"
	} else {
		file, header, err := r.FormFile("file")
		if err != nil {
			http.Error(w, "file is required", http.StatusBadRequest)
			return
		}
		defer file.Close()

		f.Filename = header.Filename
		f.FileType = header.Header.Get("Content-Type")
		if f.FileType == "" {
			f.FileType = "application/octet-stream"
		}
		f.FileSize = header.Size

		path, err := s.Storage.Save(header.Filename, f.FileType, file)
		if err != nil {
			http.Error(w, "failed to save file", http.StatusInternalServerError)
			return
		}
		f.FilePath = path

		thumbPath, err := storage.GenerateThumbnail(path, s.Config.DataDir, f.FileType)
		if err == nil && thumbPath != "" {
			f.ThumbnailPath = thumbPath
		}
	}

	created, err := s.FileStore.Create(f)
	if err != nil {
		http.Error(w, "failed to create file record", http.StatusInternalServerError)
		return
	}

	// Send push notification (non-blocking)
	// Pass sender's device token so we can exclude it from notifications
	// (handles send-to-self case: phone→iPad without notifying the sending phone)
	senderDeviceToken := r.Header.Get("X-Device-Token")
	if s.Pusher != nil {
		go s.Pusher.Notify(recipientID, user.Name, created, senderDeviceToken)
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(created)
}

func (s *Server) ListFiles(w http.ResponseWriter, r *http.Request) {
	user := auth.UserFromContext(r.Context())

	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	offset, _ := strconv.Atoi(r.URL.Query().Get("offset"))
	if limit <= 0 || limit > 100 {
		limit = 20
	}

	files, err := s.FileStore.ListForRecipient(user.ID, limit, offset)
	if err != nil {
		http.Error(w, "failed to list files", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(files)
}

func (s *Server) DownloadFile(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")

	f, err := s.FileStore.GetByID(id)
	if err != nil {
		http.Error(w, "file not found", http.StatusNotFound)
		return
	}

	// For text/link entries, return as JSON
	if f.ContentType == "text" || f.ContentType == "link" {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(f)
		return
	}

	reader, err := s.Storage.Read(f.FilePath)
	if err != nil {
		http.Error(w, "file not found on disk", http.StatusNotFound)
		return
	}
	defer reader.Close()

	w.Header().Set("Content-Type", f.FileType)
	w.Header().Set("Content-Disposition", "attachment; filename=\""+f.Filename+"\"")
	io.Copy(w, reader)
}

func (s *Server) DownloadThumbnail(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")

	f, err := s.FileStore.GetByID(id)
	if err != nil {
		http.Error(w, "file not found", http.StatusNotFound)
		return
	}

	if f.ThumbnailPath == "" {
		http.Error(w, "no thumbnail", http.StatusNotFound)
		return
	}

	reader, err := s.Storage.Read(f.ThumbnailPath)
	if err != nil {
		http.Error(w, "thumbnail not found", http.StatusNotFound)
		return
	}
	defer reader.Close()

	w.Header().Set("Content-Type", "image/jpeg")
	io.Copy(w, reader)
}

func (s *Server) DeleteFile(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")

	f, err := s.FileStore.GetByID(id)
	if err != nil {
		http.Error(w, "file not found", http.StatusNotFound)
		return
	}

	if f.FilePath != "" {
		s.Storage.Delete(f.FilePath)
	}
	if f.ThumbnailPath != "" {
		s.Storage.Delete(f.ThumbnailPath)
	}

	if err := s.FileStore.Delete(id); err != nil {
		http.Error(w, "failed to delete", http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"status": "deleted"})
}

func (s *Server) MarkFileRead(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")

	if err := s.FileStore.MarkRead(id); err != nil {
		http.Error(w, "failed to mark read", http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}
```

- [ ] **Step 4: Run all tests**

```bash
cd server && go mod tidy && go test ./... -v
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd server
git add .
git commit -m "feat: add file upload, download, list, delete, and mark-read handlers"
```

---

### Task 8: APNs Push Notifications

**Files:**
- Create: `server/internal/push/apns.go`
- Create: `server/internal/push/apns_test.go`

- [ ] **Step 1: Write failing test**

Create `server/internal/push/apns_test.go`:

```go
package push_test

import (
	"testing"

	"github.com/mondominator/beamlet/server/internal/push"
)

func TestBuildPayload_Image(t *testing.T) {
	payload := push.BuildPayload("Alice", "image/jpeg", "abc-123")
	if payload.AlertTitle != "Alice" {
		t.Fatalf("expected title Alice, got %s", payload.AlertTitle)
	}
	if payload.AlertBody != "sent you a photo" {
		t.Fatalf("expected 'sent you a photo', got %s", payload.AlertBody)
	}
	if payload.FileID != "abc-123" {
		t.Fatalf("expected file ID abc-123, got %s", payload.FileID)
	}
}

func TestBuildPayload_Video(t *testing.T) {
	payload := push.BuildPayload("Bob", "video/mp4", "def-456")
	if payload.AlertBody != "sent you a video" {
		t.Fatalf("expected 'sent you a video', got %s", payload.AlertBody)
	}
}

func TestBuildPayload_Text(t *testing.T) {
	payload := push.BuildPayload("Charlie", "text/plain", "ghi-789")
	if payload.AlertBody != "sent you a message" {
		t.Fatalf("expected 'sent you a message', got %s", payload.AlertBody)
	}
}

func TestBuildPayload_Generic(t *testing.T) {
	payload := push.BuildPayload("Dana", "application/pdf", "jkl-012")
	if payload.AlertBody != "sent you a file" {
		t.Fatalf("expected 'sent you a file', got %s", payload.AlertBody)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd server && go test ./internal/push/ -v
```

Expected: Compilation error.

- [ ] **Step 3: Implement APNs pusher**

Create `server/internal/push/apns.go`:

```go
package push

import (
	"log"
	"strings"

	"github.com/mondominator/beamlet/server/internal/model"
	"github.com/mondominator/beamlet/server/internal/store"
	"github.com/sideshow/apns2"
	"github.com/sideshow/apns2/payload"
	"github.com/sideshow/apns2/token"
)

type Payload struct {
	AlertTitle string
	AlertBody  string
	FileID     string
}

func BuildPayload(senderName, fileType, fileID string) Payload {
	var body string
	switch {
	case strings.HasPrefix(fileType, "image/"):
		body = "sent you a photo"
	case strings.HasPrefix(fileType, "video/"):
		body = "sent you a video"
	case strings.HasPrefix(fileType, "text/"):
		body = "sent you a message"
	default:
		body = "sent you a file"
	}

	return Payload{
		AlertTitle: senderName,
		AlertBody:  body,
		FileID:     fileID,
	}
}

type APNsPusher struct {
	client    *apns2.Client
	bundleID  string
	userStore *store.UserStore
}

func NewAPNsPusher(keyPath, keyID, teamID, bundleID string, userStore *store.UserStore) (*APNsPusher, error) {
	authKey, err := token.AuthKeyFromFile(keyPath)
	if err != nil {
		return nil, err
	}

	tok := &token.Token{
		AuthKey: authKey,
		KeyID:   keyID,
		TeamID:  teamID,
	}

	client := apns2.NewTokenClient(tok).Production()

	return &APNsPusher{
		client:    client,
		bundleID:  bundleID,
		userStore: userStore,
	}, nil
}

func (p *APNsPusher) Notify(recipientID, senderName string, file *model.File, excludeDeviceToken string) {
	devices, err := p.userStore.GetActiveDevices(recipientID)
	if err != nil {
		log.Printf("failed to get devices for %s: %v", recipientID, err)
		return
	}

	pl := BuildPayload(senderName, file.FileType, file.ID)

	notification := &apns2.Notification{
		Topic: p.bundleID,
		Payload: payload.NewPayload().
			AlertTitle(pl.AlertTitle).
			AlertBody(pl.AlertBody).
			MutableContent().
			Custom("file_id", pl.FileID).
			Sound("default").
			Badge(1),
	}

	for _, device := range devices {
		// Skip the device that sent the file (send-to-self case)
		if device.APNsToken == excludeDeviceToken {
			continue
		}
		notification.DeviceToken = device.APNsToken
		res, err := p.client.Push(notification)
		if err != nil {
			log.Printf("push failed for device %s: %v", device.APNsToken, err)
			continue
		}
		if res.StatusCode == 410 || res.Reason == "Unregistered" {
			log.Printf("deactivating device %s: %s", device.APNsToken, res.Reason)
			p.userStore.DeactivateDevice(device.APNsToken)
		}
	}
}
```

- [ ] **Step 4: Run tests**

```bash
cd server && go mod tidy && go test ./internal/push/ -v
```

Expected: PASS (only payload tests — no integration test for actual APNs).

- [ ] **Step 5: Commit**

```bash
cd server
git add .
git commit -m "feat: add APNs push notification support"
```

---

### Task 9: Cleanup Goroutine

**Files:**
- Create: `server/internal/cleanup/cleanup.go`
- Create: `server/internal/cleanup/cleanup_test.go`

- [ ] **Step 1: Write failing test**

Create `server/internal/cleanup/cleanup_test.go`:

```go
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

	// Save a file to disk
	path, _ := ds.Save("old.txt", "text/plain", bytes.NewReader([]byte("old")))

	// Create expired file record
	fs.Create(&model.File{
		SenderID:    sender.ID,
		RecipientID: recipient.ID,
		Filename:    "old.txt",
		FilePath:    path,
		FileType:    "text/plain",
		ContentType: "file",
		ExpiresAt:   time.Now().Add(-1 * time.Hour),
	})

	// Create non-expired file
	fs.Create(&model.File{
		SenderID:    sender.ID,
		RecipientID: recipient.ID,
		Filename:    "new.txt",
		FileType:    "text/plain",
		ContentType: "file",
		ExpiresAt:   time.Now().Add(30 * 24 * time.Hour),
	})

	deleted, err := cleanup.RunOnce(fs, ds)
	if err != nil {
		t.Fatalf("run once: %v", err)
	}
	if deleted != 1 {
		t.Fatalf("expected 1 deleted, got %d", deleted)
	}

	// Verify expired file is gone from DB
	files, _ := fs.ListForRecipient(recipient.ID, 10, 0)
	if len(files) != 1 {
		t.Fatalf("expected 1 remaining file, got %d", len(files))
	}
	if files[0].Filename != "new.txt" {
		t.Fatalf("expected new.txt to remain, got %s", files[0].Filename)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd server && go test ./internal/cleanup/ -v
```

Expected: Compilation error.

- [ ] **Step 3: Implement cleanup**

Create `server/internal/cleanup/cleanup.go`:

```go
package cleanup

import (
	"log"
	"time"

	"github.com/mondominator/beamlet/server/internal/storage"
	"github.com/mondominator/beamlet/server/internal/store"
)

func RunOnce(fileStore *store.FileStore, diskStorage *storage.DiskStorage) (int, error) {
	expired, err := fileStore.ListExpired()
	if err != nil {
		return 0, err
	}

	deleted := 0
	for _, f := range expired {
		if f.FilePath != "" {
			diskStorage.Delete(f.FilePath)
		}
		if f.ThumbnailPath != "" {
			diskStorage.Delete(f.ThumbnailPath)
		}
		if err := fileStore.Delete(f.ID); err != nil {
			log.Printf("failed to delete expired file %s: %v", f.ID, err)
			continue
		}
		deleted++
	}
	return deleted, nil
}

func StartScheduler(fileStore *store.FileStore, diskStorage *storage.DiskStorage, stop <-chan struct{}) {
	ticker := time.NewTicker(24 * time.Hour)
	defer ticker.Stop()

	// Run once at startup
	if deleted, err := RunOnce(fileStore, diskStorage); err != nil {
		log.Printf("cleanup error: %v", err)
	} else if deleted > 0 {
		log.Printf("cleaned up %d expired files", deleted)
	}

	for {
		select {
		case <-ticker.C:
			if deleted, err := RunOnce(fileStore, diskStorage); err != nil {
				log.Printf("cleanup error: %v", err)
			} else if deleted > 0 {
				log.Printf("cleaned up %d expired files", deleted)
			}
		case <-stop:
			return
		}
	}
}
```

- [ ] **Step 4: Run tests**

```bash
cd server && go test ./internal/cleanup/ -v
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd server
git add .
git commit -m "feat: add expired file cleanup scheduler"
```

---

### Task 10: CLI Commands

**Files:**
- Create: `server/cmd/serve.go`
- Create: `server/cmd/adduser.go`
- Create: `server/cmd/listusers.go`
- Create: `server/cmd/revoketoken.go`
- Modify: `server/main.go`

- [ ] **Step 1: Implement main.go with cobra**

Replace `server/main.go`:

```go
package main

import (
	"fmt"
	"os"

	"github.com/mondominator/beamlet/server/cmd"
	"github.com/spf13/cobra"
)

func main() {
	root := &cobra.Command{
		Use:   "beamlet",
		Short: "Beamlet file sharing server",
	}

	root.AddCommand(cmd.ServeCmd())
	root.AddCommand(cmd.AddUserCmd())
	root.AddCommand(cmd.ListUsersCmd())
	root.AddCommand(cmd.RevokeTokenCmd())

	if err := root.Execute(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
```

- [ ] **Step 2: Implement serve command**

Create `server/cmd/serve.go`:

```go
package cmd

import (
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"

	"github.com/mondominator/beamlet/server/internal/api"
	"github.com/mondominator/beamlet/server/internal/cleanup"
	"github.com/mondominator/beamlet/server/internal/config"
	"github.com/mondominator/beamlet/server/internal/db"
	"github.com/mondominator/beamlet/server/internal/push"
	"github.com/mondominator/beamlet/server/internal/storage"
	"github.com/mondominator/beamlet/server/internal/store"
	"github.com/spf13/cobra"
)

func ServeCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "serve",
		Short: "Start the Beamlet server",
		RunE: func(cmd *cobra.Command, args []string) error {
			cfg := config.Load()

			database, err := db.Open(cfg.DBPath, findMigrations())
			if err != nil {
				return fmt.Errorf("open database: %w", err)
			}
			defer database.Close()

			userStore := store.NewUserStore(database.SQL())
			fileStore := store.NewFileStore(database.SQL())
			diskStorage := storage.NewDiskStorage(cfg.DataDir)

			var pusher *push.APNsPusher
			if cfg.APNsKeyPath != "" {
				p, err := push.NewAPNsPusher(cfg.APNsKeyPath, cfg.APNsKeyID, cfg.APNsTeamID, cfg.APNsBundleID, userStore)
				if err != nil {
					log.Printf("warning: APNs setup failed: %v (push notifications disabled)", err)
				} else {
					pusher = p
				}
			}

			srv := &api.Server{
				UserStore: userStore,
				FileStore: fileStore,
				Storage:   diskStorage,
				Pusher:    pusher,
				Config:    cfg,
			}

			// Start cleanup scheduler
			stopCleanup := make(chan struct{})
			go cleanup.StartScheduler(fileStore, diskStorage, stopCleanup)

			router := api.NewRouter(srv)

			// Graceful shutdown
			go func() {
				sigCh := make(chan os.Signal, 1)
				signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
				<-sigCh
				log.Println("shutting down...")
				close(stopCleanup)
				os.Exit(0)
			}()

			log.Printf("beamlet server listening on :%s", cfg.Port)
			return http.ListenAndServe(":"+cfg.Port, router)
		},
	}
}

func findMigrations() string {
	candidates := []string{
		"migrations",
		"/app/migrations",
		"server/migrations",
	}
	for _, c := range candidates {
		if info, err := os.Stat(c); err == nil && info.IsDir() {
			return c
		}
	}
	return "migrations"
}
```

- [ ] **Step 3: Implement add-user command**

Create `server/cmd/adduser.go`:

```go
package cmd

import (
	"fmt"

	"github.com/mondominator/beamlet/server/internal/config"
	"github.com/mondominator/beamlet/server/internal/db"
	"github.com/mondominator/beamlet/server/internal/store"
	"github.com/spf13/cobra"
)

func AddUserCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "add-user [name]",
		Short: "Create a new user and print their API token",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			cfg := config.Load()
			database, err := db.Open(cfg.DBPath, findMigrations())
			if err != nil {
				return err
			}
			defer database.Close()

			userStore := store.NewUserStore(database.SQL())
			user, token, err := userStore.Create(args[0])
			if err != nil {
				return fmt.Errorf("create user: %w", err)
			}

			fmt.Printf("User created:\n")
			fmt.Printf("  ID:    %s\n", user.ID)
			fmt.Printf("  Name:  %s\n", user.Name)
			fmt.Printf("  Token: %s\n", token)
			fmt.Println("\nSave this token — it cannot be retrieved later.")
			return nil
		},
	}
}
```

- [ ] **Step 4: Implement list-users command**

Create `server/cmd/listusers.go`:

```go
package cmd

import (
	"fmt"

	"github.com/mondominator/beamlet/server/internal/config"
	"github.com/mondominator/beamlet/server/internal/db"
	"github.com/mondominator/beamlet/server/internal/store"
	"github.com/spf13/cobra"
)

func ListUsersCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "list-users",
		Short: "List all users",
		RunE: func(cmd *cobra.Command, args []string) error {
			cfg := config.Load()
			database, err := db.Open(cfg.DBPath, findMigrations())
			if err != nil {
				return err
			}
			defer database.Close()

			userStore := store.NewUserStore(database.SQL())
			users, err := userStore.List()
			if err != nil {
				return err
			}

			if len(users) == 0 {
				fmt.Println("No users found.")
				return nil
			}

			fmt.Printf("%-36s  %s\n", "ID", "Name")
			fmt.Printf("%-36s  %s\n", "------------------------------------", "----")
			for _, u := range users {
				fmt.Printf("%-36s  %s\n", u.ID, u.Name)
			}
			return nil
		},
	}
}
```

- [ ] **Step 5: Implement revoke-token command**

Create `server/cmd/revoketoken.go`:

```go
package cmd

import (
	"fmt"

	"github.com/mondominator/beamlet/server/internal/config"
	"github.com/mondominator/beamlet/server/internal/db"
	"github.com/mondominator/beamlet/server/internal/store"
	"github.com/spf13/cobra"
)

func RevokeTokenCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "revoke-token [user-id]",
		Short: "Regenerate a user's API token",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			cfg := config.Load()
			database, err := db.Open(cfg.DBPath, findMigrations())
			if err != nil {
				return err
			}
			defer database.Close()

			userStore := store.NewUserStore(database.SQL())
			newToken, err := userStore.RevokeToken(args[0])
			if err != nil {
				return fmt.Errorf("revoke token: %w", err)
			}

			fmt.Printf("New token: %s\n", newToken)
			fmt.Println("Save this token — it cannot be retrieved later.")
			return nil
		},
	}
}
```

- [ ] **Step 6: Install dependencies and build**

```bash
cd server && go mod tidy && go build -o beamlet .
```

Expected: Binary builds successfully.

- [ ] **Step 7: Run all tests**

```bash
cd server && go test ./... -v
```

Expected: PASS

- [ ] **Step 8: Commit**

```bash
cd server
git add .
git commit -m "feat: add CLI commands (serve, add-user, list-users, revoke-token)"
```

---

### Task 11: Docker Setup

**Files:**
- Create: `server/Dockerfile`
- Create: `server/docker-compose.yml`
- Create: `.gitignore`

- [ ] **Step 1: Create Dockerfile**

Create `server/Dockerfile`:

```dockerfile
FROM golang:1.22-alpine AS builder

RUN apk add --no-cache gcc musl-dev

WORKDIR /build
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN go build -o beamlet .

FROM alpine:3.19

RUN apk add --no-cache ca-certificates imagemagick ffmpeg

WORKDIR /app
COPY --from=builder /build/beamlet .
COPY --from=builder /build/migrations ./migrations

RUN mkdir -p /data/files

EXPOSE 8080

ENTRYPOINT ["/app/beamlet"]
CMD ["serve"]
```

- [ ] **Step 2: Create docker-compose.yml**

Create `server/docker-compose.yml`:

```yaml
services:
  beamlet:
    build: .
    container_name: beamlet
    restart: unless-stopped
    ports:
      - "8080:8080"
    volumes:
      - beamlet-data:/data
      - ./apns-key.p8:/app/apns-key.p8:ro
    environment:
      - BEAMLET_DB_PATH=/data/beamlet.db
      - BEAMLET_DATA_DIR=/data/files
      - BEAMLET_PORT=8080
      - BEAMLET_APNS_KEY_PATH=/app/apns-key.p8
      - BEAMLET_APNS_KEY_ID=YOUR_KEY_ID
      - BEAMLET_APNS_TEAM_ID=YOUR_TEAM_ID
      - BEAMLET_APNS_BUNDLE_ID=com.yourname.beamlet
      - BEAMLET_MAX_FILE_SIZE=524288000
      - BEAMLET_EXPIRY_DAYS=30

volumes:
  beamlet-data:
```

- [ ] **Step 3: Create .gitignore**

Create `.gitignore`:

```
# Go
server/beamlet
server/vendor/

# APNs key
*.p8

# Data
/data/

# OS
.DS_Store

# IDE
.idea/
.vscode/
```

- [ ] **Step 4: Verify Docker build**

```bash
cd server && docker build -t beamlet:dev .
```

Expected: Image builds successfully.

- [ ] **Step 5: Commit**

```bash
cd /home/mondo/dropship
git add .
git commit -m "feat: add Dockerfile and docker-compose for Unraid deployment"
```

---

### Task 12: Final Integration Verification

- [ ] **Step 1: Run full test suite**

```bash
cd server && go test ./... -v -count=1
```

Expected: All tests pass.

- [ ] **Step 2: Build binary**

```bash
cd server && go build -o beamlet . && ./beamlet --help
```

Expected: Help output showing serve, add-user, list-users, revoke-token commands.

- [ ] **Step 3: Smoke test the server locally**

```bash
cd server

# Start server with temp data dir
BEAMLET_DB_PATH=/tmp/beamlet-test.db BEAMLET_DATA_DIR=/tmp/beamlet-files ./beamlet serve &
SERVER_PID=$!
sleep 1

# Create a user
BEAMLET_DB_PATH=/tmp/beamlet-test.db ./beamlet add-user "TestUser"
# Copy the token from output and test:
# curl -H "Authorization: Bearer <token>" http://localhost:8080/api/users

kill $SERVER_PID
rm -f /tmp/beamlet-test.db
rm -rf /tmp/beamlet-files
```

- [ ] **Step 4: Commit and push**

```bash
cd /home/mondo/dropship
git add .
git commit -m "chore: final integration verification"
git push
```
