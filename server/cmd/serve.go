package cmd

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

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

			var apnsNotifier push.Notifier
			if cfg.APNsKeyPath != "" {
				n, err := push.NewAPNsNotifier(cfg.APNsKeyPath, cfg.APNsKeyID, cfg.APNsTeamID, cfg.APNsBundleID, userStore)
				if err != nil {
					log.Printf("warning: APNs setup failed: %v (iOS push notifications disabled)", err)
				} else {
					apnsNotifier = n
				}
			}

			var fcmNotifier push.Notifier
			if cfg.FCMServerKey != "" {
				fcmNotifier = push.NewFCMNotifier(cfg.FCMServerKey, userStore)
			}

			var pusher *push.Pusher
			if apnsNotifier != nil || fcmNotifier != nil {
				pusher = push.NewPusher(apnsNotifier, fcmNotifier, userStore)
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
			go cleanup.StartScheduler(fileStore, diskStorage, inviteStore, stopCleanup)

			router := api.NewRouter(srv)

			httpServer := &http.Server{
				Addr:              ":" + cfg.Port,
				Handler:           router,
				ReadHeaderTimeout: 10 * time.Second,
				IdleTimeout:       120 * time.Second,
			}

			go func() {
				sigCh := make(chan os.Signal, 1)
				signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
				<-sigCh
				log.Println("shutting down...")
				close(stopCleanup)
				ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
				defer cancel()
				httpServer.Shutdown(ctx)
			}()

			log.Printf("beamlet server listening on :%s", cfg.Port)
			if err := httpServer.ListenAndServe(); err != http.ErrServerClosed {
				return err
			}
			return nil
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
