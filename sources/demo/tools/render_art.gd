extends SceneTree

class Artwork extends Node2D:
	var icon := false
	func _draw() -> void:
		var offset := Vector2.ZERO if icon else Vector2(344,30)
		draw_set_transform(offset,0,Vector2.ONE*(1.0 if icon else 1.05))
		var chip := StyleBoxFlat.new()
		chip.bg_color = Color("1b263f")
		chip.border_color = Color("8cb6ff")
		chip.set_border_width_all(5)
		chip.set_corner_radius_all(44)
		draw_style_box(chip,Rect2(68,68,376,376))
		for i in 5:
			var p := 126+i*65
			draw_line(Vector2(p,44),Vector2(p,68),Color("8cb6ff"),9,true)
			draw_line(Vector2(p,444),Vector2(p,468),Color("8cb6ff"),9,true)
			draw_line(Vector2(44,p),Vector2(68,p),Color("8cb6ff"),9,true)
			draw_line(Vector2(444,p),Vector2(468,p),Color("8cb6ff"),9,true)
		draw_string(ThemeDB.fallback_font,Vector2(132,276),"API",HORIZONTAL_ALIGNMENT_LEFT,-1,104,Color.WHITE)
		draw_line(Vector2(142,334),Vector2(370,334),Color("3e5279"),12,true)
		draw_line(Vector2(142,334),Vector2(288,334),Color("89d9b1"),12,true)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var icon := "--icon" in args
	root.size = Vector2i(512,512) if icon else Vector2i(1200,600)
	root.content_scale_size = root.size
	root.transparent_bg = true
	RenderingServer.set_default_clear_color(Color.TRANSPARENT)
	var art := Artwork.new()
	art.icon = icon
	root.add_child(art)
	await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(args[args.find("--output")+1])
	quit(0 if error == OK else 1)
