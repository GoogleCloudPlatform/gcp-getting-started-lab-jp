package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"time"
	"cloud.google.com/go/spanner"
	"github.com/google/uuid"
	"golang.org/x/net/context"
)

func addNewPlayer(ctx context.Context, client *spanner.Client) error {
	tblColumns := []string{"player_id", "name", "level", "money"} // Players Table Schema
	randomid, _ := uuid.NewRandom() // Get a new Primary Key

	// Insert a recode using mutation API
	m := []*spanner.Mutation{
		spanner.InsertOrUpdate("players", tblColumns, []interface{}{randomid.String(), "player-" + randomid.String(), 1, 100}),
	}

	_, err := client.Apply(ctx, m)
	if err != nil {
		log.Fatal(err)
		return err
	}
	log.Printf(">> A new Player with the ID %v has been added!\n", randomid.String())
	return nil
}

func main() {
	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, "Example 1: Add a new player\n")
		fmt.Fprintf(os.Stderr, "  $ %v projects/my-project/instances/game/databases/player-db\n", os.Args[0])
	}

	flag.Parse()
	if flag.Arg(0) == "" {
		flag.Usage()
		os.Exit(2)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 1*time.Minute)
	defer cancel()

	dataClient, err := spanner.NewClient(ctx, flag.Arg(0))
	if err != nil {
		log.Println("Failed with %v", err)
		os.Exit(2)
	}
	defer dataClient.Close()

	addNewPlayer(ctx, dataClient)
}