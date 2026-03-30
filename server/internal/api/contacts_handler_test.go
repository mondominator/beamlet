package api_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/mondominator/beamlet/server/internal/api"
)

func TestListContacts(t *testing.T) {
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

	// Add Bob as a contact
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

	// Add Bob as a contact, then delete
	srv.ContactStore.Add(aliceID, bobID)

	req := httptest.NewRequest("DELETE", "/api/contacts/"+bobID, nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusNoContent {
		t.Fatalf("expected 204, got %d: %s", rec.Code, rec.Body.String())
	}

	// Verify contact is gone
	contacts, _ := srv.ContactStore.ListForUser(aliceID)
	if len(contacts) != 0 {
		t.Fatalf("expected 0 contacts after delete, got %d", len(contacts))
	}
}
