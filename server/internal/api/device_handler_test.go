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
