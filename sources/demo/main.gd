extends Node2D

const State = preload("res://state.gd")
const COLORS = [Color("8cb6ff"), Color("e9b96b"), Color("89d9b1")]
var plugin = null
var state: Dictionary = State.normalize(null)
var saved_snapshot: Dictionary = {}
var metadata: Dictionary = {}
var system_locale := "en"
var session_taps := 0 # RAM only: intentionally not included in the saved JSON.
var status := ""
var phase := 0.0
var image: Texture2D
var pressed := false
var press_start := Vector2.ZERO
var press_time := 0
var window_moved := false
var ignore_tap_until := 0
var cancel_next_stop := false
var fullscreen := false
var last_control_snapshot := ""
var timer: Timer

func _ready() -> void:
	get_viewport().transparent_bg = true
	RenderingServer.set_default_clear_color(Color.TRANSPARENT)
	if FileAccess.file_exists("res://metadata.json"):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://metadata.json"))
		if parsed is Dictionary:
			metadata = parsed
	if Engine.has_singleton("MyGodotPlugin"):
		plugin = Engine.get_singleton("MyGodotPlugin")
		plugin.setPluginSignals()
		system_locale = str(plugin.getLocale())
		plugin.on_widget_control_changed.connect(_on_control)
		plugin.on_locale_changed.connect(_on_locale)
		plugin.on_window_moving.connect(_on_moving)
		plugin.on_window_moving_ended.connect(_on_move_ended)
		plugin.on_graceful_end.connect(_on_end)
		plugin.makeClickPassthrough(true)
		load_state()
		plugin.updateNotificationImageFromWidget("banner.png")
	else:
		var args := OS.get_cmdline_user_args()
		if "--locale" in args:
			system_locale = args[args.find("--locale")+1]
		if "--showcase" in args:
			state.count = 12
			session_taps = 3
	status = words("Готово. Коснитесь карточки.", "Ready. Tap the card.")
	publish_menu()
	timer = Timer.new()
	timer.wait_time = 0.4
	timer.timeout.connect(_tick)
	add_child(timer)
	timer.start()
	queue_redraw()
	if "--capture" in OS.get_cmdline_user_args():
		_capture.call_deferred()

func ru() -> bool:
	return state.language == 1 or (state.language == 0 and system_locale.to_lower().begins_with("ru"))

func words(russian: String, english: String) -> String:
	return russian if ru() else english

func _on_locale(tag: String) -> void:
	system_locale = tag
	publish_menu()
	queue_redraw()

func _draw() -> void:
	var accent: Color = COLORS[state.accent]
	var card := StyleBoxFlat.new()
	card.bg_color = Color("171d2d")
	card.border_color = accent.darkened(0.55)
	card.set_border_width_all(1)
	card.set_corner_radius_all(28)
	draw_style_box(card, Rect2(20,20,320,360))
	var font := ThemeDB.fallback_font
	draw_string(font,Vector2(44,57),words("ДЕМО API", "API PLAYGROUND"),HORIZONTAL_ALIGNMENT_LEFT,-1,15,accent)
	draw_string(font,Vector2(44,87),str(state.name).substr(0,25),HORIZONTAL_ALIGNMENT_LEFT,-1,22,Color.WHITE)
	var pulse := 1.0 + sin(phase)*0.025 if state.animate else 1.0
	if image != null:
		draw_texture_rect(image,Rect2(258,102,54,54),false,Color(1,1,1,0.85))
	draw_string(font,Vector2(44,174),str(state.count),HORIZONTAL_ALIGNMENT_LEFT,-1,int(64*pulse),Color.WHITE)
	draw_string(font,Vector2(46,204),words("Касаний в этом сеансе: ","Taps this session: ")+str(session_taps),HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("a8b3cd"))
	draw_line(Vector2(44,228),Vector2(316,228),Color("303b52"),6,true)
	draw_line(Vector2(44,228),Vector2(44+272*state.level/100.0,228),accent,6,true)
	draw_string(font,Vector2(44,258),words("Уровень", "Level")+" · "+str(state.level)+"%",HORIZONTAL_ALIGNMENT_LEFT,-1,14,accent)
	draw_string(font,Vector2(44,291),str(status).substr(0,34),HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("b8c4dc"))
	draw_string(font,Vector2(44,322),words("В памяти", "In memory")+"  /  "+words("сохранено", "saved")+": "+str(saved_snapshot.get("count", "—")),HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("a8b3cd"))
	draw_string(font,Vector2(44,351),"v%s · %s · %s×%s" % [metadata.get("version","1.0.0"), "RU" if ru() else "EN", metadata.get("requestedWindowWidth",360), metadata.get("requestedWindowHeight",400)],HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("7384a6"))

