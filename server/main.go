package main

import (
	"fmt"
	"os"

	"github.com/mondominator/beamlet/server/cmd"
	"github.com/spf13/cobra"
)

func main() {
	root := &cobra.Command{
		Use:   "beamlet",
		Short: "Beamlet file sharing server",
	}

	root.AddCommand(cmd.ServeCmd())
	root.AddCommand(cmd.AddUserCmd())
	root.AddCommand(cmd.ListUsersCmd())
	root.AddCommand(cmd.RevokeTokenCmd())

	if err := root.Execute(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
