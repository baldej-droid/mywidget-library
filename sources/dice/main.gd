extends Node3D

const SIDES = [2, 4, 6, 8, 10, 12, 20, 100]
const SAVE_KEY = "dice_state_v1"
const DURATION = 1.45
const FACE_DIRECTION = Vector3(0.0, 0.38, 1.0)
var plugin = null
var locale = "en"
var sides: int = 6
var result: int = 1
var rolling := false
var elapsed := 0.0
var spin_start := Vector3.ZERO
var spin_end := Vector3.ZERO
var settle := Quaternion.IDENTITY
var rng := RandomNumberGenerator.new()
var body: Node3D
var faces: Array = []
var result_label: Label
var result_tween: Tween
var face_meshes: Array[MeshInstance3D] = []
var face_materials: Array[StandardMaterial3D] = []
var pressed_at := Vector2.ZERO
var press_time := 0
var pressed := false
var ignore_tap_until := 0
var window_moved := false
var touch_region := Rect2()

func _ready() -> void:
	rng.randomize()
	get_viewport().transparent_bg = true
	RenderingServer.set_default_clear_color(Color.TRANSPARENT)
	_setup_scene()
	if Engine.has_singleton("MyGodotPlugin"):
		plugin = Engine.get_singleton("MyGodotPlugin")
		plugin.setPluginSignals()
		locale = str(plugin.getLocale())
		var saved = plugin.getWidgetData(SAVE_KEY)
		if saved != null:
			var text: String = saved.toString() if saved is Object else str(saved)
			var state = JSON.parse_string(text)
			if state is Dictionary:
				sides = int(state.get("sides", 6))
				if sides not in SIDES:
					sides = 6
				result = clampi(int(state.get("result", 1)), 1, sides)
		plugin.on_widget_control_changed.connect(_on_control)
		plugin.on_locale_changed.connect(_on_locale)
		plugin.on_window_moving.connect(_on_moving)
		plugin.on_window_moving_ended.connect(_on_move_ended)
		plugin.on_graceful_end.connect(_on_end)
		# The host's boolean means "enable the widget's touch region".
		plugin.makeClickPassthrough(true)
		plugin.updateNotificationImageFromWidget("banner.png")
	var args := OS.get_cmdline_user_args()
	if plugin == null and "--sides" in args:
		var requested := int(args[args.find("--sides")+1])
		if requested in SIDES:
			sides = requested
			result = mini(result, sides)
	if plugin == null and "--result" in args:
		result = clampi(int(args[args.find("--result")+1]), 1, sides)
	_rebuild()
	_publish_controls()
	set_process(false)
	if DisplayServer.get_name() != "headless":
		var touch_timer := Timer.new()
		touch_timer.wait_time = 0.1
		touch_timer.timeout.connect(_update_touch_region)
		add_child(touch_timer)
		touch_timer.start()
		_update_touch_region_after_draw()
	if "--capture" in OS.get_cmdline_user_args():
		_capture.call_deferred()

func _setup_scene() -> void:
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_CLEAR_COLOR
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("b9c5f6")
	world.environment.ambient_light_energy = 0.65
	add_child(world)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.6
	camera.position = Vector3(0, -0.25, 7)
	add_child(camera)
	camera.current = true
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-28, -32, 0)
	light.light_energy = 1.8
	add_child(light)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(25, 140, -20)
	rim.light_color = Color("8bbcff")
	rim.light_energy = 0.9
	add_child(rim)
	body = Node3D.new()
	add_child(body)
	var layer := CanvasLayer.new()
	add_child(layer)
	result_label = _label(layer, 304, 54, Color.WHITE)
	result_label.visible = false

func _label(parent: Node, y: float, size: int, color: Color) -> Label:
	var label := Label.new()
	label.position = Vector2(0, y)
	label.size = Vector2(360, 50)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.02, 0.025, 0.06, 0.9))
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func ru() -> bool:
	return locale.to_lower().begins_with("ru")

