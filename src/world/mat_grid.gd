class_name MatGrid
extends VoxelGrid
## 带方块种类的体素网格：每个体素额外记录一个方块种类（BlockTex.K_*），供 BlockMesher 选择纹理层。
## 用法：绘制前设置 kind，之后经 set_raw / set_color / fill_* 写入的体素都记为该种类。

var mat := PackedByteArray()
## 当前绘制使用的方块种类
var kind := 0


func _init(size_x: int = 16, size_y: int = 16, size_z: int = 16) -> void:
	super(size_x, size_y, size_z)
	mat.resize(sx * sy * sz)


func set_raw(x: int, y: int, z: int, v: int) -> void:
	if x < 0 or y < 0 or z < 0 or x >= sx or y >= sy or z >= sz:
		return
	var i := x + sx * (y + sy * z)
	data[i] = v
	mat[i] = kind


func get_kind(x: int, y: int, z: int) -> int:
	if x < 0 or y < 0 or z < 0 or x >= sx or y >= sy or z >= sz:
		return 0
	return mat[x + sx * (y + sy * z)]


## 只改种类（已有体素）：范围 [a, b]
func paint_kind(a: Vector3i, b: Vector3i, k: int) -> void:
	for z in range(maxi(mini(a.z, b.z), 0), mini(maxi(a.z, b.z), sz - 1) + 1):
		for y in range(maxi(mini(a.y, b.y), 0), mini(maxi(a.y, b.y), sy - 1) + 1):
			for x in range(maxi(mini(a.x, b.x), 0), mini(maxi(a.x, b.x), sx - 1) + 1):
				var i := x + sx * (y + sy * z)
				if data[i] != 0:
					mat[i] = k


func duplicate_grid() -> VoxelGrid:
	var g := MatGrid.new(sx, sy, sz)
	g.data = data.duplicate()
	g.mat = mat.duplicate()
	g.kind = kind
	return g


## 2× 降采样（远景 LOD）：8 个子体素中 ≥3 个实心则实心，颜色与种类取第一个实心（优先上层）
func downsampled() -> MatGrid:
	var nx := (sx + 1) / 2
	var ny := (sy + 1) / 2
	var nz := (sz + 1) / 2
	var o := MatGrid.new(nx, ny, nz)
	for z in nz:
		for y in ny:
			for x in nx:
				var cnt := 0
				var first := 0
				var fk := 0
				for dz in 2:
					for dy in 2:
						for dx in 2:
							var xx := x * 2 + dx
							var yy := y * 2 + dy
							var zz := z * 2 + dz
							if xx >= sx or yy >= sy or zz >= sz:
								continue
							var i := xx + sx * (yy + sy * zz)
							var v := data[i]
							if v != 0:
								cnt += 1
								if first == 0 or dy == 1:
									first = v
									fk = mat[i]
				if cnt >= 3:
					o.kind = fk
					o.set_raw(x, y, z, first)
	return o
