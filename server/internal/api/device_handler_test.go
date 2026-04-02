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

func TestRegisterDeviceBodyTooLarge(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	// Send a body larger than the 1MB MaxBytesReader limit
	largeBody := `{"apns_token":"` + strings.Repeat("x", 2*1024*1024) + `","platform":"ios"}`
	req := httptest.NewRequest("POST", "/api/auth/register-device", strings.NewReader(largeBody))
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for oversized body, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestRegisterDeviceMissingToken(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	// Send empty apns_token
	body := `{"apns_token":"","platform":"ios"}`
	req := httptest.NewRequest("POST", "/api/auth/register-device", strings.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for empty apns_token, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestRegisterDeviceDefaultPlatform(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	// Send without platform -- should default to "ios"
	body := `{"apns_token":"abc123def456"}`
	req := httptest.NewRequest("POST", "/api/auth/register-device", strings.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestRegisterDeviceInvalidJSON(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	body := `{invalid json}`
	req := httptest.NewRequest("POST", "/api/auth/register-device", strings.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for invalid JSON, got %d: %s", rec.Code, rec.Body.String())
	}
}