func build_menu() -> Array:
	return [
		{"type":"text","text":words("Демо API MyWidget", "MyWidget API demo")},
		{"type":"spinner","name":"demo_language","text":words("Язык", "Language"),"values":[words("Как в приложении","Follow app"),"Русский","English"],"value":state.language},
		{"type":"group","text":words("Состояние и элементы меню", "State and controls"),"items":[
			{"type":"edittext","name":"demo_name","text":words("Подпись карточки","Card title"),"value":state.name},
			{"type":"button","name":"demo_add","id":"example.counter.add","text":words("Увеличить счётчик","Increment counter")},
			{"type":"switch","name":"demo_auto_save","text":words("Сохранять каждое изменение","Save each change"),"value":state.auto_save},
			{"type":"checkbox","name":"demo_animate","text":words("Анимация","Animation"),"value":state.animate},
			{"type":"spinner","name":"demo_accent","text":words("Цвет","Accent"),"values":[words("Синий","Blue"),words("Золотой","Gold"),words("Зелёный","Green")],"value":state.accent},
			{"type":"seekbar","name":"demo_level","text":words("Уровень, шаг 5","Level, step 5"),"min":0,"max":100,"step":5,"value":state.level},
			{"type":"progress","name":"demo_progress","text":words("Уровень","Level"),"max":100,"value":state.level},
			{"type":"divider"},
			{"type":"button","name":"demo_random","text":words("Изменить значения из Godot","Change controls from Godot")}
		]},
		{"type":"group","text":words("Постоянное хранилище","Persistent storage"),"items":[
			{"type":"button","name":"demo_save","text":words("Сохранить JSON","Save JSON")},
			{"type":"button","name":"demo_load","text":words("Восстановить JSON","Restore JSON")},
			{"type":"button","name":"demo_delete","text":words("Удалить сохранение и сбросить","Delete saved state and reset")}
		]},
		{"type":"group","text":words("Изображения и уведомления","Images and notifications"),"items":[
			{"type":"mediapicker","name":"demo_image","text":words("Выбрать изображение","Choose image"),"filetypes":"image/*"},
			{"type":"button","name":"demo_notify_banner","text":words("Баннер в уведомление","Use banner in notification")},
			{"type":"button","name":"demo_notify_image","text":words("Выбранное изображение в уведомление","Use chosen image in notification")}
		]},
		{"type":"group","text":words("Управление окном","Window controls"),"items":[
			{"type":"button","name":"demo_geometry","text":words("Прочитать положение и размер","Read position and size")},
			{"type":"button","name":"demo_move","text":words("Сдвинуть на 20 пикселей","Move by 20 pixels")},
			{"type":"button","name":"demo_resize","text":words("Размер из meta.json","Restore meta.json size")},
			{"type":"button","name":"demo_fullscreen","text":words("Полный экран","Enter fullscreen")},
			{"type":"button","name":"demo_exit_fullscreen","text":words("Выйти из полного экрана","Exit fullscreen")},
			{"type":"button","name":"demo_passthrough","text":words("Пропускать касания 3 секунды","Pass touches through for 3 seconds")},
			{"type":"button","name":"demo_refresh","text":words("Обновить поверхность","Refresh render surface")}
		]},
		{"type":"group","text":words("Сигналы и завершение","Signals and shutdown"),"items":[
			{"type":"button","name":"demo_inspect","text":words("Прочитать значения контролов","Read control values")},
			{"type":"checkbox","name":"demo_cancel_stop","text":words("Один раз отменить остановку","Cancel next stop once"),"value":cancel_next_stop},
			{"type":"button","name":"demo_stop","text":words("Сохранить и завершить","Save and stop")}
		]}
	]

