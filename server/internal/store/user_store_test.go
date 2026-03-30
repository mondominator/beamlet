package store_test

import (
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
