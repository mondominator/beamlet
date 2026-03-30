package main

import (
	"fmt"
	"os"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: beamlet <command>")
		fmt.Fprintln(os.Stderr, "commands: serve, add-user, list-users, revoke-token")
		os.Exit(1)
	}
	fmt.Fprintln(os.Stderr, "command not yet implemented:", os.Args[1])
	os.Exit(1)
}
