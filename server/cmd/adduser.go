package cmd

import (
	"fmt"

	"github.com/mondominator/beamlet/server/internal/config"
	"github.com/mondominator/beamlet/server/internal/db"
	"github.com/mondominator/beamlet/server/internal/store"
	"github.com/spf13/cobra"
)

func AddUserCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "add-user [name]",
		Short: "Create a new user and print their API token",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			cfg := config.Load()
			database, err := db.Open(cfg.DBPath, findMigrations())
			if err != nil {
				return err
			}
			defer database.Close()

			userStore := store.NewUserStore(database.SQL())
			user, token, err := userStore.Create(args[0])
			if err != nil {
				return fmt.Errorf("create user: %w", err)
			}

			fmt.Printf("User created:\n")
			fmt.Printf("  ID:    %s\n", user.ID)
			fmt.Printf("  Name:  %s\n", user.Name)
			fmt.Printf("  Token: %s\n", token)
			fmt.Println("\nSave this token — it cannot be retrieved later.")
			return nil
		},
	}
}
