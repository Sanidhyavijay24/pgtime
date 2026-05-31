/**
 * @file detach.go
 * @description detach command setup for pgtime CLI
 * @module cli/cmd
 */

package cmd

import (
	"context"
	"fmt"
	"os"

	"github.com/spf13/cobra"
)

var detachCmd = &cobra.Command{
	Use:   "detach [table]",
	Short: "Detach temporal tracking from a table (keeps history table)",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		ctx := context.Background()
		table := args[0]

		conn, err := getConn(ctx)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error connecting to database: %v\n", err)
			os.Exit(1)
		}
		defer conn.Close(ctx)

		_, err = conn.Exec(ctx, "SELECT pgtime.detach($1);", table)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error detaching pgtime from table %s: %v\n", table, err)
			os.Exit(1)
		}

		fmt.Printf("Successfully detached temporal tracking from table %s.\n", table)
	},
}

func init() {
	RootCmd.AddCommand(detachCmd)
}
