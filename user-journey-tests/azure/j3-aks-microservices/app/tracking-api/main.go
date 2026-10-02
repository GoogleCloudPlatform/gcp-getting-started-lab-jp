// tracking-api — the public parcel-tracking edge for the platform (fictional).
//
// Every Azure call goes through internal/azclients; nothing in this file
// imports an Azure SDK directly.
//
// Routes:
//
//	GET  /health              dependency substatus, always HTTP 200
//	GET  /admin/azure-check   per-service ok/fail dashboard
//	GET  /parcels/{id}        one parcel document
//	POST /parcels             accept a parcel and publish its first scan
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"sync"
	"syscall"
	"time"

	"akm.example/tracking/internal/azclients"
)

const (
	pingBudget      = 2 * time.Second
	requestTimeout  = 15 * time.Second
	shutdownTimeout = 10 * time.Second
)

type server struct {
	az *azclients.Clients
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	az, err := azclients.New(azclients.ConfigFromEnv())
	if err != nil {
		log.Fatalf("startup: %v", err)
	}
	srv := &server{az: az}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", srv.handleHealth)
	mux.HandleFunc("GET /admin/azure-check", srv.handleAzureCheck)
	mux.HandleFunc("GET /parcels/{id}", srv.handleGetParcel)
	mux.HandleFunc("POST /parcels", srv.handleCreateParcel)

	httpServer := &http.Server{
		Addr:              ":" + port,
		Handler:           mux,
		ReadHeaderTimeout: 10 * time.Second,
	}

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		log.Printf("tracking-api listening on :%s", port)
		if err := httpServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("listen: %v", err)
		}
	}()

	<-stop
	log.Print("shutting down")
	ctx, cancel := context.WithTimeout(context.Background(), shutdownTimeout)
	defer cancel()
	_ = httpServer.Shutdown(ctx)
	az.Close(ctx)
}

// ---- handlers ---------------------------------------------------------------

// handleHealth never fails the request. A dependency that is down is reported
// in the body so the load balancer keeps the pod in rotation long enough for
// someone to read it.
func (s *server) handleHealth(w http.ResponseWriter, r *http.Request) {
	deps := pingAll(r.Context(), map[string]func(context.Context) error{
		"cosmos":     s.az.PingCosmos,
		"servicebus": s.az.PingServiceBus,
	})
	overall := "ok"
	for _, v := range deps {
		if v != "ok" {
			overall = "degraded"
		}
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"service":      "tracking-api",
		"status":       overall,
		"dependencies": deps,
	})
}

// handleAzureCheck is the parity dashboard: one line per service the pod
// touches. After a migration the same page reports the replacement services.
func (s *server) handleAzureCheck(w http.ResponseWriter, r *http.Request) {
	cfg := s.az.Config()
	checks := pingAll(r.Context(), map[string]func(context.Context) error{
		"identity":   s.az.PingIdentity,
		"cosmos":     s.az.PingCosmos,
		"servicebus": s.az.PingServiceBus,
	})
	overall := "ok"
	for _, v := range checks {
		if v != "ok" {
			overall = "fail"
		}
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"service": "tracking-api",
		"overall": overall,
		"checks":  checks,
		"targets": map[string]string{
			"cosmos_database":      cfg.CosmosDatabase,
			"cosmos_container":     cfg.CosmosContainer,
			"servicebus_queue":     cfg.ServiceBusQueue,
			"servicebus_namespace": cfg.ServiceBusNamespace,
		},
	})
}

func (s *server) handleGetParcel(w http.ResponseWriter, r *http.Request) {
	parcelID := strings.TrimSpace(r.PathValue("id"))
	if parcelID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "parcel id is required"})
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), requestTimeout)
	defer cancel()

	parcel, err := s.az.GetParcel(ctx, parcelID)
	if err != nil {
		log.Printf("get parcel %s: %v", parcelID, err)
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "parcel lookup failed"})
		return
	}
	if parcel == nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "no such parcel", "parcelId": parcelID})
		return
	}
	writeJSON(w, http.StatusOK, parcel)
}

