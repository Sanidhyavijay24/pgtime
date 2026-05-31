/**
 * @file attach.go
 * @description attach command setup for pgtime CLI
 * @module cli/cmd
 */

package cmd

import (
	"context"
	"fmt"
	"os"

	"github.com/spf13/cobra"
)

var attachCmd = &cobra.Command{
	Use:   "attach [table]",
	Short: "Attach temporal tracking to a table",
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

		_, err = conn.Exec(ctx, "SELECT pgtime.attach($1);", table)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error attaching pgtime to table %s: %v\n", table, err)
			os.Exit(1)
		}

		fmt.Printf("Successfully attached temporal tracking to table %s.\n", table)
	},
}

func init() {
	RootCmd.AddCommand(attachCmd)
}
