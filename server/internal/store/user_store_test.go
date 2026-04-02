package store_test

import (
	"strings"
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

	_, err = s.Authenticate(oldToken)
	if err == nil {
		t.Fatal("old token should no longer work")
	}

	_, err = s.Authenticate(newToken)
	if err != nil {
		t.Fatalf("new token should work: %v", err)
	}
}

func TestUserStore_GetByID_NotFound(t *testing.T) {
	db := testutil.TestDB(t)
	s := store.NewUserStore(db.SQL())

	_, err := s.GetByID("nonexistent-id")
	if err == nil {
		t.Fatal("expected error for non-existent user")
	}
}

func TestUserStore_GetByID_FieldsCorrect(t *testing.T) {
	db := testutil.TestDB(t)
	s := store.NewUserStore(db.SQL())

	created, _, err := s.Create("Charlie")
	if err != nil {
		t.Fatalf("create: %v", err)
	}

	got, err := s.GetByID(created.ID)
	if err != nil {
		t.Fatalf("get by id: %v", err)
	}
	if got.ID != created.ID {
		t.Fatalf("expected ID %s, got %s", created.ID, got.ID)
	}
	if got.Name != "Charlie" {
		t.Fatalf("expected name Charlie, got %s", got.Name)
	}
	if got.TokenHash == "" {
		t.Fatal("expected non-empty token hash")
	}
	if got.CreatedAt.IsZero() {
		t.Fatal("expected non-zero created_at")
	}
}

func TestUserStore_RevokeToken_NonExistentUser(t *testing.T) {
	db := testutil.TestDB(t)
	s := store.NewUserStore(db.SQL())

	_, err := s.RevokeToken("nonexistent-user-id")
	if err == nil {
		t.Fatal("expected error revoking token for non-existent user")
	}
	if !strings.Contains(err.Error(), "user not found") {
		t.Fatalf("expected 'user not found' error, got: %v", err)
	}
}

func TestUserStore_Authenticate_ShortToken(t *testing.T) {
	db := testutil.TestDB(t)
	s := store.NewUserStore(db.SQL())

	s.Create("Alice")

	// Token shorter than 8 characters should fail fast
	_, err := s.Authenticate("short")
	if err == nil {
		t.Fatal("expected error for short token")
	}
}

func TestUserStore_Authenticate_EmptyToken(t *testing.T) {
	db := testutil.TestDB(t)
	s := store.NewUserStore(db.SQL())

	_, err := s.Authenticate("")
	if err == nil {
		t.Fatal("expected error for empty token")
	}
}

func TestUserStore_Authenticate_WrongTokenLongEnough(t *testing.T) {
	db := testutil.TestDB(t)
	s := store.NewUserStore(db.SQL())

	s.Create("Alice")

	// A token that's long enough (>8 chars) but wrong
	_, err := s.Authenticate("aaaaaaaabbbbbbbbcccccccc")
	if err == nil {
		t.Fatal("expected error for wrong but properly-sized token")
	}
}

func TestUserStore_Authenticate_FallbackPath(t *testing.T) {
	db := testutil.TestDB(t)
	s := store.NewUserStore(db.SQL())

	// Create a user, then null out token_prefix to simulate a pre-migration row
	user, token, err := s.Create("Legacy")
	if err != nil {
		t.Fatalf("create: %v", err)
	}

	// Manually set token_prefix to NULL
	_, err = db.SQL().Exec("UPDATE users SET token_prefix = NULL WHERE id = ?", user.ID)
	if err != nil {
		t.Fatalf("nullify prefix: %v", err)
	}

	// Authenticate should fall through to the fallback scan path
	got, err := s.Authenticate(token)
	if err != nil {
		t.Fatalf("authenticate fallback: %v", err)
	}
	if got.ID != user.ID {
		t.Fatalf("expected user %s, got %s", user.ID, got.ID)
	}
	if got.Name != "Legacy" {
		t.Fatalf("expected name Legacy, got %s", got.Name)
	}

	// After fallback, the prefix should be backfilled - verify by authenticating again (fast path)
	got2, err := s.Authenticate(token)
	if err != nil {
		t.Fatalf("authenticate after backfill: %v", err)
	}
	if got2.ID != user.ID {
		t.Fatalf("expected user %s after backfill, got %s", user.ID, got2.ID)
	}
}

