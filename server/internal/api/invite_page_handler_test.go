package api_test

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/mondominator/beamlet/server/internal/api"
)

func TestInviteWebPage(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	// Create an invite as Alice
	req := httptest.NewRequest("POST", "/api/invites", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("create invite: expected 201, got %d: %s", rec.Code, rec.Body.String())
	}

	// Extract invite_token from response
	body := rec.Body.String()
	// Parse invite_token from JSON manually to avoid import cycle issues
	start := strings.Index(body, `"invite_token":"`) + len(`"invite_token":"`)
	end := strings.Index(body[start:], `"`) + start
	inviteToken := body[start:end]

	// Hit the web page endpoint
	req = httptest.NewRequest("GET", "/invite/"+inviteToken, nil)
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	contentType := rec.Header().Get("Content-Type")
	if !strings.Contains(contentType, "text/html") {
		t.Fatalf("expected text/html content type, got %s", contentType)
	}

	responseBody := rec.Body.String()
	if !strings.Contains(responseBody, "Alice") {
		t.Fatal("expected invite page to contain creator name 'Alice'")
	}
	if !strings.Contains(responseBody, "invited") {
		t.Fatal("expected invite page to contain 'invited'")
	}
}

func TestInviteWebPageExpired(t *testing.T) {
	srv, _ := setupTestServer(t)
	router := api.NewRouter(srv)

	// Try a fake/invalid token
	req := httptest.NewRequest("GET", "/invite/invalidtoken12345678", nil)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected 404 for invalid invite, got %d", rec.Code)
	}

	if !strings.Contains(rec.Body.String(), "Invite Expired") {
		t.Fatal("expected expired page content")
	}
}

func TestAppleAppSiteAssociation(t *testing.T) {
	srv, _ := setupTestServer(t)
	router := api.NewRouter(srv)

	req := httptest.NewRequest("GET", "/.well-known/apple-app-site-association", nil)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	contentType := rec.Header().Get("Content-Type")
	if contentType != "application/json" {
		t.Fatalf("expected application/json, got %s", contentType)
	}

	body := rec.Body.String()
	if !strings.Contains(body, "applinks") {
		t.Fatal("expected applinks in response")
	}
	if !strings.Contains(body, "S6WU9SVVDW.com.beamlet.app") {
		t.Fatal("expected app ID in response")
	}
}
