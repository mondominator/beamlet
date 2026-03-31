package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"time"

	"github.com/mdp/qrterminal/v3"
	"github.com/mondominator/beamlet/server/internal/config"
	"github.com/mondominator/beamlet/server/internal/db"
	"github.com/mondominator/beamlet/server/internal/store"
	"github.com/spf13/cobra"
)

func AddUserCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "add-user [name]",
		Short: "Create a new user and print their API token and setup QR code",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			cfg := config.Load()
			database, err := db.Open(cfg.DBPath, findMigrations())
			if err != nil {
				return err
			}
			defer database.Close()

			userStore := store.NewUserStore(database.SQL())
			inviteStore := store.NewInviteStore(database.SQL())

			user, token, err := userStore.Create(args[0])
			if err != nil {
				return fmt.Errorf("create user: %w", err)
			}

			// Create a setup invite linked to this user
			_, inviteToken, err := inviteStore.Create(user.ID, user.ID, 24*time.Hour)
			if err != nil {
				return fmt.Errorf("create invite: %w", err)
			}

			serverURL := os.Getenv("BEAMLET_URL")
			if serverURL == "" {
				serverURL = fmt.Sprintf("http://localhost:%s", cfg.Port)
			}

			fmt.Printf("User created:\n")
			fmt.Printf("  ID:    %s\n", user.ID)
			fmt.Printf("  Name:  %s\n", user.Name)
			fmt.Printf("  Token: %s\n", token)
			fmt.Println("\nSave this token — it cannot be retrieved later.")

			// Generate QR code
			qrPayload, _ := json.Marshal(map[string]string{
				"u": serverURL,
				"i": inviteToken,
			})

			fmt.Println("\nScan this QR code with the Beamlet iOS app:")
			qrterminal.GenerateWithConfig(string(qrPayload), qrterminal.Config{
				Level:      qrterminal.L,
				Writer:     os.Stdout,
				HalfBlocks: true,
				QuietZone:  1,
			})

			return nil
		},
	}
}
