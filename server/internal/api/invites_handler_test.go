package api_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/mondominator/beamlet/server/internal/api"
)

func TestCreateInvite(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	req := httptest.NewRequest("POST", "/api/invites", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d: %s", rec.Code, rec.Body.String())
	}

	var resp map[string]string
	if err := json.NewDecoder(rec.Body).Decode(&resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if resp["invite_token"] == "" {
		t.Fatal("expected invite_token in response")
	}
	if resp["expires_at"] == "" {
		t.Fatal("expected expires_at in response")
	}
}

func TestRedeemInviteNewUser(t *testing.T) {
	srv, token := setupTestServer(t)
	router := api.NewRouter(srv)

	// Create an invite as Alice
	req := httptest.NewRequest("POST", "/api/invites", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	var createResp map[string]string
	json.NewDecoder(rec.Body).Decode(&createResp)
	inviteToken := createResp["invite_token"]

	// Redeem as a new user (no auth header)
	body := `{"invite_token":"` + inviteToken + `","name":"Charlie"}`
	req = httptest.NewRequest("POST", "/api/invites/redeem", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	var resp map[string]interface{}
	json.NewDecoder(rec.Body).Decode(&resp)

	if resp["user_id"] == nil || resp["user_id"] == "" {
		t.Fatal("expected user_id in response")
	}
	if resp["name"] != "Charlie" {
		t.Fatalf("expected name Charlie, got %v", resp["name"])
	}
	if resp["token"] == nil || resp["token"] == "" {
		t.Fatal("expected token in response")
	}
	contact, ok := resp["contact"].(map[string]interface{})
	if !ok {
		t.Fatal("expected contact in response")
	}
	if contact["name"] != "Alice" {
		t.Fatalf("expected contact name Alice, got %v", contact["name"])
	}
}

func TestRedeemInviteExistingUser(t *testing.T) {
	srv, aliceToken := setupTestServer(t)
	router := api.NewRouter(srv)

	// Get Bob's token
	users, _ := srv.UserStore.List()
	var bobID string
	for _, u := range users {
		if u.Name == "Bob" {
			bobID = u.ID
		}
	}
	bobToken, _ := srv.UserStore.RevokeToken(bobID)

	// Create an invite as Alice
	req := httptest.NewRequest("POST", "/api/invites", nil)
	req.Header.Set("Authorization", "Bearer "+aliceToken)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	var createResp map[string]string
	json.NewDecoder(rec.Body).Decode(&createResp)
	inviteToken := createResp["invite_token"]

	// Redeem as Bob (existing user with auth header)
	body := `{"invite_token":"` + inviteToken + `"}`
	req = httptest.NewRequest("POST", "/api/invites/redeem", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+bobToken)
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	var resp map[string]interface{}
	json.NewDecoder(rec.Body).Decode(&resp)

	contact, ok := resp["contact"].(map[string]interface{})
	if !ok {
		t.Fatal("expected contact in response")
	}
	if contact["name"] != "Alice" {
		t.Fatalf("expected contact name Alice, got %v", contact["name"])
	}

	// Verify bidirectional contact was created
	areContacts, _ := srv.ContactStore.AreContacts(bobID, resp["contact"].(map[string]interface{})["id"].(string))
	if !areContacts {
		t.Fatal("expected Bob and Alice to be contacts")
	}
}

func TestRedeemInviteCLISetup(t *testing.T) {
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

	// Create a new user via CLI (with created_user_id)
	newUser, _, _ := srv.UserStore.Create("NewDevice")
	invite, inviteToken, _ := srv.InviteStore.Create(aliceID, newUser.ID, 24*60*60*1e9) // 24h

	_ = invite // used for verification

	// Redeem the CLI setup invite
	body := `{"invite_token":"` + inviteToken + `"}`
	req := httptest.NewRequest("POST", "/api/invites/redeem", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	var resp map[string]interface{}
	json.NewDecoder(rec.Body).Decode(&resp)

	if resp["user_id"] != newUser.ID {
		t.Fatalf("expected user_id %s, got %v", newUser.ID, resp["user_id"])
	}
	if resp["name"] != "NewDevice" {
		t.Fatalf("expected name NewDevice, got %v", resp["name"])
	}
	if resp["token"] == nil || resp["token"] == "" {
		t.Fatal("expected token in response")
	}
}

func TestRedeemInviteInvalidToken(t *testing.T) {
	srv, _ := setupTestServer(t)
	router := api.NewRouter(srv)

	body := `{"invite_token":"invalidtoken123"}`
	req := httptest.NewRequest("POST", "/api/invites/redeem", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestRedeemInviteMissingToken(t *testing.T) {
	srv, _ := setupTestServer(t)
	router := api.NewRouter(srv)

	body := `{"name":"Nobody"}`
	req := httptest.NewRequest("POST", "/api/invites/redeem", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d: %s", rec.Code, rec.Body.String())
	}
}
