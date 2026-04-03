package api

import (
	"encoding/json"
	"log"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/mondominator/beamlet/server/internal/auth"
	"github.com/mondominator/beamlet/server/internal/model"
)

func (s *Server) GetMe(w http.ResponseWriter, r *http.Request) {
	user := auth.UserFromContext(r.Context())

	// Get storage stats
	stats, err := s.FileStore.GetUserStats(user.ID)
	if err != nil {
		log.Printf("failed to get user stats for %s: %v", user.ID, err)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"id":              user.ID,
		"name":            user.Name,
		"discoverability": user.Discoverability,
		"files_sent":      stats.FilesSent,
		"files_received":  stats.FilesReceived,
		"storage_used":    stats.StorageUsed,
	})
}

func (s *Server) UpdateDiscoverability(w http.ResponseWriter, r *http.Request) {
	user := auth.UserFromContext(r.Context())

	r.Body = http.MaxBytesReader(w, r.Body, 1<<20)
	var req struct {
		Discoverability string `json:"discoverability"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid request body", http.StatusBadRequest)
		return
	}

	if !model.IsValidDiscoverability(req.Discoverability) {
		http.Error(w, "invalid discoverability value (must be off, contactsOnly, or everyone)", http.StatusBadRequest)
		return
	}

	if err := s.UserStore.UpdateDiscoverability(user.ID, req.Discoverability); err != nil {
		log.Printf("update discoverability: user=%s err=%v", user.ID, err)
		http.Error(w, "failed to update discoverability", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"discoverability": req.Discoverability,
	})
}

func (s *Server) GetUserProfile(w http.ResponseWriter, r *http.Request) {
	userID := chi.URLParam(r, "id")

	user, err := s.UserStore.GetByID(userID)
	if err != nil {
		http.Error(w, "user not found", http.StatusNotFound)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"id":   user.ID,
		"name": user.Name,
	})
}
