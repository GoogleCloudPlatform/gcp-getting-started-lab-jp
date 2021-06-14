package model

import (
	"gorm.io/driver/mysql"
	"gorm.io/gorm"
	"log"
	"os"
	"time"
)

type Order struct {
	gorm.Model
	ItemID              uint       `json:"item_id" gorm:"not null"`
	Purchaser           string     `json:"purchaser" gorm:"not null"`
	ItemCompleted       bool       `json:"item_completed"`
	DeliveryCompleted   bool       `json:"delivery_completed"`
	DeliveryCompletedAt *time.Time `json:"delivery_completed_at"`
}

type Item struct {
	gorm.Model
	Name  string `json:"name" gorm:"not null"`
	Price int    `json:"price" gorm:"not null"`
	Currency string `json:"currency" gorm:"default:'JPY'"`
}

type Event struct {
	EventName string `json:"event_name"`
	Purchaser string `json:"purchaser"`
	OrderID uint `json:"order_id"`
	ItemID uint `json:"item_id"`
}

var db *gorm.DB
var err error

func GetAllOrders(order *[]Order) {
	db.Find(&order)
}

func GetOrder(order *Order, key string) {
	db.Find(&order, key)
}

func InsertOrder(order *Order) {
	db.Create(&order)
}

func UpdateOrder(order *Order, key string) {
	db.Model(&order).Where("id = ?", key).Updates(
		map[string]interface{}{
			"purchaser":             order.Purchaser,
			"item_completed":        order.ItemCompleted,
			"delivery_completed":    order.DeliveryCompleted,
			"delivery_completed_at": order.DeliveryCompletedAt,
		})
}

func DeleteOrder(key string) {
	db.Where("id = ?", key).Delete(&Order{})
}
func GetAllItems(items *[]Item) {
	db.Find(&items)
}

func GetItem(item *Item, key string) {
	db.Find(&item, key)
}

func InsertItem(item *Item) {
	db.Create(&item)
}

func UpdateItem(item *Item, key string) {
	db.Model(&item).Where("id = ?", key).Updates(
		map[string]interface{}{
			"name":  item.Name,
			"price": item.Price,
			"currency": item.Currency,
		})
}

func DeleteItem(key string) {
	db.Where("id = ?", key).Delete(&Item{})
}

func init() {
	dsn := os.Getenv("DB_USER") +
		":" +
		os.Getenv("DB_PWD") +
		"@unix(" +
		os.Getenv("DB_CONNECTION") +
		")/handson?charset=utf8mb4&parseTime=True&loc=Local"
	db, err = gorm.Open(mysql.Open(dsn), &gorm.Config{})
	if err != nil {
		log.Fatalln(err)
	}
	if !(db.Migrator().HasTable("orders")) {
		err = db.AutoMigrate(&Order{})
		if err != nil {
			log.Fatalln(err)
		}
	}
	if !(db.Migrator().HasTable("items")) {
		err = db.AutoMigrate(&Item{})
		if err != nil {
			log.Fatalln(err)
		}
		db.Create(&Item{
			Name:  "Simple Pizza",
			Price: 1000,
		})
		db.Create(&Item{
			Name:  "Normal Pizza",
			Price: 2000,
		})
		db.Create(&Item{
			Name:  "Luxury Pizza",
			Price: 3000,
		})
	}
}
