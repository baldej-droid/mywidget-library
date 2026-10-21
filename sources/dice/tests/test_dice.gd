extends SceneTree

var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var dice = load("res://main.tscn").instantiate()
	root.add_child(dice)
	await process_frame
	for count in dice.SIDES:
		dice.set_sides(count)
		check(dice.faces.size() == (0 if count == 2 else count), "Incorrect face count for d%d" % count)
		if count != 2:
			for number in range(1, count+1):
				var normal: Vector3 = dice._face_normal(dice.faces[number-1])
				check((dice._result_rotation(number) * normal).distance_to(dice.FACE_DIRECTION.normalized()) < 0.001, "Result face is not facing camera")
				var digit_basis: Basis = Basis(dice._result_rotation(number)) * dice._face_basis(normal)
				check(digit_basis.y.dot(Vector3.UP) > 0.9, "Result digit is upside down")
		check(not dice.result_label.visible, "Persistent overlay label remains")
		check(dice.face_materials.size() == count, "Missing paint material or face")
		for mesh in dice.face_meshes:
			check(mesh.mesh.get_surface_count() >= 3, "Engraving or bevel surface missing")
			var has_recess := false
			for surface_index in mesh.mesh.get_surface_count():
				if mesh.mesh.surface_get_material(surface_index).resource_name == "EngravedInk":
					var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(surface_index)[Mesh.ARRAY_VERTEX]
					for vertex in vertices:
						if vertex.z < -0.025:
							has_recess = true
			check(has_recess, "Painted numeral has no inward extrusion")
		for n in 30:
			dice.roll()
			var chosen: int = dice.result
			check(chosen >= 1 and chosen <= count, "Out-of-range roll")
			dice.roll()
			check(dice.result == chosen, "Repeated tap changed active roll")
			dice._process(0.5)
			check(dice.rolling and not dice.result_label.visible, "Result appeared before animation finished")
			dice._process(2.0)
			check(not dice.rolling and dice.body.position == Vector3.ZERO, "Animation failed to settle")
			check(absf(dice.body.quaternion.dot(dice._result_rotation(chosen))) > 0.999, "Final orientation disagrees with result")
			check(dice.result_label.visible and dice.result_label.text == str(chosen), "Result popup missing")
			check(dice.face_materials[chosen-1].albedo_color != dice.face_materials[0 if chosen != 1 else 1].albedo_color, "Result face is not highlighted")
			dice._hide_result()
	dice.set_sides(6)
	dice.roll()
	dice.set_sides(2)
	check(not dice.rolling and dice.result == 1, "Type change did not cancel roll")
	dice._on_locale("ru-RU")
	check(dice.ru() and not dice.result_label.visible, "Russian locale enabled a persistent caption")
	dice.result = 2
	dice._refresh_text()
	check(not dice.result_label.visible, "Notification refresh showed a caption")
	dice._on_locale("en-US")
	check(not dice.ru() and not dice.result_label.visible, "English locale enabled a persistent caption")
	var touch_image := Image.create(720, 840, false, Image.FORMAT_RGBA8)
	touch_image.fill(Color.TRANSPARENT)
	touch_image.fill_rect(Rect2i(200, 200, 320, 440), Color.WHITE)
	dice._apply_touch_image(touch_image)
	var canvas: Rect2 = dice.get_viewport().get_visible_rect()
	check(dice.touch_region.position.is_equal_approx(canvas.position + Vector2(200,200) * canvas.size / Vector2(720,840)), "Touch bounds did not scale from render pixels")
	check(dice.touch_region.size.is_equal_approx(Vector2(320,440) * canvas.size / Vector2(720,840)), "Touch bounds include transparent margins")
	dice._tap(true, Vector2(30,40))
	dice._tap(false, Vector2(30,40))
	check(not dice.rolling, "Transparent window margin triggered a roll")
	dice._tap(true, Vector2(180,210))
	dice._tap(false, Vector2(230,210))
	check(not dice.rolling, "Drag triggered roll")
	dice._tap(true, Vector2(180,210))
	dice._on_moving(100.0, 0.0)
	dice._on_move_ended()
	dice._tap(false, Vector2(180,210))
	check(not dice.rolling, "Window drag triggered roll")
	dice.ignore_tap_until = 0
	dice._tap(true, Vector2(180,210))
	dice._on_move_ended()
	dice._tap(false, Vector2(180,210))
	check(dice.rolling, "Host ACTION_UP signal blocked stationary tap")
	dice._process(2.0)
	var popup_start_y: float = dice.result_label.position.y
	await create_timer(0.3).timeout
	check(dice.result_label.visible and dice.result_label.position.y < popup_start_y, "Popup did not fly upward")
	await create_timer(1.2).timeout
	check(not dice.result_label.visible, "Popup did not disappear")
	touch_image.fill(Color.TRANSPARENT)
	dice._apply_touch_image(touch_image)
	check(not dice.touch_region.has_area(), "Empty frame retained a stale touch region")
	dice.set_sides(7)
	check(dice.sides == 2, "Unsupported face count accepted")
	if failures.is_empty():
		print("ALL DICE CHECKS PASSED: engraved beveled meshes, upright faces, highlight, 240 rolls, popup lifecycle, gestures, locale")
	dice.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

