package api_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/mondominator/beamlet/server/internal/api"
)

func TestGetMe(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	req := httptest.NewRequest("GET", "/api/me", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	var result struct {
		ID   string `json:"id"`
		Name string `json:"name"`
	}
	if err := json.NewDecoder(rec.Body).Decode(&result); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if result.Name != "Alice" {
		t.Fatalf("expected Alice, got %s", result.Name)
	}
	if result.ID == "" {
		t.Fatal("expected non-empty ID")
	}
}

func TestGetMe_Unauthorized(t *testing.T) {
	srv, _ := setupTestServer(t)
	router := api.NewRouter(srv)

	req := httptest.NewRequest("GET", "/api/me", nil)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", rec.Code)
	}
}

func TestGetUserProfile(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	// Get Bob's ID
	users, _ := srv.UserStore.List()
	var bobID string
	for _, u := range users {
		if u.Name == "Bob" {
			bobID = u.ID
		}
	}

	req := httptest.NewRequest("GET", "/api/users/"+bobID+"/profile", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	var result struct {
		ID   string `json:"id"`
		Name string `json:"name"`
	}
	if err := json.NewDecoder(rec.Body).Decode(&result); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if result.Name != "Bob" {
		t.Fatalf("expected Bob, got %s", result.Name)
	}
	if result.ID != bobID {
		t.Fatalf("expected ID %s, got %s", bobID, result.ID)
	}
}

func TestGetUserProfile_NotFound(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	req := httptest.NewRequest("GET", "/api/users/nonexistent-id/profile", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected 404, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestGetUserProfile_Exists(t *testing.T) {
	srv, _ := setupTestServer(t)
	router := api.NewRouter(srv)

	// Get Alice's ID
	users, _ := srv.UserStore.List()
	var aliceID string
	for _, u := range users {
		if u.Name == "Alice" {
			aliceID = u.ID
		}
	}

	// Public endpoint - no auth required
	req := httptest.NewRequest("GET", "/api/users/"+aliceID+"/profile", nil)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	var result struct {
		ID   string `json:"id"`
		Name string `json:"name"`
	}
	if err := json.NewDecoder(rec.Body).Decode(&result); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if result.Name != "Alice" {
		t.Fatalf("expected Alice, got %s", result.Name)
	}
	if result.ID != aliceID {
		t.Fatalf("expected ID %s, got %s", aliceID, result.ID)
	}
}
