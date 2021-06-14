package util

import (
	"cloud.google.com/go/pubsub"
	"context"
	"eats.com/model"
	"encoding/json"
	"fmt"
	"log"
	"os"
)

var projectId = os.Getenv("PROJECT_ID")
var topicId = os.Getenv("TOPIC_ID")

func Publish(eventName, purchaser string, orderId, itemId uint){
	ctx := context.Background()

	// make client
	client, err := pubsub.NewClient(ctx, projectId)
	if err != nil {
		fmt.Print("client error.err:",err)
		os.Exit(1)
	}
	// make json message
	event := &model.Event{
	 	EventName: eventName,
		Purchaser: purchaser,
		OrderID:   orderId,
		ItemID:    itemId,
	}
	msg, _ := json.Marshal(event)
	// publish message
	t := client.Topic(topicId)
	result := t.Publish(ctx, &pubsub.Message{
		Data: []byte(msg),
	})
	// error handling
	id, err := result.Get(ctx)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("Published a message; msg ID: %v\n", id)
}
