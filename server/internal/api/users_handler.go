package api

import (
	"encoding/json"
	"net/http"

	"github.com/mondominator/beamlet/server/internal/auth"
	"github.com/mondominator/beamlet/server/internal/model"
)

func (s *Server) ListUsers(w http.ResponseWriter, r *http.Request) {
	user := auth.UserFromContext(r.Context())

	contacts, err := s.ContactStore.ListForUser(user.ID)
	if err != nil {
		http.Error(w, "failed to list users", http.StatusInternalServerError)
		return
	}

	if contacts == nil {
		contacts = []model.ContactUser{}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(contacts)
}
