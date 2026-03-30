package store_test

import (
	"testing"

	"github.com/mondominator/beamlet/server/internal/store"
	"github.com/mondominator/beamlet/server/testutil"
)

func TestContactStore_AddAndList(t *testing.T) {
	db := testutil.TestDB(t)
	userStore := store.NewUserStore(db.SQL())
	contactStore := store.NewContactStore(db.SQL())

	alice, _, _ := userStore.Create("Alice")
	bob, _, _ := userStore.Create("Bob")

	if err := contactStore.Add(alice.ID, bob.ID); err != nil {
		t.Fatalf("add contact: %v", err)
	}

	// Alice should see Bob
	contacts, err := contactStore.ListForUser(alice.ID)
	if err != nil {
		t.Fatalf("list contacts: %v", err)
	}
	if len(contacts) != 1 || contacts[0].ID != bob.ID {
		t.Fatalf("expected Bob in Alice's contacts, got %v", contacts)
	}

	// Bob should see Alice (mutual)
	contacts, err = contactStore.ListForUser(bob.ID)
	if err != nil {
		t.Fatalf("list contacts: %v", err)
	}
	if len(contacts) != 1 || contacts[0].ID != alice.ID {
		t.Fatalf("expected Alice in Bob's contacts, got %v", contacts)
	}
}

func TestContactStore_Delete(t *testing.T) {
	db := testutil.TestDB(t)
	userStore := store.NewUserStore(db.SQL())
	contactStore := store.NewContactStore(db.SQL())

	alice, _, _ := userStore.Create("Alice")
	bob, _, _ := userStore.Create("Bob")

	contactStore.Add(alice.ID, bob.ID)

	if err := contactStore.Delete(alice.ID, bob.ID); err != nil {
		t.Fatalf("delete contact: %v", err)
	}

	contacts, _ := contactStore.ListForUser(alice.ID)
	if len(contacts) != 0 {
		t.Fatalf("expected empty contacts after delete, got %v", contacts)
	}

	// Bob side also gone
	contacts, _ = contactStore.ListForUser(bob.ID)
	if len(contacts) != 0 {
		t.Fatalf("expected empty contacts for Bob after delete, got %v", contacts)
	}
}

func TestContactStore_AddDuplicate(t *testing.T) {
	db := testutil.TestDB(t)
	userStore := store.NewUserStore(db.SQL())
	contactStore := store.NewContactStore(db.SQL())

	alice, _, _ := userStore.Create("Alice")
	bob, _, _ := userStore.Create("Bob")

	contactStore.Add(alice.ID, bob.ID)

	// Adding again should not error (idempotent)
	if err := contactStore.Add(alice.ID, bob.ID); err != nil {
		t.Fatalf("duplicate add should not error: %v", err)
	}

	contacts, _ := contactStore.ListForUser(alice.ID)
	if len(contacts) != 1 {
		t.Fatalf("expected 1 contact after duplicate add, got %d", len(contacts))
	}
}

func TestContactStore_AreContacts(t *testing.T) {
	db := testutil.TestDB(t)
	userStore := store.NewUserStore(db.SQL())
	contactStore := store.NewContactStore(db.SQL())

	alice, _, _ := userStore.Create("Alice")
	bob, _, _ := userStore.Create("Bob")
	carol, _, _ := userStore.Create("Carol")

	contactStore.Add(alice.ID, bob.ID)

	if ok, _ := contactStore.AreContacts(alice.ID, bob.ID); !ok {
		t.Fatal("Alice and Bob should be contacts")
	}
	if ok, _ := contactStore.AreContacts(alice.ID, carol.ID); ok {
		t.Fatal("Alice and Carol should not be contacts")
	}
}
