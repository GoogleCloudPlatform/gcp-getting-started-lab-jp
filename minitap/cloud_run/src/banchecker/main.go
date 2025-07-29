package main

import (
	"context"
	"log"
	"net/http"
	"os"

	"golang.org/x/oauth2/google"
)

var projectID string

func main() {
	// Initialize the credential and projectID with Application Default Credentials (ADC)
	ctx := context.Background()
	cred, err := google.FindDefaultCredentials(ctx)
	if err != nil {
		log.Fatal(err.Error())
	}

	projectID = cred.ProjectID
	if len(projectID) == 0 {
		log.Fatal("Failed to retrieve Google Cloud Project ID. Shutting down...")
	} else {
		log.Printf("Successfully retrieved GCP Project ID: %v", projectID)
	}

	http.HandleFunc("/", BanChecker)

	// Determine port for HTTP service.
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
		log.Printf("Defaulting to port %s", port)
	}

	// Start HTTP server.
	log.Printf("Listening on port %s", port)
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatal(err)
	}
}
