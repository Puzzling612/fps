# nav_baker.gd — runtime NavMesh baker for the level.
# The walkable geometry lives as siblings (Ground, Building, Cover, ...), so we
# parse the whole scene root into a source-geometry buffer and bake from it.
# Baked once on _ready (deferred so all geometry exists).
extends NavigationRegion3D

func _ready() -> void:
	call_deferred("_bake_runtime")

func _bake_runtime() -> void:
	var nm: NavigationMesh = navigation_mesh
	if nm == null:
		push_warning("[NavBaker] no NavigationMesh assigned")
		return
	# Match the navigation map's voxel size to the mesh to avoid rasterization
	# mismatch warnings/edge errors.
	var map: RID = get_navigation_map()
	if map.is_valid():
		NavigationServer3D.map_set_cell_size(map, nm.cell_size)
		NavigationServer3D.map_set_cell_height(map, nm.cell_height)

	var src := NavigationMeshSourceGeometryData3D.new()
	var root: Node = get_tree().current_scene
	if root == null:
		root = get_parent()
	NavigationServer3D.parse_source_geometry_data(nm, src, root)
	NavigationServer3D.bake_from_source_geometry_data(nm, src)
	set_navigation_mesh(nm)
