package handler

import (
	"eats.com/model"
	//"eats.com/util"
	"encoding/json"
	"github.com/gorilla/mux"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"strconv"
)

var port = os.Getenv("PORT")

type rootResponse struct {
	Version string `json:"version"` // v1, v2, v3...
	Message string `json:"message"`
}

type deleteResponse struct {
	Id      string `json:"id"`
	Message string `json:"message"`
}

func fetchRootResponse(w http.ResponseWriter, r *http.Request) {
	responseBody, err := json.Marshal(&rootResponse{Version: "v1", Message: "This is Eats service API"})
	if err != nil {
		log.Printf("could not json.Marshal: %v", err)
		w.WriteHeader(http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-type", "application/json")
	w.Write(responseBody)
}

func fetchAllOrders(w http.ResponseWriter, r *http.Request) {
	var orders []model.Order
	model.GetAllOrders(&orders)

	responseBody, err := json.Marshal(orders)
	if err != nil {
		log.Printf("could not json.Marshal: %v", err)
		w.WriteHeader(http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-type", "application/json")
	w.Write(responseBody)
}

func fetchOrder(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	id := vars["id"]

	var order model.Order
	model.GetOrder(&order, id)

	responseBody, err := json.Marshal(order)
	if err != nil {
		log.Printf("could not json.Marshal: %v", err)
		w.WriteHeader(http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.Write(responseBody)
}

func createOrder(w http.ResponseWriter, r *http.Request) {
	requestBody, _ := ioutil.ReadAll(r.Body)

	var order model.Order
	if err := json.Unmarshal(requestBody, &order); err != nil {
		log.Printf("could not json.Unmarshal: %v", err)
		w.WriteHeader(http.StatusBadRequest)
		return
	}
	model.InsertOrder(&order)

	responseBody, err := json.Marshal(order)
	if err != nil {
		log.Printf("could not json.Marshal: %v", err)
		w.WriteHeader(http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	w.Write(responseBody)

	// publish message to Cloud Pub/Sub
	//util.Publish("Order received", order.Purchaser, order.ID, order.ItemID)
}

func updateOrder(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	id := vars["id"]
	requestBody, _ := ioutil.ReadAll(r.Body)

	var order model.Order
	if err := json.Unmarshal(requestBody, &order); err != nil {
		log.Printf("could not json.Unmarshal: %v", err)
		w.WriteHeader(http.StatusBadRequest)
		return
	}
	model.UpdateOrder(&order, id)
	convertUintId, _ := strconv.ParseInt(id, 10, 64)
	order.Model.ID = uint(convertUintId)

	responseBody, err := json.Marshal(order)
	if err != nil {
		log.Printf("could not json.Marshal: %v", err)
		w.WriteHeader(http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.Write(responseBody)

	// TODO: only when item_completed_at or delivery_completed_at has been set
	//util.Publish("Order updated", order.Purchaser, order.ID, order.ItemID)
}

func deleteOrder(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	id := vars["id"]
	model.DeleteOrder(id)

	responseBody, err := json.Marshal(deleteResponse{Id: id, Message: "deleted"})
	if err != nil {
		log.Printf("could not json.Marshal: %v", err)
		w.WriteHeader(http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.Write(responseBody)
}
func fetchAllItems(w http.ResponseWriter, r *http.Request) {
	var items []model.Item
	model.GetAllItems(&items)

	responseBody, err := json.Marshal(items)
	if err != nil {
		log.Printf("could not json.Marshal: %v", err)
		w.WriteHeader(http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-type", "application/json")
	w.Write(responseBody)
}

func fetchItem(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	id := vars["id"]
	var item model.Item
	model.GetItem(&item, id)

	responseBody, err := json.Marshal(item)
	if err != nil {
		log.Printf("could not json.Marshal: %v", err)
		w.WriteHeader(http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.Write(responseBody)
}

func createItem(w http.ResponseWriter, r *http.Request) {
	requestBody, _ := ioutil.ReadAll(r.Body)
	var item model.Item
	if err := json.Unmarshal(requestBody, &item); err != nil {
		log.Printf("could not json.Unmarshal: %v", err)
		w.WriteHeader(http.StatusBadRequest)
		return
	}
	model.InsertItem(&item)

	responseBody, err := json.Marshal(item)
	if err != nil {
		log.Printf("could not json.Marshal: %v", err)
		w.WriteHeader(http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusCreated)
	w.Header().Set("Content-Type", "application/json")
	w.Write(responseBody)
}

func updateItem(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	id := vars["id"]
	requestBody, _ := ioutil.ReadAll(r.Body)
	var item model.Item
	if err := json.Unmarshal(requestBody, &item); err != nil {
		log.Printf("could not json.Unmarshal: %v", err)
		w.WriteHeader(http.StatusBadRequest)
		return
	}
	model.UpdateItem(&item, id)

	convertUintId, _ := strconv.ParseInt(id, 10, 64)
	item.Model.ID = uint(convertUintId)
	responseBody, err := json.Marshal(item)
	if err != nil {
		log.Printf("could not json.Marshal: %v", err)
		w.WriteHeader(http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.Write(responseBody)
}

func deleteItem(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	id := vars["id"]
	model.DeleteItem(id)

	responseBody, err := json.Marshal(deleteResponse{Id: id, Message: "deleted"})
	if err != nil {
		log.Printf("could not json.Marshal: %v", err)
		w.WriteHeader(http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.Write(responseBody)
}

func StartServer() {
	router := mux.NewRouter().StrictSlash(true)

	router.HandleFunc("/", fetchRootResponse).Methods("GET")

	router.HandleFunc("/items", fetchAllItems).Methods("GET")
	router.HandleFunc("/items/{id}", fetchItem).Methods("GET")

	router.HandleFunc("/items", createItem).Methods("POST")
	router.HandleFunc("/items/{id}", deleteItem).Methods("DELETE")
	router.HandleFunc("/items/{id}", updateItem).Methods("PUT")

	router.HandleFunc("/orders", fetchAllOrders).Methods("GET")
	router.HandleFunc("/orders/{id}", fetchOrder).Methods("GET")

	router.HandleFunc("/orders", createOrder).Methods("POST")
	router.HandleFunc("/orders/{id}", deleteOrder).Methods("DELETE")
	router.HandleFunc("/orders/{id}", updateOrder).Methods("PUT")

	err := http.ListenAndServe(":" + port, router)
	if err != nil {
		log.Fatal("ListenAndServe:", err)
	}
}
