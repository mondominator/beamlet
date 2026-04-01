package api

import (
	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/mondominator/beamlet/server/internal/auth"
	"github.com/mondominator/beamlet/server/internal/config"
	"github.com/mondominator/beamlet/server/internal/push"
	"github.com/mondominator/beamlet/server/internal/storage"
	"github.com/mondominator/beamlet/server/internal/store"
)

type Server struct {
	UserStore    *store.UserStore
	FileStore    *store.FileStore
	ContactStore *store.ContactStore
	InviteStore  *store.InviteStore
	Storage      *storage.DiskStorage
	Pusher       *push.APNsPusher
	Config       config.Config
}

func NewRouter(s *Server) *chi.Mux {
	r := chi.NewRouter()
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)

	// Public web page for invite links
	r.Get("/invite/{token}", s.InviteWebPage)

	r.Route("/api", func(r chi.Router) {
		// Public routes (no auth)
		r.Post("/invites/redeem", s.RedeemInvite)
		r.Get("/users/{id}/profile", s.GetUserProfile)

		// Authenticated routes
		r.Group(func(r chi.Router) {
			r.Use(auth.Middleware(s.UserStore))

			r.Get("/me", s.GetMe)
			r.Get("/users", s.ListUsers)
			r.Post("/auth/register-device", s.RegisterDevice)
			r.Post("/files", s.UploadFile)
			r.Get("/files", s.ListFiles)
			r.Get("/files/{id}", s.DownloadFile)
			r.Get("/files/{id}/thumbnail", s.DownloadThumbnail)
			r.Delete("/files/{id}", s.DeleteFile)
			r.Put("/files/{id}/read", s.MarkFileRead)

			r.Get("/contacts", s.ListContacts)
			r.Delete("/contacts/{id}", s.DeleteContact)
			r.Post("/invites", s.CreateInvite)
		})
	})

	return r
}
