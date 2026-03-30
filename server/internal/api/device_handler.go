package api

import (
	"encoding/json"
	"net/http"

	"github.com/mondominator/beamlet/server/internal/auth"
)

type registerDeviceRequest struct {
	APNsToken string `json:"apns_token"`
	Platform  string `json:"platform"`
}

func (s *Server) RegisterDevice(w http.ResponseWriter, r *http.Request) {
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
	if err := s.UserStore.RegisterDevice(user.ID, req.APNsToken, req.Platform); err != nil {
		http.Error(w, "failed to register device", http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}