func TestUserStore_RegisterDevice(t *testing.T) {
	db := testutil.TestDB(t)
	s := store.NewUserStore(db.SQL())

	user, _, _ := s.Create("Alice")

	err := s.RegisterDevice(user.ID, "apns-token-123", "ios")
	if err != nil {
		t.Fatalf("register device: %v", err)
	}

	devices, err := s.GetActiveDevices(user.ID)
	if err != nil {
		t.Fatalf("get devices: %v", err)
	}
	if len(devices) != 1 {
		t.Fatalf("expected 1 device, got %d", len(devices))
	}
	if devices[0].APNsToken != "apns-token-123" {
		t.Fatalf("expected token apns-token-123, got %s", devices[0].APNsToken)
	}
	if devices[0].Platform != "ios" {
		t.Fatalf("expected platform ios, got %s", devices[0].Platform)
	}
}

func TestUserStore_RegisterDevice_Duplicate(t *testing.T) {
	db := testutil.TestDB(t)
	s := store.NewUserStore(db.SQL())

	user, _, _ := s.Create("Alice")

	s.RegisterDevice(user.ID, "apns-token-123", "ios")
	err := s.RegisterDevice(user.ID, "apns-token-123", "ios")
	if err != nil {
		t.Fatalf("duplicate register: %v", err)
	}

	devices, _ := s.GetActiveDevices(user.ID)
	if len(devices) != 1 {
		t.Fatalf("expected 1 device after duplicate, got %d", len(devices))
	}
}

func TestUserStore_DeactivateDevice(t *testing.T) {
	db := testutil.TestDB(t)
	s := store.NewUserStore(db.SQL())

	user, _, _ := s.Create("Alice")
	s.RegisterDevice(user.ID, "apns-token-456", "ios")

	err := s.DeactivateDevice("apns-token-456")
	if err != nil {
		t.Fatalf("deactivate: %v", err)
	}

	devices, _ := s.GetActiveDevices(user.ID)
	if len(devices) != 0 {
		t.Fatalf("expected 0 active devices after deactivation, got %d", len(devices))
	}
}

func TestUserStore_GetActiveDevices_Empty(t *testing.T) {
	db := testutil.TestDB(t)
	s := store.NewUserStore(db.SQL())

	user, _, _ := s.Create("Alice")

	devices, err := s.GetActiveDevices(user.ID)
	if err != nil {
		t.Fatalf("get devices: %v", err)
	}
	if len(devices) != 0 {
		t.Fatalf("expected 0 devices, got %d", len(devices))
	}
}

func TestUserStore_RegisterDevice_ReactivateAfterDeactivation(t *testing.T) {
	db := testutil.TestDB(t)
	s := store.NewUserStore(db.SQL())

	user, _, _ := s.Create("Alice")

	s.RegisterDevice(user.ID, "apns-token-789", "ios")
	s.DeactivateDevice("apns-token-789")

	// Re-register should reactivate
	err := s.RegisterDevice(user.ID, "apns-token-789", "ios")
	if err != nil {
		t.Fatalf("re-register: %v", err)
	}

	devices, _ := s.GetActiveDevices(user.ID)
	if len(devices) != 1 {
		t.Fatalf("expected 1 active device after reactivation, got %d", len(devices))
	}
}

func TestUserStore_ListOrdering(t *testing.T) {
	db := testutil.TestDB(t)
	s := store.NewUserStore(db.SQL())

	s.Create("Charlie")
	s.Create("Alice")
	s.Create("Bob")

	users, err := s.List()
	if err != nil {
		t.Fatalf("list: %v", err)
	}
	if len(users) != 3 {
		t.Fatalf("expected 3 users, got %d", len(users))
	}
	// List should be ordered by name
	if users[0].Name != "Alice" {
		t.Fatalf("expected Alice first, got %s", users[0].Name)
	}
	if users[1].Name != "Bob" {
		t.Fatalf("expected Bob second, got %s", users[1].Name)
	}
	if users[2].Name != "Charlie" {
		t.Fatalf("expected Charlie third, got %s", users[2].Name)
	}
}
