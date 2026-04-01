package api

import (
	"encoding/json"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/mondominator/beamlet/server/internal/auth"
)

func (s *Server) GetMe(w http.ResponseWriter, r *http.Request) {
	user := auth.UserFromContext(r.Context())

	// Get storage stats
	stats, _ := s.FileStore.GetUserStats(user.ID)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"id":             user.ID,
		"name":           user.Name,
		"files_sent":     stats.FilesSent,
		"files_received": stats.FilesReceived,
		"storage_used":   stats.StorageUsed,
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
