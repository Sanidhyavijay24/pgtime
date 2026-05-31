/**
 * @file init.go
 * @description init command setup for pgtime CLI
 * @module cli/cmd
 */

package cmd

import (
	"context"
	"fmt"
	"os"

	"github.com/spf13/cobra"
)

var initCmd = &cobra.Command{
	Use:   "init",
	Short: "Install pgtime extension in the database",
	Run: func(cmd *cobra.Command, args []string) {
		ctx := context.Background()
		conn, err := getConn(ctx)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error connecting to database: %v\n", err)
			os.Exit(1)
		}
		defer conn.Close(ctx)

		_, err = conn.Exec(ctx, "CREATE EXTENSION IF NOT EXISTS pgtime CASCADE;")
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error installing pgtime extension: %v\n", err)
			os.Exit(1)
		}

		fmt.Println("Successfully installed pgtime extension.")
	},
}

func init() {
	RootCmd.AddCommand(initCmd)
}
