extends SceneTree

var geometry = preload("res://main.gd").new()
var paint: StandardMaterial3D
var ink: StandardMaterial3D
var bevel: StandardMaterial3D

func _initialize() -> void:
	run.call_deferred()

func material(color: Color, name_tag: String, metallic: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = 0.34
	mat.resource_name = name_tag
	return mat

func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://meshes")
	for count in geometry.SIDES:
		var coin: bool = count == 2
		paint = material(Color("e5b34e") if coin else Color("5369ce"), "FacePaint", 0.55 if coin else 0.16)
		ink = material(Color("fff0bc") if coin else Color("f4f1ff"), "EngravedInk", 0.1)
		bevel = material(Color("c18a32") if coin else Color("465bb9"), "Bevel", 0.55 if coin else 0.18)
		var polygons: Array = geometry._geometry(count) if not coin else []
		if coin:
			for side in [1, -1]:
				var polygon: Array = []
				for i in 96:
					polygon.append(Vector3(cos(TAU*i/96)*1.15, sin(TAU*i/96)*1.15, side*0.14))
				polygons.append(polygon)
		for index in polygons.size():
			await bake_face(polygons[index], count, index+1)
		if coin:
			bake_coin_edge()
		print("BAKED D", count, " · ", polygons.size(), " engraved faces")
	geometry.free()
	quit()

func triangle(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void:
	# Godot front faces use clockwise winding viewed from outside.
	var vertices: Array = [a,c,b] if (b-a).cross(c-a).dot(normal) > 0 else [a,b,c]
	for vertex in vertices:
		tool.set_normal(normal)
		tool.add_vertex(vertex)

func slab(points: Array[Vector2], depth: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(1, points.size()-1):
		triangle(surface, Vector3(points[0].x,points[0].y,0), Vector3(points[i].x,points[i].y,0), Vector3(points[i+1].x,points[i+1].y,0), Vector3.BACK)
		triangle(surface, Vector3(points[0].x,points[0].y,-depth), Vector3(points[i].x,points[i].y,-depth), Vector3(points[i+1].x,points[i+1].y,-depth), Vector3.FORWARD)
	for i in points.size():
		var j := (i+1)%points.size()
		var a := Vector3(points[i].x,points[i].y,0)
		var b := Vector3(points[j].x,points[j].y,0)
		var normal := Vector3((points[i]+points[j]).x, (points[i]+points[j]).y, 0).normalized()
		triangle(surface, a,b,b-Vector3(0,0,depth),normal)
		triangle(surface, a,b-Vector3(0,0,depth),a-Vector3(0,0,depth),normal)
	return surface.commit()

func bake_face(polygon: Array, count: int, number: int) -> void:
	var normal: Vector3 = geometry._face_normal(polygon)
	var center := Vector3.ZERO
	for vertex in polygon:
		center += vertex
	center /= polygon.size()
	var local_basis: Basis = geometry._face_basis(normal)
	var points: Array[Vector2] = []
	var outer: Array[Vector3] = []
	var coin: bool = count == 2
	for vertex in polygon:
		var local: Vector3 = local_basis.inverse() * (vertex-center)
		points.append(Vector2(local.x, local.y) * (0.955 if coin else 0.94))
		outer.append(Vector3(local.x,local.y,-0.045) if coin else local_basis.inverse()*(vertex*0.973-center))
	var cap := CSGMesh3D.new()
	cap.mesh = slab(points, 0.10)
	cap.material = paint
	root.add_child(cap)
	var text := TextMesh.new()
	text.font = ThemeDB.fallback_font
	text.font_size = 96
	text.pixel_size = 0.009 if coin else (0.007 if count <= 12 else (0.0045 if count == 20 else 0.0014))
	text.text = str(number) + ("." if number in [6,9] else "")
	text.depth = 0.065
	text.material = ink
	var bounds := text.get_aabb()
	# Fit narrow triangular faces without letting a glyph cross their bevels.
	var minimum_edge_distance := INF
	for i in points.size():
		var a := points[i]
		var b := points[(i+1)%points.size()]
		minimum_edge_distance = minf(minimum_edge_distance, absf(a.cross(b)) / a.distance_to(b))
	var fit := minf(1.0, minimum_edge_distance*1.25 / maxf(bounds.size.x, bounds.size.y))
	var cutter := CSGMesh3D.new()
	cutter.mesh = text
	cutter.material = ink
	cutter.operation = CSGShape3D.OPERATION_SUBTRACTION
	cutter.scale = Vector3(fit,fit,1)
	cutter.position = Vector3(-bounds.get_center().x*fit, -bounds.get_center().y*fit, -0.018)
	cap.add_child(cutter)
	await process_frame
	await process_frame
	var baked: ArrayMesh = cap.bake_static_mesh()
	assert(baked != null and baked.get_surface_count() >= 2, "Engraving CSG failed")
	var edge := SurfaceTool.new()
	edge.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in points.size():
		var j := (i+1)%points.size()
		var a := Vector3(points[i].x, points[i].y, 0)
		var b := Vector3(points[j].x, points[j].y, 0)
		var n := (b-a).cross(outer[i]-a).normalized()
		if n.z < 0:
			n = -n
		triangle(edge,a,b,outer[j],n)
		triangle(edge,a,outer[j],outer[i],n)
	edge.set_material(bevel)
	edge.commit(baked)
	var error := ResourceSaver.save(baked,"res://meshes/d%d-face%d.res" % [count,number], ResourceSaver.FLAG_COMPRESS)
	assert(error == OK)
	cap.queue_free()
	await process_frame

func bake_coin_edge() -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 96:
		var angle_a := TAU*i/96
		var angle_b := TAU*(i+1)/96
		var a := Vector3(cos(angle_a)*1.15,sin(angle_a)*1.15,0.095)
		var b := Vector3(cos(angle_b)*1.15,sin(angle_b)*1.15,0.095)
		var normal := Vector3(cos((angle_a+angle_b)*0.5),sin((angle_a+angle_b)*0.5),0)
		triangle(surface,a,b,b-Vector3(0,0,0.19),normal)
		triangle(surface,a,b-Vector3(0,0,0.19),a-Vector3(0,0,0.19),normal)
	surface.set_material(bevel)
	ResourceSaver.save(surface.commit(),"res://meshes/coin-edge.res", ResourceSaver.FLAG_COMPRESS)