func publish_menu() -> void:
	if plugin != null:
		plugin.populateScrollViewFromJSONString(JSON.stringify(build_menu()))
		_push_controls.call_deferred()

func _push(name: String, value: Variant) -> void:
	if plugin != null:
		plugin.updateControlValue(name,str(value).to_lower() if value is bool else str(value))

func _push_controls() -> void:
	var values := {"demo_language":state.language,"demo_name":state.name,"demo_auto_save":state.auto_save,"demo_animate":state.animate,"demo_accent":state.accent,"demo_level":state.level,"demo_progress":state.level,"demo_cancel_stop":cancel_next_stop}
	for entry in values:
		_push(entry,values[entry])

func _on_control(cname: String, _id: String, _type: String, value: String) -> void:
	match cname:
		"demo_language":
			state.language = clampi(value.to_int(),0,2)
			publish_menu()
		"demo_name": state.name = value.substr(0,48)
		"demo_auto_save": state.auto_save = value == "true"
		"demo_animate": state.animate = value == "true"
		"demo_accent": state.accent = clampi(value.to_int(),0,2)
		"demo_level":
			state.level = clampi(value.to_int(),0,100)
			_push("demo_progress",state.level)
		"demo_add":
			increment()
			return
		"demo_random":
			state.level = randi_range(0,20)*5
			state.accent = (state.accent+1)%3
			_push_controls()
		"demo_save":
			save_state()
			return
		"demo_load":
			load_state()
			publish_menu()
			return
		"demo_delete":
			delete_state()
			publish_menu()
			return
		"demo_image":
			state.image = value
			_load_image()
		"demo_cancel_stop": cancel_next_stop = value == "true"
		"demo_stop":
			_on_end()
			return
		_:
			_window_or_debug_action(cname)
			return
	if state.auto_save:
		save_state()
	_notify()
	queue_redraw()

func increment() -> void:
	state.count = mini(state.count+1,999999)
	session_taps += 1
	status = words("Изменено в памяти", "Changed in memory")
	if state.auto_save:
		save_state()
	_notify()
	queue_redraw()

func save_state() -> void:
	saved_snapshot = State.normalize(state)
	if plugin != null:
		plugin.saveWidgetData(State.KEY,JSON.stringify(saved_snapshot))
	status = words("JSON сохранён", "JSON saved")
	queue_redraw()

func load_state() -> void:
	var saved = plugin.getWidgetData(State.KEY) if plugin != null else saved_snapshot
	state = State.decode(saved)
	saved_snapshot = state.duplicate(true) if saved != null and (saved is not Dictionary or not saved.is_empty()) else {}
	_load_image()
	status = words("JSON восстановлен", "JSON restored")
	_notify()
	queue_redraw()

func delete_state() -> void:
	if plugin != null:
		plugin.delWidgetData(State.KEY)
	state = State.normalize(null)
	saved_snapshot = {}
	image = null
	status = words("Сохранение удалено", "Saved state deleted")
	_notify()
	queue_redraw()

func _load_image() -> void:
	image = null
	if state.image.is_empty():
		return
	var loaded := Image.new()
	if loaded.load(state.image) == OK:
		image = ImageTexture.create_from_image(loaded)
	else:
		state.image = ""
		status = words("Изображение недоступно", "Image unavailable")

