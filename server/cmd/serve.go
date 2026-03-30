package cmd

import (
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"

	"github.com/mondominator/beamlet/server/internal/api"
	"github.com/mondominator/beamlet/server/internal/cleanup"
	"github.com/mondominator/beamlet/server/internal/config"
	"github.com/mondominator/beamlet/server/internal/db"
	"github.com/mondominator/beamlet/server/internal/push"
	"github.com/mondominator/beamlet/server/internal/storage"
	"github.com/mondominator/beamlet/server/internal/store"
	"github.com/spf13/cobra"
)

func ServeCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "serve",
		Short: "Start the Beamlet server",
		RunE: func(cmd *cobra.Command, args []string) error {
			cfg := config.Load()

			database, err := db.Open(cfg.DBPath, findMigrations())
			if err != nil {
				return fmt.Errorf("open database: %w", err)
			}
			defer database.Close()

			userStore := store.NewUserStore(database.SQL())
			fileStore := store.NewFileStore(database.SQL())
			contactStore := store.NewContactStore(database.SQL())
			inviteStore := store.NewInviteStore(database.SQL())
			diskStorage := storage.NewDiskStorage(cfg.DataDir)

			var pusher *push.APNsPusher
			if cfg.APNsKeyPath != "" {
				p, err := push.NewAPNsPusher(cfg.APNsKeyPath, cfg.APNsKeyID, cfg.APNsTeamID, cfg.APNsBundleID, userStore)
				if err != nil {
					log.Printf("warning: APNs setup failed: %v (push notifications disabled)", err)
				} else {
					pusher = p
				}
			}

			srv := &api.Server{
				UserStore:    userStore,
				FileStore:    fileStore,
				ContactStore: contactStore,
				InviteStore:  inviteStore,
				Storage:      diskStorage,
				Pusher:       pusher,
				Config:       cfg,
			}

			stopCleanup := make(chan struct{})
			go cleanup.StartScheduler(fileStore, diskStorage, stopCleanup)

			router := api.NewRouter(srv)

			go func() {
				sigCh := make(chan os.Signal, 1)
				signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
				<-sigCh
				log.Println("shutting down...")
				close(stopCleanup)
				os.Exit(0)
			}()

			log.Printf("beamlet server listening on :%s", cfg.Port)
			return http.ListenAndServe(":"+cfg.Port, router)
		},
	}
}

func findMigrations() string {
	candidates := []string{
		"migrations",
		"/app/migrations",
		"server/migrations",
	}
	for _, c := range candidates {
		if info, err := os.Stat(c); err == nil && info.IsDir() {
			return c
		}
	}
	return "migrations"
}
