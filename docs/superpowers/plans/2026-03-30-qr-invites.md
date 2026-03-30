# QR Code Setup & Contact Invites Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add QR code-based setup, a contacts system (users only see connected users), and an invite flow where any user can invite others from the iOS app or CLI.

**Architecture:** Two new DB tables (contacts, invites) with corresponding stores and handlers. A public `/api/invites/redeem` endpoint handles both new-user registration and existing-user contact linking. CLI `add-user` prints a QR code. iOS app gets a QR scanner for setup and a QR generator for sharing invites.

**Tech Stack:** Go (chi router, bcrypt, qrterminal), SQLite, Swift/SwiftUI (AVFoundation for scanning, CoreImage for QR generation)

**Prerequisites:** The `feature/ios-app` branch must be merged or the iOS worktree available. The server runs in a podman container or via `go run`.

---

## File Structure

### Server (new files)
```
server/
├── migrations/
│   ├── 004_create_contacts.up.sql
│   ├── 004_create_contacts.down.sql
│   ├── 005_create_invites.up.sql
│   └── 005_create_invites.down.sql
├── internal/
│   ├── model/
│   │   ├── contact.go
│   │   └── invite.go
│   ├── store/
│   │   ├── contact_store.go
│   │   ├── contact_store_test.go
│   │   ├── invite_store.go
│   │   └── invite_store_test.go
│   └── api/
│       ├── contacts_handler.go
│       ├── contacts_handler_test.go
│       ├── invites_handler.go
│       └── invites_handler_test.go
```

### Server (modified files)
```
server/
├── internal/api/
│   ├── router.go              # Add public route group, new endpoints
│   └── users_handler.go       # Return contacts instead of all users
├── cmd/
│   ├── adduser.go             # Print QR code after creating user
│   └── serve.go               # Wire up ContactStore, InviteStore
└── go.mod                     # Add qrterminal dependency
```

### iOS (new files)
```
ios/Beamlet/
├── Presentation/
│   ├── Scanner/
│   │   └── QRScannerView.swift
│   ├── Setup/
│   │   └── NameEntryView.swift
│   └── Settings/
│       ├── AddContactView.swift
│       └── ScanInviteView.swift
```

### iOS (modified files)
```
ios/Beamlet/
├── Data/
│   └── BeamletAPI.swift       # Add invite/contact endpoints
├── Model/
│   └── Models.swift           # Add InviteResponse, RedeemResponse
├── Presentation/
│   ├── Setup/
│   │   └── SetupView.swift    # Add "Scan QR Code" button
│   └── Settings/
│       └── SettingsView.swift  # Add contact management rows
└── project.yml                # Add AVFoundation framework, camera usage description
```

---

### Task 1: Database Migrations and Models

**Files:**
- Create: `server/migrations/004_create_contacts.up.sql`
- Create: `server/migrations/004_create_contacts.down.sql`
- Create: `server/migrations/005_create_invites.up.sql`
- Create: `server/migrations/005_create_invites.down.sql`
- Create: `server/internal/model/contact.go`
- Create: `server/internal/model/invite.go`

- [ ] **Step 1: Create contacts migration (up)**

Create `server/migrations/004_create_contacts.up.sql`:

```sql
CREATE TABLE contacts (
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    contact_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, contact_id)
);

CREATE INDEX idx_contacts_user_id ON contacts(user_id);

-- Migrate existing users: create contacts between all pairs
INSERT INTO contacts (user_id, contact_id)
SELECT a.id, b.id FROM users a, users b WHERE a.id != b.id;
```

- [ ] **Step 2: Create contacts migration (down)**

Create `server/migrations/004_create_contacts.down.sql`:

```sql
DROP TABLE IF EXISTS contacts;
```

- [ ] **Step 3: Create invites migration (up)**

Create `server/migrations/005_create_invites.up.sql`:

```sql
CREATE TABLE invites (
    id TEXT PRIMARY KEY,
    token_hash TEXT NOT NULL,
    creator_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_user_id TEXT REFERENCES users(id) ON DELETE SET NULL,
    redeemed_by TEXT REFERENCES users(id) ON DELETE SET NULL,
    expires_at TIMESTAMP NOT NULL,
    redeemed_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_invites_creator_id ON invites(creator_id);
CREATE INDEX idx_invites_expires_at ON invites(expires_at);
```

- [ ] **Step 4: Create invites migration (down)**

Create `server/migrations/005_create_invites.down.sql`:

```sql
DROP TABLE IF EXISTS invites;
```

- [ ] **Step 5: Create Contact model**

Create `server/internal/model/contact.go`:

```go
package model

import "time"

type Contact struct {
	UserID    string    `json:"user_id"`
	ContactID string    `json:"contact_id"`
	CreatedAt time.Time `json:"created_at"`
}

type ContactUser struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	CreatedAt time.Time `json:"created_at"`
}
```

- [ ] **Step 6: Create Invite model**

Create `server/internal/model/invite.go`:

```go
package model

import (
	"database/sql"
	"time"
)

type Invite struct {
	ID            string         `json:"id"`
	TokenHash     string         `json:"-"`
	CreatorID     string         `json:"creator_id"`
	CreatedUserID sql.NullString `json:"-"`
	RedeemedBy    sql.NullString `json:"-"`
	ExpiresAt     time.Time      `json:"expires_at"`
	RedeemedAt    sql.NullTime   `json:"-"`
	CreatedAt     time.Time      `json:"created_at"`
}

func (i *Invite) IsExpired() bool {
	return time.Now().UTC().After(i.ExpiresAt)
}

func (i *Invite) IsRedeemed() bool {
	return i.RedeemedAt.Valid
}
```

- [ ] **Step 7: Commit**

```bash
git add server/migrations/ server/internal/model/contact.go server/internal/model/invite.go
git commit -m "feat: add contacts and invites database migrations and models"
```

---

### Task 2: Contact Store

**Files:**
- Create: `server/internal/store/contact_store.go`
- Create: `server/internal/store/contact_store_test.go`

- [ ] **Step 1: Write contact store tests**

Create `server/internal/store/contact_store_test.go`:

