package model

type Event struct {
	EventName string `json:"event_name"`
	Purchaser string `json:"purchaser"`
	OrderID   uint   `json:"order_id"`
	ItemID    uint   `json:"item_id"`
}
