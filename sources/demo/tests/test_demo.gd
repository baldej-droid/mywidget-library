extends SceneTree

const State = preload("res://state.gd")
var failures: Array[String] = []

class AndroidJson extends RefCounted:
	func toString() -> String:
		return '{"count":42,"language":1,"level":35}'

class FakePlugin extends RefCounted:
	var saved: Dictionary = {}
	var updates: Dictionary = {}
	var statuses: Array[int] = []
	var menu := ""
	var notification := ""
	func saveWidgetData(key: String,value: String) -> void: saved[key] = value
	func getWidgetData(key: String): return saved.get(key)
	func delWidgetData(key: String) -> void: saved.erase(key)
	func updateControlValue(key: String,value: String) -> void: updates[key] = value
	func populateScrollViewFromJSONString(value: String) -> void: menu = value
	func updateNotificationText(value: String) -> void: notification = value
	func gracefulEndNotify(value: int) -> void: statuses.append(value)

func check(condition: bool,message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	run.call_deferred()

func collect_types(items: Array,types: Dictionary) -> void:
	for item in items:
		types[item.type] = true
		if item.has("items"):
			collect_types(item.items,types)

func run() -> void:
	check(State.decode(null).count == 0,"Missing state must use defaults")
	check(State.decode("broken").name == "MyWidget","Malformed state must recover")
	check(State.decode(AndroidJson.new()).count == 42,"Android JSONObject conversion failed")
	check(State.normalize({"count":-2,"accent":99,"level":53}).count == 0,"Negative counter accepted")
	check(State.normalize({"level":53}).level == 55,"Step quantization failed")
	var demo = load("res://main.tscn").instantiate()
	root.add_child(demo)
	await process_frame
	demo.timer.stop()
	var fake := FakePlugin.new()
	demo.plugin = fake
	demo.increment()
	check(demo.session_taps == 1 and demo.state.count == 1,"Counter did not change in RAM")
	check(fake.saved.is_empty(),"Manual mode unexpectedly saved")
	demo.save_state()
	demo.increment()
	demo.load_state()
	check(demo.state.count == 1 and demo.session_taps == 2,"Restore did not separate persistent/RAM values")
	demo._on_control("demo_auto_save","","bool","true")
	demo.increment()
	check(State.decode(fake.saved[State.KEY]).count == 2,"Auto-save failed")
	demo._on_control("demo_level","","number","75")
	check(fake.updates["demo_progress"] == "75","Godot did not update progress control")
	demo._on_control("demo_language","","number","1")
	check(demo.ru() and fake.menu.contains("Постоянное хранилище"),"Russian menu missing")
	demo._on_control("demo_language","","number","2")
	check(not demo.ru() and fake.menu.contains("Persistent storage"),"English menu missing")
	demo.state.language = 0
	demo._on_locale("ru-RU")
	check(demo.ru(),"Application locale did not propagate")
	var types := {}
	collect_types(demo.build_menu(),types)
	for required in ["text","spinner","switch","checkbox","edittext","seekbar","progress","divider","group","button","mediapicker"]:
		check(types.has(required),"Missing control type: "+required)
	demo.cancel_next_stop = true
	demo._on_end()
	check(fake.statuses == [2],"Stop cancellation failed")
	demo._on_end()
	check(fake.statuses == [2,1,0],"Graceful prepare/save/complete failed")
	demo.delete_state()
	check(not fake.saved.has(State.KEY) and demo.state.count == 0,"Delete did not clear persistent state")
	check(demo.session_taps > 0,"Delete must not silently reset RAM session metric")
	demo.plugin = null
	demo._tap(true,Vector2(80,80))
	demo._on_move_ended()
	demo._tap(false,Vector2(80,80))
	check(demo.state.count == 1,"Stationary host ACTION_UP blocked tap")
	demo._tap(true,Vector2(80,80))
	demo._on_moving(10,10)
	demo._on_move_ended()
	demo._tap(false,Vector2(80,80))
	check(demo.state.count == 1,"Window drag counted as tap")
	if failures.is_empty():
		print("ALL DEMO CHECKS PASSED: persistence, RAM isolation, Android JSON, all menu types, control updates, locale, lifecycle, gestures")
	demo.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
