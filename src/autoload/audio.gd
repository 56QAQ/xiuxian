extends Node
## 音频（autoload: Audio）。
## 音效：res://assets/audio/sfx/<name>.wav，由 tools/gen_sfx.py 程序化生成；缺失的音效会被静默忽略。
## 音乐：res://assets/audio/music/<name>.ogg，由 tools/gen_music.py 生成的无缝循环曲目
##   （music_menu / music_overworld / music_battle / music_realm）。
##   play_music() 在两个 AudioStreamPlayer 之间交叉淡入淡出；音量取 Settings.music_volume，设置变化时自动跟随。

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"
const POOL_2D := 12
const POOL_3D := 32

var _cache: Dictionary = {}
var _players_2d: Array[AudioStreamPlayer] = []
var _players_3d: Array[AudioStreamPlayer3D] = []
var _next_2d := 0
var _next_3d := 0

## 音乐：两个播放器轮流担任“当前”，用于交叉淡变
var _music_players: Array[AudioStreamPlayer] = []
var _music_levels: Array[float] = [0.0, 0.0]
var _music_tweens: Array[Tween] = [null, null]
var _music_active := 0
var _music_name := ""
var _music_volume_seen := -1.0


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
	for i in 2:
		var mp := AudioStreamPlayer.new()
		mp.name = "Music%d" % i
		if AudioServer.get_bus_index("Music") >= 0:
			mp.bus = "Music"
		add_child(mp)
		_music_players.append(mp)
		_apply_music_level(i)
	_music_volume_seen = Settings.music_volume


func _process(_delta: float) -> void:
	# 设置界面修改音乐音量后立即生效（Settings 没有信号，这里轮询一个浮点数，开销可忽略）
	if not is_equal_approx(_music_volume_seen, Settings.music_volume):
		_music_volume_seen = Settings.music_volume
		for i in _music_players.size():
			_apply_music_level(i)


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


# ---------------------------------------------------------------- 音乐

## 播放背景音乐（循环）。与当前曲目交叉淡变 fade 秒；同一曲目正在播放时不做任何事。
## music_name 为空等同于 stop_music(fade)。文件缺失时静默忽略。
func play_music(music_name: String, fade: float = 1.0) -> void:
	if music_name == "":
		stop_music(fade)
		return
	if music_name == _music_name and _music_players[_music_active].playing:
		return
	var s := _music_stream(music_name)
	if s == null:
		return
	var old := _music_active
	var nxt := 1 - old
	_kill_music_tween(nxt)
	_music_name = music_name
	_music_active = nxt
	var p := _music_players[nxt]
	p.stream = s
	_set_music_level(0.0, nxt)
	p.play()
	_fade_music(nxt, 1.0, fade)
	_fade_music(old, 0.0, fade)


## 淡出并停止背景音乐
func stop_music(fade: float = 1.0) -> void:
	_music_name = ""
	for i in _music_players.size():
		_fade_music(i, 0.0, fade)


## 当前（或正在淡入的）曲目名，没有则为空
func current_music() -> String:
	return _music_name


func is_music_playing() -> bool:
	return _music_name != "" and _music_players[_music_active].playing


func _music_stream(music_name: String) -> AudioStream:
	var key := "music:" + music_name
	if _cache.has(key):
		return _cache[key]
	var path := MUSIC_DIR + music_name + ".ogg"
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path)
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
		(s as AudioStreamOggVorbis).loop_offset = 0.0
	elif s is AudioStreamWAV:
		(s as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	_cache[key] = s
	return s


func _kill_music_tween(i: int) -> void:
	var tw: Tween = _music_tweens[i]
	if tw != null and tw.is_valid():
		tw.kill()
	_music_tweens[i] = null


func _fade_music(i: int, target: float, fade: float) -> void:
	_kill_music_tween(i)
	var p := _music_players[i]
	if fade <= 0.0 or not p.playing:
		_set_music_level(target, i)
		if target <= 0.0:
			p.stop()
		return
	var tw := create_tween()
	tw.tween_method(_set_music_level.bind(i), _music_levels[i], target, fade)
	if target <= 0.0:
		tw.tween_callback(p.stop)
	_music_tweens[i] = tw


func _set_music_level(level: float, i: int) -> void:
	_music_levels[i] = level
	_apply_music_level(i)


func _apply_music_level(i: int) -> void:
	var v := _music_levels[i] * maxf(Settings.music_volume, 0.0)
	_music_players[i].volume_db = linear_to_db(maxf(v, 0.0001))