func _update_touch_region() -> void:
	# Same alpha-bounds limiter as Alicia Solid, rather than a fixed window-sized box.
	_apply_touch_image(get_viewport().get_texture().get_image())

func _update_touch_region_after_draw() -> void:
	await RenderingServer.frame_post_draw
	_update_touch_region()

func _apply_touch_image(image: Image) -> void:
	if image == null or image.is_empty():
		return
	var rect := Rect2(image.get_used_rect())
	var image_size := Vector2(image.get_size())
	var canvas := get_viewport().get_visible_rect()
	touch_region = Rect2(canvas.position + rect.position * canvas.size / image_size, rect.size * canvas.size / image_size)
	if plugin != null:
		# Texture, canvas and Android surface sizes can differ after stretching/scaling.
		var scale_px := Vector2(get_window().size) / image_size
		var start := (rect.position * scale_px).floor()
		var end := (rect.end * scale_px).ceil()
		plugin.setViewRegion(int(start.x), int(start.y), int(end.x-start.x), int(end.y-start.y))

func _refresh_text() -> void:
	if plugin != null:
		var title: String = ("Монетка" if ru() else "Coin") if sides == 2 else "D%d" % sides
		plugin.updateNotificationText(title + " · " + str(result))

func _hide_result() -> void:
	if result_tween != null:
		result_tween.kill()
	result_label.hide()

