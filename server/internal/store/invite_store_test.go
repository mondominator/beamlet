package store_test

import (
	"testing"
	"time"

	"github.com/mondominator/beamlet/server/internal/store"
	"github.com/mondominator/beamlet/server/testutil"
)

func TestInviteStore_CreateAndFind(t *testing.T) {
	database := testutil.TestDB(t)
	userStore := store.NewUserStore(database.SQL())
	inviteStore := store.NewInviteStore(database.SQL())

	alice, _, _ := userStore.Create("Alice")

	invite, token, err := inviteStore.Create(alice.ID, "", 24*time.Hour)
	if err != nil {
		t.Fatalf("create invite: %v", err)
	}
	if invite.CreatorID != alice.ID {
		t.Fatalf("expected creator %s, got %s", alice.ID, invite.CreatorID)
	}
	if token == "" {
		t.Fatal("expected non-empty token")
	}

	found, err := inviteStore.FindByToken(token)
	if err != nil {
		t.Fatalf("find by token: %v", err)
	}
	if found.ID != invite.ID {
		t.Fatalf("expected invite %s, got %s", invite.ID, found.ID)
	}
}

func TestInviteStore_CreateWithUser(t *testing.T) {
	database := testutil.TestDB(t)
	userStore := store.NewUserStore(database.SQL())
	inviteStore := store.NewInviteStore(database.SQL())

	alice, _, _ := userStore.Create("Alice")

	invite, _, err := inviteStore.Create(alice.ID, alice.ID, 24*time.Hour)
	if err != nil {
		t.Fatalf("create invite with user: %v", err)
	}
	if !invite.CreatedUserID.Valid || invite.CreatedUserID.String != alice.ID {
		t.Fatal("expected created_user_id to be set")
	}
}

func TestInviteStore_Redeem(t *testing.T) {
	database := testutil.TestDB(t)
	userStore := store.NewUserStore(database.SQL())
	inviteStore := store.NewInviteStore(database.SQL())

	alice, _, _ := userStore.Create("Alice")
	bob, _, _ := userStore.Create("Bob")

	invite, token, _ := inviteStore.Create(alice.ID, "", 24*time.Hour)

	if err := inviteStore.Redeem(invite.ID, bob.ID); err != nil {
		t.Fatalf("redeem: %v", err)
	}

	_, err := inviteStore.FindByToken(token)
	if err == nil {
		t.Fatal("expected error finding redeemed invite")
	}
}

func TestInviteStore_Expired(t *testing.T) {
	database := testutil.TestDB(t)
	userStore := store.NewUserStore(database.SQL())
	inviteStore := store.NewInviteStore(database.SQL())

	alice, _, _ := userStore.Create("Alice")

	_, token, _ := inviteStore.Create(alice.ID, "", -1*time.Hour)

	_, err := inviteStore.FindByToken(token)
	if err == nil {
		t.Fatal("expected error finding expired invite")
	}
}
