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
