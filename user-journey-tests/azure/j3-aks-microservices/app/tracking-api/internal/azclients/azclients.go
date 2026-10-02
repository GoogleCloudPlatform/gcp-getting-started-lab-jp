// Package azclients is the single funnel for every Azure SDK call tracking-api
// makes. Keep any new Azure call in this package so the call sites stay in one
// place and stay easy to find.
//
// Where each of these is expected to land on Google Cloud, per service:
//
//	Cosmos DB (SQL API) tracking/parcels     -> Firestore
//	Service Bus queue parcel-events          -> Pub/Sub
//	AKS cluster akm-aks                      -> GKE
//	Entra federated pod credential           -> Workload Identity Federation for GKE
//	Container registry akmacr<suffix>        -> Artifact Registry
//	Standard load balancer from the Service  -> GKE LoadBalancer Service
//
// The last three are platform, not code: nothing in this package names them,
// and nothing in this package would change if they moved.
//
// Credentials: none are configured here, and none exist in the container. In
// the cluster the pod's service account is federated to a user-assigned
// identity in Entra ID; the kubelet projects a signed service-account token
// into the pod, the Azure SDK exchanges it for an Entra token, and
// DefaultAzureCredential picks all of that up without being told about it.
// Running the binary anywhere else falls back to whatever the local
// credential chain finds, which is why the health endpoints report per-service
// status rather than refusing to start.
package azclients

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/Azure/azure-sdk-for-go/sdk/azcore/policy"
	"github.com/Azure/azure-sdk-for-go/sdk/azidentity"
	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/Azure/azure-sdk-for-go/sdk/messaging/azservicebus"
)

// Config is everything the service needs to reach Azure, all of it supplied by
// the deployment. Nothing is compiled in.
type Config struct {
	CosmosEndpoint      string
	CosmosDatabase      string
	CosmosContainer     string
	ServiceBusNamespace string
	ServiceBusQueue     string
}

