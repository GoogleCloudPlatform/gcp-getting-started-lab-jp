package main

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials"
	"log"
	"notification.com/model"
	"notification.com/proto"
	"os"
	"strconv"
	"time"
)

var domain = os.Getenv("DOMAIN")
var port = os.Getenv("PORT")
var insecureStr = os.Getenv("INSECURE")

type notificationClient struct {
	client    proto.NotificationClient
	conn      *grpc.ClientConn
	eventName string
}

func makeNotificationClient(eventName string) *notificationClient {
	conn, err := makeConnection()
	if err != nil {
		log.Fatalf("could not make connection")
	}
	return &notificationClient{
		client:    proto.NewNotificationClient(conn),
		conn:      conn,
		eventName: eventName,
	}
}

func (c *notificationClient) getNotification() (proto.Notification_GetNotificationClient, error) {
	return c.client.GetNotification(context.Background(), &proto.NotificationRequest{EventName: c.eventName})
}

func (c *notificationClient) startSubscription() {
	var err error
	var stream proto.Notification_GetNotificationClient
	log.Println("Subscribing...")
	for {
		if stream == nil {
			if stream, err = c.getNotification(); err != nil {
				log.Printf("Failed to have stream: %v", err)
				c.sleep()
				continue
			}
		}
		msg, err := stream.Recv()
		if err != nil {
			log.Printf("Failed to receive message: %v", err)
			stream = nil
			c.sleep()
			continue
		}
		event := model.Event{
			EventName: msg.GetEventName(),
			Purchaser: msg.GetPurchaser(),
			OrderID:   uint(msg.GetOrderId()),
			ItemID:    uint(msg.GetItemId()),
		}
		bytes, _ := json.Marshal(&event)
		log.Println(string(bytes))
	}
}

func (c *notificationClient) sleep() {
	time.Sleep(time.Second * 5)
}

func makeConnection() (*grpc.ClientConn, error) {
	var opts []grpc.DialOption
	host := domain + ":" + port
	insecure, _ := strconv.ParseBool(insecureStr)
	if insecure {
		opts = append(opts, grpc.WithInsecure())
	}else {
		systemRoots, err := x509.SystemCertPool()
		if err != nil {
			log.Fatalf("Could not make cert pool: %v", err)
		}
		cred := credentials.NewTLS(&tls.Config{
			RootCAs: systemRoots,
		})
		opts = append(opts, grpc.WithTransportCredentials(cred))
	}
	return grpc.Dial(host, opts...)
}

func main() {
	client := makeNotificationClient("all")
	client.startSubscription()
}
