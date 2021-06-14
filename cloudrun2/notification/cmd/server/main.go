package main

import (
	"cloud.google.com/go/pubsub"
	"context"
	"encoding/json"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"log"
	"net"
	"notification.com/model"
	"notification.com/proto"
	"os"
	"sync"
	"time"
)

var port = os.Getenv("PORT")
var projectID = os.Getenv("PROJECT_ID")
var subID = os.Getenv("SUB_ID")

type notificationServer struct {
	stream      proto.UnimplementedNotificationServer
	subscribers sync.Map
}

type subsub struct {
	stream   proto.Notification_GetNotificationServer
	finished chan<- bool
}

func main() {
	lis, err := net.Listen("tcp", ":"+port)
	if err != nil {
		log.Fatalf("failed to listen: %v", err)
	}
	grpcServer := grpc.NewServer([]grpc.ServerOption{}...)

	server := &notificationServer{}

	// start sending msg to client
	go server.msgHandler()

	proto.RegisterNotificationServer(grpcServer, server)

	log.Printf("Starting server on address %s", lis.Addr().String())

	if err := grpcServer.Serve(lis); err != nil {
		log.Fatalf("failed to listen: %v", err)
	}
}

func (s *notificationServer) GetNotification(request *proto.NotificationRequest, stream proto.Notification_GetNotificationServer) error {
	log.Printf("Reveived get notification request")

	fin := make(chan bool)
	// TODO: will be able to filter msg per EventName
	s.subscribers.Store(request.EventName, subsub{stream: stream, finished: fin})

	ctx := stream.Context()
	for {
		select {
		case <-fin:
			log.Printf("Closing stream")
			return nil
		case <-ctx.Done():
			log.Printf("Disconeected")
			return nil
		}
	}
}

func pullMessageSync(projectID, subID string) ([]model.Event, error) {
	ctx := context.Background()
	client, err := pubsub.NewClient(ctx, projectID)
	if err != nil {
		return nil, err
	}
	defer client.Close()

	sub := client.Subscription(subID)
	sub.ReceiveSettings.Synchronous = true
	sub.ReceiveSettings.MaxOutstandingMessages = 1

	ctx, cancel := context.WithTimeout(ctx, 3*time.Second)
	defer cancel()

	cm := make(chan *pubsub.Message)
	defer close(cm)

	var msgList []model.Event

	go func() {
		for msg := range cm {
			log.Printf("Got message :%q\n", string(msg.Data))
			msg.Ack()
		}
	}()

	err = sub.Receive(ctx, func(ctx context.Context, msg *pubsub.Message) {
		cm <- msg
		var event model.Event
		err := json.Unmarshal(msg.Data, &event)
		if err != nil {
			log.Printf("json unmarshal: %v", err)
		}
		msgList = append(msgList, event)
	})

	if err != nil && status.Code(err) != codes.Canceled {
		return nil, err
	}
	return msgList, nil
}

func (s *notificationServer) msgHandler() {
	log.Println("Starting msg pulling from Cloud Pub/Sub")

	for {
		time.Sleep(time.Second)

		s.subscribers.Range(func(k, v interface{}) bool {
			_, ok := k.(string)
			if !ok {
				log.Printf("Failed to cast given event name: %v", k)
				return false
			}
			sub, ok := v.(subsub)
			if !ok {
				log.Printf("Failed to cast stream value: %v", v)
				return false
			}

			msgList, err := pullMessageSync(projectID, subID)
			if err != nil {
				log.Printf("pullMessageSync error: %v", err)
				return false
			}

			for _, e := range msgList {
				if err := sub.stream.Send(&proto.NotificationReply{
					EventName: e.EventName,
					Purchaser: e.Purchaser,
					OrderId:   uint64(e.OrderID),
					ItemId:    uint64(e.ItemID),
				}); err != nil {
					log.Printf("could not send data to stream: %v", err)
				}
				log.Printf("message from pubsub sent to the stream")
			}
			return true
		})
	}
}