func _show_result() -> void:
	_hide_result()
	result_label.text = str(result)
	var canvas_size := get_viewport().get_visible_rect().size
	result_label.position = Vector2((canvas_size.x-360)*0.5, canvas_size.y*0.76)
	result_label.modulate = Color(1, 1, 1, 0)
	result_label.show()
	result_tween = create_tween().set_parallel(true)
	result_tween.tween_property(result_label, "position:y", canvas_size.y*0.49, 1.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	result_tween.tween_property(result_label, "modulate:a", 1.0, 0.16)
	result_tween.tween_property(result_label, "modulate:a", 0.0, 0.65).set_delay(0.7)
	result_tween.chain().tween_callback(result_label.hide)

func _publish_controls() -> void:
	if plugin == null:
		return
	plugin.populateScrollViewFromJSONString(JSON.stringify([
		{"type": "text", "text": "Количество граней" if ru() else "Number of sides"},
		{"type": "spinner", "name": "dice_sides", "values": ["2 · Орёл / решка" if ru() else "2 · Heads / tails", "4", "6", "8", "10", "12", "20", "100"], "value": SIDES.find(sides)},
		{"type": "button", "name": "dice_roll", "text": "Бросить" if ru() else "Roll"}
	]))

func _on_control(cname: String, _id: String, _type: String, value: String) -> void:
	if cname == "dice_sides":
		var index := value.to_int()
		if index >= 0 and index < SIDES.size():
			set_sides(SIDES[index])
	elif cname == "dice_roll":
		roll()

func _on_locale(tag: String) -> void:
	locale = tag
	_refresh_text()
	_publish_controls()

func _on_moving(_x: float, _y: float) -> void:
	window_moved = true
	pressed = false
	ignore_tap_until = Time.get_ticks_msec() + 300

func _on_move_ended() -> void:
	# The host sends this signal for every ACTION_UP, including stationary taps.
	if not window_moved:
		return
	window_moved = false
	pressed = false
	ignore_tap_until = Time.get_ticks_msec() + 300

func _on_end() -> void:
	_save()
	plugin.gracefulEndNotify(0)

func _save() -> void:
	if plugin != null:
		plugin.saveWidgetData(SAVE_KEY, JSON.stringify({"sides": sides, "result": result}))

func set_sides(count: int) -> void:
	if count not in SIDES or count == sides:
		return
	sides = count
	result = 1
	rolling = false
	set_process(false)
	_rebuild()
	_save()

func _material(color: Color, metal: float = 0.15) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metal
	mat.roughness = 0.32
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat

func _rebuild() -> void:
	_hide_result()
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	faces.clear()
	face_meshes.clear()
	face_materials.clear()
	body.position = Vector3.ZERO
	body.scale = Vector3.ONE * 0.9
	if sides == 2:
		_build_coin()
	else:
		faces = _geometry(sides)
		for i in faces.size():
			_build_face(faces[i], i)
	settle = _result_rotation(result)
	body.quaternion = settle
	_highlight_result()
	_refresh_text()

func _geometry(count: int) -> Array:
	var vertices: Array[Vector3] = []
	var phi := (1.0 + sqrt(5.0)) / 2.0
	match count:
		4:
			vertices.assign([Vector3(1,1,1), Vector3(-1,-1,1), Vector3(-1,1,-1), Vector3(1,-1,-1)])
		6:
			for x in [-1, 1]:
				for y in [-1, 1]:
					for z in [-1, 1]:
						vertices.append(Vector3(x,y,z))
		8:
			vertices.assign([Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK])
		12:
			for x in [-1, 1]:
				for y in [-1, 1]:
					for z in [-1, 1]:
						vertices.append(Vector3(x,y,z))
			for a in [-1, 1]:
				for b in [-1, 1]:
					vertices.append(Vector3(0, a / phi, b * phi))
					vertices.append(Vector3(a / phi, b * phi, 0))
					vertices.append(Vector3(b * phi, 0, a / phi))
		20:
			for a in [-1, 1]:
				for b in [-1, 1]:
					vertices.append(Vector3(0, a, b * phi))
					vertices.append(Vector3(a, b * phi, 0))
					vertices.append(Vector3(b * phi, 0, a))
		_:
			# Even-sided bipyramid: exactly count numbered triangular faces.
			var polygons: Array = []
			var ring := count / 2
			for i in ring:
				var a := Vector3(cos(TAU * i / ring), 0, sin(TAU * i / ring)) * 1.22
				var b := Vector3(cos(TAU * (i+1) / ring), 0, sin(TAU * (i+1) / ring)) * 1.22
				polygons.append([Vector3(0,1.3,0), a, b])
				polygons.append([Vector3(0,-1.3,0), b, a])
			return polygons
	for i in vertices.size():
		vertices[i] = vertices[i].normalized() * 1.3
	return _convex_faces(vertices)

func _convex_faces(vertices: Array[Vector3]) -> Array:
	var polygons: Array = []
	var found := {}
	for a in vertices.size():
		for b in range(a+1, vertices.size()):
			for c in range(b+1, vertices.size()):
				var normal := (vertices[b]-vertices[a]).cross(vertices[c]-vertices[a]).normalized()
				if normal.length_squared() < 0.5:
					continue
				var distance := normal.dot(vertices[a])
				if distance < 0:
					normal = -normal
					distance = -distance
				var indices: Array[int] = []
				var outside := false
				for i in vertices.size():
					var delta := normal.dot(vertices[i]) - distance
					if delta > 0.001:
						outside = true
						break
					if absf(delta) < 0.001:
						indices.append(i)
				if outside or found.has(str(indices)):
					continue
				found[str(indices)] = true
				var center := normal * distance
				var u := (vertices[indices[0]] - center).normalized()
				var v := normal.cross(u)
				indices.sort_custom(func(i, j): return atan2((vertices[i]-center).dot(v), (vertices[i]-center).dot(u)) < atan2((vertices[j]-center).dot(v), (vertices[j]-center).dot(u)))
				var polygon: Array = []
				for i in indices:
					polygon.append(vertices[i])
				polygons.append(polygon)
	return polygons

func _face_normal(polygon: Array) -> Vector3:
	var normal: Vector3 = (polygon[1]-polygon[0]).cross(polygon[2]-polygon[0]).normalized()
	return normal if normal.dot(polygon[0]) > 0 else -normal

func _build_face(polygon: Array, index: int) -> void:
	var normal := _face_normal(polygon)
	var center := Vector3.ZERO
	for vertex in polygon:
		center += vertex
	center /= polygon.size()
	var mesh := MeshInstance3D.new()
	mesh.mesh = load("res://meshes/d%d-face%d.res" % [sides, index+1])
	mesh.transform = Transform3D(_face_basis(normal), center)
	for surface_index in mesh.mesh.get_surface_count():
		var material: StandardMaterial3D = mesh.mesh.surface_get_material(surface_index)
		if material.resource_name == "FacePaint":
			var paint: StandardMaterial3D = material.duplicate()
			mesh.set_surface_override_material(surface_index, paint)
			face_materials.append(paint)
	body.add_child(mesh)
	face_meshes.append(mesh)

func _face_basis(normal: Vector3) -> Basis:
	var up := Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	return Basis.looking_at(-normal, up)

func _build_coin() -> void:
	var mesh := MeshInstance3D.new()
	mesh.mesh = load("res://meshes/coin-edge.res")
	body.add_child(mesh)
	for side in [1, -1]:
		var polygon: Array = []
		for i in 96:
			polygon.append(Vector3(cos(TAU*i/96)*1.15, sin(TAU*i/96)*1.15, side*0.14))
		_build_face(polygon, 0 if side == 1 else 1)

func _result_rotation(number: int) -> Quaternion:
	var normal := (Vector3.BACK if number == 1 else Vector3.FORWARD) if sides == 2 else _face_normal(faces[number-1])
	var upright_target := Basis.looking_at(-FACE_DIRECTION.normalized(), Vector3.UP)
	return (upright_target * _face_basis(normal).inverse()).get_rotation_quaternion()

func _highlight_result() -> void:
	for i in face_materials.size():
		var paint := face_materials[i]
		var base := Color("e5b34e") if sides == 2 else Color("5369ce")
		paint.albedo_color = base.lerp(Color("8cafff") if sides != 2 else Color("ffe3a0"), 0.23) if not rolling and i == result-1 else base

func roll() -> void:
	if rolling:
		return
	result = rng.randi_range(1, sides)
	rolling = true
	_hide_result()
	_highlight_result()
	elapsed = 0.0
	spin_start = body.rotation
	spin_end = spin_start + Vector3(TAU * rng.randi_range(3, 5), TAU * rng.randi_range(2, 4), TAU)
	settle = _result_rotation(result)
	_refresh_text()
	set_process(true)

func _process(delta: float) -> void:
	if not rolling:
		return
	elapsed = minf(elapsed + delta, DURATION)
	var t := elapsed / DURATION
	if t < 0.72:
		var p := t / 0.72
		body.rotation = spin_start.lerp(spin_end, 1.0 - pow(1.0-p, 2.0))
	else:
		var p := (t-0.72)/0.28
		body.quaternion = Quaternion.from_euler(spin_end).slerp(settle, smoothstep(0.0, 1.0, p))
	body.position.y = sin(t * PI) * 0.25 + absf(sin(t * PI * 3)) * (1.0-t) * 0.08
	if t >= 1:
		body.quaternion = settle
		body.position = Vector3.ZERO
		rolling = false
		set_process(false)
		_highlight_result()
		_refresh_text()
		_show_result()
		_save()

func _input(event: InputEvent) -> void:
	# Touch and mouse share one gesture; Android's synthetic mouse events are ignored.
	if event is InputEventScreenTouch:
		_tap(event.pressed, event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.device != InputEvent.DEVICE_ID_EMULATION:
		_tap(event.pressed, event.position)

func _tap(down: bool, point: Vector2) -> void:
	if down:
		pressed = touch_region.has_point(point)
		pressed_at = point
		press_time = Time.get_ticks_msec()
	else:
		var now := Time.get_ticks_msec()
		if pressed and now >= ignore_tap_until and now-press_time < 450 and point.distance_to(pressed_at) < 18:
			roll()
		pressed = false

func _capture() -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var args := OS.get_cmdline_user_args()
	var path := args[args.find("--capture")+1]
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()
