package main

import (
	"database/sql"
	_ "github.com/go-sql-driver/mysql"

	"fmt"
	"log"
	"net/http"
	"os"
	"strings"

	"cloud.google.com/go/firestore"
	"encoding/json"
	"google.golang.org/api/iterator"
	"io"
	"strconv"

	"github.com/gomodule/redigo/redis"
)

var db *sql.DB

func main() {
	var err error

	// DB
	db, err = initConnectionPool()
	if err != nil {
		log.Fatalf("unable to connect: %s", err)
	}

	// Redis
	initRedis()

	http.HandleFunc("/", indexHandler)
	http.HandleFunc("/firestore", firestoreHandler)
	http.HandleFunc("/firestore/", firestoreHandler)
	http.HandleFunc("/sql", sqlHandler)

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
func firestoreHandler(w http.ResponseWriter, r *http.Request) {

	// Firestore クライアント作成
	pid := os.Getenv("GOOGLE_CLOUD_PROJECT")
	ctx := r.Context()
	client, err := firestore.NewClient(ctx, pid)
	if err != nil {
		log.Fatal(err)
	}
	defer client.Close()

	// Redis クライアント作成
	conn := pool.Get()
	defer conn.Close()

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
		} else {
            cache, _ := redis.String(conn.Do("GET", id))
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
			log.Fatal(err)
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		fmt.Fprintln(w, "success deleting")
	// それ以外のHTTPメソッド
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
}

type Users struct {
	Id    string `firestore:id, json:id, db:id`
	Email string `firestore:email, json:email, db:email`
	Name  string `firestore:name, json:name, db:name`
}

func initConnectionPool() (*sql.DB, error) {

	var (
		dbUser     = os.Getenv("DB_USER")
		dbPwd      = os.Getenv("DB_PASS")
		dbInstance = os.Getenv("DB_INSTANCE")
		dbName     = "egg"
	)
	dbURI := fmt.Sprintf("%s:%s@unix(/cloudsql/%s)/%s", dbUser, dbPwd, dbInstance, dbName)
	dbPool, err := sql.Open("mysql", dbURI)
	if err != nil {
		return nil, fmt.Errorf("sql.Open: %v", err)
	}
	dbPool.SetMaxIdleConns(5)
	dbPool.SetMaxOpenConns(5)
	dbPool.SetConnMaxLifetime(1800)

	return dbPool, nil
}

func sqlHandler(w http.ResponseWriter, r *http.Request) {

	switch r.Method {
	case http.MethodPost:
		u, err := getUserBody(r)
		if err != nil {
			log.Fatal(err)
			w.WriteHeader(http.StatusInternalServerError)
			return
		}

		ins, err := db.Prepare("INSERT INTO user(id, email, name) VALUES(?,?,?)")
		if err != nil {
			log.Fatal(err)
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		defer ins.Close()
		_, err = ins.Exec(u.Id, u.Email, u.Name)
		if err != nil {
			log.Fatal(err)
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		log.Print("success: id is %v", u.Id)
		fmt.Fprintf(w, "success: id is %v \n", u.Id)

	case http.MethodGet:
		rows, err := db.Query(`SELECT id, email, name FROM user`)
		if err != nil {
			log.Fatal(err)
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		defer rows.Close()
		var users []Users
		for rows.Next() {
			var u Users
			err = rows.Scan(&u.Id, &u.Email, &u.Name)
			if err != nil {
				log.Fatal(err)
				w.WriteHeader(http.StatusInternalServerError)
				return
			}
			users = append(users, u)
		}
		if len(users) == 0 {
			w.WriteHeader(http.StatusNoContent)
		} else {
			json, err := json.Marshal(users)
			if err != nil {
				log.Fatal(err)
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
