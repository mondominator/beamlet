package api

import (
	"encoding/json"
	"log"
	"net/http"

	"github.com/mondominator/beamlet/server/internal/auth"
)

type registerDeviceRequest struct {
	APNsToken string `json:"apns_token"`
	Platform  string `json:"platform"`
}

func (s *Server) RegisterDevice(w http.ResponseWriter, r *http.Request) {
	r.Body = http.MaxBytesReader(w, r.Body, 1<<20) // 1 MB
	var req registerDeviceRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid request body", http.StatusBadRequest)
		return
	}

	if req.APNsToken == "" {
		http.Error(w, "apns_token is required", http.StatusBadRequest)
		return
	}
	if req.Platform == "" {
		req.Platform = "ios"
	}

	user := auth.UserFromContext(r.Context())
	log.Printf("register-device: user=%s token=%s... platform=%s", user.Name, req.APNsToken[:min(16, len(req.APNsToken))], req.Platform)
	if err := s.UserStore.RegisterDevice(user.ID, req.APNsToken, req.Platform); err != nil {
		log.Printf("register-device: FAILED for user %s: %v", user.Name, err)
		http.Error(w, "failed to register device", http.StatusInternalServerError)
		return
	}
	log.Printf("register-device: OK for user %s", user.Name)

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}
