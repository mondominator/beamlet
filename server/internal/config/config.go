package config

import (
	"os"
	"strconv"
)

type Config struct {
	DBPath       string
	DataDir      string
	Port         string
	APNsKeyPath  string
	APNsKeyID    string
	APNsTeamID   string
	APNsBundleID string
	MaxFileSize  int64
	ExpiryDays   int
}

func Load() Config {
	maxSize, _ := strconv.ParseInt(getEnv("BEAMLET_MAX_FILE_SIZE", "524288000"), 10, 64)
	expiryDays, _ := strconv.Atoi(getEnv("BEAMLET_EXPIRY_DAYS", "30"))

	return Config{
		DBPath:       getEnv("BEAMLET_DB_PATH", "/data/beamlet.db"),
		DataDir:      getEnv("BEAMLET_DATA_DIR", "/data/files"),
		Port:         getEnv("BEAMLET_PORT", "8080"),
		APNsKeyPath:  getEnv("BEAMLET_APNS_KEY_PATH", ""),
		APNsKeyID:    getEnv("BEAMLET_APNS_KEY_ID", ""),
		APNsTeamID:   getEnv("BEAMLET_APNS_TEAM_ID", ""),
		APNsBundleID: getEnv("BEAMLET_APNS_BUNDLE_ID", ""),
		MaxFileSize:  maxSize,
		ExpiryDays:   expiryDays,
	}
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