```go
package store

import (
	"testing"

	"github.com/mondominator/beamlet/server/testutil"
)

func TestContactStore_AddAndList(t *testing.T) {
	db := testutil.NewTestDB(t)
	userStore := NewUserStore(db)
	contactStore := NewContactStore(db)

	alice, _, _ := userStore.Create("Alice")
	bob, _, _ := userStore.Create("Bob")

	if err := contactStore.Add(alice.ID, bob.ID); err != nil {
		t.Fatalf("add contact: %v", err)
	}

	// Alice should see Bob
	contacts, err := contactStore.ListForUser(alice.ID)
	if err != nil {
		t.Fatalf("list contacts: %v", err)
	}
	if len(contacts) != 1 || contacts[0].ID != bob.ID {
		t.Fatalf("expected Bob in Alice's contacts, got %v", contacts)
	}

	// Bob should see Alice (mutual)
	contacts, err = contactStore.ListForUser(bob.ID)
	if err != nil {
		t.Fatalf("list contacts: %v", err)
	}
	if len(contacts) != 1 || contacts[0].ID != alice.ID {
		t.Fatalf("expected Alice in Bob's contacts, got %v", contacts)
	}
}

func TestContactStore_Delete(t *testing.T) {
	db := testutil.NewTestDB(t)
	userStore := NewUserStore(db)
	contactStore := NewContactStore(db)

	alice, _, _ := userStore.Create("Alice")
	bob, _, _ := userStore.Create("Bob")

	contactStore.Add(alice.ID, bob.ID)

	if err := contactStore.Delete(alice.ID, bob.ID); err != nil {
		t.Fatalf("delete contact: %v", err)
	}

	contacts, _ := contactStore.ListForUser(alice.ID)
	if len(contacts) != 0 {
		t.Fatalf("expected empty contacts after delete, got %v", contacts)
	}

	// Bob side also gone
	contacts, _ = contactStore.ListForUser(bob.ID)
	if len(contacts) != 0 {
		t.Fatalf("expected empty contacts for Bob after delete, got %v", contacts)
	}
}

func TestContactStore_AddDuplicate(t *testing.T) {
	db := testutil.NewTestDB(t)
	userStore := NewUserStore(db)
	contactStore := NewContactStore(db)

	alice, _, _ := userStore.Create("Alice")
	bob, _, _ := userStore.Create("Bob")

	contactStore.Add(alice.ID, bob.ID)

	// Adding again should not error (idempotent)
	if err := contactStore.Add(alice.ID, bob.ID); err != nil {
		t.Fatalf("duplicate add should not error: %v", err)
	}

	contacts, _ := contactStore.ListForUser(alice.ID)
	if len(contacts) != 1 {
		t.Fatalf("expected 1 contact after duplicate add, got %d", len(contacts))
	}
}

func TestContactStore_AreContacts(t *testing.T) {
	db := testutil.NewTestDB(t)
	userStore := NewUserStore(db)
	contactStore := NewContactStore(db)

	alice, _, _ := userStore.Create("Alice")
	bob, _, _ := userStore.Create("Bob")
	carol, _, _ := userStore.Create("Carol")

	contactStore.Add(alice.ID, bob.ID)

	if ok, _ := contactStore.AreContacts(alice.ID, bob.ID); !ok {
		t.Fatal("Alice and Bob should be contacts")
	}
	if ok, _ := contactStore.AreContacts(alice.ID, carol.ID); ok {
		t.Fatal("Alice and Carol should not be contacts")
	}
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd server
go test ./internal/store/ -run TestContactStore -v
```

Expected: FAIL — `NewContactStore` undefined.

- [ ] **Step 3: Implement contact store**

Create `server/internal/store/contact_store.go`:

```go
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
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd server
go test ./internal/store/ -run TestContactStore -v
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add server/internal/store/contact_store.go server/internal/store/contact_store_test.go
git commit -m "feat: add contact store with mutual add/delete/list"
```

---

### Task 3: Invite Store

**Files:**
- Create: `server/internal/store/invite_store.go`
- Create: `server/internal/store/invite_store_test.go`

- [ ] **Step 1: Write invite store tests**

Create `server/internal/store/invite_store_test.go`:

```go
package store

import (
	"testing"
	"time"

	"github.com/mondominator/beamlet/server/testutil"
)

func TestInviteStore_CreateAndFind(t *testing.T) {
	db := testutil.NewTestDB(t)
	userStore := NewUserStore(db)
	inviteStore := NewInviteStore(db)

	alice, _, _ := userStore.Create("Alice")

	invite, token, err := inviteStore.Create(alice.ID, "", 24*time.Hour)
	if err != nil {
		t.Fatalf("create invite: %v", err)
	}
	if invite.CreatorID != alice.ID {
		t.Fatalf("expected creator %s, got %s", alice.ID, invite.CreatorID)
	}
	if token == "" {
		t.Fatal("expected non-empty token")
	}

	// Find by token
	found, err := inviteStore.FindByToken(token)
	if err != nil {
		t.Fatalf("find by token: %v", err)
	}
	if found.ID != invite.ID {
		t.Fatalf("expected invite %s, got %s", invite.ID, found.ID)
	}
}

func TestInviteStore_CreateWithUser(t *testing.T) {
	db := testutil.NewTestDB(t)
	userStore := NewUserStore(db)
	inviteStore := NewInviteStore(db)

	alice, _, _ := userStore.Create("Alice")

	invite, _, err := inviteStore.Create(alice.ID, alice.ID, 24*time.Hour)
	if err != nil {
		t.Fatalf("create invite with user: %v", err)
	}
	if !invite.CreatedUserID.Valid || invite.CreatedUserID.String != alice.ID {
		t.Fatal("expected created_user_id to be set")
	}
}

func TestInviteStore_Redeem(t *testing.T) {
	db := testutil.NewTestDB(t)
	userStore := NewUserStore(db)
	inviteStore := NewInviteStore(db)

	alice, _, _ := userStore.Create("Alice")
	bob, _, _ := userStore.Create("Bob")

	invite, token, _ := inviteStore.Create(alice.ID, "", 24*time.Hour)

	if err := inviteStore.Redeem(invite.ID, bob.ID); err != nil {
		t.Fatalf("redeem: %v", err)
	}

	// Should not be findable again (redeemed)
	_, err := inviteStore.FindByToken(token)
	if err == nil {
		t.Fatal("expected error finding redeemed invite")
	}
}

func TestInviteStore_Expired(t *testing.T) {
	db := testutil.NewTestDB(t)
	userStore := NewUserStore(db)
	inviteStore := NewInviteStore(db)

	alice, _, _ := userStore.Create("Alice")

	// Create with 0 duration (already expired)
	_, token, _ := inviteStore.Create(alice.ID, "", -1*time.Hour)

	_, err := inviteStore.FindByToken(token)
	if err == nil {
		t.Fatal("expected error finding expired invite")
	}
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd server
go test ./internal/store/ -run TestInviteStore -v
```

