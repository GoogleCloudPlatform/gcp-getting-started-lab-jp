package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"strings"

	"cloud.google.com/go/spanner"
	"github.com/google/uuid"
	"google.golang.org/api/iterator"
)

var (
	tblColumns = []string{"player_id", "name", "level", "money"}
	db         string
)

type spanHandler struct {
	// spanner client
	client *spanner.Client
}

func init() {
	db = GetSpannerInstanceFromEnv()
}

func main() {
	handler := &spanHandler{}
	http.Handle("/players", handler)
	http.Handle("/players/", handler)
	http.HandleFunc("/healthz", healthHandler)
	http.HandleFunc("/readyz", healthHandler)

	// create spanner client
	handler.client = CreateClient(context.Background(), db)
	defer handler.client.Close()

	// serve http server at ${PORT}
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
		log.Printf("Defaulting to port %s", port)
	}
	log.Printf("Listening on port %s", port)
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatal(err)
	}
}

// func ServeHTTP write reply headers and data to the ResponseWriter and then return
func (h *spanHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	// 追加処理(HTTP POST)
	case http.MethodPost:
		p := NewPlayers()
		// get player info from POST request
		err := GetPlayerBody(r, p)
		if err != nil {
			LogErrorResponse(err, w)
			return
		}
		// use UUID for primary-key value
		randomId, _ := uuid.NewRandom()
		// insert a recode using mutation API
		m := []*spanner.Mutation{
			spanner.InsertOrUpdate("players", tblColumns, []interface{}{randomId.String(), p.Name, p.Level, p.Money}),
		}
		// apply mutation to cloud spanner instance
		_, err = h.client.Apply(r.Context(), m)
		if err != nil {
			LogErrorResponse(err, w)
			return
		}
		LogSuccessResponse(w, "A new Player with the ID %s has been added!\n", randomId.String())

	// 取得処理(HTTP GET)
	case http.MethodGet:
		// select recodes using Read API
		iter := h.client.Single().Read(r.Context(), "players", spanner.AllKeys(),
			[]string{"player_id", "name", "level", "money"})
		defer iter.Stop()
		for {
			row, err := iter.Next()
			if err == iterator.Done {
				return
			}
			if err != nil {
				LogErrorResponse(err, w)
				return
			}
			var playerId, name string
			var level, money int64
			if err := row.Columns(&playerId, &name, &level, &money); err != nil {
				LogErrorResponse(err, w)
				return
			}
			LogSuccessResponse(w, "player_id: %s, name: %s, level: %d, money: %d\n", playerId, name, level, money)
		}

	// 更新処理(HTTP PUT)
	case http.MethodPut:
		p := NewPlayers()
		// get player info from PUT request
		err := GetPlayerBody(r, p)
		if err != nil {
			LogErrorResponse(err, w)
			return
		}
		// update a recode using mutation API
		m := []*spanner.Mutation{
			spanner.InsertOrUpdate("players", tblColumns, []interface{}{p.PlayerId, p.Name, p.Level, p.Money}),
		}
		// apply mutation to cloud spanner instance
		_, err = h.client.Apply(r.Context(), m)
		if err != nil {
			LogErrorResponse(err, w)
			return
		}
		LogSuccessResponse(w, "A new Player with the ID %s has been updated!\n", p.PlayerId)

		// 削除処理
	case http.MethodDelete:
		// get playerId from request path
		playerId := strings.TrimPrefix(r.URL.Path, "/players/")
		// delete a recode using mutation API
		m := []*spanner.Mutation{
			spanner.Delete("players", spanner.Key{playerId}),
		}
		// apply mutation to cloud spanner instance
		_, err := h.client.Apply(r.Context(), m)
		if err != nil {
			LogErrorResponse(err, w)
			return
		}
		LogSuccessResponse(w, "Success deleting player: %s\n", playerId)

	// それ以外の処理
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
}

// func healthHandler responds 200 health check
func healthHandler(w http.ResponseWriter, r *http.Request) {
	// respond HTTP 200 OK
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("OK\n"))
}
