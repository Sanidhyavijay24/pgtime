/**
 * @file main.go
 * @description Entry point for the pgtime Go CLI
 * @module cli
 */

package main

import (
	"fmt"
	"os"

	"github.com/yourorg/pgtime-cli/cmd"
)

func main() {
	if err := cmd.RootCmd.Execute(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}