Expected: FAIL — `NewInviteStore` undefined.

- [ ] **Step 3: Implement invite store**

Create `server/internal/store/invite_store.go`:

```go
package store

import (
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/mondominator/beamlet/server/internal/model"
	"golang.org/x/crypto/bcrypt"
)

type InviteStore struct {
	db *sql.DB
}

func NewInviteStore(db *sql.DB) *InviteStore {
	return &InviteStore{db: db}
}

func (s *InviteStore) Create(creatorID, createdUserID string, ttl time.Duration) (*model.Invite, string, error) {
	tokenBytes := make([]byte, 32)
	if _, err := rand.Read(tokenBytes); err != nil {
		return nil, "", fmt.Errorf("generate token: %w", err)
	}
	token := hex.EncodeToString(tokenBytes)

	hash, err := bcrypt.GenerateFromPassword([]byte(token), bcrypt.DefaultCost)
	if err != nil {
		return nil, "", fmt.Errorf("hash token: %w", err)
	}

	invite := &model.Invite{
		ID:        uuid.New().String(),
		TokenHash: string(hash),
		CreatorID: creatorID,
		ExpiresAt: time.Now().UTC().Add(ttl),
		CreatedAt: time.Now().UTC(),
	}

	if createdUserID != "" {
		invite.CreatedUserID = sql.NullString{String: createdUserID, Valid: true}
	}

	_, err = s.db.Exec(
		`INSERT INTO invites (id, token_hash, creator_id, created_user_id, expires_at, created_at)
		 VALUES (?, ?, ?, ?, ?, ?)`,
		invite.ID, invite.TokenHash, invite.CreatorID,
		invite.CreatedUserID, invite.ExpiresAt, invite.CreatedAt,
	)
	if err != nil {
		return nil, "", fmt.Errorf("insert invite: %w", err)
	}

	return invite, token, nil
}

func (s *InviteStore) FindByToken(token string) (*model.Invite, error) {
	rows, err := s.db.Query(
		`SELECT id, token_hash, creator_id, created_user_id, redeemed_by, expires_at, redeemed_at, created_at
		 FROM invites
		 WHERE redeemed_at IS NULL AND expires_at > ?`,
		time.Now().UTC(),
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	for rows.Next() {
		var inv model.Invite
		if err := rows.Scan(
			&inv.ID, &inv.TokenHash, &inv.CreatorID, &inv.CreatedUserID,
			&inv.RedeemedBy, &inv.ExpiresAt, &inv.RedeemedAt, &inv.CreatedAt,
		); err != nil {
			return nil, err
		}
		if bcrypt.CompareHashAndPassword([]byte(inv.TokenHash), []byte(token)) == nil {
			return &inv, nil
		}
	}

	return nil, fmt.Errorf("invite not found or expired")
}

func (s *InviteStore) Redeem(inviteID, redeemedByID string) error {
	_, err := s.db.Exec(
		`UPDATE invites SET redeemed_by = ?, redeemed_at = ? WHERE id = ?`,
		redeemedByID, time.Now().UTC(), inviteID,
	)
	return err
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd server
go test ./internal/store/ -run TestInviteStore -v
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add server/internal/store/invite_store.go server/internal/store/invite_store_test.go
git commit -m "feat: add invite store with create, find by token, and redeem"
```

---

### Task 4: Contacts Handler

**Files:**
- Create: `server/internal/api/contacts_handler.go`
- Create: `server/internal/api/contacts_handler_test.go`
- Modify: `server/internal/api/router.go`
- Modify: `server/cmd/serve.go`

- [ ] **Step 1: Add ContactStore and InviteStore to Server struct**

In `server/internal/api/router.go`, add to the `Server` struct and update the router:

Replace the existing `Server` struct with:

```go
type Server struct {
	UserStore    *store.UserStore
	FileStore    *store.FileStore
	ContactStore *store.ContactStore
	InviteStore  *store.InviteStore
	Storage      *storage.DiskStorage
	Pusher       *push.APNsPusher
	Config       config.Config
}
```

Replace the existing `NewRouter` function with:

```go
func NewRouter(s *Server) *chi.Mux {
	r := chi.NewRouter()
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)

	r.Route("/api", func(r chi.Router) {
		// Public routes (no auth)
		r.Post("/invites/redeem", s.RedeemInvite)

		// Authenticated routes
		r.Group(func(r chi.Router) {
			r.Use(auth.Middleware(s.UserStore))

			r.Get("/users", s.ListUsers)
			r.Post("/auth/register-device", s.RegisterDevice)
			r.Post("/files", s.UploadFile)
			r.Get("/files", s.ListFiles)
			r.Get("/files/{id}", s.DownloadFile)
			r.Get("/files/{id}/thumbnail", s.DownloadThumbnail)
			r.Delete("/files/{id}", s.DeleteFile)
			r.Put("/files/{id}/read", s.MarkFileRead)

			r.Get("/contacts", s.ListContacts)
			r.Delete("/contacts/{id}", s.DeleteContact)
			r.Post("/invites", s.CreateInvite)
		})
	})

	return r
}
```

- [ ] **Step 2: Update serve.go to wire up new stores**

In `server/cmd/serve.go`, add the new store creation after the existing stores:

After `fileStore := store.NewFileStore(database.SQL())` add:

```go
			contactStore := store.NewContactStore(database.SQL())
			inviteStore := store.NewInviteStore(database.SQL())
```

And update the Server initialization to include the new fields:

```go
			srv := &api.Server{
				UserStore:    userStore,
				FileStore:    fileStore,
				ContactStore: contactStore,
				InviteStore:  inviteStore,
				Storage:      diskStorage,
				Pusher:       pusher,
				Config:       cfg,
			}
```

- [ ] **Step 3: Write contacts handler tests**

Create `server/internal/api/contacts_handler_test.go`:

