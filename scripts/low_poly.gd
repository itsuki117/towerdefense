class_name LowPoly
extends RefCounted
## ローポリの塊メッシュを作る小さな道具箱。
##
## 岩・茂み・敵は「球を粗く割って頂点をずらしただけ」で作っている。
## 同じ作り方をあちこちに書くと手癖がずれていくので、ここに集約する。
##
## 面ごとの法線（フラットシェーディング）にするのが肝。面の向きごとに
## 明るさが変わるので、テクスチャが無くても情報量が出る。


## 球をつぶして頂点をずらした塊。底は平らにして地面に接地させる。
##
## 頂点カラーには陰影のむらだけを入れ、色そのものはマテリアルの
## albedo_color 側で掛ける（同じメッシュを色違いで使い回せる）。
static func blob(size: Vector3, color: Color, wobble: float, salt: float = 0.0) -> ArrayMesh:
	var source := SphereMesh.new()
	source.radial_segments = 6
	source.rings = 3
	source.radius = 0.5
	source.height = 1.0
	var arrays := source.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	for i in indices.size():
		var vertex := vertices[indices[i]]
		# ずらす量は座標から決める。同じ位置の頂点は同じだけ動くので継ぎ目が割れない。
		vertex += Vector3(
			hash_offset(vertex, salt),
			hash_offset(vertex, salt + 11.0),
			hash_offset(vertex, salt + 23.0)
		) * wobble
		vertex *= size * 2.0
		# 埋まって見えるよう、底を持ち上げて平らにする。
		vertex.y = maxf(vertex.y, -size.y * 0.55) + size.y * 0.5
		var shade := hash_offset(vertex, salt + 5.0)
		st.set_color(color.darkened(maxf(-shade, 0.0) * 0.28))
		st.add_vertex(vertex)
	st.generate_normals()
	st.set_material(vertex_color_material())
	return st.commit()


## PrimitiveMesh の三角形を、色を付けながら SurfaceTool へ流し込む。
static func append_shape(
	st: SurfaceTool, source: PrimitiveMesh, offset: Vector3, color: Color
) -> void:
	var arrays := source.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for i in indices.size():
		st.set_color(color)
		st.add_vertex(vertices[indices[i]] + offset)


## 頂点カラーをそのまま色として使う、つや消しのマテリアル。
static func vertex_color_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return material


## 座標から決まる -1〜1 の値。毎回同じ形になるようにするため。
static func hash_offset(point: Vector3, salt: float) -> float:
	var value := sin(point.x * 27.13 + point.y * 91.7 + point.z * 53.31 + salt) * 43758.5453
	return (value - floor(value)) * 2.0 - 1.0
