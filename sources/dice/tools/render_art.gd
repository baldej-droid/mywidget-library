extends SceneTree

var stage: Node3D
var icon_mode := false

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var args := OS.get_cmdline_user_args()
	icon_mode = "--icon" in args
	root.size = Vector2i(512,512) if icon_mode else Vector2i(1200,600)
	root.content_scale_size = root.size
	root.transparent_bg = true
	stage = Node3D.new()
	root.add_child(stage)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_CLEAR_COLOR
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("c4d1ff")
	world.environment.ambient_light_energy = 0.65
	stage.add_child(world)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-25,-30,0)
	key.light_energy = 1.25
	stage.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(20,135,-20)
	rim.light_color = Color("a4c5ff")
	rim.light_energy = 0.9
	stage.add_child(rim)
	if icon_mode:
		add_die(6,6,Vector3(0,0,0),1.22)
	else:
		add_die(20,20,Vector3(-2.5,0.05,-0.65),0.92)
		add_die(6,6,Vector3(0,-0.02,0.35),1.22)
		add_die(2,1,Vector3(2.65,0.0,-0.35),1.02)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = 3.6 if icon_mode else 4.2
	camera.position = Vector3(0,0,7)
	stage.add_child(camera)
	camera.current = true
	root.msaa_3d = Viewport.MSAA_4X
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var output: String = args[args.find("--output")+1]
	var error := root.get_texture().get_image().save_png(output)
	quit(0 if error == OK else 1)

func add_die(count: int, number: int, position: Vector3, scale_factor: float) -> void:
	var source = load("res://main.tscn").instantiate()
	root.add_child(source)
	source.sides = count
	source.result = number
	source._rebuild()
	var model: Node3D = source.body
	source.remove_child(model)
	stage.add_child(model)
	model.position = position
	model.scale = Vector3.ONE * scale_factor
	source.queue_free()