```go
package api

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/mondominator/beamlet/server/internal/model"
	"github.com/mondominator/beamlet/server/internal/store"
	"github.com/mondominator/beamlet/server/testutil"
)

func TestListContacts(t *testing.T) {
	db := testutil.NewTestDB(t)
	userStore := store.NewUserStore(db)
	contactStore := store.NewContactStore(db)

	alice, aliceToken, _ := userStore.Create("Alice")
	bob, _, _ := userStore.Create("Bob")
	contactStore.Add(alice.ID, bob.ID)

	srv := &Server{UserStore: userStore, ContactStore: contactStore}
	router := NewRouter(srv)

	req := httptest.NewRequest("GET", "/api/contacts", nil)
	req.Header.Set("Authorization", "Bearer "+aliceToken)
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}

	var contacts []model.ContactUser
	json.NewDecoder(w.Body).Decode(&contacts)
	if len(contacts) != 1 || contacts[0].Name != "Bob" {
		t.Fatalf("expected [Bob], got %v", contacts)
	}
}

func TestDeleteContact(t *testing.T) {
	db := testutil.NewTestDB(t)
	userStore := store.NewUserStore(db)
	contactStore := store.NewContactStore(db)

	alice, aliceToken, _ := userStore.Create("Alice")
	bob, _, _ := userStore.Create("Bob")
	contactStore.Add(alice.ID, bob.ID)

	srv := &Server{UserStore: userStore, ContactStore: contactStore}
	router := NewRouter(srv)

	req := httptest.NewRequest("DELETE", "/api/contacts/"+bob.ID, nil)
	req.Header.Set("Authorization", "Bearer "+aliceToken)
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusNoContent {
		t.Fatalf("expected 204, got %d: %s", w.Code, w.Body.String())
	}

	contacts, _ := contactStore.ListForUser(alice.ID)
	if len(contacts) != 0 {
		t.Fatalf("expected no contacts after delete, got %v", contacts)
	}
}
```

- [ ] **Step 4: Implement contacts handler**

Create `server/internal/api/contacts_handler.go`:

```go
package api

import (
	"encoding/json"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/mondominator/beamlet/server/internal/auth"
	"github.com/mondominator/beamlet/server/internal/model"
)

func (s *Server) ListContacts(w http.ResponseWriter, r *http.Request) {
	user := auth.UserFromContext(r.Context())

	contacts, err := s.ContactStore.ListForUser(user.ID)
	if err != nil {
		http.Error(w, "failed to list contacts", http.StatusInternalServerError)
		return
	}

	if contacts == nil {
		contacts = []model.ContactUser{}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(contacts)
}

func (s *Server) DeleteContact(w http.ResponseWriter, r *http.Request) {
	user := auth.UserFromContext(r.Context())
	contactID := chi.URLParam(r, "id")

	if err := s.ContactStore.Delete(user.ID, contactID); err != nil {
		http.Error(w, "failed to delete contact", http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}
```

- [ ] **Step 5: Run tests**

```bash
cd server
go test ./internal/api/ -run TestListContacts -v
go test ./internal/api/ -run TestDeleteContact -v
```

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add server/internal/api/contacts_handler.go server/internal/api/contacts_handler_test.go server/internal/api/router.go server/cmd/serve.go
git commit -m "feat: add contacts handler with list and delete endpoints"
```

---

### Task 5: Invites Handler

**Files:**
- Create: `server/internal/api/invites_handler.go`
- Create: `server/internal/api/invites_handler_test.go`

- [ ] **Step 1: Write invites handler tests**

Create `server/internal/api/invites_handler_test.go`:

```go
package api

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/mondominator/beamlet/server/internal/store"
	"github.com/mondominator/beamlet/server/testutil"
)

func TestCreateInvite(t *testing.T) {
	db := testutil.NewTestDB(t)
	userStore := store.NewUserStore(db)
	inviteStore := store.NewInviteStore(db)
	contactStore := store.NewContactStore(db)

	alice, aliceToken, _ := userStore.Create("Alice")
	_ = alice

	srv := &Server{UserStore: userStore, InviteStore: inviteStore, ContactStore: contactStore}
	router := NewRouter(srv)

	req := httptest.NewRequest("POST", "/api/invites", nil)
	req.Header.Set("Authorization", "Bearer "+aliceToken)
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d: %s", w.Code, w.Body.String())
	}

	var resp struct {
		InviteToken string `json:"invite_token"`
		ExpiresAt   string `json:"expires_at"`
	}
	json.NewDecoder(w.Body).Decode(&resp)
	if resp.InviteToken == "" {
		t.Fatal("expected non-empty invite token")
	}
}

func TestRedeemInvite_NewUser(t *testing.T) {
	db := testutil.NewTestDB(t)
	userStore := store.NewUserStore(db)
	inviteStore := store.NewInviteStore(db)
	contactStore := store.NewContactStore(db)

	alice, _, _ := userStore.Create("Alice")

	srv := &Server{UserStore: userStore, InviteStore: inviteStore, ContactStore: contactStore}
	router := NewRouter(srv)

	// Create invite as Alice
	_, token, _ := inviteStore.Create(alice.ID, "", 24*60*60*1e9) // 24h in nanoseconds

	// Redeem as new user (no auth header)
	body, _ := json.Marshal(map[string]string{
		"invite_token": token,
		"name":         "Bob",
	})
	req := httptest.NewRequest("POST", "/api/invites/redeem", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}

	var resp struct {
		UserID  string `json:"user_id"`
		Token   string `json:"token"`
		Contact struct {
			ID   string `json:"id"`
			Name string `json:"name"`
		} `json:"contact"`
	}
	json.NewDecoder(w.Body).Decode(&resp)

	if resp.UserID == "" || resp.Token == "" {
		t.Fatal("expected user_id and token in response")
	}
	if resp.Contact.ID != alice.ID || resp.Contact.Name != "Alice" {
		t.Fatalf("expected Alice as contact, got %v", resp.Contact)
	}

	// Verify mutual contacts
	ok, _ := contactStore.AreContacts(alice.ID, resp.UserID)
	if !ok {
		t.Fatal("expected mutual contact between Alice and Bob")
	}
}

func TestRedeemInvite_ExistingUser(t *testing.T) {
	db := testutil.NewTestDB(t)
	userStore := store.NewUserStore(db)
	inviteStore := store.NewInviteStore(db)
	contactStore := store.NewContactStore(db)

	alice, _, _ := userStore.Create("Alice")
	bob, bobToken, _ := userStore.Create("Bob")

	srv := &Server{UserStore: userStore, InviteStore: inviteStore, ContactStore: contactStore}
	router := NewRouter(srv)

	_, inviteToken, _ := inviteStore.Create(alice.ID, "", 24*60*60*1e9)

	body, _ := json.Marshal(map[string]string{"invite_token": inviteToken})
	req := httptest.NewRequest("POST", "/api/invites/redeem", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+bobToken)
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}

	ok, _ := contactStore.AreContacts(alice.ID, bob.ID)
	if !ok {
		t.Fatal("expected mutual contact")
	}
}

