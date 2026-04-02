package api_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/mondominator/beamlet/server/internal/api"
	"github.com/mondominator/beamlet/server/internal/config"
	"github.com/mondominator/beamlet/server/internal/storage"
	"github.com/mondominator/beamlet/server/internal/store"
	"github.com/mondominator/beamlet/server/testutil"
)

func setupTestServer(t *testing.T) (*api.Server, string) {
	t.Helper()
	db := testutil.TestDB(t)
	tmpDir := t.TempDir()

	us := store.NewUserStore(db.SQL())
	fs := store.NewFileStore(db.SQL())
	cs := store.NewContactStore(db.SQL())
	is := store.NewInviteStore(db.SQL())
	ds := storage.NewDiskStorage(tmpDir)

	_, token, _ := us.Create("Alice")
	us.Create("Bob")

	srv := &api.Server{
		UserStore:    us,
		FileStore:    fs,
		ContactStore: cs,
		InviteStore:  is,
		Storage:      ds,
		Config:       config.Config{MaxFileSize: 524288000, ExpiryDays: 30, DataDir: tmpDir},
	}
	return srv, token
}

func TestListContacts(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	// Get Alice and Bob's IDs
	users, _ := srv.UserStore.List()
	var aliceID, bobID string
	for _, u := range users {
		if u.Name == "Alice" {
			aliceID = u.ID
		} else if u.Name == "Bob" {
			bobID = u.ID
		}
	}

	// Add Bob as a contact of Alice
	srv.ContactStore.Add(aliceID, bobID)

	req := httptest.NewRequest("GET", "/api/contacts", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	var contacts []struct {
		ID   string `json:"id"`
		Name string `json:"name"`
	}
	if err := json.NewDecoder(rec.Body).Decode(&contacts); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(contacts) != 1 {
		t.Fatalf("expected 1 contact, got %d", len(contacts))
	}
	if contacts[0].Name != "Bob" {
		t.Fatalf("expected Bob, got %s", contacts[0].Name)
	}
}

func TestListContactsEmpty(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	// No contacts added - should return empty array
	req := httptest.NewRequest("GET", "/api/contacts", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	var contacts []struct {
		Name string `json:"name"`
	}
	if err := json.NewDecoder(rec.Body).Decode(&contacts); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(contacts) != 0 {
		t.Fatalf("expected 0 contacts, got %d", len(contacts))
	}
}

func TestListUsersLegacyRoute(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	req := httptest.NewRequest("GET", "/api/users", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("legacy /api/users route should return 200, got %d", rec.Code)
	}
}

func TestDeleteContact(t *testing.T) {
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

	// Add Bob as a contact of Alice
	srv.ContactStore.Add(aliceID, bobID)

	// Verify they are contacts
	areContacts, _ := srv.ContactStore.AreContacts(aliceID, bobID)
	if !areContacts {
		t.Fatal("expected Alice and Bob to be contacts before delete")
	}

	// Delete contact
	req := httptest.NewRequest("DELETE", "/api/contacts/"+bobID, nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusNoContent {
		t.Fatalf("expected 204, got %d: %s", rec.Code, rec.Body.String())
	}

	// Verify they are no longer contacts
	areContacts, _ = srv.ContactStore.AreContacts(aliceID, bobID)
	if areContacts {
		t.Fatal("expected Alice and Bob to NOT be contacts after delete")
	}
}

func TestDeleteContactNonExistent(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	// Delete a contact that doesn't exist - should still return 204
	req := httptest.NewRequest("DELETE", "/api/contacts/nonexistent-id", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusNoContent {
		t.Fatalf("expected 204, got %d: %s", rec.Code, rec.Body.String())
	}
}
