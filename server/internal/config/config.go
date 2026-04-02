package config

import (
	"log"
	"os"
	"strconv"
)

type Config struct {
	DBPath       string
	DataDir      string
	Port         string
	ExternalURL  string
	APNsKeyPath  string
	APNsKeyID    string
	APNsTeamID   string
	APNsBundleID string
	FCMServerKey string
	MaxFileSize  int64
	ExpiryDays   int
}

func Load() Config {
	maxSize, err := strconv.ParseInt(getEnv("BEAMLET_MAX_FILE_SIZE", "524288000"), 10, 64)
	if err != nil {
		log.Printf("invalid BEAMLET_MAX_FILE_SIZE, using default 500MB")
		maxSize = 524288000
	}
	expiryDays, err := strconv.Atoi(getEnv("BEAMLET_EXPIRY_DAYS", "30"))
	if err != nil {
		log.Printf("invalid BEAMLET_EXPIRY_DAYS, using default 30")
		expiryDays = 30
	}

	return Config{
		DBPath:       getEnv("BEAMLET_DB_PATH", "/data/beamlet.db"),
		DataDir:      getEnv("BEAMLET_DATA_DIR", "/data/files"),
		Port:         getEnv("BEAMLET_PORT", "8080"),
		ExternalURL:  getEnv("BEAMLET_EXTERNAL_URL", ""),
		APNsKeyPath:  getEnv("BEAMLET_APNS_KEY_PATH", ""),
		APNsKeyID:    getEnv("BEAMLET_APNS_KEY_ID", ""),
		APNsTeamID:   getEnv("BEAMLET_APNS_TEAM_ID", ""),
		APNsBundleID: getEnv("BEAMLET_APNS_BUNDLE_ID", ""),
		FCMServerKey: getEnv("BEAMLET_FCM_SERVER_KEY", ""),
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