func TestRedeemInvite_CLISetup(t *testing.T) {
	db := testutil.NewTestDB(t)
	userStore := store.NewUserStore(db)
	inviteStore := store.NewInviteStore(db)
	contactStore := store.NewContactStore(db)

	alice, _, _ := userStore.Create("Alice")

	srv := &Server{UserStore: userStore, InviteStore: inviteStore, ContactStore: contactStore}
	router := NewRouter(srv)

	// CLI invite with created_user_id set
	_, inviteToken, _ := inviteStore.Create(alice.ID, alice.ID, 24*60*60*1e9)

	body, _ := json.Marshal(map[string]string{"invite_token": inviteToken})
	req := httptest.NewRequest("POST", "/api/invites/redeem", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}

	var resp struct {
		UserID string `json:"user_id"`
		Name   string `json:"name"`
		Token  string `json:"token"`
	}
	json.NewDecoder(w.Body).Decode(&resp)

	if resp.UserID != alice.ID {
		t.Fatalf("expected alice's user ID, got %s", resp.UserID)
	}
	if resp.Token == "" {
		t.Fatal("expected new auth token")
	}
}
```

- [ ] **Step 2: Implement invites handler**

Create `server/internal/api/invites_handler.go`:

```go
package api

import (
	"encoding/json"
	"net/http"
	"strings"
	"time"

	"github.com/mondominator/beamlet/server/internal/auth"
)

