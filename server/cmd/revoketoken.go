package cmd

import (
	"fmt"

	"github.com/mondominator/beamlet/server/internal/config"
	"github.com/mondominator/beamlet/server/internal/db"
	"github.com/mondominator/beamlet/server/internal/store"
	"github.com/spf13/cobra"
)

func RevokeTokenCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "revoke-token [user-id]",
		Short: "Regenerate a user's API token",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			cfg := config.Load()
			database, err := db.Open(cfg.DBPath, findMigrations())
			if err != nil {
				return err
			}
			defer database.Close()

			userStore := store.NewUserStore(database.SQL())
			newToken, err := userStore.RevokeToken(args[0])
			if err != nil {
				return fmt.Errorf("revoke token: %w", err)
			}

			fmt.Printf("New token: %s\n", newToken)
			fmt.Println("Save this token — it cannot be retrieved later.")
			return nil
		},
	}
}
