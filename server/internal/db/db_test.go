package db_test

import (
	"testing"

	"github.com/mondominator/beamlet/server/testutil"
)

func TestOpen_RunsMigrations(t *testing.T) {
	database := testutil.TestDB(t)

	rows, err := database.SQL().Query(
		"SELECT name FROM sqlite_master WHERE type='table' AND name IN ('users', 'devices', 'files') ORDER BY name",
	)
	if err != nil {
		t.Fatalf("query failed: %v", err)
	}
	defer rows.Close()

	var tables []string
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err != nil {
			t.Fatalf("scan failed: %v", err)
		}
		tables = append(tables, name)
	}

	if len(tables) != 3 {
		t.Fatalf("expected 3 tables, got %d: %v", len(tables), tables)
	}
	if tables[0] != "devices" || tables[1] != "files" || tables[2] != "users" {
		t.Fatalf("unexpected tables: %v", tables)
	}
}