func (s *Server) CreateInvite(w http.ResponseWriter, r *http.Request) {
	user := auth.UserFromContext(r.Context())

	invite, token, err := s.InviteStore.Create(user.ID, "", 24*time.Hour)
	if err != nil {
		http.Error(w, "failed to create invite", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(map[string]string{
		"invite_token": token,
		"expires_at":   invite.ExpiresAt.Format(time.RFC3339),
	})
}

func (s *Server) RedeemInvite(w http.ResponseWriter, r *http.Request) {
	var req struct {
		InviteToken string `json:"invite_token"`
		Name        string `json:"name"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid request body", http.StatusBadRequest)
		return
	}
	if req.InviteToken == "" {
		http.Error(w, "invite_token is required", http.StatusBadRequest)
		return
	}

	invite, err := s.InviteStore.FindByToken(req.InviteToken)
	if err != nil {
		http.Error(w, "invalid or expired invite", http.StatusBadRequest)
		return
	}

	// Check if caller is an existing authenticated user
	var existingUserID string
	if authHeader := r.Header.Get("Authorization"); authHeader != "" {
		token := strings.TrimPrefix(authHeader, "Bearer ")
		if user, err := s.UserStore.Authenticate(token); err == nil {
			existingUserID = user.ID
		}
	}

	// Case 1: CLI setup invite (created_user_id set)
	if invite.CreatedUserID.Valid {
		user, err := s.UserStore.GetByID(invite.CreatedUserID.String)
		if err != nil {
			http.Error(w, "user not found", http.StatusInternalServerError)
			return
		}

		// Update name if provided
		if req.Name != "" {
			// Name update is optional for CLI invites, skip if not needed
		}

		newToken, err := s.UserStore.RevokeToken(user.ID)
		if err != nil {
			http.Error(w, "failed to generate token", http.StatusInternalServerError)
			return
		}

		s.InviteStore.Redeem(invite.ID, user.ID)

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"user_id": user.ID,
			"name":    user.Name,
			"token":   newToken,
		})
		return
	}

	// Case 2: Existing user scanning an invite
	if existingUserID != "" {
		if err := s.ContactStore.Add(invite.CreatorID, existingUserID); err != nil {
			http.Error(w, "failed to add contact", http.StatusInternalServerError)
			return
		}

		s.InviteStore.Redeem(invite.ID, existingUserID)

		creator, _ := s.UserStore.GetByID(invite.CreatorID)
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"contact": map[string]string{
				"id":   creator.ID,
				"name": creator.Name,
			},
		})
		return
	}

	// Case 3: New user from in-app invite
	if req.Name == "" {
		http.Error(w, "name is required for new users", http.StatusBadRequest)
		return
	}

	newUser, userToken, err := s.UserStore.Create(req.Name)
	if err != nil {
		http.Error(w, "failed to create user", http.StatusInternalServerError)
		return
	}

	if err := s.ContactStore.Add(invite.CreatorID, newUser.ID); err != nil {
		http.Error(w, "failed to add contact", http.StatusInternalServerError)
		return
	}

	s.InviteStore.Redeem(invite.ID, newUser.ID)

	creator, _ := s.UserStore.GetByID(invite.CreatorID)
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"user_id": newUser.ID,
		"name":    newUser.Name,
		"token":   userToken,
		"contact": map[string]string{
			"id":   creator.ID,
			"name": creator.Name,
		},
	})
}
```

- [ ] **Step 3: Run tests**

```bash
cd server
go test ./internal/api/ -run TestCreateInvite -v
go test ./internal/api/ -run TestRedeemInvite -v
```

Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add server/internal/api/invites_handler.go server/internal/api/invites_handler_test.go
git commit -m "feat: add invites handler with create and redeem (new user, existing user, CLI)"
```

---

### Task 6: Modify Users Handler to Return Contacts Only

**Files:**
- Modify: `server/internal/api/users_handler.go`
- Modify: `server/internal/api/users_handler_test.go`

- [ ] **Step 1: Update users handler**

Replace the body of the `ListUsers` method in `server/internal/api/users_handler.go`. The current implementation calls `s.UserStore.List()`. Change it to return contacts:

```go
func (s *Server) ListUsers(w http.ResponseWriter, r *http.Request) {
	user := auth.UserFromContext(r.Context())

	contacts, err := s.ContactStore.ListForUser(user.ID)
	if err != nil {
		http.Error(w, "failed to list users", http.StatusInternalServerError)
		return
	}

	if contacts == nil {
		contacts = []model.ContactUser{}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(contacts)
}
```

Make sure the imports include `model`:

```go
import (
	"encoding/json"
	"net/http"

	"github.com/mondominator/beamlet/server/internal/auth"
	"github.com/mondominator/beamlet/server/internal/model"
)
```

- [ ] **Step 2: Update users handler test**

Update `server/internal/api/users_handler_test.go` to account for the contacts-based behavior. The existing test creates users and expects to see all of them. Now it should set up contacts first:

Replace the test that lists users. Find the test function (likely `TestListUsers`) and update it to add contacts before asserting:

```go
func TestListUsers(t *testing.T) {
	db := testutil.NewTestDB(t)
	userStore := store.NewUserStore(db)
	contactStore := store.NewContactStore(db)

	alice, aliceToken, _ := userStore.Create("Alice")
	bob, _, _ := userStore.Create("Bob")
	userStore.Create("Carol") // Not a contact

	contactStore.Add(alice.ID, bob.ID)

	srv := &Server{UserStore: userStore, ContactStore: contactStore}
	router := NewRouter(srv)

	req := httptest.NewRequest("GET", "/api/users", nil)
	req.Header.Set("Authorization", "Bearer "+aliceToken)
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}

	var users []model.ContactUser
	json.NewDecoder(w.Body).Decode(&users)

	// Should only see Bob, not Carol
	if len(users) != 1 || users[0].Name != "Bob" {
		t.Fatalf("expected [Bob], got %v", users)
	}
}
```

- [ ] **Step 3: Run tests**

```bash
cd server
go test ./internal/api/ -run TestListUsers -v
```

Expected: PASS

- [ ] **Step 4: Run all server tests**

```bash
cd server
go test ./...
```

Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add server/internal/api/users_handler.go server/internal/api/users_handler_test.go
git commit -m "feat: change /api/users to return contacts only"
```

---

### Task 7: CLI Add-User QR Code

**Files:**
- Modify: `server/cmd/adduser.go`
- Modify: `server/go.mod`

- [ ] **Step 1: Add qrterminal dependency**

```bash
cd server
go get github.com/mdp/qrterminal/v3
```

- [ ] **Step 2: Update add-user command**

Replace the contents of `server/cmd/adduser.go`:

```go
package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"time"

	"github.com/mdp/qrterminal/v3"
	"github.com/mondominator/beamlet/server/internal/config"
	"github.com/mondominator/beamlet/server/internal/db"
	"github.com/mondominator/beamlet/server/internal/store"
	"github.com/spf13/cobra"
)

func AddUserCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "add-user [name]",
		Short: "Create a new user and print their API token and setup QR code",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			cfg := config.Load()
			database, err := db.Open(cfg.DBPath, findMigrations())
			if err != nil {
				return err
			}
			defer database.Close()

			userStore := store.NewUserStore(database.SQL())
			inviteStore := store.NewInviteStore(database.SQL())

			user, token, err := userStore.Create(args[0])
			if err != nil {
				return fmt.Errorf("create user: %w", err)
			}

			// Create a setup invite linked to this user
			_, inviteToken, err := inviteStore.Create(user.ID, user.ID, 24*time.Hour)
			if err != nil {
				return fmt.Errorf("create invite: %w", err)
			}

			serverURL := os.Getenv("BEAMLET_URL")
			if serverURL == "" {
				serverURL = fmt.Sprintf("http://localhost:%s", cfg.Port)
			}

			fmt.Printf("User created:\n")
			fmt.Printf("  ID:    %s\n", user.ID)
			fmt.Printf("  Name:  %s\n", user.Name)
			fmt.Printf("  Token: %s\n", token)
			fmt.Println("\nSave this token — it cannot be retrieved later.")

			// Generate QR code
			qrPayload, _ := json.Marshal(map[string]string{
				"url":    serverURL,
				"invite": inviteToken,
			})

			fmt.Println("\nScan this QR code with the Beamlet iOS app:")
			qrterminal.GenerateWithConfig(string(qrPayload), qrterminal.Config{
				Level:     qrterminal.L,
				Writer:    os.Stdout,
				BlackChar: qrterminal.BLACK,
				WhiteChar: qrterminal.WHITE,
			})

			return nil
		},
	}
}
```

- [ ] **Step 3: Verify build**

```bash
cd server
go build ./...
```

Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
git add server/cmd/adduser.go server/go.mod server/go.sum
git commit -m "feat: add QR code output to add-user CLI command"
```

---

### Task 8: iOS API and Model Updates

**Files:**
- Modify: `ios/Beamlet/Data/BeamletAPI.swift`
- Modify: `ios/Beamlet/Model/Models.swift`

- [ ] **Step 1: Add new models**

Append to `ios/Beamlet/Model/Models.swift`:

```swift
struct InviteResponse: Codable {
    let inviteToken: String
    let expiresAt: String

    enum CodingKeys: String, CodingKey {
        case inviteToken = "invite_token"
        case expiresAt = "expires_at"
    }
}

struct RedeemResponse: Codable {
    let userID: String?
    let name: String?
    let token: String?
    let contact: RedeemContact?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case name, token, contact
    }
}

struct RedeemContact: Codable {
    let id: String
    let name: String
}

struct QRPayload: Codable {
    let url: String
    let invite: String
}
```

- [ ] **Step 2: Add invite and contact API methods**

Append these methods to the `BeamletAPI` class in `ios/Beamlet/Data/BeamletAPI.swift`, before the closing `}` of the class:

```swift
    // MARK: - Invites

    func createInvite() async throws -> InviteResponse {
        try await request("/api/invites", method: "POST")
    }

    func redeemInvite(serverURL: URL, inviteToken: String, name: String) async throws -> RedeemResponse {
        let url = serverURL.appendingPathComponent("/api/invites/redeem")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "invite_token": inviteToken,
            "name": name,
        ])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            let msg = String(data: data, encoding: .utf8)
            throw APIError.httpError(
                statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0,
                message: msg
            )
        }

        return try decoder.decode(RedeemResponse.self, from: data)
    }

    func redeemInviteAsExistingUser(inviteToken: String) async throws -> RedeemResponse {
        guard let baseURL = authRepository.serverURL,
              let token = authRepository.token else {
            throw APIError.notAuthenticated
        }

        let url = baseURL.appendingPathComponent("/api/invites/redeem")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(["invite_token": inviteToken])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            let msg = String(data: data, encoding: .utf8)
            throw APIError.httpError(
                statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0,
                message: msg
            )
        }

        return try decoder.decode(RedeemResponse.self, from: data)
    }

    // MARK: - Contacts

    func deleteContact(_ contactID: String) async throws {
        try await requestVoid("/api/contacts/\(contactID)", method: "DELETE")
    }
```

- [ ] **Step 3: Commit**

```bash
cd ios
git add .
git commit -m "feat(ios): add invite/contact API methods and response models"
```

---

### Task 9: iOS QR Scanner Component

**Files:**
- Create: `ios/Beamlet/Presentation/Scanner/QRScannerView.swift`
- Modify: `ios/Beamlet/Resources/Info.plist` (add camera usage description)
- Modify: `ios/project.yml` (add camera usage description)

- [ ] **Step 1: Add camera usage description to Info.plist**

Add to `ios/Beamlet/Resources/Info.plist`, inside the top-level `<dict>`:

```xml
    <key>NSCameraUsageDescription</key>
    <string>Beamlet uses the camera to scan QR codes for connecting with other users.</string>
