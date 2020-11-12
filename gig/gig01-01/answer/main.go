package main

import (
	"cloud.google.com/go/firestore"
	"encoding/json"
	"fmt"
	"github.com/gomodule/redigo/redis"
	"google.golang.org/api/iterator"
	"io"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
)

func main() {
	// Redis
	initRedis()

	http.HandleFunc("/", indexHandler)
	http.HandleFunc("/firestore", firestoreHandler)
	http.HandleFunc("/firestore/", firestoreHandler)

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
	fmt.Fprint(w, "Hello, GIG!")
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
		// 書き込み
		ref, _, err := client.Collection("users").Add(ctx, u)
		if err != nil {
			log.Fatalf("Failed adding data: %v", err)
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		log.Print("success: id is %v", ref.ID)
		fmt.Fprintf(w, "success: id is %v \n", ref.ID)
		// それ以外のHTTPメソッド
		// 取得処理
	case http.MethodGet:
		id := strings.TrimPrefix(r.URL.Path, "/firestore/")
		log.Printf("id=%v", id)
		if id == "/firestore" || id == "" {
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
		} // Redis クライアント作成
		conn := pool.Get()
		defer conn.Close()

		cache, err := redis.String(conn.Do("GET", id))
		if err != nil {
			log.Println(err)
		}
		log.Printf("cache : %v", cache)

		if cache != "" {
			json, err := json.Marshal(cache)
			if err != nil {
				w.WriteHeader(http.StatusInternalServerError)
				return
			}
			w.Write(json)
			log.Printf("find cache")
		} else {
			doc, err := client.Collection("users").Doc(id).Get(ctx)
			if err != nil {
				w.WriteHeader(http.StatusInternalServerError)
				return
			}
			var u Users
			err = doc.DataTo(&u)
			if err != nil {
				log.Fatal(err)
			}
			u.Id = doc.Ref.ID
			json, err := json.Marshal(u)
			if err != nil {
				w.WriteHeader(http.StatusInternalServerError)
				return
			}
			conn.Do("SET", id, string(json))
			w.Write(json)
		}
		// 更新処理
	case http.MethodPut:
		u, err := getUserBody(r)
		if err != nil {
			log.Fatal(err)
			w.WriteHeader(http.StatusInternalServerError)
			return
		}

		_, err = client.Collection("users").Doc(u.Id).Set(ctx, u)
		if err != nil {
			w.WriteHeader(http.StatusInternalServerError)
			return
		}

		fmt.Fprintln(w, "success updating")
		// 削除処理
	case http.MethodDelete:
		id := strings.TrimPrefix(r.URL.Path, "/firestore/")
		_, err := client.Collection("users").Doc(id).Delete(ctx)
		if err != nil {
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		fmt.Fprintln(w, "success deleting")
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

var pool *redis.Pool

func initRedis() {
	var (
		host = os.Getenv("REDIS_HOST")
		port = os.Getenv("REDIS_PORT")
		addr = fmt.Sprintf("%s:%s", host, port)
	)
	pool = redis.NewPool(func() (redis.Conn, error) {
		return redis.Dial("tcp", addr)
	}, 10)
}
