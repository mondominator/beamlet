package config

import (
	"os"
	"testing"
)

func TestLoad_Defaults(t *testing.T) {
	// Clear any env vars that might be set
	envVars := []string{
		"BEAMLET_DB_PATH", "BEAMLET_DATA_DIR", "BEAMLET_PORT",
		"BEAMLET_EXTERNAL_URL", "BEAMLET_APNS_KEY_PATH", "BEAMLET_APNS_KEY_ID",
		"BEAMLET_APNS_TEAM_ID", "BEAMLET_APNS_BUNDLE_ID", "BEAMLET_MAX_FILE_SIZE",
		"BEAMLET_EXPIRY_DAYS",
	}
	for _, k := range envVars {
		os.Unsetenv(k)
	}

	cfg := Load()
	if cfg.DBPath != "/data/beamlet.db" {
		t.Fatalf("expected default DBPath, got %s", cfg.DBPath)
	}
	if cfg.DataDir != "/data/files" {
		t.Fatalf("expected default DataDir, got %s", cfg.DataDir)
	}
	if cfg.Port != "8080" {
		t.Fatalf("expected default Port, got %s", cfg.Port)
	}
	if cfg.ExternalURL != "" {
		t.Fatalf("expected empty ExternalURL, got %s", cfg.ExternalURL)
	}
	if cfg.MaxFileSize != 524288000 {
		t.Fatalf("expected default MaxFileSize, got %d", cfg.MaxFileSize)
	}
	if cfg.ExpiryDays != 30 {
		t.Fatalf("expected default ExpiryDays, got %d", cfg.ExpiryDays)
	}
}

func TestLoad_CustomValues(t *testing.T) {
	os.Setenv("BEAMLET_DB_PATH", "/custom/db.sqlite")
	os.Setenv("BEAMLET_DATA_DIR", "/custom/files")
	os.Setenv("BEAMLET_PORT", "9090")
	os.Setenv("BEAMLET_EXTERNAL_URL", "https://example.com")
	os.Setenv("BEAMLET_MAX_FILE_SIZE", "1000000")
	os.Setenv("BEAMLET_EXPIRY_DAYS", "7")
	defer func() {
		os.Unsetenv("BEAMLET_DB_PATH")
		os.Unsetenv("BEAMLET_DATA_DIR")
		os.Unsetenv("BEAMLET_PORT")
		os.Unsetenv("BEAMLET_EXTERNAL_URL")
		os.Unsetenv("BEAMLET_MAX_FILE_SIZE")
		os.Unsetenv("BEAMLET_EXPIRY_DAYS")
	}()

	cfg := Load()
	if cfg.DBPath != "/custom/db.sqlite" {
		t.Fatalf("expected custom DBPath, got %s", cfg.DBPath)
	}
	if cfg.DataDir != "/custom/files" {
		t.Fatalf("expected custom DataDir, got %s", cfg.DataDir)
	}
	if cfg.Port != "9090" {
		t.Fatalf("expected custom Port, got %s", cfg.Port)
	}
	if cfg.ExternalURL != "https://example.com" {
		t.Fatalf("expected custom ExternalURL, got %s", cfg.ExternalURL)
	}
	if cfg.MaxFileSize != 1000000 {
		t.Fatalf("expected custom MaxFileSize, got %d", cfg.MaxFileSize)
	}
	if cfg.ExpiryDays != 7 {
		t.Fatalf("expected custom ExpiryDays, got %d", cfg.ExpiryDays)
	}
}

func TestLoad_InvalidMaxFileSize(t *testing.T) {
	os.Setenv("BEAMLET_MAX_FILE_SIZE", "not-a-number")
	defer os.Unsetenv("BEAMLET_MAX_FILE_SIZE")

	cfg := Load()
	if cfg.MaxFileSize != 524288000 {
		t.Fatalf("expected default MaxFileSize for invalid value, got %d", cfg.MaxFileSize)
	}
}

func TestLoad_InvalidExpiryDays(t *testing.T) {
	os.Setenv("BEAMLET_EXPIRY_DAYS", "not-a-number")
	defer os.Unsetenv("BEAMLET_EXPIRY_DAYS")

	cfg := Load()
	if cfg.ExpiryDays != 30 {
		t.Fatalf("expected default ExpiryDays for invalid value, got %d", cfg.ExpiryDays)
	}
}

func TestGetEnv_Fallback(t *testing.T) {
	os.Unsetenv("BEAMLET_TEST_KEY_XXXXX")
	val := getEnv("BEAMLET_TEST_KEY_XXXXX", "fallback")
	if val != "fallback" {
		t.Fatalf("expected fallback, got %s", val)
	}
}

func TestGetEnv_EnvSet(t *testing.T) {
	os.Setenv("BEAMLET_TEST_KEY_XXXXX", "custom")
	defer os.Unsetenv("BEAMLET_TEST_KEY_XXXXX")

	val := getEnv("BEAMLET_TEST_KEY_XXXXX", "fallback")
	if val != "custom" {
		t.Fatalf("expected custom, got %s", val)
	}
}
