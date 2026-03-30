package api

import (
	"encoding/json"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/mondominator/beamlet/server/internal/auth"
	"github.com/mondominator/beamlet/server/internal/model"
)

func (s *Server) ListContacts(w http.ResponseWriter, r *http.Request) {
	user := auth.UserFromContext(r.Context())

	contacts, err := s.ContactStore.ListForUser(user.ID)
	if err != nil {
		http.Error(w, "failed to list contacts", http.StatusInternalServerError)
		return
	}

	if contacts == nil {
		contacts = []model.ContactUser{}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(contacts)
}

func (s *Server) DeleteContact(w http.ResponseWriter, r *http.Request) {
	user := auth.UserFromContext(r.Context())
	contactID := chi.URLParam(r, "id")

	if err := s.ContactStore.Delete(user.ID, contactID); err != nil {
		http.Error(w, "failed to delete contact", http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}