```

- [ ] **Step 2: Create QR scanner view**

Create `ios/Beamlet/Presentation/Scanner/QRScannerView.swift`:

```swift
import SwiftUI
import AVFoundation

struct QRScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let vc = ScannerViewController()
        vc.onScan = onScan
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}
}

class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((String) -> Void)?
    private var captureSession: AVCaptureSession?
    private var hasScanned = false

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
    }

    private func setupCamera() {
        let session = AVCaptureSession()

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            return
        }

        if session.canAddInput(input) {
            session.addInput(input)
        }

        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]
        }

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = view.bounds
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)

        captureSession = session
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !hasScanned,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              object.type == .qr,
              let value = object.stringValue else {
            return
        }

        hasScanned = true
        captureSession?.stopRunning()
        AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
        onScan?(value)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureSession?.stopRunning()
    }
}
```

- [ ] **Step 3: Commit**

```bash
cd ios
git add .
git commit -m "feat(ios): add QR scanner view component with camera support"
```

---

### Task 10: iOS Setup Flow with QR Scan

**Files:**
- Modify: `ios/Beamlet/Presentation/Setup/SetupView.swift`
- Create: `ios/Beamlet/Presentation/Setup/NameEntryView.swift`

- [ ] **Step 1: Create name entry view**

Create `ios/Beamlet/Presentation/Setup/NameEntryView.swift`:

```swift
import SwiftUI

struct NameEntryView: View {
    @Environment(AuthRepository.self) private var authRepository
    @Environment(BeamletAPI.self) private var api

    let serverURL: URL
    let inviteToken: String
    let onComplete: () -> Void

