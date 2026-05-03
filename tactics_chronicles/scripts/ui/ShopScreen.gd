class_name ShopScreen
extends Control
## Shop screen: buy items, sell items, browse by category.

@onready var item_list:      ItemList    = $ItemList
@onready var detail_panel:   Control     = $DetailPanel
@onready var buy_btn:        Button      = $BuyBtn
@onready var sell_btn:       Button      = $SellBtn
@onready var gil_label:      Label       = $GilLabel
@onready var category_tabs:  TabBar      = $CategoryTabs
@onready var qty_spinner:    SpinBox     = $QtySpinner

var shop_data:     Dictionary = {}
var selected_item: String     = ""
var _mode:         String     = "buy"   # "buy" | "sell"

func _ready() -> void:
	buy_btn.pressed.connect(_on_buy_pressed)
	sell_btn.pressed.connect(_on_sell_pressed)
	item_list.item_selected.connect(_on_item_selected)
	category_tabs.tab_changed.connect(_on_category_changed)
	EventBus.gil_changed.connect(_refresh_gil)

func open(data: Dictionary) -> void:
	shop_data = data
	_mode = "buy"
	_refresh_gil(GameState.gil, 0)
	_populate_buy_list()
	visible = true
	EventBus.shop_opened.emit(data)

func close() -> void:
	visible = false
	EventBus.menu_closed.emit("shop")

# ─────────────────────────────────────────────────────────────────────────────
# Buy
# ─────────────────────────────────────────────────────────────────────────────

func _populate_buy_list() -> void:
	item_list.clear()
	var tier_limit = shop_data.get("tier_limit", 4)
	for item_id in shop_data.get("stock", []):
		var item = DataManager.get_item(item_id)
		if item.is_empty() or item.get("tier", 1) > tier_limit: continue
		item_list.add_item("%s  — %d Gil" % [item["name"], item["price"]])
		item_list.set_item_metadata(item_list.item_count - 1, item_id)

func _on_buy_pressed() -> void:
	if selected_item == "": return
	var item  = DataManager.get_item(selected_item)
	var price = item.get("price", 0) * int(qty_spinner.value)
	if not GameState.spend_gil(price):
		EventBus.notification_requested.emit("Not enough Gil!", Color.RED)
		return
	GameState.add_item(selected_item, int(qty_spinner.value))
	EventBus.notification_requested.emit("Purchased %s x%d" % [item["name"], int(qty_spinner.value)], Color.GREEN)

# ─────────────────────────────────────────────────────────────────────────────
# Sell
# ─────────────────────────────────────────────────────────────────────────────

func _populate_sell_list() -> void:
	item_list.clear()
	for item_id in GameState.inventory:
		var item = DataManager.get_item(item_id)
		if item.is_empty(): continue
		var qty = GameState.item_count(item_id)
		item_list.add_item("%s x%d  — %d Gil ea" % [item["name"], qty, item.get("sell_price", 0)])
		item_list.set_item_metadata(item_list.item_count - 1, item_id)

func _on_sell_pressed() -> void:
	if selected_item == "": return
	var item  = DataManager.get_item(selected_item)
	var qty   = int(qty_spinner.value)
	if not GameState.remove_item(selected_item, qty):
		EventBus.notification_requested.emit("Not enough items.", Color.RED)
		return
	var earned = item.get("sell_price", 0) * qty
	GameState.add_gil(earned)
	EventBus.notification_requested.emit("Sold for %d Gil" % earned, Color.GREEN)
	_populate_sell_list()

# ─────────────────────────────────────────────────────────────────────────────
# Shared
# ─────────────────────────────────────────────────────────────────────────────

func _on_item_selected(idx: int) -> void:
	selected_item = item_list.get_item_metadata(idx)
	_refresh_detail(selected_item)

func _refresh_detail(item_id: String) -> void:
	var item = DataManager.get_item(item_id)
	if item.is_empty(): return
	# TODO: populate detail_panel labels with item stats and description
	pass

func _refresh_gil(new_total: int, _delta: int) -> void:
	gil_label.text = "Gil: %d" % new_total

func _on_category_changed(tab: int) -> void:
	_mode = "sell" if tab == 1 else "buy"
	if _mode == "buy":
		_populate_buy_list()
	else:
		_populate_sell_list()
