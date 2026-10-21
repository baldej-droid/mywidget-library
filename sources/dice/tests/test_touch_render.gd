extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var dice = load("res://main.tscn").instantiate()
	root.add_child(dice)
	for window_size in [Vector2i(360,420), Vector2i(540,630), Vector2i(420,360)]:
		root.size = window_size
		for count in dice.SIDES:
			dice.set_sides(count)
			await process_frame
			await RenderingServer.frame_post_draw
			dice._update_touch_region()
			var region: Rect2 = dice.touch_region
			var canvas: Rect2 = root.get_visible_rect()
			if not region.has_area() or region.get_area() >= canvas.get_area()*0.8:
				push_error("Touch limiter still covers the window for d%d at %s: %s" % [count,window_size,region])
				quit(1)
				return
			dice._tap(true,canvas.position+Vector2(2,2))
			dice._tap(false,canvas.position+Vector2(2,2))
			if dice.rolling:
				push_error("Transparent margin rolled d%d" % count)
				quit(1)
				return
			dice._tap(true,region.get_center())
			dice._tap(false,region.get_center())
			if not dice.rolling:
				push_error("Visible model no longer accepts taps")
				quit(1)
				return
			dice._process(2.0)
			dice._hide_result()
	print("TOUCH RENDER CHECKS PASSED: all 8 models, 3 window sizes, transparent margins, model taps")
	dice.queue_free()
	await process_frame
	quit()
