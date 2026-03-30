package cmd

import (
	"fmt"

	"github.com/mondominator/beamlet/server/internal/config"
	"github.com/mondominator/beamlet/server/internal/db"
	"github.com/mondominator/beamlet/server/internal/store"
	"github.com/spf13/cobra"
)

func ListUsersCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "list-users",
		Short: "List all users",
		RunE: func(cmd *cobra.Command, args []string) error {
			cfg := config.Load()
			database, err := db.Open(cfg.DBPath, findMigrations())
			if err != nil {
				return err
			}
			defer database.Close()

			userStore := store.NewUserStore(database.SQL())
			users, err := userStore.List()
			if err != nil {
				return err
			}

			if len(users) == 0 {
				fmt.Println("No users found.")
				return nil
			}

			fmt.Printf("%-36s  %s\n", "ID", "Name")
			fmt.Printf("%-36s  %s\n", "------------------------------------", "----")
			for _, u := range users {
				fmt.Printf("%-36s  %s\n", u.ID, u.Name)
			}
			return nil
		},
	}
}
