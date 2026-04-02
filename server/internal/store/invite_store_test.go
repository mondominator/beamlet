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

func TestInviteStore_FindByToken_WrongToken(t *testing.T) {
	database := testutil.TestDB(t)
	userStore := store.NewUserStore(database.SQL())
	inviteStore := store.NewInviteStore(database.SQL())

	alice, _, _ := userStore.Create("Alice")
	inviteStore.Create(alice.ID, "", 24*time.Hour)

	_, err := inviteStore.FindByToken("aaaabbbbccccddddeeeeffffgggg0000")
	if err == nil {
		t.Fatal("expected error for wrong token")
	}
}

func TestInviteStore_FindByToken_ShortToken(t *testing.T) {
	database := testutil.TestDB(t)
	inviteStore := store.NewInviteStore(database.SQL())

	_, err := inviteStore.FindByToken("short")
	if err == nil {
		t.Fatal("expected error for short token")
	}
}

func TestInviteStore_FindByToken_EmptyToken(t *testing.T) {
	database := testutil.TestDB(t)
	inviteStore := store.NewInviteStore(database.SQL())

	_, err := inviteStore.FindByToken("")
	if err == nil {
		t.Fatal("expected error for empty token")
	}
}

func TestInviteStore_DeleteExpired(t *testing.T) {
	database := testutil.TestDB(t)
	userStore := store.NewUserStore(database.SQL())
	inviteStore := store.NewInviteStore(database.SQL())

	alice, _, _ := userStore.Create("Alice")

	// Create an invite that expired more than 7 days ago
	// We do this by creating with a very negative TTL
	inviteStore.Create(alice.ID, "", -8*24*time.Hour)

	// Also create a valid invite
	_, validToken, _ := inviteStore.Create(alice.ID, "", 24*time.Hour)

	deleted, err := inviteStore.DeleteExpired()
	if err != nil {
		t.Fatalf("delete expired: %v", err)
	}
	if deleted != 1 {
		t.Fatalf("expected 1 deleted, got %d", deleted)
	}

	// Valid invite should still work
	_, err = inviteStore.FindByToken(validToken)
	if err != nil {
		t.Fatalf("valid invite should still be findable: %v", err)
	}
}

func TestInviteStore_DeleteExpired_None(t *testing.T) {
	database := testutil.TestDB(t)
	userStore := store.NewUserStore(database.SQL())
	inviteStore := store.NewInviteStore(database.SQL())

	alice, _, _ := userStore.Create("Alice")

	// Create only a valid invite
	inviteStore.Create(alice.ID, "", 24*time.Hour)

	deleted, err := inviteStore.DeleteExpired()
	if err != nil {
		t.Fatalf("delete expired: %v", err)
	}
	if deleted != 0 {
		t.Fatalf("expected 0 deleted, got %d", deleted)
	}
}

func TestInviteStore_DeleteExpired_Redeemed(t *testing.T) {
	database := testutil.TestDB(t)
	userStore := store.NewUserStore(database.SQL())
	inviteStore := store.NewInviteStore(database.SQL())

	alice, _, _ := userStore.Create("Alice")
	bob, _, _ := userStore.Create("Bob")

	invite, _, _ := inviteStore.Create(alice.ID, "", 24*time.Hour)

	// Redeem the invite
	inviteStore.Redeem(invite.ID, bob.ID)

	// Manually backdate the redeemed_at to more than 7 days ago
	database.SQL().Exec(
		"UPDATE invites SET redeemed_at = ? WHERE id = ?",
		time.Now().Add(-8*24*time.Hour), invite.ID,
	)

	deleted, err := inviteStore.DeleteExpired()
	if err != nil {
		t.Fatalf("delete expired: %v", err)
	}
	if deleted != 1 {
		t.Fatalf("expected 1 deleted (old redeemed), got %d", deleted)
	}
}

func TestInviteStore_Redeem_CannotFindAfter(t *testing.T) {
	database := testutil.TestDB(t)
	userStore := store.NewUserStore(database.SQL())
	inviteStore := store.NewInviteStore(database.SQL())

	alice, _, _ := userStore.Create("Alice")
	bob, _, _ := userStore.Create("Bob")

	invite, token, _ := inviteStore.Create(alice.ID, "", 24*time.Hour)

	if err := inviteStore.Redeem(invite.ID, bob.ID); err != nil {
		t.Fatalf("redeem: %v", err)
	}

	// Should not be findable after redemption
	_, err := inviteStore.FindByToken(token)
	if err == nil {
		t.Fatal("expected error finding redeemed invite")
	}
}

func TestInviteStore_FindByToken_FallbackPath(t *testing.T) {
	database := testutil.TestDB(t)
	userStore := store.NewUserStore(database.SQL())
	inviteStore := store.NewInviteStore(database.SQL())

	alice, _, _ := userStore.Create("Alice")

	invite, token, err := inviteStore.Create(alice.ID, "", 24*time.Hour)
	if err != nil {
		t.Fatalf("create: %v", err)
	}

	// Null out token_prefix to simulate a pre-migration invite
	_, err = database.SQL().Exec("UPDATE invites SET token_prefix = NULL WHERE id = ?", invite.ID)
	if err != nil {
		t.Fatalf("nullify prefix: %v", err)
	}

	// FindByToken should fall through to fallback scan
	found, err := inviteStore.FindByToken(token)
	if err != nil {
		t.Fatalf("find by token fallback: %v", err)
	}
	if found.ID != invite.ID {
		t.Fatalf("expected invite %s, got %s", invite.ID, found.ID)
	}

	// After fallback, prefix should be backfilled
	found2, err := inviteStore.FindByToken(token)
	if err != nil {
		t.Fatalf("find after backfill: %v", err)
	}
	if found2.ID != invite.ID {
		t.Fatalf("expected invite %s after backfill, got %s", invite.ID, found2.ID)
	}
}

func TestInviteStore_CreateMultipleAndFindEach(t *testing.T) {
	database := testutil.TestDB(t)
	userStore := store.NewUserStore(database.SQL())
	inviteStore := store.NewInviteStore(database.SQL())

	alice, _, _ := userStore.Create("Alice")

	tokens := make([]string, 3)
	ids := make([]string, 3)
	for i := 0; i < 3; i++ {
		invite, token, err := inviteStore.Create(alice.ID, "", 24*time.Hour)
		if err != nil {
			t.Fatalf("create invite %d: %v", i, err)
		}
		tokens[i] = token
		ids[i] = invite.ID
	}

	for i, token := range tokens {
		found, err := inviteStore.FindByToken(token)
		if err != nil {
			t.Fatalf("find invite %d: %v", i, err)
		}
		if found.ID != ids[i] {
			t.Fatalf("invite %d: expected ID %s, got %s", i, ids[i], found.ID)
		}
	}
}
