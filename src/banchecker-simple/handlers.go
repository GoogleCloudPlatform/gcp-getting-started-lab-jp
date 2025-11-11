package main

import (
	"context"
	"encoding/json"
	"io"
	"log"
	"net/http"
	"time"

	"cloud.google.com/go/firestore"
)

type PubSubMessage struct {
	Message struct {
		Data []byte `json:"data,omitempty"`
		ID   string `json:"id"`
	} `json:"message"`
	Subscription string `json:"subscription"`
}

type Message struct {
	Name      string    `firestore:"name"`
	Text      string    `firestore:"text"`
	Animal    string    `firestore:"animal"`
	Color     string    `firestore:"color"`
	Timestamp time.Time `firestore:"timestamp,serverTimestamp"`
	Banned    bool      `firestore:"banned"`
}

type PubSubData struct {
	Name   string `json:"name"`
	Text   string `json:"text"`
	Animal string `json:"animal"`
	Color  string `json:"color"`
}

// BanChecker receives and processes a Pub/Sub push message.
func BanChecker(w http.ResponseWriter, r *http.Request) {
	var m PubSubMessage
	body, err := io.ReadAll(r.Body)
	if err != nil {
		log.Printf("ioutil.ReadAll: %v", err)
		http.Error(w, "Bad Request", http.StatusBadRequest)
		return
	}

	// byte slice unmarshalling handles base64 decoding.
	if err := json.Unmarshal(body, &m); err != nil {
		log.Printf("json.Unmarshal: %v", err)
		http.Error(w, "Bad Request", http.StatusBadRequest)
		return
	}

	var pubsubData PubSubData
	if err := json.Unmarshal(m.Message.Data, &pubsubData); err != nil {
		log.Printf("Failed to unmarshal a message from pubsub: %v", err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	ctx := context.Background()
	client, err := firestore.NewClient(ctx, projectID)
	if err != nil {
		log.Printf("Failed to create a new client: %v", err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	messages := client.Collection("messages")
	doc, _, err := messages.Add(ctx, Message{
		Name:   pubsubData.Name,
		Text:   pubsubData.Text,
		Animal: pubsubData.Animal,
		Color:  pubsubData.Color,
		Banned: IncludeBannedWords(pubsubData.Text),
	})
	if err != nil {
		log.Printf("Failed to write a message to firestore: %v", err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	log.Printf("Successfully write a message to firestore: %s", doc.ID)
	w.WriteHeader(http.StatusNoContent)
}
