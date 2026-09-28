extends Node
## 音效播放（autoload: Audio）。音效文件位于 res://assets/audio/sfx/<name>.wav，
## 由 tools/gen_sfx.py 程序化生成，缺失的音效会被静默忽略。

const SFX_DIR := "res://assets/audio/sfx/"
const POOL_2D := 12
const POOL_3D := 32

var _cache: Dictionary = {}
var _players_2d: Array[AudioStreamPlayer] = []
var _players_3d: Array[AudioStreamPlayer3D] = []
var _next_2d := 0
var _next_3d := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players_2d.append(p)
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 12.0
		p.max_distance = 140.0
		p.attenuation_filter_cutoff_hz = 8000.0
		add_child(p)
		_players_3d.append(p)


func _stream(sfx_name: String) -> AudioStream:
	if _cache.has(sfx_name):
		return _cache[sfx_name]
	var path := SFX_DIR + sfx_name + ".wav"
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path)
	_cache[sfx_name] = s
	return s


## 播放界面/非空间音效
func play(sfx_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var s := _stream(sfx_name)
	if s == null:
		return
	var p := _players_2d[_next_2d]
	_next_2d = (_next_2d + 1) % POOL_2D
	p.stream = s
	p.volume_db = volume_db + linear_to_db(maxf(Settings.sfx_volume, 0.0001))
	p.pitch_scale = pitch
	p.play()


## 在世界坐标播放 3D 音效，pitch 随机浮动 ±variance
func play_at(sfx_name: String, pos: Vector3, volume_db: float = 0.0, variance: float = 0.08) -> void:
	var s := _stream(sfx_name)
	if s == null:
		return
	var p := _players_3d[_next_3d]
	_next_3d = (_next_3d + 1) % POOL_3D
	p.stream = s
	p.global_position = pos
	p.volume_db = volume_db + linear_to_db(maxf(Settings.sfx_volume, 0.0001))
	p.pitch_scale = 1.0 + randf_range(-variance, variance)
	p.play()