    @State private var name = ""
    @State private var isSubmitting = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 12) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)
                Text("What's your name?")
                    .font(.title2.bold())
                Text("This is how others will see you in Beamlet.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            TextField("Your name", text: $name)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            if let error = error {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            Button(action: submit) {
                if isSubmitting {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
            .padding(.horizontal)
        }
        .padding()
    }

    private func submit() {
        isSubmitting = true
        error = nil

        Task {
            do {
                let response = try await api.redeemInvite(
                    serverURL: serverURL,
                    inviteToken: inviteToken,
                    name: name.trimmingCharacters(in: .whitespaces)
                )

                guard let token = response.token else {
                    self.error = "Invalid response from server"
                    isSubmitting = false
                    return
                }

                authRepository.store(serverURL: serverURL, token: token)
                onComplete()
            } catch {
                self.error = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}
```

- [ ] **Step 2: Update SetupView with QR scan button**

Replace `ios/Beamlet/Presentation/Setup/SetupView.swift` with:

```swift
import SwiftUI

struct SetupView: View {
    @Environment(AuthRepository.self) private var authRepository
    @Environment(BeamletAPI.self) private var api

    @State private var serverURL = ""
    @State private var token = ""
    @State private var isConnecting = false
    @State private var error: String?
    @State private var showScanner = false
    @State private var scannedPayload: QRPayload?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "paperplane.circle.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(.blue)

                        Text("Beamlet")
                            .font(.largeTitle.bold())

                        Text("Scan a QR code or enter your server details")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 40)

                    // QR Scan button
                    Button {
                        showScanner = true
                    } label: {
                        Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.horizontal)

                    // Divider
                    HStack {
                        Rectangle().frame(height: 1).foregroundStyle(.secondary.opacity(0.3))
                        Text("or enter manually")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Rectangle().frame(height: 1).foregroundStyle(.secondary.opacity(0.3))
                    }
                    .padding(.horizontal)

                    // Manual form
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Server URL")
                                .font(.headline)
                            TextField("https://beamlet.example.com", text: $serverURL)
                                .textFieldStyle(.roundedBorder)
                                .textContentType(.URL)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .keyboardType(.URL)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("API Token")
                                .font(.headline)
                            SecureField("Paste your token here", text: $token)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .padding(.horizontal)

                    if let error = error {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.callout)
                            .padding(.horizontal)
                    }

                    Button(action: connect) {
                        if isConnecting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Connect")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(serverURL.isEmpty || token.isEmpty || isConnecting)
                    .padding(.horizontal)
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showScanner) {
                NavigationStack {
                    QRScannerView { value in
                        handleScan(value)
                    }
                    .ignoresSafeArea()
                    .navigationTitle("Scan QR Code")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showScanner = false }
                        }
                    }
                }
            }
            .sheet(item: $scannedPayload) { payload in
                NavigationStack {
                    NameEntryView(
                        serverURL: URL(string: payload.url)!,
                        inviteToken: payload.invite,
                        onComplete: { scannedPayload = nil }
                    )
                    .environment(authRepository)
                    .environment(api)
                    .navigationTitle("Setup")
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
    }

    private func handleScan(_ value: String) {
        showScanner = false
        guard let data = value.data(using: .utf8),
              let payload = try? JSONDecoder().decode(QRPayload.self, from: data) else {
            error = "Invalid QR code"
            return
        }
        scannedPayload = payload
    }

    private func connect() {
        guard let url = URL(string: serverURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            error = "Invalid URL"
            return
        }

        isConnecting = true
        error = nil

        Task {
            authRepository.store(serverURL: url, token: token.trimmingCharacters(in: .whitespacesAndNewlines))

            do {
                let _ = try await api.listUsers()

                let center = UNUserNotificationCenter.current()
                let granted = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
                if granted == true {
                    await MainActor.run {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                }

                if let deviceToken = UserDefaults(suiteName: "group.com.beamlet.shared")?.string(forKey: "apnsDeviceToken") {
                    authRepository.storeDeviceToken(deviceToken)
                    try? await api.registerDevice(apnsToken: deviceToken)
                }
            } catch {
                authRepository.clear()
                self.error = error.localizedDescription
            }

            isConnecting = false
        }
    }
}
```

- [ ] **Step 3: Make QRPayload conform to Identifiable**

In `ios/Beamlet/Model/Models.swift`, update the QRPayload struct to conform to `Identifiable` (needed for `.sheet(item:)`):

```swift
struct QRPayload: Codable, Identifiable {
    var id: String { invite }
    let url: String
    let invite: String
}
```

- [ ] **Step 4: Commit**

```bash
cd ios
git add .
git commit -m "feat(ios): add QR scan setup flow with name entry"
```

---

### Task 11: iOS Settings - Add Contact and Scan Invite

**Files:**
- Create: `ios/Beamlet/Presentation/Settings/AddContactView.swift`
- Create: `ios/Beamlet/Presentation/Settings/ScanInviteView.swift`
- Modify: `ios/Beamlet/Presentation/Settings/SettingsView.swift`

- [ ] **Step 1: Create Add Contact view (shows QR code)**

Create `ios/Beamlet/Presentation/Settings/AddContactView.swift`:

```swift
import SwiftUI
import CoreImage.CIFilterBuiltins

struct AddContactView: View {
    @Environment(BeamletAPI.self) private var api
    @Environment(AuthRepository.self) private var authRepository

    @State private var inviteToken: String?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        VStack(spacing: 24) {
            if isLoading {
                ProgressView("Creating invite...")
            } else if let error = error {
                ErrorView(message: error) {
                    Task { await createInvite() }
                }
            } else if let token = inviteToken, let url = authRepository.serverURL {
                let payload = QRPayload(url: url.absoluteString, invite: token)

                VStack(spacing: 16) {
                    Text("Have them scan this with Beamlet")
                        .font(.headline)

                    if let qrImage = generateQRCode(from: payload) {
                        Image(uiImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 250, height: 250)
                            .padding()
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    Text("This code expires in 24 hours")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .navigationTitle("Add Contact")
        .task {
            await createInvite()
        }
    }

    private func createInvite() async {
        isLoading = true
        error = nil
        do {
            let response = try await api.createInvite()
            inviteToken = response.inviteToken
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func generateQRCode(from payload: QRPayload) -> UIImage? {
        guard let data = try? JSONEncoder().encode(payload) else { return nil }

        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let ciImage = filter.outputImage else { return nil }

        let scale = 10.0
        let transformed = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }

        return UIImage(cgImage: cgImage)
    }
}
```

- [ ] **Step 2: Create Scan Invite view (for existing users)**

Create `ios/Beamlet/Presentation/Settings/ScanInviteView.swift`:

```swift
import SwiftUI

struct ScanInviteView: View {
    @Environment(BeamletAPI.self) private var api
    @Environment(\.dismiss) private var dismiss

    @State private var connectedName: String?
    @State private var error: String?
    @State private var isRedeeming = false

    var body: some View {
        Group {
            if let name = connectedName {
                VStack(spacing: 20) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.green)
                    Text("Connected with \(name)!")
                        .font(.title2.bold())
                    Button("Done") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }
            } else if isRedeeming {
                ProgressView("Connecting...")
            } else {
                QRScannerView { value in
                    handleScan(value)
                }
                .ignoresSafeArea()
                .overlay(alignment: .bottom) {
                    if let error = error {
                        Text(error)
                            .foregroundStyle(.white)
                            .padding()
                            .background(.red.opacity(0.8))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .padding()
                    }
                }
            }
        }
        .navigationTitle("Scan Invite")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func handleScan(_ value: String) {
        guard let data = value.data(using: .utf8),
              let payload = try? JSONDecoder().decode(QRPayload.self, from: data) else {
            error = "Invalid QR code"
            return
        }

        isRedeeming = true
        error = nil

        Task {
            do {
                let response = try await api.redeemInviteAsExistingUser(inviteToken: payload.invite)
                connectedName = response.contact?.name ?? "New contact"
            } catch {
                self.error = error.localizedDescription
                isRedeeming = false
            }
        }
    }
}
```

- [ ] **Step 3: Update SettingsView with contact management**

Replace `ios/Beamlet/Presentation/Settings/SettingsView.swift`:

```swift
import SwiftUI

struct SettingsView: View {
    @Environment(AuthRepository.self) private var authRepository
    @Environment(BeamletAPI.self) private var api

    @State private var showLogoutConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section("Contacts") {
                    NavigationLink {
                        AddContactView()
                    } label: {
                        Label("Add Contact", systemImage: "person.badge.plus")
                    }

                    NavigationLink {
                        ScanInviteView()
                    } label: {
                        Label("Scan Invite", systemImage: "qrcode.viewfinder")
                    }
                }

                Section("Server") {
                    if let url = authRepository.serverURL {
                        LabeledContent("URL", value: url.absoluteString)
                    }
                    LabeledContent("Status") {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(.green)
                                .frame(width: 8, height: 8)
                            Text("Connected")
                        }
                    }
                }

                Section("Notifications") {
                    LabeledContent("Push") {
                        if authRepository.deviceToken != nil {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(.green)
                                    .frame(width: 8, height: 8)
                                Text("Enabled")
                            }
                        } else {
                            Text("Not registered")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                }

                Section {
                    Button("Disconnect", role: .destructive) {
                        showLogoutConfirmation = true
                    }
                }
            }
            .navigationTitle("Settings")
            .alert("Disconnect?", isPresented: $showLogoutConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Disconnect", role: .destructive) {
                    authRepository.clear()
                }
            } message: {
                Text("You'll need to re-enter your server details to reconnect.")
            }
        }
    }
}
```

- [ ] **Step 4: Commit**

```bash
cd ios
git add .
git commit -m "feat(ios): add contact management with QR invite generation and scanning"
```

---

### Task 12: Build Verification

**Files:** None (verification only)

- [ ] **Step 1: Run all server tests**

```bash
cd server
go test ./... -v
```

Expected: All tests pass

- [ ] **Step 2: Rebuild container and verify**

```bash
cd server
podman build -f - -t beamlet . <<'DOCKERFILE'
FROM golang:1.25rc2-alpine AS builder
WORKDIR /build
COPY go.mod go.sum ./
ENV GOTOOLCHAIN=auto
ENV GOFLAGS=-mod=mod
RUN go mod download || true
COPY . .
ENV CGO_ENABLED=0
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
DOCKERFILE
```

Expected: Build succeeds

- [ ] **Step 3: Generate Xcode project and build iOS app**

```bash
cd ios
xcodegen generate
xcodebuild -scheme Beamlet -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Run iOS tests**

```bash
cd ios
xcodebuild -scheme Beamlet -destination 'platform=iOS Simulator,name=iPhone 16' test 2>&1 | tail -10
```

Expected: Tests pass

- [ ] **Step 5: Commit any generated changes**

```bash
git add .
git commit -m "chore: regenerate Xcode project with camera permission and new files"
```

---

## Post-Implementation Testing

1. Stop old container: `podman stop beamlet && podman rm beamlet`
2. Start new container: `podman run -d --name beamlet -p 8080:8080 beamlet`
3. Create user: `podman exec beamlet /app/beamlet add-user mondo` — should show QR code
4. Scan QR with iOS app — should show name entry, then connect
5. Create second user via invite from Settings → Add Contact
6. Verify both users see each other in Send tab
7. Verify users NOT connected do not see each other
