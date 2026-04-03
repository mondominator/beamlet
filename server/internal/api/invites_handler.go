package api

import (
	"encoding/json"
	"log"
	"net/http"
	"strings"
	"time"

	"github.com/mondominator/beamlet/server/internal/auth"
)

func (s *Server) CreateInvite(w http.ResponseWriter, r *http.Request) {
	user := auth.UserFromContext(r.Context())

	invite, token, err := s.InviteStore.Create(user.ID, "", 24*time.Hour)
	if err != nil {
		http.Error(w, "failed to create invite", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(map[string]string{
		"invite_token": token,
		"expires_at":   invite.ExpiresAt.Format(time.RFC3339),
	})
}

func (s *Server) RedeemInvite(w http.ResponseWriter, r *http.Request) {
	r.Body = http.MaxBytesReader(w, r.Body, 1<<20) // 1 MB
	var req struct {
		InviteToken string `json:"invite_token"`
		Name        string `json:"name"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid request body", http.StatusBadRequest)
		return
	}
	if req.InviteToken == "" {
		http.Error(w, "invite_token is required", http.StatusBadRequest)
		return
	}

	invite, err := s.InviteStore.FindByToken(req.InviteToken)
	if err != nil {
		http.Error(w, "invalid or expired invite", http.StatusBadRequest)
		return
	}

	// Check if caller is an existing authenticated user
	var existingUserID string
	if authHeader := r.Header.Get("Authorization"); authHeader != "" {
		token := strings.TrimPrefix(authHeader, "Bearer ")
		if user, err := s.UserStore.Authenticate(token); err == nil {
			existingUserID = user.ID
		}
	}

	// Case 1: CLI setup invite (created_user_id set)
	if invite.CreatedUserID.Valid {
		user, err := s.UserStore.GetByID(invite.CreatedUserID.String)
		if err != nil {
			http.Error(w, "user not found", http.StatusInternalServerError)
			return
		}

		newToken, err := s.UserStore.RevokeToken(user.ID)
		if err != nil {
			http.Error(w, "failed to generate token", http.StatusInternalServerError)
			return
		}

		if err := s.InviteStore.Redeem(invite.ID, user.ID); err != nil {
			log.Printf("failed to redeem invite: %v", err)
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"user_id": user.ID,
			"name":    user.Name,
			"token":   newToken,
		})
		return
	}

	// Case 2: Existing user scanning an invite
	if existingUserID != "" {
		if existingUserID == invite.CreatorID {
			http.Error(w, "cannot redeem your own invite", http.StatusBadRequest)
			return
		}

		if err := s.ContactStore.Add(invite.CreatorID, existingUserID); err != nil {
			http.Error(w, "failed to add contact", http.StatusInternalServerError)
			return
		}

		if err := s.InviteStore.Redeem(invite.ID, existingUserID); err != nil {
			log.Printf("failed to redeem invite: %v", err)
		}

		creator, err := s.UserStore.GetByID(invite.CreatorID)
		if err != nil || creator == nil {
			http.Error(w, "invite creator not found", http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"contact": map[string]string{
				"id":   creator.ID,
				"name": creator.Name,
			},
		})
		return
	}

	// Case 3: New user from in-app invite
	if req.Name == "" {
		http.Error(w, "name is required for new users", http.StatusBadRequest)
		return
	}
	if len(req.Name) > 100 {
		http.Error(w, "name too long (max 100 characters)", http.StatusBadRequest)
		return
	}

	newUser, userToken, err := s.UserStore.Create(req.Name)
	if err != nil {
		http.Error(w, "failed to create user", http.StatusInternalServerError)
		return
	}

	if err := s.ContactStore.Add(invite.CreatorID, newUser.ID); err != nil {
		// Cleanup: delete the newly created user
		if delErr := s.UserStore.Delete(newUser.ID); delErr != nil {
			log.Printf("failed to cleanup user %s after contact add failure: %v", newUser.ID, delErr)
		}
		http.Error(w, "failed to add contact", http.StatusInternalServerError)
		return
	}

	if err := s.InviteStore.Redeem(invite.ID, newUser.ID); err != nil {
		log.Printf("failed to redeem invite: %v", err)
		// Non-fatal: user and contact were created successfully.
		// The invite will remain unredeemed but will expire naturally.
	}

	creator, err := s.UserStore.GetByID(invite.CreatorID)
	if err != nil || creator == nil {
		http.Error(w, "invite creator not found", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"user_id": newUser.ID,
		"name":    newUser.Name,
		"token":   userToken,
		"contact": map[string]string{
			"id":   creator.ID,
			"name": creator.Name,
		},
	})
}
