package api

import (
	"encoding/json"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/mondominator/beamlet/server/internal/auth"
)

func (s *Server) GetMe(w http.ResponseWriter, r *http.Request) {
	user := auth.UserFromContext(r.Context())

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"id":   user.ID,
		"name": user.Name,
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