// ConfigFromEnv reads the deployment's environment.
func ConfigFromEnv() Config {
	return Config{
		CosmosEndpoint:      os.Getenv("COSMOS_ENDPOINT"),
		CosmosDatabase:      envOr("COSMOS_DATABASE", "tracking"),
		CosmosContainer:     envOr("COSMOS_CONTAINER", "parcels"),
		ServiceBusNamespace: os.Getenv("SERVICEBUS_NAMESPACE"),
		ServiceBusQueue:     envOr("SERVICEBUS_QUEUE", "parcel-events"),
	}
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

// Scan is one handheld reading in a depot.
type Scan struct {
	At       string `json:"at"`
	Location string `json:"location"`
	Status   string `json:"status"`
}

// Parcel is one document in the parcels container. The Cosmos DB document id
// and the partition key are both the parcel id: a parcel is only ever read and
// written whole, so there is nothing to gain from spreading one across
// partitions.
type Parcel struct {
	ID          string `json:"id"`
	ParcelID    string `json:"parcelId"`
	Origin      string `json:"origin"`
	Destination string `json:"destination"`
	Status      string `json:"status"`
	UpdatedAt   string `json:"updatedAt"`
	NotifiedAt  string `json:"notifiedAt,omitempty"`
	Scans       []Scan `json:"scans"`
}

// ScanEvent is the message body put on parcel-events.
type ScanEvent struct {
	ParcelID    string `json:"parcelId"`
	Status      string `json:"status"`
	Location    string `json:"location"`
	Destination string `json:"destination"`
	At          string `json:"at"`
}

// Clients holds the long-lived Azure clients. Build one at start-up and share
// it; each of these is safe for concurrent use and holds its own connection.
type Clients struct {
	cfg        Config
	credential azcore.TokenCredential
	container  *azcosmos.ContainerClient
	sbClient   *azservicebus.Client
	sender     *azservicebus.Sender
}

// New builds the clients. It does no network I/O, so a service whose
// dependencies are down still starts and still reports why through /health.
func New(cfg Config) (*Clients, error) {
	if cfg.CosmosEndpoint == "" {
		return nil, errors.New("COSMOS_ENDPOINT is not set")
	}
	if cfg.ServiceBusNamespace == "" {
		return nil, errors.New("SERVICEBUS_NAMESPACE is not set")
	}

	credential, err := azidentity.NewDefaultAzureCredential(nil)
	if err != nil {
		return nil, fmt.Errorf("credential: %w", err)
	}

	cosmosClient, err := azcosmos.NewClient(cfg.CosmosEndpoint, credential, nil)
	if err != nil {
		return nil, fmt.Errorf("cosmos client: %w", err)
	}
	container, err := cosmosClient.NewContainer(cfg.CosmosDatabase, cfg.CosmosContainer)
	if err != nil {
		return nil, fmt.Errorf("cosmos container: %w", err)
	}

	sbClient, err := azservicebus.NewClient(cfg.ServiceBusNamespace, credential, nil)
	if err != nil {
		return nil, fmt.Errorf("service bus client: %w", err)
	}
	sender, err := sbClient.NewSender(cfg.ServiceBusQueue, nil)
	if err != nil {
		return nil, fmt.Errorf("service bus sender: %w", err)
	}

	return &Clients{
		cfg:        cfg,
		credential: credential,
		container:  container,
		sbClient:   sbClient,
		sender:     sender,
	}, nil
}

// Close releases the Service Bus connection.
func (c *Clients) Close(ctx context.Context) {
	if c.sender != nil {
		_ = c.sender.Close(ctx)
	}
	if c.sbClient != nil {
		_ = c.sbClient.Close(ctx)
	}
}

// Config returns the resolved configuration, for the status endpoints.
func (c *Clients) Config() Config { return c.cfg }

// UpsertParcel writes the whole document.
func (c *Clients) UpsertParcel(ctx context.Context, p Parcel) error {
	p.ID = p.ParcelID
	body, err := json.Marshal(p)
	if err != nil {
		return fmt.Errorf("marshal parcel: %w", err)
	}
	pk := azcosmos.NewPartitionKeyString(p.ParcelID)
	if _, err := c.container.UpsertItem(ctx, pk, body, nil); err != nil {
		return fmt.Errorf("upsert parcel %s: %w", p.ParcelID, err)
	}
	return nil
}

// GetParcel reads one document. A parcel that does not exist returns
// (nil, nil) rather than an error — the caller turns that into a 404.
func (c *Clients) GetParcel(ctx context.Context, parcelID string) (*Parcel, error) {
	pk := azcosmos.NewPartitionKeyString(parcelID)
	resp, err := c.container.ReadItem(ctx, pk, parcelID, nil)
	if err != nil {
		var respErr *azcore.ResponseError
		if errors.As(err, &respErr) && respErr.StatusCode == http.StatusNotFound {
			return nil, nil
		}
		return nil, fmt.Errorf("read parcel %s: %w", parcelID, err)
	}
	var p Parcel
	if err := json.Unmarshal(resp.Value, &p); err != nil {
		return nil, fmt.Errorf("unmarshal parcel %s: %w", parcelID, err)
	}
	return &p, nil
}

// PublishScan puts one scan event on the queue.
//
// SessionID is the parcel id, and that is the whole point of the queue: the
// receiver locks a session at a time, so every scan for a given parcel is
// handled in the order it was sent and never by two workers at once. A
// "delivered" overtaking a "picked up" puts a wrong status on the public
// tracking page.
func (c *Clients) PublishScan(ctx context.Context, ev ScanEvent) error {
	body, err := json.Marshal(ev)
	if err != nil {
		return fmt.Errorf("marshal scan event: %w", err)
	}
	sessionID := ev.ParcelID
	contentType := "application/json"
	msg := &azservicebus.Message{
		Body:        body,
		SessionID:   &sessionID,
		ContentType: &contentType,
	}
	if err := c.sender.SendMessage(ctx, msg, nil); err != nil {
		return fmt.Errorf("send scan event for %s: %w", ev.ParcelID, err)
	}
	return nil
}

// PingCosmos reads the container's own metadata — the cheapest call that
// proves both the endpoint and the data-plane role assignment work.
func (c *Clients) PingCosmos(ctx context.Context) error {
	if _, err := c.container.Read(ctx, nil); err != nil {
		return err
	}
	return nil
}

// PingServiceBus opens a message batch, which establishes the AMQP link and
// asks the service for the maximum message size. Nothing is sent.
func (c *Clients) PingServiceBus(ctx context.Context) error {
	if _, err := c.sender.NewMessageBatch(ctx, nil); err != nil {
		return err
	}
	return nil
}

// PingIdentity asks for a token. It proves the pod's federated credential is
// being accepted by Entra ID, independently of whether any particular resource
// role has been granted yet.
func (c *Clients) PingIdentity(ctx context.Context) error {
	_, err := c.credential.GetToken(ctx, policy.TokenRequestOptions{
		Scopes: []string{"https://management.azure.com/.default"},
	})
	return err
}

// Now is the timestamp format used in every document and message.
func Now() string {
	return time.Now().UTC().Format(time.RFC3339)
}
