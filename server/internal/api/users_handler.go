package api

import (
	"encoding/json"
	"net/http"
)

func (s *Server) ListUsers(w http.ResponseWriter, r *http.Request) {
	users, err := s.UserStore.List()
	if err != nil {
		http.Error(w, "failed to list users", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(users)
}
