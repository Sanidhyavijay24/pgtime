/**
 * @file status.go
 * @description status command setup for pgtime CLI
 * @module cli/cmd
 */

package cmd

import (
	"context"
	"fmt"
	"os"

	"github.com/spf13/cobra"
)

var statusCmd = &cobra.Command{
	Use:   "status",
	Short: "Check the status and health of the pgtime extension",
	Run: func(cmd *cobra.Command, args []string) {
		ctx := context.Background()
		conn, err := getConn(ctx)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error connecting to database: %v\n", err)
			os.Exit(1)
		}
		defer conn.Close(ctx)

		// 1. Check if the extension is installed
		var extVersion string
		err = conn.QueryRow(ctx, "SELECT extversion FROM pg_extension WHERE extname = 'pgtime';").Scan(&extVersion)
		if err != nil {
			fmt.Fprintln(os.Stderr, "pgtime extension is NOT installed in this database. Run 'pgtime init' to install it.")
			os.Exit(1)
		}

		// 2. Count tracked tables
		var trackedCount int
		err = conn.QueryRow(ctx, "SELECT count(*)::int FROM pgtime._tracked_tables;").Scan(&trackedCount)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error querying metadata table: %v\n", err)
			os.Exit(1)
		}

		fmt.Println("pgtime extension status: ACTIVE")
		fmt.Printf("Version:                 %s\n", extVersion)
		fmt.Printf("Tracked Tables:          %d\n", trackedCount)
	},
}

func init() {
	RootCmd.AddCommand(statusCmd)
}
