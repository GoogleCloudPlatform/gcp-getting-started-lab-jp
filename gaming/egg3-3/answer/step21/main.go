package main

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strconv"

	"cloud.google.com/go/firestore"
	"google.golang.org/api/iterator"
)

func main() {
	http.HandleFunc("/", indexHandler)
	http.HandleFunc("/firestore", firestoreHandler)

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

func indexHandler(w http.ResponseWriter, r *http.Request) {
	fmt.Fprint(w, "Hello, Egg!")
}

func firestoreHandler(w http.ResponseWriter, r *http.Request) {

	// Firestore クライアント作成
	pid := os.Getenv("GOOGLE_CLOUD_PROJECT")
	ctx := r.Context()
	client, err := firestore.NewClient(ctx, pid)
	if err != nil {
		log.Fatal(err)
	}
	defer client.Close()

	switch r.Method {
	// 追加処理
	case http.MethodPost:
		u, err := getUserBody(r)
		if err != nil {
			log.Fatal(err)
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		ref, _, err := client.Collection("users").Add(ctx, u)
		if err != nil {
			log.Fatalf("Failed adding data: %v", err)
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		log.Print("success: id is %v", ref.ID)
		fmt.Fprintf(w, "success: id is %v \n", ref.ID)

	// 取得処理
	case http.MethodGet:
		iter := client.Collection("users").Documents(ctx)
		var u []Users

		for {
			doc, err := iter.Next()
			if err == iterator.Done {
				break
			}
			if err != nil {
				log.Fatal(err)
			}
			var user Users
			err = doc.DataTo(&user)
			if err != nil {
				log.Fatal(err)
			}
			user.Id = doc.Ref.ID
			log.Print(user)
			u = append(u, user)
		}
		if len(u) == 0 {
			w.WriteHeader(http.StatusNoContent)
		} else {
			json, err := json.Marshal(u)
			if err != nil {
				w.WriteHeader(http.StatusInternalServerError)
				return
			}
			w.Write(json)
		}

	// それ以外のHTTPメソッド
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
}

type Users struct {
	Id    string `firestore:id, json:id`
	Email string `firestore:email, json:email`
	Name  string `firestore:name, json:name`
}

func getUserBody(r *http.Request) (u Users, err error) {
	length, err := strconv.Atoi(r.Header.Get("Content-Length"))
	if err != nil {
		return u, err
	}

	body := make([]byte, length)
	length, err = r.Body.Read(body)
	if err != nil && err != io.EOF {
		return u, err
	}

	//parse json
	err = json.Unmarshal(body[:length], &u)
	if err != nil {
		return u, err
	}
	log.Print(u)
	return u, nil
}