func _notify() -> void:
	if plugin != null:
		plugin.updateNotificationText(words("Демо API", "API Demo")+" · "+str(state.count))

func _window_or_debug_action(cname: String) -> void:
	if plugin == null:
		status = words("Доступно внутри MyWidget", "Available inside MyWidget")
		queue_redraw()
		return
	match cname:
		"demo_geometry":
			last_control_snapshot = str(plugin.getWindowPosition())
			status = "%d,%d · %d×%d" % [plugin.getWidgetX(),plugin.getWidgetY(),plugin.getWidgetW(),plugin.getWidgetH()]
		"demo_move": plugin.changeWidgetPosition(plugin.getWidgetX()+20,plugin.getWidgetY()+20)
		"demo_resize": plugin.changeWidgetSize(int(metadata.get("requestedWindowWidth",360)),int(metadata.get("requestedWindowHeight",400)))
		"demo_fullscreen":
			fullscreen = true
			plugin.makeFullscreen()
		"demo_exit_fullscreen":
			fullscreen = false
			plugin.exitFullscreen()
		"demo_refresh": plugin.refreshRenderView()
		"demo_notify_banner": plugin.updateNotificationImageFromWidget("banner.png")
		"demo_notify_image":
			if not state.image.is_empty():
				plugin.updateNotificationImageFromPath(state.image)
		"demo_inspect":
			last_control_snapshot = str(plugin.getWidgetControlValues())
			status = "demo_level="+str(plugin.getWidgetControlValueByName("demo_level"))
			print("Demo control snapshot: ",last_control_snapshot)
		"demo_passthrough":
			status = words("Касания отключены на 3 с", "Touches off for 3 seconds")
			plugin.makeClickPassthrough(false)
			queue_redraw()
			await get_tree().create_timer(3.0).timeout
			plugin.makeClickPassthrough(true)
			status = words("Касания восстановлены", "Touches restored")
	queue_redraw()

func _on_end() -> void:
	if plugin == null:
		save_state()
		return
	if cancel_next_stop:
		cancel_next_stop = false
		_push("demo_cancel_stop",false)
		plugin.gracefulEndNotify(2)
		status = words("Остановка отменена один раз", "Stop cancelled once")
		queue_redraw()
		return
	plugin.gracefulEndNotify(1)
	save_state()
	plugin.gracefulEndNotify(0)

func _tick() -> void:
	if plugin != null:
		var size_px := Vector2(get_window().size)
		var logical_size := get_viewport().get_visible_rect().size
		var factor := size_px/logical_size
		plugin.setViewRegion(int(20*factor.x),int(20*factor.y),int(320*factor.x),int(360*factor.y))

func _process(delta: float) -> void:
	if state.animate:
		phase += delta*2.0
		queue_redraw()

func _on_moving(_x: float,_y: float) -> void:
	window_moved = true
	pressed = false
	ignore_tap_until = Time.get_ticks_msec()+300

func _on_move_ended() -> void:
	# Android sends this even for a stationary ACTION_UP.
	if window_moved:
		window_moved = false
		pressed = false
		ignore_tap_until = Time.get_ticks_msec()+300

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_tap(event.pressed,event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.device != InputEvent.DEVICE_ID_EMULATION:
		_tap(event.pressed,event.position)

func _tap(down: bool,point: Vector2) -> void:
	if down:
		pressed = Rect2(20,20,320,360).has_point(point)
		press_start = point
		press_time = Time.get_ticks_msec()
	else:
		if pressed and Time.get_ticks_msec() >= ignore_tap_until and Time.get_ticks_msec()-press_time < 450 and point.distance_to(press_start) < 18:
			increment()
		pressed = false

func _capture() -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var args := OS.get_cmdline_user_args()
	get_viewport().get_texture().get_image().save_png(args[args.find("--capture")+1])
	get_tree().quit()
