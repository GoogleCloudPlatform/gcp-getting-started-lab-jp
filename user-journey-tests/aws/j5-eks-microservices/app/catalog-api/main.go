// catalog-api — read-only inventory service of the equipment marketplace (fictional).
//
// Serves the rental catalog embedded at build time from items.json. It has
// no persistence and calls no cloud APIs; booking-api validates items against
// it over the cluster network. Stdlib only, Go 1.22+ pattern-matching mux.
//
// Routes:
//
//	GET /health         liveness/readiness (always 200)
//	GET /catalog        full item list
//	GET /catalog/{id}   single item by numeric id (404 if unknown)
package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
	"strconv"

	_ "embed"
)

//go:embed items.json
var itemsJSON []byte

// Item is one rentable unit of equipment.
type Item struct {
	ID           int    `json:"id"`
	Name         string `json:"name"`
	Category     string `json:"category"`
	DailyRateJPY int    `json:"daily_rate_jpy"`
}

var items []Item

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(v); err != nil {
		log.Printf("encode response: %v", err)
	}
}

func handleHealth(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"status":       "ok",
		"service":      "catalog-api",
		"items_loaded": len(items),
	})
}

func handleList(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"items": items,
		"count": len(items),
	})
}

func handleGet(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.Atoi(r.PathValue("id"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "id must be an integer"})
		return
	}
	for _, item := range items {
		if item.ID == id {
			writeJSON(w, http.StatusOK, item)
			return
		}
	}
	writeJSON(w, http.StatusNotFound, map[string]string{"error": "item not found"})
}

func main() {
	if err := json.Unmarshal(itemsJSON, &items); err != nil {
		log.Fatalf("FATAL: embedded items.json is invalid: %v", err)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", handleHealth)
	mux.HandleFunc("GET /catalog", handleList)
	mux.HandleFunc("GET /catalog/{id}", handleGet)

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	log.Printf("catalog-api listening on :%s (%d items)", port, len(items))
	log.Fatal(http.ListenAndServe(":"+port, mux))
}