type createParcelRequest struct {
	ParcelID    string `json:"parcelId"`
	Origin      string `json:"origin"`
	Destination string `json:"destination"`
	Location    string `json:"location"`
}

// handleCreateParcel writes the document first and publishes second. A write
// that succeeds with no event produces a parcel that is simply never notified,
// which the depot notices; an event with no document produces a notifier that
// cannot find the parcel, which nobody notices.
func (s *server) handleCreateParcel(w http.ResponseWriter, r *http.Request) {
	var req createParcelRequest
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 16<<10)).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "body must be JSON"})
		return
	}
	req.ParcelID = strings.TrimSpace(req.ParcelID)
	if req.ParcelID == "" || req.Destination == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "parcelId and destination are required"})
		return
	}
	if req.Origin == "" {
		req.Origin = "Tokyo"
	}
	if req.Location == "" {
		req.Location = req.Origin
	}

	ctx, cancel := context.WithTimeout(r.Context(), requestTimeout)
	defer cancel()

	now := azclients.Now()
	parcel := azclients.Parcel{
		// The document id and the partition key are both the parcel id. Set it
		// here as well as in the client, so the body we return matches the
		// document that was stored.
		ID:          req.ParcelID,
		ParcelID:    req.ParcelID,
		Origin:      req.Origin,
		Destination: req.Destination,
		Status:      "accepted",
		UpdatedAt:   now,
		Scans: []azclients.Scan{
			{At: now, Location: req.Location, Status: "accepted"},
		},
	}
	if err := s.az.UpsertParcel(ctx, parcel); err != nil {
		log.Printf("upsert parcel %s: %v", req.ParcelID, err)
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "could not store the parcel"})
		return
	}

	if err := s.az.PublishScan(ctx, azclients.ScanEvent{
		ParcelID:    req.ParcelID,
		Status:      "accepted",
		Location:    req.Location,
		Destination: req.Destination,
		At:          now,
	}); err != nil {
		log.Printf("publish scan %s: %v", req.ParcelID, err)
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "parcel stored but the scan event was not published"})
		return
	}

	writeJSON(w, http.StatusCreated, parcel)
}

// ---- helpers ----------------------------------------------------------------

// pingAll runs the named checks concurrently, each under its own deadline, so
// the endpoint costs one deadline rather than one per dependency.
func pingAll(parent context.Context, checks map[string]func(context.Context) error) map[string]string {
	out := make(map[string]string, len(checks))
	var mu sync.Mutex
	var wg sync.WaitGroup

	for name, fn := range checks {
		wg.Add(1)
		go func() {
			defer wg.Done()
			result := status(pingWithin(parent, fn))
			mu.Lock()
			defer mu.Unlock()
			out[name] = result
		}()
	}
	wg.Wait()
	return out
}

// pingWithin runs one dependency check under a hard deadline.
//
// A context alone is not enough. The SDKs honour one for ordinary requests,
// but bringing up the AMQP link to Service Bus for the first time can outlast
// it, and the kubelet's probes call this on a one-second budget by default. A
// probe endpoint that reports "timed out" is useful; one that hangs gets the
// pod restarted.
func pingWithin(parent context.Context, fn func(context.Context) error) error {
	ctx, cancel := context.WithTimeout(parent, pingBudget)
	defer cancel()

	// Buffered, so the goroutine can finish and exit after we have given up.
	done := make(chan error, 1)
	go func() { done <- fn(ctx) }()

	select {
	case err := <-done:
		return err
	case <-ctx.Done():
		return fmt.Errorf("timed out after %s", pingBudget)
	}
}

func status(err error) string {
	if err != nil {
		return "fail: " + truncate(err.Error(), 160)
	}
	return "ok"
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n] + "..."
}

func writeJSON(w http.ResponseWriter, code int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	if err := json.NewEncoder(w).Encode(payload); err != nil {
		log.Printf("write response: %v", err)
	}
}
