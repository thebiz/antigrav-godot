# AntiGrav 3D – erste Godot-Version: Neon Night, ein Gleitermodell, drei Gegner, echte Beleuchtung,
# Bildschirm-Spiegelungen, Schatten, Glühen. Alles wird beim Start im Code aufgebaut.
extends Node3D

# gespeichertes Replay, das nach dem Neuladen der Szene abgespielt werden soll (bleibt über reload_current_scene erhalten)
static var pending_rp = ""
static var pending_free = false
static var pending_test = false
static var stt_spd = 1.0   # Tempo auf der Teststrecke (Anteil vom normalen Tempo)   # Neustart direkt in die Lenk-Teststrecke   # nach dem FX Lab gleich wieder ins Free ride (Live-Regler vom PC)
static var restart = false
static var bench_req = false   # Leistungstest: nach dem Neuladen direkt starten   # „Race again“: nach dem Neuladen direkt losfahren

const T = preload("res://track.gd")
# Gleiter: Datei, Name, Nase zeigt im Modell nach hinten (wird umgedreht), Herkunft
const SHIPS = [
	["res://ships/qirex.glb", "Qirex", false, "“WipeOut – Qirex” by Nobby76, CC BY 4.0"],
	["res://ships/assegai/scene.gltf", "Assegai", false, "“WipeOut – Assegai” by Nobby76, CC BY 4.0"],
	["res://ships/apex.glb", "Apex", false, "“Apex Wipeout Anti-grav Racer” by rafta, CC BY-NC 4.0"],
	["res://ships/rhsx/scene.gltf", "RHS-X", true, "“RHS-X” by Hassan Bassassi, CC BY 4.0"],
	["res://ships/r37.glb", "R-37", false, "“R-37” design by John Dammbacher, 3D via Tripo AI"]]
# Düsen je Schiff (im Schiffsraum: x, Höhe, z, Radius) – nachgemessen an den Modellen
const JETS = [
	[[0.0, 0.148, -0.76, 0.05], [-0.09, 0.1, -0.74, 0.03], [0.09, 0.1, -0.74, 0.03]],
	[[0.0, 0.133, -0.77, 0.05], [-0.09, 0.1, -0.74, 0.03], [0.09, 0.1, -0.74, 0.03]],
	[[-0.08, 0.075, -0.75, 0.042], [0.08, 0.075, -0.75, 0.042]],
	[[0.0, 0.11, -0.76, 0.05], [-0.184, 0.139, -0.72, 0.03], [0.184, 0.139, -0.72, 0.03]],
	[[-0.069, 0.145, -0.72, 0.042], [0.069, 0.145, -0.72, 0.042]]]
# Antigrav-Ringe unter dem Rumpf (wie Räder: zwei vorn, zwei hinten): Position, Radius
const RINGS = {4: [[Vector3(0.0, 0.012, 0.26), 0.062], [Vector3(0.115, 0.03, -0.43), 0.08], [Vector3(-0.115, 0.03, -0.43), 0.08]]}
# Behang (Cyber Gothic): je Schiff Ketten mit Anhängern, schwingen frei (Punkt im Schiffsraum, Glieder: Art + Länge)
const DANG = {4: [
	[Vector3(-0.24, 0.06, -0.245), [["link", 0.022], ["link", 0.022], ["knot", 0.024], ["tassel", 0.06]]],
	[Vector3(0.24, 0.06, -0.245), [["link", 0.022], ["link", 0.022], ["knot", 0.024], ["tassel", 0.06]]],
	[Vector3(-0.335, 0.16, -0.42), [["link", 0.026], ["link", 0.026], ["link", 0.026], ["link", 0.026], ["spike", 0.05]]],
	[Vector3(0.335, 0.16, -0.42), [["link", 0.026], ["link", 0.026], ["link", 0.026], ["link", 0.026], ["spike", 0.05]]]]}
const CFG_PATH = "user://settings.cfg"

# Lenkung wie in der HTML-Version (von John abgestimmt)
const RAMP = 0.56
const START = 0.55
const SHAPE = 2.3
const YAW_P = 1.4
const YAW_AI = 1.5
const INTRO_T = 3.2
const BASE_DEF = 12.0  # Grundtempo (Einheiten/s) bei Tempo 100 %
const NAMES = ["You", "Vega", "Kato", "Mira"]

var laps: Array[Node3D] = []
var lap_meshes = []
var bld_mm: MultiMesh
var cam: Camera3D
var ships: Array = []  # Zustand je Gleiter (Dictionary), [0] = du
var state = "menu"
var cfg = {"pads": 0, "ship": 0, "speed": 1.0, "gfx": 2, "glow": 0.5, "neon": 0.8, "vol": 0.9, "ai": 1.05, "look": 0, "res": 0.85, "fps": 0, "cap": 0, "perf": 0, "pname": "", "tips": 1, "tseen": "", "live": 0, "comic": 1, "hud": 2, "ctrl": 1}
var neon_mats = []  # [Material, Grundhelligkeit]
var snd = {}
var loops = {}
var base_spd = 12.0
var wenv: Environment
var moon: DirectionalLight3D
var ui = {}
var menu_t = 0.0
var last_c = 99
# Waffen und Energie (wie im alten Spiel)
const WP = [["rak", 0.2], ["lenk", 0.2], ["mine", 0.12], ["schild", 0.09], ["turbo", 0.11], ["beben", 0.08], ["auto", 0.05], ["wand", 0.07], ["orbs", 0.08]]
const WP_AI = [["lenk", 0.35], ["rak", 0.25], ["mine", 0.2], ["schild", 0.1], ["turbo", 0.1]]
# eigene Farbe je Waffe, damit man sie im Augenwinkel unterscheiden kann
const WC = {"rak": Color(1.0, 0.55, 0.12), "lenk": Color(1.0, 0.18, 0.22), "mine": Color(1.0, 0.86, 0.1), "orbs": Color(0.3, 0.6, 1.0),
	"wand": Color(0.1, 0.95, 0.85), "beben": Color(0.72, 0.32, 1.0), "schild": Color(0.35, 1.0, 0.45), "turbo": Color(1.0, 0.3, 0.75), "auto": Color(0.92, 0.92, 0.95)}
# kurze Erklärung je Waffe (Hinweise beim ersten Mal und „How to play“)
const WD = {"rak": "Flies straight ahead – aim by steering.", "lenk": "Locks onto the rival ahead and hits for sure.",
	"mine": "Drops mines behind you.", "schild": "Protects you from two hits.", "turbo": "A big burst of speed.",
	"beben": "A shock wave rolls ahead and throws rivals off course.", "auto": "Autopilot for 5 seconds – steers for you.",
	"wand": "An energy wall ahead – rivals flying through it get zapped.", "orbs": "Glowing orbs circle you and hit anyone close."}
const WN = {"rak": "ROCKET", "lenk": "HOMING", "mine": "MINES", "schild": "SHIELD", "turbo": "TURBO", "beben": "QUAKE", "auto": "AUTO", "wand": "FORCE FIELD", "orbs": "ORBS"}
var shots = []
var mines = []
var fxs = []
var walls = []
var quake = null
var quake2 = null   # Super-Quake: zweite Welle rollt nach hinten
var bwaves = []     # Super-Turbo: Druckwellen nach hinten
var fire_req = false
var fire_rect = Rect2()
var t_state = 0.0
var race_t = 0.0
var steer_btn = 0
var btn_t = 0.0
var rel_t = 9.0      # Zeit seit dem Loslassen
var rel_v = 0.0      # Lenkung beim Loslassen (klingt über die Loslass-Kurve ab)
var last_steer = 0.0
var st_hist = []     # gedrückte Seite mit Zeit, für die Eingabe-Verzögerung
var touches = {}
var hud = {}
var cam_psi = 0.0
var cam_d = 0.0


var rpf = {}   # geladenes Replay aus einer Datei


func _ready() -> void:
	if pending_rp != "":
		var fa = FileAccess.open_compressed(pending_rp, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
		if fa != null:
			var d = fa.get_var()
			if d is Dictionary and d.has("rec"):
				rpf = d
		pending_rp = ""
	Engine.time_scale = 1.0
	AudioServer.playback_speed_scale = 1.0
	_load_cfg()
	_fx_load()
	_curves_load()
	if OS.get_cmdline_user_args().has("--noir"):
		cfg.look = 1
	if OS.get_cmdline_user_args().has("--jungle"):
		cfg.look = 2
	T.J = _jungle()   # eigene Streckenführung im Dschungel
	T.S = pending_test or OS.get_cmdline_user_args().has("--steertest")
	if T.S:
		pending_test = false
		T.J = false
		free_ride = true
		_start.call_deferred()
	if OS.get_cmdline_user_args().has("--bench"):
		bench_req = true
	if OS.get_cmdline_user_args().has("--free"):
		free_ride = true
	if pending_free:
		pending_free = false
		free_ride = true
		_start.call_deferred()
	if OS.get_environment("SHOTAFTER") != "":
		# Testbild nach N Sekunden (zum Prüfen am Rechner)
		get_tree().create_timer(float(OS.get_environment("SHOTAFTER"))).timeout.connect(func():
			get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOTPATH"))
			get_tree().quit())
	if OS.get_cmdline_user_args().has("--settings"):
		_show_settings.call_deferred(true)
		if OS.get_environment("SHOTPATH") != "":
			get_tree().create_timer(4.0).timeout.connect(func():
				var sc: ScrollContainer = ui.setp
				if OS.get_environment("SCRTEST") != "":
					var tv0 = cfg.tips
					var steps = [[true, Vector2(360, 900)], [Vector2(360, 880)], [Vector2(360, 800)], [Vector2(360, 650)], [false, Vector2(360, 650)]]
					for st in steps:
						var e
						if st.size() == 2:
							e = InputEventScreenTouch.new()
							e.pressed = st[0]
							e.position = st[1]
						else:
							e = InputEventScreenDrag.new()
							e.position = st[0]
							e.relative = Vector2(0, -60)
						e.index = 0
						Input.parse_input_event(e)
						await get_tree().process_frame
						await get_tree().process_frame
					await get_tree().create_timer(0.8).timeout
					print("SCRTEST scroll=", sc.scroll_vertical, " cfg_changed=", cfg.tips != tv0, " speed=", cfg.speed)
				sc.scroll_vertical = int(OS.get_environment("SCROLL").to_int())
				await get_tree().create_timer(0.5).timeout
				get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOTPATH"))
				get_tree().quit())
	if OS.get_cmdline_user_args().has("--live"):
		cfg.live = 1
	if OS.get_cmdline_user_args().has("--howto"):
		_show_help.call_deferred(true)
	if OS.get_cmdline_user_args().has("--records"):
		_show_records.call_deferred(true)
	if OS.get_cmdline_user_args().has("--replays"):
		_show_replays.call_deferred(true)
	if OS.get_cmdline_user_args().has("--lab"):
		get_tree().create_timer(2.0).timeout.connect(func():
			_lab_open()
			if OS.get_environment("LABTAB") != "":
				_lab_tab(OS.get_environment("LABTAB")))
	if OS.get_cmdline_user_args().has("--toastdemo"):
		get_tree().create_timer(2.5).timeout.connect(func():
			_toast("Open " + _live_addr() + " in the PC browser (same Wi-Fi)")
			await get_tree().create_timer(0.6).timeout
			if OS.get_environment("SHOTPATH") != "":
				get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOTPATH"))
				get_tree().quit())
	if OS.get_cmdline_user_args().has("--namedemo"):
		_name_entry.call_deferred([["lap", 31.42, 0], ["dmg", 2.4, 2]])
	if _noir():
		CY = Color(0.9, 0.92, 0.95)
		MG = OR
		AM = OR
	if _jungle():
		# Biolumineszenz: Grün-Türkis links, Violett rechts, Bernstein für die Irrlichter
		CY = Color(0.2, 1.0, 0.65)
		MG = Color(0.75, 0.35, 1.0)
		AM = Color(1.0, 0.75, 0.3)
	# Feld-Verteilung: fest (0) oder je Rennen neu gewürfelt; ein Replay aus der Datei bringt seine eigene mit
	if not rpf.is_empty():
		pad_seed = int(rpf.get("ps", 0))
	else:
		pad_seed = (randi() % 2000000000) + 1 if int(cfg.pads) == 1 else 0
	_pads_gen()
	_env()
	_post()
	_build_track()
	_build_city()
	_spawn_ships()
	_nav_apply()
	cam = Camera3D.new()
	cam.fov = 52.0
	cam.near = 0.08
	cam.far = 400.0
	add_child(cam)
	_hud()
	_kc_overlay()
	_menu()
	_sounds()
	_apply_cfg()
	_env_apply()


# ---------------------------------------------------------------- Klänge aus dem alten Spiel (Dateien in sfx/)
# Zwei Kanäle: „Game“ (Motor, Effekte) und „Voice“ (Ansagen). Spricht die Stimme, wird „Game“ kurz abgesenkt (Ducking).
func _buses() -> void:
	for nm in ["Game", "Voice"]:
		if AudioServer.get_bus_index(nm) == -1:
			AudioServer.add_bus()
			var i = AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, nm)
			AudioServer.set_bus_send(i, "Master")
	var vi = AudioServer.get_bus_index("Voice")
	AudioServer.set_bus_volume_db(vi, 6.0)
	# Begrenzer, damit die lautere Stimme nicht übersteuert
	if AudioServer.get_bus_effect_count(vi) == 0:
		var lim = AudioEffectHardLimiter.new()
		lim.ceiling_db = -0.5
		AudioServer.add_bus_effect(vi, lim)


# ---------------------------------------------------------------- Startsound-Labor: eigener Kanal „Start“ mit Tonhöhe, Klang, Echo, Hall, Biss
# Countdown-Piepser und Startgrollen laufen über diesen Kanal; die Regler im Reiter „Sound“ wirken sofort.
# Dazu auf Wunsch eigene Synth-Piepser (Tonhöhe, Klangfarbe, GO-Anstieg), im Spiel erzeugt.
var start_prev = []   # gerade laufende Vorhör-Klänge
var synth_c = {}      # erzeugte Synth-Piepser (nach Einstellungen)


func _start_bus() -> int:
	var bi = AudioServer.get_bus_index("Start")
	if bi == -1:
		AudioServer.add_bus()
		bi = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bi, "Start")
		AudioServer.set_bus_send(bi, "Master")
		AudioServer.add_bus_effect(bi, AudioEffectPitchShift.new())   # 0 Tonhöhe (Tempo bleibt)
		AudioServer.add_bus_effect(bi, AudioEffectEQ6.new())          # 1 Bass/Höhen
		var ds = AudioEffectDistortion.new()                            # 2 Biss
		ds.mode = AudioEffectDistortion.MODE_OVERDRIVE
		AudioServer.add_bus_effect(bi, ds)
		AudioServer.add_bus_effect(bi, AudioEffectDelay.new())        # 3 Echo
		AudioServer.add_bus_effect(bi, AudioEffectReverb.new())       # 4 Hall
		var lim = AudioEffectHardLimiter.new()                          # 5 nichts übersteuert
		lim.ceiling_db = -0.5
		AudioServer.add_bus_effect(bi, lim)
	return bi


func _start_bus_apply() -> void:
	var S: Dictionary = fx.sound
	var bi = _start_bus()
	AudioServer.set_bus_volume_db(bi, linear_to_db(maxf(0.001, float(S.vol))))
	var ps: AudioEffectPitchShift = AudioServer.get_bus_effect(bi, 0)
	ps.pitch_scale = float(S.pitch)
	AudioServer.set_bus_effect_enabled(bi, 0, absf(float(S.pitch) - 1.0) > 0.01)
	var eq: AudioEffectEQ6 = AudioServer.get_bus_effect(bi, 1)
	var bs = (float(S.bass) - 1.0)
	var tr = (float(S.treble) - 1.0)
	var gains = [bs * 12.0, bs * 15.0, bs * 7.0, 0.0, tr * 10.0, tr * 15.0]
	for i in range(6):
		eq.set_band_gain_db(i, gains[i])
	AudioServer.set_bus_effect_enabled(bi, 1, absf(bs) > 0.01 or absf(tr) > 0.01)
	var ds: AudioEffectDistortion = AudioServer.get_bus_effect(bi, 2)
	var gr = float(S.grit)
	ds.drive = clampf(gr * 0.45, 0.0, 0.95)
	ds.post_gain = -gr * 5.0
	AudioServer.set_bus_effect_enabled(bi, 2, gr > 0.01)
	var dl: AudioEffectDelay = AudioServer.get_bus_effect(bi, 3)
	var ec = float(S.echo)
	var ms = 250.0 * float(S.etime)
	dl.tap1_active = true
	dl.tap1_delay_ms = ms
	dl.tap1_level_db = linear_to_db(maxf(0.001, ec * 0.5))
	dl.tap2_active = true
	dl.tap2_delay_ms = ms * 2.0
	dl.tap2_level_db = linear_to_db(maxf(0.001, ec * 0.28))
	dl.feedback_active = true
	dl.feedback_delay_ms = ms * 3.0
	dl.feedback_level_db = linear_to_db(maxf(0.001, ec * 0.18))
	AudioServer.set_bus_effect_enabled(bi, 3, ec > 0.01)
	var rv: AudioEffectReverb = AudioServer.get_bus_effect(bi, 4)
	rv.room_size = float(S.room)
	rv.wet = clampf(float(S.reverb) * 0.4, 0.0, 1.0)
	rv.dry = 1.0
	AudioServer.set_bus_effect_enabled(bi, 4, float(S.reverb) > 0.01)


# Synth-Piepser: kurzer Ton (3, 2, 1) oder langer GO-Ton mit Anstieg; Sinus bis rechteckig
func _synth(go: bool) -> AudioStreamWAV:
	var S: Dictionary = fx.sound
	var key = "%s|%.3f|%.3f|%.3f" % [go, float(S.spitch), float(S.sshape), float(S.sweep)]
	if synth_c.has(key):
		return synth_c[key]
	var sr = 22050
	var dur = 1.15 if go else 0.24
	var n = int(dur * sr)
	var f0 = (1320.0 if go else 880.0) * float(S.spitch)
	var sh = float(S.sshape)
	var sw = float(S.sweep) if go else 0.0
	var data = PackedByteArray()
	data.resize(n * 2)
	var ph = 0.0
	for i in range(n):
		var t = float(i) / sr
		var fq = f0 * (1.0 + sw * 0.35 * minf(t / 0.25, 1.0))
		ph += TAU * fq / sr
		var sn = sin(ph)
		var sq = clampf(sn * 6.0, -1.0, 1.0)
		var v = lerpf(sn, sq, sh) * 0.85 + sin(ph * 2.0) * 0.08
		var env = minf(t / 0.006, 1.0) * clampf((dur - t) / (0.25 if go else 0.05), 0.0, 1.0)
		data.encode_s16(i * 2, int(clampf(v * env, -1.0, 1.0) * 26000.0))
	var w = AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = sr
	w.stereo = false
	w.data = data
	if synth_c.size() > 16:
		synth_c.clear()
	synth_c[key] = w
	return w


func _start_snd(st: AudioStream, db: float, from := 0.0) -> AudioStreamPlayer:
	if st == null or warm:
		return null
	_start_bus()
	var p = AudioStreamPlayer.new()
	p.stream = st
	p.volume_db = db
	p.bus = "Start"
	add_child(p)
	p.play(from)
	p.finished.connect(p.queue_free)
	return p


# Countdown-Schritt im Rennen: c = 3, 2, 1 kurze Piepser, 0 = GO; beim ersten Schritt Original-Piepser und Grollen
func _start_step(c: int, first: bool) -> void:
	var S: Dictionary = fx.sound
	_start_bus_apply()
	if first:
		if float(S.beeps) > 0.01:
			_start_snd(snd.get("count"), linear_to_db(float(S.beeps)))
		if float(S.rumble) > 0.01:
			_start_snd(snd.get("start"), linear_to_db(float(S.rumble)))
	if float(S.synth) > 0.01:
		_start_snd(_synth(c <= 0), linear_to_db(float(S.synth)) - 4.0)


# Labor: ganzer Countdown (PLAY) oder kurzes Vorhören nach dem Verstellen (letzter Piepser + GO)
func _start_play(short: bool) -> void:
	for p in start_prev:
		if is_instance_valid(p):
			p.queue_free()
	start_prev.clear()
	var S: Dictionary = fx.sound
	_start_bus_apply()
	var t0 = 2.0 if short else 0.0
	if float(S.beeps) > 0.01:
		start_prev.append(_start_snd(snd.get("count"), linear_to_db(float(S.beeps)), t0))
	if float(S.rumble) > 0.01:
		start_prev.append(_start_snd(snd.get("start"), linear_to_db(float(S.rumble)), t0 * 0.5))
	if float(S.synth) > 0.01:
		var steps = [[0.0, 1], [1.0, 0]] if short else [[0.0, 3], [1.0, 2], [2.0, 1], [3.0, 0]]
		for stp in steps:
			var c: int = stp[1]
			if stp[0] <= 0.0:
				start_prev.append(_start_snd(_synth(c <= 0), linear_to_db(float(S.synth)) - 4.0))
			else:
				get_tree().create_timer(stp[0]).timeout.connect(func():
					if state == "lab":
						start_prev.append(_start_snd(_synth(c <= 0), linear_to_db(float(S.synth)) - 4.0)))


var duck_until = 0.0
var duck_db = 0.0


func _duck(delta: float) -> void:
	var now = Time.get_ticks_msec() / 1000.0
	var target = -14.0 if now < duck_until else 0.0
	var tau = 0.06 if target < duck_db else 0.45   # schnell runter, sanft wieder hoch
	duck_db += (target - duck_db) * (1.0 - exp(-delta / tau))
	var gi = AudioServer.get_bus_index("Game")
	if gi >= 0:
		AudioServer.set_bus_volume_db(gi, duck_db)


func _sounds() -> void:
	_buses()
	for n in ["boom.ogg", "count.ogg", "engine.wav", "idle.wav", "mine.ogg", "pick.ogg", "rak.ogg", "shield.ogg", "start.ogg", "win.ogg", "wallon.ogg",
			"boost.wav", "zap.wav", "beep.wav", "go.wav", "pass.wav", "land.wav", "field.wav", "gbomb.wav", "phase.wav",
			"vo_rak.wav", "vo_lenk.wav", "vo_mine.wav", "vo_orbs.wav", "vo_wand.wav", "vo_beben.wav", "vo_schild.wav", "vo_auto.wav", "vo_turbo.wav", "vo_elim.wav", "vo_enlow.wav", "vo_super.wav", "vo_mega.wav", "minedrop.wav",
			"cm_whoosh.wav", "cm_hit.wav", "cm_pop.wav", "cm_stamp.wav", "cm_crash.wav"]:
		snd[n.get_basename()] = load("res://sfx/" + n)
	# Fahrer-Stimmen (japanisch) für die Comic-Seiten
	for c in ["ren", "vega", "kato", "mira"]:
		for k in ["start", "win", "mad", "lose", "ko"]:
			var pth = "res://sfx/cv_%s_%s.wav" % [c, k]
			if ResourceLoader.exists(pth):
				snd["cv_%s_%s" % [c, k]] = load(pth)
	for k in ["engine", "idle", "field"]:
		var p = AudioStreamPlayer.new()
		p.stream = _looped(snd[k])
		p.volume_db = -80.0
		p.bus = "Game"
		add_child(p)
		p.play()
		loops[k] = p
	_ship_sounds()


func _looped(st: AudioStream) -> AudioStream:
	if st is AudioStreamWAV:
		# Schleife kommt schon aus dem Import (sicherer als zur Laufzeit gesetzte Schleifenpunkte)
		if (st as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED:
			return st
		var w = (st as AudioStreamWAV).duplicate()
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate)
		return w
	if st is AudioStreamOggVorbis:
		var o = (st as AudioStreamOggVorbis).duplicate()
		o.loop = true
		return o
	return st


# Gegner: eigenes Triebwerk im Raum (lauter, wenn nah; mit Kopfhörern von hinten/vorn/seitlich)
var bar_mat: ShaderMaterial


func _ship_sounds() -> void:
	if not snd.has("engine"):
		return
	if bar_mat == null:
		bar_mat = _shader_mat("""
shader_type spatial;
render_mode unshaded,cull_disabled,depth_draw_never,shadows_disabled;
instance uniform float fill = 1.0;
void vertex(){MODELVIEW_MATRIX=VIEW_MATRIX*mat4(INV_VIEW_MATRIX[0],INV_VIEW_MATRIX[1],INV_VIEW_MATRIX[2],MODEL_MATRIX[3]);}
void fragment(){
	vec3 c=fill>.5?vec3(.3,1.,.55):(fill>.25?vec3(1.,.85,.25):vec3(1.,.3,.25));
	ALBEDO=mix(vec3(.3),c*1.8,step(UV.x,fill));ALPHA=.85;
}""")
	for i in range(1, ships.size()):
		var nd: Node3D = ships[i].node
		if nd.has_meta("eng"):
			continue
		var p = AudioStreamPlayer3D.new()
		p.stream = _looped(snd.engine)
		p.unit_size = 2.5
		p.max_distance = 45.0
		p.volume_db = -4.0
		p.bus = "Game"
		nd.add_child(p)
		p.play()
		nd.set_meta("eng", p)
		var q = QuadMesh.new()
		q.size = Vector2(0.9, 0.08)
		var bar = MeshInstance3D.new()
		bar.mesh = q
		bar.material_override = bar_mat
		bar.position = Vector3(0, 0.85, 0)
		bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		nd.add_child(bar)
		nd.set_meta("bar", bar)


func _snd(k: String, db := 0.0, pitch := 1.0, at = null) -> void:
	if warm or not snd.has(k):
		return
	var p
	if at == null:
		p = AudioStreamPlayer.new()
	else:
		p = AudioStreamPlayer3D.new()
		p.unit_size = 4.0
		p.max_distance = 70.0
		p.position = at
	p.stream = snd[k]
	p.volume_db = db
	p.pitch_scale = pitch
	if k.begins_with("vo_"):
		_rev(["vo", k, db])   # Ansagen auch in der Wiederholung
		p.bus = "Voice"
		# solange die Stimme spricht (ohne den Hall am Ende), alles andere absenken
		duck_until = maxf(duck_until, Time.get_ticks_msec() / 1000.0 + maxf(0.4, snd[k].get_length() - 0.25) / maxf(0.1, AudioServer.playback_speed_scale))
	else:
		p.bus = "Game"
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


func _sound_update(dt: float) -> void:
	if loops.is_empty():
		return
	var g: Dictionary = ships[0]
	var sp = g.spd / maxf(1.0, base_spd)
	var on = state == "race" or state == "done"
	loops.engine.pitch_scale = clampf(0.7 + 0.6 * sp + 0.35 * g.boost, 0.3, 3.0)
	loops.engine.volume_db = linear_to_db(0.02 + (0.5 + 0.35 * sp + 0.35 * g.boost if on else 0.12))
	loops.idle.pitch_scale = clampf(0.75 + 0.45 * sp + 0.25 * g.boost, 0.3, 3.0)
	loops.idle.volume_db = linear_to_db(0.32 if state != "menu" else 0.2)
	var scr = on and absf(g.lat) >= T.TW - 0.31 and not g.air and g.spd > 1.0 and g.shield <= 0.0
	var tv = 0.7 if scr else 0.0
	scr_v += (tv - scr_v) * (1.0 - exp(-dt / (0.02 if scr else 0.08)))
	loops.field.volume_db = linear_to_db(maxf(0.0005, scr_v))
	for i in range(1, ships.size()):
		var o: Dictionary = ships[i]
		var nd: Node3D = o.node
		if nd.has_meta("eng"):
			var p: AudioStreamPlayer3D = nd.get_meta("eng")
			p.pitch_scale = clampf(0.7 + 0.6 * o.spd / maxf(1.0, base_spd) + 0.35 * o.boost, 0.3, 3.0)


var scr_v = 0.0


# ---------------------------------------------------------------- Bildfilter über der 3D-Szene (unter der Anzeige)
var post: ShaderMaterial
var post_rect: ColorRect


func _post() -> void:
	var cl = CanvasLayer.new()
	cl.layer = 0
	add_child(cl)
	var r = ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post = _shader_mat("""
shader_type canvas_item;
// Geschwindigkeit (Zoom-Unschärfe, Farbversatz, Speed-Linien), Gravitationsbombe (Sog, schwarzer Kern, Einstein-Ring, Rückstoß-Welle), Phasen-Glitch
uniform sampler2D scr:hint_screen_texture,filter_linear;
uniform float spd=0.;
uniform vec2 gc=vec2(.5);
uniform float gs=0.;
uniform float gr=-1.;
uniform float gk=0.;
uniform float gz=1.;
uniform float gd=1.;uniform float grw=1.;uniform float grb=1.;uniform vec3 grc=vec3(.75,.55,1.);
uniform float gl=0.;
uniform float asp=.46;
uniform float shp=.6;
uniform float grn=.035;
float h21(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
// Filmkorn-Zufall ohne sin(): bleibt auch bei großen Pixelzahlen gleichmäßig (sin großer Werte wird auf Handy-GPUs ungenau → Muster)
float hg(vec2 p){vec3 p3=fract(vec3(p.xyx)*.1031);p3+=dot(p3,p3.yzx+33.33);return fract((p3.x+p3.y)*p3.z);}
void fragment(){
	vec2 uv=SCREEN_UV;
	// Gravitationsbombe: Bild wird zur Mitte gesogen, danach läuft eine Welle nach außen
	// (alles Teure nur, wenn wirklich eine Bombe oder ein Glitch läuft – sonst spart das Handy die Rechnerei)
	bool bomb=gs!=0.||gr>=0.;
	float r=1.;
	if(bomb){
		vec2 dd=uv-gc;dd.x*=asp;r=length(dd)+1e-4;vec2 dir=dd/r;dir.x/=asp;
		r/=max(gz,.05);   // Gesamtgröße des schwarzen Lochs
		float pull=gs*.05/(r*r*30.+.12)*smoothstep(0.,.03,r);
		float rip=gr>=0.?sin((r-gr)*60.)*exp(-pow(abs((r-gr)*9.),2.))*.022*gk:0.;
		uv-=dir*(pull-rip)*min(gz,2.);
	}
	// Phasen-Glitch: Zeilen verrutschen, Farben laufen auseinander
	if(gl>0.){
		float band=floor(uv.y*46.+floor(TIME*24.)*3.1);
		uv.x+=(h21(vec2(band,floor(TIME*30.)))-.5)*.05*gl*step(.55,h21(vec2(band,1.7)));
	}
	// Geschwindigkeit: radiale Zoom-Unschärfe mit Farbversatz zu den Rändern
	vec2 cd=uv-vec2(.5,.47);float e=smoothstep(.12,.75,length(cd*vec2(asp,1.)));
	float ca=.004*spd*e+.006*gl+.01*abs(gs);
	vec3 col=vec3(0.);
	vec3 c0=texture(scr,uv).rgb;
	// nur wo wirklich verwischt wird, mehrfach lesen (spart auf dem Handy viel)
	if(spd*e<.02&&ca<.0004){col=c0;}
	else{for(int i=0;i<6;i++){float f=1.-float(i)*.0147*spd*e;vec2 q=vec2(.5,.47)+cd*f;
		col+=vec3(texture(scr,q-cd*ca).r,texture(scr,q).g,texture(scr,q+cd*ca).b);}
	col/=6.;}
	// schwarzer Kern und leuchtender Ring der Bombe
	if(bomb){
		float gp=max(gs,0.);
		col*=1.-smoothstep(.06*gp+.01,.0,r)*gp*gd;
		col+=grc*exp(-pow(abs((r-.075*gp)*55./grw),2.))*gp*1.6*grb;
		if(gr>=0.)col+=vec3(.6,.45,1.)*exp(-pow(abs((r-gr)*30.),2.))*gk*.8;
	}
	// Speed-Linien: helle Streifen fliegen von der Mitte nach außen
	if(spd*e>.001){
		float an=atan(cd.y,cd.x*asp);float lane=floor(an*70.);float hl=h21(vec2(lane,3.));
		float ph=fract(length(cd)*2.2-TIME*(2.5+hl*3.)+hl);
		col+=vec3(.75,.88,1.)*step(.93,hl)*smoothstep(.0,.15,ph)*smoothstep(.5,.1,ph)*spd*e*.45;
	}
	// knackig: Kanten schärfen, feines Filmkorn
	vec2 px=SCREEN_PIXEL_SIZE;
	vec3 bl=(texture(scr,uv+px*vec2(1.,.5)).rgb+texture(scr,uv-px*vec2(1.,.5)).rgb)*.5;
	col+=(c0-bl)*shp;
	col=max(col,vec3(0.));
	col+=(hg(floor(SCREEN_UV/px)+floor(fract(TIME*7.3)*91.)*17.)-.5)*grn*(.5+.5*(1.-clamp(dot(col,vec3(.33)),0.,1.)));
	// Vignette bei Tempo
	col*=1.-spd*.25*smoothstep(.3,.9,length(cd*vec2(asp,1.))*1.4);
	COLOR=vec4(col,1.);
}""")
	r.material = post
	post_rect = r
	cl.add_child(r)


func _post_update(dt: float) -> void:
	if post == null:
		return
	var vp = get_viewport().get_visible_rect().size
	_sp(post, "asp", vp.x / maxf(1.0, vp.y))
	_sp(post, "shp", 0.9 if _noir() else 0.6)
	_sp(post, "grn", 0.06 if _noir() else 0.035)
	var g: Dictionary = ships[0]
	var q = int(cfg.gfx)
	var sp = 0.0
	if state == "race" or state == "done":
		sp = clampf((g.spd / BASE_DEF - 1.1) * 0.35 + g.boost * 0.55 + (0.4 if g.turbo > 0.0 else 0.0), 0.0, 1.0)
	post_spd += (sp - post_spd) * (1.0 - exp(-dt / 0.25))
	_sp(post, "spd", post_spd * (1.0 if q >= 1 else 0.0) if post_spd > 0.002 else 0.0)
	gl_v = maxf(0.0, gl_v - dt * 1.4)
	_sp(post, "gl", gl_v)
	# stärkste aktive Gravitationsbombe
	var best = null
	var bk = 0.0
	for e in fxs:
		if e.get("gb", false):
			var k = clampf(1.0 - (e.pos - cam.global_position).length() / 50.0, 0.0, 1.0)
			if not cam.is_position_behind(e.pos) and k > bk:
				bk = k
				best = e
	if best == null:
		_sp(post, "gs", 0.0)
		_sp(post, "gr", -1.0)
		return
	var c = cam.unproject_position(best.pos) / vp
	post.set_shader_parameter("gc", c)
	var t: float = best.t
	var gs = 0.0
	if t < 0.55:
		gs = pow(t / 0.55, 1.6) * 1.2
	elif t < 0.62:
		gs = -1.2
	bk *= best.get("lens", 1.0)
	post.set_shader_parameter("gz", best.get("ps", 1.0))
	post.set_shader_parameter("gd", best.get("dark", 1.0))
	post.set_shader_parameter("grw", best.get("rimw", 1.0))
	post.set_shader_parameter("grb", best.get("rimb", 1.0))
	post.set_shader_parameter("grc", _v3(_hs(Color(0.75, 0.55, 1.0), best.get("rimh", 0.0))))
	post.set_shader_parameter("gs", gs * bk)
	post.set_shader_parameter("gr", (t - 0.55) * 1.1 if t >= 0.55 else -1.0)
	post.set_shader_parameter("gk", bk * clampf(1.0 - (t - 0.55) / 0.8, 0.0, 1.0))


var post_spd = 0.0


func asp_v(vp: Vector2) -> float:
	return vp.y / maxf(1.0, vp.x)
var gl_v = 0.0


# ---------------------------------------------------------------- FX Lab: Regler für alle Effekte und die Umgebung (user://fx.json)
const FX_PATH = "user://fx.json"
# je Bereich: [Schlüssel, Anzeige, min, max, Standard]  (Farbregler heißen "hue…": -0.5…0.5 = einmal ums Farbrad)
const FXS = {
	"boom": [["size", "Size", 0.2, 6.0, 1.0], ["fire", "Fire", 0.0, 8.0, 1.0], ["after", "Extra fireballs", 0.0, 8.0, 1.0], ["smoke", "Smoke", 0.0, 8.0, 1.0],
		["slife", "Smoke duration", 0.1, 6.0, 1.0], ["sparks", "Sparks", 0.0, 8.0, 1.0], ["debris", "Metal shards", 0.0, 8.0, 1.0], ["dglow", "Shard glow", 0.0, 8.0, 1.0],
		["ring", "Shock ring", 0.0, 8.0, 1.0], ["light", "Light flash", 0.0, 8.0, 1.0], ["flash", "Screen flash", 0.0, 6.0, 1.0], ["shake", "Camera shake", 0.0, 8.0, 1.0],
		["hue", "Color", -0.5, 0.5, 0.0]],
	"mine": [["size", "Size", 0.2, 8.0, 1.0], ["glow", "Glow", 0.0, 10.0, 1.0], ["blink", "Blink speed", 0.1, 8.0, 1.0], ["life", "Lifetime", 3.0, 120.0, 25.0],
		["boom", "Explosion size", 0.2, 6.0, 1.0], ["hue", "Color", -0.5, 0.5, 0.0]],
	"quake": [["height", "Wave height", 0.1, 6.0, 1.0], ["speed", "Speed", 0.2, 6.0, 1.0], ["dur", "Range", 0.1, 5.0, 1.0], ["glow", "Glow", 0.0, 8.0, 1.0],
		["sparks", "Sparks & shards", 0.0, 8.0, 1.0], ["shake", "Camera shake", 0.0, 8.0, 1.0], ["hue", "Color", -0.5, 0.5, 0.0]],
	"gb": [["scale", "Size (all)", 0.1, 4.0, 1.0], ["size", "Pull radius", 0.2, 6.0, 1.0], ["time", "Duration", 0.2, 8.0, 1.0],
		["core", "Core size", 0.2, 6.0, 1.0], ["dark", "Core blackness", 0.0, 1.0, 1.0],
		["rimw", "Rim width", 0.2, 6.0, 1.0], ["rimb", "Rim brightness", 0.0, 8.0, 1.0], ["rimh", "Rim color", -0.5, 0.5, 0.0],
		["wave", "Shock sphere", 0.0, 8.0, 1.0], ["wthick", "Sphere thickness", 0.1, 6.0, 1.0], ["wspeed", "Sphere speed", 0.2, 6.0, 1.0], ["wsize", "Sphere size", 0.2, 6.0, 1.0],
		["whue", "Sphere color", -0.5, 0.5, 0.0], ["gring", "Ground ring", 0.0, 8.0, 1.0],
		["sparks", "Sparks", 0.0, 8.0, 1.0], ["light", "Light", 0.0, 8.0, 1.0], ["lens", "Space warp", 0.0, 8.0, 1.0], ["shake", "Camera shake", 0.0, 8.0, 1.0],
		["hue", "Color (all)", -0.5, 0.5, 0.0]],
	"rak": [["size", "Size", 0.2, 8.0, 1.0], ["speed", "Speed", 0.2, 6.0, 1.0], ["light", "Light", 0.0, 10.0, 1.0],
		["hue", "Color", -0.5, 0.5, 0.0]],
	"jungle": [["trees", "Trees", 0.0, 1.0, 1.0], ["under", "Undergrowth", 0.0, 1.0, 1.0], ["flies", "Fireflies", 0.0, 1.0, 1.0], ["fsize", "Firefly size", 0.3, 3.0, 1.0],
		["mush", "Mushroom glow", 0.0, 4.0, 1.0], ["wall", "Wall height (restart)", 0.3, 2.0, 1.0], ["meteor", "Shooting stars", 0.0, 4.0, 1.0], ["far", "Far mountains", 0.0, 2.0, 1.0]],
	"lock": [["shape", "Shape", 0.0, 4.0, 0.0], ["size", "Size", 0.3, 4.0, 1.0], ["thick", "Line thickness", 0.2, 5.0, 1.0], ["glow", "Glow", 0.0, 10.0, 1.0],
		["spin", "Rotation", 0.0, 6.0, 1.0], ["hue", "Color (tracking)", -0.5, 0.5, 0.0], ["lhue", "Color (locked)", -0.5, 0.5, 0.0],
		["time", "Lock time", 0.2, 4.0, 1.0], ["vol", "Beep volume", 0.0, 3.0, 1.0], ["pitch", "Beep pitch", 0.5, 2.0, 1.0]],
	"wall": [["height", "Height", 0.2, 8.0, 1.0], ["dur", "Duration", 0.2, 8.0, 1.0], ["bolts", "Lightning", 0.0, 8.0, 1.0], ["glow", "Glow", 0.0, 8.0, 1.0],
		["hue", "Color", -0.5, 0.5, 0.0]],
	"shield": [["size", "Size", 0.5, 4.0, 1.0], ["glow", "Glow", 0.0, 10.0, 1.0], ["edge", "Edge sharpness", 0.2, 6.0, 1.0], ["flicker", "Flicker", 0.0, 8.0, 1.0],
		["hue", "Color", -0.5, 0.5, 0.0]],
	"orbs": [["shue", "Super orbs color", -0.5, 0.5, 0.0], ["sglow", "Super orbs glow", 0.0, 10.0, 1.0], ["size", "Size", 0.2, 6.0, 1.0], ["radius", "Orbit radius", 0.3, 5.0, 1.0], ["speed", "Orbit speed", 0.1, 6.0, 1.0], ["trail", "Trail length", 0.0, 6.0, 1.0],
		["glow", "Glow", 0.0, 10.0, 1.0], ["hue", "Color", -0.5, 0.5, 0.0]],
	"haze": [["jglow", "Plasma glow", 0.0, 4.0, 1.0], ["jlen", "Plasma length", 0.2, 4.0, 1.0], ["jwid", "Plasma width", 0.3, 3.0, 1.0], ["jboost", "Plasma with boost", 0.0, 4.0, 1.0],
		["jdia", "Shock rings", 0.0, 3.0, 1.0], ["jhue", "Plasma color", -0.5, 0.5, 0.0],
		["amp", "Heat shimmer", 0.0, 10.0, 1.0], ["fine", "Fineness", 0.3, 6.0, 1.0], ["speed", "Speed", 0.0, 8.0, 1.0], ["size", "Size", 0.2, 6.0, 1.0],
		["len", "Length", 0.2, 6.0, 1.0], ["boost", "Extra with boost", 0.0, 8.0, 1.0]],
	"pillar": [["speed", "Ring speed", 0.0, 6.0, 1.0], ["size", "Ring size", 0.3, 5.0, 1.0], ["glow", "Ring glow", 0.0, 10.0, 1.0], ["squash", "Rubber squash", 0.0, 6.0, 1.0],
		["soft", "Soft bounce", 0.0, 2.0, 1.0], ["beam", "Pillar light", 0.0, 10.0, 1.0], ["hitw", "Hit width", 0.2, 1.0, 0.5]],
	"ship": [["height", "Hover height", 0.2, 8.0, 1.0], ["bob", "Hover bob", 0.0, 10.0, 1.0], ["bank", "Lean in curves", 0.0, 6.0, 1.0], ["pitch", "Nose pitch", 0.0, 8.0, 1.0],
		["wobble", "Spring wobble", 0.0, 8.0, 0.0], ["stiff", "Spring stiffness", 0.2, 5.0, 1.0], ["steer", "Steering lag", 0.2, 8.0, 1.0],
		["steerk", "Steering strength", 0.3, 3.0, 1.0], ["grip", "Grip", 0.2, 4.0, 1.0], ["drift", "Drift", 0.0, 4.0, 0.0],
		["nav", "Nav lights", 0.0, 4.0, 1.0], ["navb", "Nav blink speed", 0.2, 4.0, 1.0], ["trim", "Nose trim (down +)", -1.0, 1.0, 0.0],
		["weight", "Tassel weight", 0.1, 3.0, 1.0], ["swing", "Tassel swing", 0.1, 3.0, 1.0], ["wind", "Tassel wind (driving)", 0.0, 3.0, 1.0],
		["breeze", "Breeze (also standing)", 0.0, 3.0, 1.0],
		["center", "Auto-center nose", 0.0, 3.0, 1.0], ["spdst", "Softer steering at speed", 0.0, 2.0, 0.25]],
	"steer": [["ptime", "Press: ramp time", 0.05, 2.0, 0.56], ["rtime", "Release: fade time", 0.0, 1.5, 0.12], ["delay", "Input delay", 0.0, 0.3, 0.0],
		["swrange", "Swipe: full-lock distance", 0.05, 0.4, 0.16], ["velk", "Swipe: speed boost", 0.0, 1.0, 0.3], ["hold", "Swipe: lift hold", 0.0, 0.4, 0.15], ["dtap", "Double-tap window", 0.2, 0.6, 0.35],
		["revmode", "Swipe: reverse = counter-steer (0 off / 1 on)", 0.0, 1.0, 1.0], ["revbuf", "Swipe: reverse buffer", 0.0, 0.04, 0.008], ["velmin", "Swipe: speed boost threshold", 0.0, 0.9, 0.35],
		["psens", "Pointer: sensitivity", 0.5, 8.0, 3.0], ["paccel", "Pointer: acceleration", 0.0, 4.0, 1.0], ["vib", "Lanes: vibration (0 off / 1 on)", 0.0, 1.0, 1.0], ["ltime", "Lane tap: full change time (outer to outer)", 0.1, 1.2, 0.35], ["lhold", "Lane tap: hold time for the next lane", 0.1, 1.0, 0.25], ["lbeep", "Lanes: change beep volume (0 = off)", 0.0, 2.0, 1.0],
		["glide", "Glide: follow time", 0.05, 1.0, 0.25], ["gwidth", "Glide: reach to edge", 0.3, 1.0, 0.85], ["gpull", "Glide: curve pull", 0.0, 2.0, 0.5]],
	"env": [["city", "Buildings", 0.0, 1.0, 1.0], ["dens", "Building count", 0.0, 5.0, 1.0], ["bh", "Height", 0.3, 6.0, 1.0], ["bw", "Width", 0.2, 6.0, 1.0],
		["bd", "Distance", 0.2, 6.0, 1.0], ["win", "Lit windows", 0.0, 2.5, 1.0], ["hue_w", "Window color", -0.5, 0.5, 0.0], ["edge", "Neon edges", 0.0, 10.0, 1.0],
		["hue_s", "Sky color", -0.5, 0.5, 0.0], ["skyb", "Sky brightness", 0.0, 6.0, 1.0], ["stars", "Stars", 0.0, 10.0, 1.0], ["skyl", "Skyline", 0.0, 5.0, 1.0],
		["fog", "Fog density", 0.0, 12.0, 1.0], ["hue_f", "Fog color", -0.5, 0.5, 0.0], ["moon", "Moon", 0.0, 6.0, 1.0], ["beams", "Light pillars", 0.0, 10.0, 1.0],
		["lamps", "Track lights", 0.0, 10.0, 1.0], ["nlight", "Neon reflections", 0.0, 6.0, 1.0],
		["gloss", "Road gloss", 0.0, 4.0, 2.0], ["wet", "Wet road", 0.0, 4.0, 1.0]],
	"city": [["holo", "Holograms", 0.0, 4.0, 1.0], ["hsize", "Hologram size", 0.3, 3.0, 1.0], ["hflick", "Hologram glitch", 0.0, 12.0, 1.0], ["hhue", "Hologram color", -0.5, 0.5, 0.0],
		["signs", "Neon signs", 0.0, 4.0, 1.0], ["search", "Searchlights", 0.0, 4.0, 1.0], ["cars", "Flying cars", 0.0, 4.0, 1.0],
		["mega", "Mega towers", 0.0, 3.0, 1.0]],
	"sound": [["vol", "Volume", 0.0, 3.0, 1.0], ["pitch", "Pitch", 0.5, 2.0, 1.0], ["bass", "Bass", 0.0, 2.0, 1.0], ["treble", "Treble", 0.0, 2.0, 1.0],
		["grit", "Grit", 0.0, 2.0, 0.0], ["echo", "Echo", 0.0, 2.0, 0.0], ["etime", "Echo time", 0.2, 3.0, 1.0], ["reverb", "Reverb", 0.0, 2.0, 0.0], ["room", "Room size", 0.0, 1.0, 0.6],
		["rumble", "Engine rumble", 0.0, 3.0, 1.0], ["beeps", "Original beeps", 0.0, 3.0, 1.0], ["synth", "Synth beeps", 0.0, 3.0, 0.0], ["spitch", "Synth pitch", 0.25, 4.0, 1.0],
		["sshape", "Synth shape", 0.0, 1.0, 0.3], ["sweep", "GO sweep", 0.0, 2.0, 0.5]],
}
const FXT = [["boom", "Boom"], ["mine", "Mine"], ["quake", "Quake"], ["gb", "Hole"], ["rak", "Rocket"], ["lock", "Lock"], ["wall", "Field"], ["shield", "Shield"], ["orbs", "Orbs"], ["haze", "Jet"], ["pillar", "Pillar"], ["ship", "Ship"], ["steer", "Steering"], ["env", "World"], ["city", "City"], ["jungle", "Jungle"], ["sound", "Sound"]]
var fx = {}


func _fx_load() -> void:
	fx = {}
	for gk in FXS:
		fx[gk] = {}
		for it in FXS[gk]:
			fx[gk][it[0]] = it[4]
	if not FileAccess.file_exists(FX_PATH):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(FX_PATH))
	if not (d is Dictionary):
		return
	for gk in FXS:
		if d.get(gk) is Dictionary:
			for it in FXS[gk]:
				var v = d[gk].get(it[0])
				if v is float or v is int:
					fx[gk][it[0]] = clampf(float(v), it[2], it[3])


func _fx_save() -> void:
	var f = FileAccess.open(FX_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(fx))


# Farbe ums Farbrad drehen, Helligkeit (auch über 1, HDR) bleibt
func _hs(c: Color, h: float) -> Color:
	if absf(h) < 0.001:
		return c
	var m = maxf(c.r, maxf(c.g, c.b))
	if m <= 0.0:
		return c
	var n = Color(c.r / m, c.g / m, c.b / m)
	var r = Color.from_hsv(fposmod(n.h + h, 1.0), n.s, n.v)
	return Color(r.r * m, r.g * m, r.b * m, c.a)


func _rh(cols: Array, h: float) -> Array:
	if absf(h) < 0.001:
		return cols
	return cols.map(func(c): return [c[0], _hs(c[1], h)])


func _v3(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)


# ---------------------------------------------------------------- Einstellungen (im Handy gespeichert)
func _load_cfg() -> void:
	var c = ConfigFile.new()
	if c.load(CFG_PATH) == OK:
		for k in cfg.keys():
			cfg[k] = c.get_value("s", k, cfg[k])
	cfg.ship = clampi(int(cfg.ship), 0, SHIPS.size() - 1)
	cfg.gfx = clampi(int(cfg.gfx), 0, 2)


func _save_cfg() -> void:
	var c = ConfigFile.new()
	for k in cfg.keys():
		c.set_value("s", k, cfg[k])
	c.save(CFG_PATH)


# Glow: ab Godot 4.6 wird er vor der Farbumrechnung berechnet und ist auf dem Handy neu gebaut – dort braucht er andere Werte
# Ab Godot 4.6 rechnet der Handy-Renderer Licht und Himmel anders: Ausgleichswerte (nur dort)
const NEWR = {"sky": 0.4, "moon": 3.0, "ship": 1.5, "amb": 1.5, "expo": 1.0}
var newr_c = {}   # einmal ermittelt (wird jedes Bild gebraucht)


func _newr(k: String, d: float) -> float:
	if newr_c.has(k):
		return newr_c[k]
	var v = d
	var vi = Engine.get_version_info()
	if vi.major > 4 or vi.minor >= 6:
		v = NEWR.get(k, d)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--nr" + k + "="):
			v = float(a.split("=")[1])
	newr_c[k] = v
	return v


# ---------------------------------------------------------------- Neon-Flächenlicht (ab Godot 4.7: AreaLight3D)
# Zwei lange Leuchtflächen auf Höhe der Neonbänder an den Leitplanken wandern mit dir mit. So spiegeln sich
# Cyan und Magenta auf der nassen Fahrbahn und an den Schiffsflanken – wie bei echten Neonröhren.
var nlights = []
var has_al = false   # Flächenlichter kosteten am Handy 13 ms pro Bild – der Neonschein kommt jetzt aus dem Fahrbahn-Shader


func _neon_lights() -> void:
	var nk = float(fx.env.nlight)
	if not nlights.is_empty() and not is_instance_valid(nlights[0]):
		nlights.clear()
	if nlights.is_empty():
		if not has_al or nk <= 0.01:
			return
		for sd in [-1.0, 1.0]:
			var al: Light3D = ClassDB.instantiate("AreaLight3D")
			al.set("area_size", Vector2(14.0, 0.12))
			al.set("area_range", 7.0)
			al.set("area_attenuation", 1.0)
			al.light_color = CY if sd < 0.0 else MG
			al.shadow_enabled = false
			al.light_specular = 1.0
			add_child(al)
			nlights.append(al)
	var g: Dictionary = _focus()
	var f = T.frame(g.z + 5.0)
	for i in range(nlights.size()):
		var sd = -1.0 if i == 0 else 1.0
		var al: Light3D = nlights[i]
		al.visible = nk > 0.01 and tun_k < 0.5
		al.light_energy = 2.5 * nk
		var pos: Vector3 = f.c + f.rr * (sd * (T.TW - 0.05)) + f.uu * 0.33
		# Licht strahlt entlang -Z: zur Fahrbahnmitte hin
		al.global_transform = Transform3D(Basis.looking_at(-f.rr * sd, f.uu), pos)


var expo_v = 0.0   # Helligkeits-Stoß bei Explosionen (nur neuer Renderer)


# Streckenlampen: nur die nächsten paar vor der Kamera einschalten. Der Handy-Renderer nimmt pro Fläche nur
# wenige Lichter – sonst verdrängen die Lampen das Licht der Schiffe (Abgasstrahl auf der Fahrbahn).
func _lamps_cull() -> void:
	if cam == null or float(fx.env.lamps) <= 0.01:
		return
	var cz = cam.global_position.z
	near_l.clear()
	for b in lights_nodes:
		var dz = (b as Node3D).global_position.z - cz
		if dz > -8.0 and dz < 70.0:
			near_l.append([absf(dz - 10.0), b])
	near_l.sort_custom(_by_first)
	var on = {}
	for i in range(mini(6, near_l.size())):
		on[near_l[i][1]] = true
	# nur umschalten, wenn sich etwas ändert – sonst muss der Renderer die Lichter jedes Bild neu zuordnen
	for b in lights_nodes:
		var v = on.has(b)
		if b.visible != v:
			b.visible = v


var near_l = []


func _by_first(x, y) -> bool:
	return x[0] < y[0]


func _glow_k() -> Dictionary:
	var k = {"i": 1.0, "s": 1.0, "b": 0.08, "t": 1.0, "l6": 0.0, "l1": 0.0}
	var vi = Engine.get_version_info()
	if vi.major > 4 or vi.minor >= 6:
		k = GLOW_NEW.duplicate()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--gk="):
			var v = a.substr(5).split(",")
			for j in range(mini(v.size(), 6)):
				k[["i", "s", "b", "t", "l6", "l1"][j]] = float(v[j])
		if a.begins_with("--gl="):
			k["lv"] = Array(a.substr(5).split(",")).map(func(x): return float(x))
	return k
# Werte für Godot 4.6+ (am Handy-Renderer verglichen): Schwelle etwas tiefer, enge Stufen, kräftiger – sonst fehlt das Neon-Leuchten
const GLOW_NEW = {"i": 4.5, "s": 1.0, "b": 0.0, "t": 0.72, "l6": 0.0, "l1": 0.3, "lv": [0.3, 1.0, 1.0, 0.5, 0.0, 0.0]}


# Grafikstufe: 0 niedrig, 1 mittel, 2 hoch
func _apply_cfg() -> void:
	base_spd = BASE_DEF * float(cfg.speed)
	Engine.max_fps = 60 if int(cfg.cap) == 1 else 0
	if ui.has("fps"):
		ui.fps.visible = int(cfg.fps) == 1
	var q = int(cfg.gfx)
	# Bildschirm-Spiegelungen und Umgebungsverdeckung gibt es nur im Desktop-Renderer (Forward+), nicht auf dem Handy
	var fp = _fplus()
	_wet_apply()
	wenv.ssr_enabled = q >= 2 and fp
	wenv.ssao_enabled = q >= 2 and fp
	# Medium: ein einfacher, kurzer Schatten statt zwei Stufen, schnelle Kantenglättung (FXAA) statt MSAA
	moon.shadow_enabled = q >= 1
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if q >= 2 else DirectionalLight3D.SHADOW_ORTHOGONAL
	moon.directional_shadow_max_distance = 35.0 if q >= 2 else 18.0
	get_viewport().msaa_3d = Viewport.MSAA_4X if q >= 2 else Viewport.MSAA_DISABLED
	get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if q == 1 else Viewport.SCREEN_SPACE_AA_DISABLED
	get_viewport().scaling_3d_scale = [0.7, 0.8, 1.0][q] * float(cfg.res)
	var GK = _glow_k()
	wenv.glow_intensity = 1.6 * float(cfg.glow) * (0.7 if _noir() else 1.0) * GK.i
	wenv.adjustment_contrast = 1.18 if _noir() else 1.05
	wenv.glow_strength = (0.6 + 0.6 * float(cfg.glow)) * GK.s
	wenv.glow_bloom = GK.b
	wenv.glow_hdr_threshold = GK.t
	wenv.set_glow_level(6, GK.l6)
	wenv.set_glow_level(1, GK.l1)
	if GK.has("lv"):
		for li in range(mini(GK.lv.size(), 6)):
			wenv.set_glow_level(li + 1, GK.lv[li])
	for nm in neon_mats:
		nm[0].emission_energy_multiplier = nm[1] * float(cfg.neon)
	for b in lights_nodes:
		b.light_energy = 2.2 * float(cfg.neon) * float(fx.env.lamps)
		b.visible = float(fx.env.lamps) > 0.01
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.001, float(cfg.vol))))


var sky_m: ShaderMaterial
var fog_c = Color()


# Regler aus dem FX Lab (Bereich „World“) auf Himmel, Nebel, Häuser, Lichtsäulen und Lampen anwenden
func _env_apply() -> void:
	var E: Dictionary = fx.env
	if mats.has("road"):
		_rset("rgl", float(E.gloss))
		_rset("nk", 0.0 if _jungle() else float(E.nlight))
		_rset("ncl", _v3(CY))
		_rset("ncr", _v3(MG))
	_wet_apply()
	_city_apply()
	if sky_m != null:
		sky_m.set_shader_parameter("sb", float(E.skyb) * _newr("sky", 1.0))
		sky_m.set_shader_parameter("st", float(E.stars))
		sky_m.set_shader_parameter("sl", float(E.skyl))
		sky_m.set_shader_parameter("mn", float(E.moon))
		sky_m.set_shader_parameter("hu", float(E.hue_s))
	if wenv != null:
		wenv.fog_light_color = _hs(fog_c, float(E.hue_f))
	if city_mat != null:
		city_mat.set_shader_parameter("wl", float(E.win))
		city_mat.set_shader_parameter("wh", float(E.hue_w))
		city_mat.set_shader_parameter("eg", float(E.edge))
	_pillar_apply()
	for b in beam_n:
		b.visible = float(E.beams) > 0.01
	if moon != null:
		moon.visible = float(E.moon) > 0.01
	if wenv != null and moon != null:
		_apply_cfg()


# ---------------------------------------------------------------- Umgebung: Himmel, Licht, Glühen, Spiegelungen, Nebel
func _env() -> void:
	var sky_mat = ShaderMaterial.new()
	sky_m = sky_mat
	sky_mat.shader = Shader.new()
	sky_mat.shader.code = _nz("""
shader_type sky;
uniform float sb=1.;uniform float st=1.;uniform float sl=1.;uniform float mn=1.;uniform float hu=0.;
float h21(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
vec3 hr(vec3 c,float a){vec3 k=vec3(.57735);float ca=cos(a);return c*ca+cross(k,c)*sin(a)+k*dot(k,c)*(1.-ca);}
void sky(){
	vec3 d=EYEDIR;float h=d.y;float an=atan(d.x,d.z);
	vec3 c=hr(mix(vec3(.04,.02,.07),vec3(.002,.003,.012),smoothstep(0.,.5,h)),hu*6.2832)*sb;
	vec2 sp=vec2(an*90.,h*160.);vec2 ci=floor(sp);
	c+=vec3(.8,.85,1.)*step(.986,h21(ci))*smoothstep(.03,.25,h)*(1.-step(.3,length(fract(sp)-.5)))*1.6*st;
	vec3 md=normalize(vec3(.5,.32,.8));float mo=dot(d,md);
	c+=(vec3(.9,.92,1.)*smoothstep(.0346,.0245,length(d-md))*4.+vec3(.25,.3,.5)*pow(max(0.,mo),60.)*.35)*mn;
	// Skyline in zwei Tiefen mit Fenstern und Neonkanten
	for(int k=0;k<2;k++){float fk=float(k);float s=55.-fk*20.;float bx=floor(an*s);
		float bh=(.014+.05*pow(h21(vec2(bx,fk)),2.2))*(1.+fk*.7)*sl;
		if(h<bh&&h>-.04&&sl>.01){vec2 w=vec2(fract(an*s)*5.,h*s*6.);vec2 wi=floor(w);
			float lit=step(.68,h21(wi+bx*1.3+fk*7.))*step(.25,fract(w.x))*step(.3,fract(w.y));
			vec3 wc=h21(wi+3.1)>.8?vec3(.3,.8,1.):vec3(1.,.7,.45);
			c=vec3(.004,.005,.01)*(1.+fk)+wc*lit*(.6-fk*.2);
			if(h>bh-.0025)c+=(h21(vec2(bx,9.))>.5?vec3(0.,.78,1.):vec3(1.,.06,.42))*1.5;}}
	c+=hr(vec3(.5,.12,.45)*exp(-abs(h)*22.)*.22,hu*6.2832)*sb;
	if(h<-.04)c=mix(c,vec3(.006,.005,.012),smoothstep(-.04,-.15,h));
	COLOR=c;
}
""", [["vec3(.04,.02,.07),vec3(.002,.003,.012)", "vec3(.05),vec3(.004)"], ["vec3(.3,.8,1.):vec3(1.,.7,.45)", "vec3(.9):vec3(.7)"],
		["(h21(vec2(bx,9.))>.5?vec3(0.,.78,1.):vec3(1.,.06,.42))", "(h21(vec2(bx,9.))>.7?vec3(1.,.36,.03):vec3(.55))"],
		["vec3(.5,.12,.45)*exp", "vec3(.5,.18,.02)*exp"], ["vec3(.25,.3,.5)*pow", "vec3(.35)*pow"], ["vec3(.006,.005,.012)", "vec3(.007)"]])
	if _jungle():
		sky_mat.shader.code = JSKY_CODE
	var sky = Sky.new()
	sky.sky_material = sky_mat
	var env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.19, 0.19, 0.2) if _noir() else (Color(0.1, 0.2, 0.17) if _jungle() else Color(0.16, 0.12, 0.26))
	env.ambient_light_energy = 0.35
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_strength = 0.9
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	for i in range(1, 7):
		env.set_glow_level(i, 1.0 if i >= 2 and i <= 5 else 0.0)
	env.ssr_enabled = _fplus()
	env.ssr_max_steps = 72
	env.ssr_fade_in = 0.1
	env.ssr_fade_out = 2.5
	env.ssr_depth_tolerance = 0.35
	env.ssao_enabled = _fplus()
	env.ssao_intensity = 1.6
	env.fog_enabled = true
	env.fog_light_color = Color(0.045, 0.045, 0.05) if _noir() else (Color(0.025, 0.07, 0.06) if _jungle() else Color(0.05, 0.03, 0.09))
	fog_c = env.fog_light_color
	env.fog_density = 0.012
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	env.adjustment_contrast = 1.05
	wenv = env
	var we = WorldEnvironment.new()
	we.environment = env
	add_child(we)
	# Mondlicht mit echten Schatten
	moon = DirectionalLight3D.new()
	moon.light_color = Color(0.85, 0.87, 0.9) if _noir() else (Color(0.55, 0.8, 0.85) if _jungle() else Color(0.6, 0.66, 1.0))
	moon.light_energy = 0.45
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 35.0
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	moon.rotation = Vector3(deg_to_rad(-62.0), deg_to_rad(150.0), 0.0)
	add_child(moon)


# ---------------------------------------------------------------- Materialien
func _metal(c: Color, rough: float = 0.3, metal: float = 0.85) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


# Metall mit Textur: Farbe (Rauheit im Alpha) + Oberflächenstruktur; scale = Wiederholungen je Einheit
func _tex_metal(nm: String, c: Color, scale: float, rough: float, metal: float = 0.85, glow := 0.0, gc := Color(0.4, 0.5, 0.7)) -> StandardMaterial3D:
	var m = _metal(c, rough, metal)
	var tc: Texture2D = load("res://tex/%s_cr.png" % nm)
	m.albedo_texture = tc
	m.roughness_texture = tc
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_ALPHA
	m.roughness = clampf(rough / 0.35, 0.2, 1.5)
	m.normal_enabled = true
	m.normal_texture = load("res://tex/%s_n.png" % nm)
	m.normal_scale = 0.8
	m.uv1_scale = Vector3(scale, scale, 1.0)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if glow > 0.0:
		# schwacher Neon-Widerschein auf dem Metall – sonst bleibt die Textur in der Nacht unsichtbar
		m.emission_enabled = true
		m.emission = gc
		m.emission_energy_multiplier = glow
		m.emission_texture = tc
	return m


const NAV_CODE = """
shader_type spatial;
render_mode unshaded,shadows_disabled;
uniform vec3 c=vec3(1.,.1,.1);uniform float k=1.;uniform float rt=1.;uniform float ph=0.;
void fragment(){float t=fract(TIME*.7*rt+ph);float b=step(t,.08)+.5*step(.16,t)*step(t,.22);ALBEDO=c*(.25+b*7.)*k;}
"""
var nav_m = {}


func nav_mat(sd: float) -> ShaderMaterial:
	if not nav_m.has(sd):
		var m = _shader_mat(NAV_CODE)
		m.set_shader_parameter("c", Vector3(0.1, 1.0, 0.3) if sd < 0.0 else Vector3(1.0, 0.08, 0.06))   # von hinten gesehen: links rot, rechts grün
		m.set_shader_parameter("ph", 0.0 if sd < 0.0 else 0.5)
		nav_m[sd] = m
	return nav_m[sd]


func _nav_apply() -> void:
	for m in nav_m.values():
		(m as ShaderMaterial).set_shader_parameter("k", float(fx.ship.nav))
		(m as ShaderMaterial).set_shader_parameter("rt", float(fx.ship.navb))


func _neon(c: Color, e: float = 5.0) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = Color(0, 0, 0)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	neon_mats.append([m, e])
	return m


func _road_mat() -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = Color(0.022, 0.022, 0.03)
	m.metallic = 0.0
	m.metallic_specular = 0.7
	var n = FastNoiseLite.new()
	n.frequency = 0.035
	n.fractal_octaves = 4
	var nt = NoiseTexture2D.new()
	nt.noise = n
	nt.seamless = true
	nt.width = 512
	nt.height = 512
	m.roughness_texture = nt
	m.roughness = 0.42  # Pfützen (dunkle Stellen im Rauschen) glänzen wie Spiegel
	var n2 = FastNoiseLite.new()
	n2.frequency = 0.09
	var nn = NoiseTexture2D.new()
	nn.noise = n2
	nn.seamless = true
	nn.as_normal_map = true
	nn.bump_strength = 3.0
	nn.width = 512
	nn.height = 512
	m.normal_enabled = true
	m.normal_texture = nn
	m.normal_scale = 0.18
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static var shader_cache = {}   # bleibt beim Neustart erhalten: keine Neu-Kompilierung, kein Ruckeln


# Fahrbahn-Wert setzen – Bebenwelle auch für die Nass-Spiegelung (zweiter Durchgang), damit beide gleich gewölbt sind
func _rset(p: StringName, v) -> void:
	mats.road.set_shader_parameter(p, v)
	if road_wet != null and (String(p).begins_with("qz") or String(p).begins_with("qs")):
		road_wet.set_shader_parameter(p, v)


# Nasse Fahrbahn wie im alten HTML-Spiel: Helles über einem Punkt (Neonbänder, Lampen, Fenster, Gleiter) spiegelt
# sich als weicher Streifen darunter. Zweiter Durchgang über der Fahrbahn, liest das fertige Bild (ohne Durchsichtiges).
var road_wet: ShaderMaterial
const WET_CODE = """
shader_type spatial;
render_mode unshaded,blend_add,depth_draw_never,shadows_disabled,fog_disabled;
uniform sampler2D scr:hint_screen_texture,filter_linear_mipmap;
uniform float qz=-1000.;uniform float qs=0.;uniform float qz2=-1000.;uniform float qs2=0.;
uniform float wk=1.;uniform float wn=12.;
float qw(float d,float s){return s*(1.6*exp(-pow(abs(d/2.6),2.))-.5*exp(-pow(abs((d+6.)/2.6),2.))+.22*exp(-pow(abs((d+12.)/2.4),2.)));}
float quake(float z){return qw(z-qz,qs)+qw(qz2-z,qs2);}
void vertex(){float wz=(MODEL_MATRIX*vec4(VERTEX,1.)).z;VERTEX+=NORMAL*(quake(wz)+.002);}
void fragment(){
	vec3 r=vec3(0.);float ws=0.;
	// kein Zufallsversatz mehr (der machte die Spiegelung körnig): stattdessen stärker geglättete Bildstufen,
	// so verschwimmen die Stufen zu einem weichen Schein
	float jt=.5;
	// wenige, weite Schritte aus einer verkleinerten Bildstufe: weich wie vorher, aber ein Bruchteil der Rechenarbeit
	for(int i=1;i<=7;i++){
		float k=float(i);
		if(k>wn)break;
		vec2 q=SCREEN_UV-vec2(0.,(k-jt)*.008);   // enge Abstände + starke Glättung: die Kopien fließen ineinander
		if(q.y<0.)break;
		float lv=3.+k*.4;
		vec3 c=textureLod(scr,q,lv).rgb;

		float w=exp(-k*.18);
		r+=(max(c-.45,vec3(0.))*1.4+c*.05)*w;ws+=w;
	}
	float fr=.3+.7*pow(1.-clamp(dot(NORMAL,VIEW),0.,1.),3.);
	float fd=exp(-length(VERTEX)*.018);
	ALBEDO=min(r/max(ws,.001),vec3(3.))*.75*fr*fd*wk;   // dezenter, weicher Glanz
}"""


func _wet_apply() -> void:
	if not mats.has("road"):
		return
	var wk = float(fx.env.wet)
	var q = int(cfg.gfx)
	if wk <= 0.01 or q <= 0:
		mats.road.next_pass = null
		return
	if road_wet == null:
		road_wet = _shader_mat(WET_CODE)
		road_wet.render_priority = -1   # nach dem Hitzeflimmern, vor allem anderen Durchsichtigen (Funken, Rauch)
		for k in ["qz", "qs", "qz2", "qs2"]:
			var v = mats.road.get_shader_parameter(k)
			if v != null:
				road_wet.set_shader_parameter(k, v)
	_sp(road_wet, "wk", wk)
	_sp(road_wet, "wn", 6.0 if q >= 2 else 4.0)
	mats.road.next_pass = road_wet


# Shader-Wert nur setzen, wenn er sich ändert (jedes Setzen lädt die Materialdaten neu auf die Grafikkarte)
func _sp(m: ShaderMaterial, p: StringName, v) -> void:
	if m.get_shader_parameter(p) != v:
		m.set_shader_parameter(p, v)


func _shader_mat(code: String) -> ShaderMaterial:
	# gleicher Code = gleicher Shader: wird nur einmal kompiliert (sonst ruckelt jede Explosion)
	if not shader_cache.has(code):
		var sh = Shader.new()
		sh.code = code
		shader_cache[code] = sh
	var m = ShaderMaterial.new()
	m.shader = shader_cache[code]
	return m


var CY = Color(0.0, 0.78, 1.0)
var MG = Color(1.0, 0.06, 0.42)
var AM = Color(1.0, 0.62, 0.08)
const OR = Color(1.0, 0.36, 0.03)


# Desktop-Renderer (Forward+)? Die Abfrage gibt es erst ab Godot 4.4 – auf 4.3 also vorsichtig über has_method
func _fplus() -> bool:
	if RenderingServer.has_method("get_current_rendering_method"):
		return str(RenderingServer.call("get_current_rendering_method")) == "forward_plus"
	return str(ProjectSettings.get_setting_with_override("rendering/renderer/rendering_method")) == "forward_plus"


func _noir() -> bool:
	return int(cfg.get("look", 0)) == 1


func _jungle() -> bool:
	return int(cfg.get("look", 0)) == 2


# Schwarz-Weiß-Look: Shader-Farben tauschen (nur wenn aktiv)
func _nz(code: String, pairs: Array) -> String:
	if not _noir():
		return code
	for pr in pairs:
		assert(code.contains(pr[0]), pr[0])
		code = code.replace(pr[0], pr[1])
	return code


func _neo(k: float) -> Color:
	k = fposmod(k, 1.0)
	return CY if k < 0.5 else (MG if k < 0.88 else AM)


# ---------------------------------------------------------------- Geometrie-Helfer (alles in einer Runde, z 20…720)
var sts = {}
var st_z = 20.0   # Streckenstelle des gerade gebauten Teils
const CHUNK = 50.0   # Runde in Abschnitte zerlegt: gezeichnet wird nur, was die Kamera sieht


func _st(key: String) -> SurfaceTool:
	var ck = key + "|" + str(clampi(int(floor((st_z - 20.0) / CHUNK)), 0, int(T.LAP / CHUNK) - 1))
	if not sts.has(ck):
		var st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		sts[ck] = st
	return sts[ck]


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, ua = Vector2.ZERO, ub = Vector2.ZERO, uc = Vector2.ZERO) -> void:
	st.set_normal(n); st.set_uv(ua); st.add_vertex(a)
	st.set_normal(n); st.set_uv(ub); st.add_vertex(b)
	st.set_normal(n); st.set_uv(uc); st.add_vertex(c)


var keep_wind = false   # Felder mit Texturkoordinaten aus der Eckreihenfolge (_fix_uv) nicht umdrehen


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, ua = Vector2.ZERO, ub = Vector2.ZERO, uc = Vector2.ZERO, ud = Vector2.ZERO) -> void:
	# Vorderseite (bei Godot im Uhrzeigersinn) muss zur Normalen passen – sonst dreht der Renderer bei
	# beidseitigen Materialien die Normale um und die Fläche wird falsch beleuchtet / spiegelt das Falsche
	if not keep_wind and (c - a).cross(b - a).dot(n) < 0.0:
		_tri(st, a, c, b, n, ua, uc, ub)
		_tri(st, a, d, c, n, ua, ud, uc)
		return
	_tri(st, a, b, c, n, ua, ub, uc)
	_tri(st, a, c, d, n, ua, uc, ud)


# Kasten im Streckenrahmen: Mitte (lat, h) an Stelle z, halbe Maße (seitlich, hoch, längs)
func _box(key: String, z: float, lat: float, h: float, hx: float, hy: float, hz: float) -> void:
	st_z = z
	var f = T.frame(z)
	var c: Vector3 = f.c + f.rr * lat + f.uu * h
	var X: Vector3 = f.rr * hx
	var Y: Vector3 = f.uu * hy
	var Z: Vector3 = f.fw * hz
	var st = _st(key)
	for ax in [[X, Y, Z], [-X, Y, -Z], [Y, Z, X], [-Y, Z, -X], [Z, X, Y], [-Z, X, -Y]]:
		var n: Vector3 = ax[0]
		var u: Vector3 = ax[1]
		var w: Vector3 = ax[2]
		var o: Vector3 = c + n
		_quad(st, o - u - w, o + u - w, o + u + w, o - u + w, n.normalized(), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))


# Leuchtstreifen auf/an der Strecke: von lat a nach b, Höhe h, entlang z0…z1
func _strip(key: String, z0: float, z1: float, la: float, lb: float, ha: float, hb: float) -> void:
	# kurze Streifen (Felder, Startlinie) bleiben am Stück in einem Abschnitt – ihre Texturkoordinaten zählen die Vierecke
	var whole = z1 - z0 < 10.0
	keep_wind = key == "pad" or key == "start" or key == "wpad"
	st_z = z0
	var z = z0
	var prev = []
	while z <= z1 + 0.001:
		var f = T.frame(z)
		var p: Array = [f.c + f.rr * la + f.uu * ha, f.c + f.rr * lb + f.uu * hb]
		if prev.size() > 0 and not T.gap(z - 0.25):
			if not whole:
				st_z = z - 0.25
			# echte Flächennormale (bei senkrechten Bändern zeigt sie zur Seite, nicht nach oben)
			var n: Vector3 = (p[0] - prev[0]).cross(prev[1] - prev[0])
			if n.length_squared() < 1e-10:
				n = f.uu
			n = n.normalized()
			if n.dot(f.uu) < -0.2 or (absf(n.dot(f.uu)) <= 0.2 and n.dot(f.rr * signf(la + lb + 0.0001)) > 0.0):
				n = -n
			if key == "wall":
				# Leitplanke: Texturkoordinaten längs (z) und quer (Höhe/Breite des Bandes)
				var L = absf(lb - la) + absf(hb - ha)
				_quad(_st(key), prev[0], prev[1], p[1], p[0], n, Vector2(z - 0.5, 0.0), Vector2(z - 0.5, L), Vector2(z, L), Vector2(z, 0.0))
			else:
				_quad(_st(key), prev[0], prev[1], p[1], p[0], n)
		prev = p
		z += 0.5
	keep_wind = false


# Ring um die Strecke (Röhre mit Radius rt), Bogen von -am bis am (Winkel 0 = oben)
func _ring(key: String, z: float, rad: float, cy: float, rt: float, am: float = PI, ns: int = 40) -> void:
	st_z = z
	var f = T.frame(z)
	var st = _st(key)
	var prev = []
	for i in range(ns + 1):
		var th = -am + 2.0 * am * i / ns
		var rn: Vector3 = f.rr * sin(th) + f.uu * cos(th)
		var cen: Vector3 = f.c + f.uu * cy + rn * rad
		var ring = []
		for j in range(6):
			var an = j * PI / 3.0
			var o: Vector3 = rn * cos(an) * rt + f.fw * sin(an) * rt
			ring.append([cen + o, o.normalized()])
		if prev.size() > 0:
			for j in range(6):
				var j2 = (j + 1) % 6
				_quad(st, prev[j][0], ring[j][0], ring[j2][0], prev[j2][0], (prev[j][1] + ring[j2][1]).normalized())
		prev = ring


# ---------------------------------------------------------------- Strecke „Neon Night“
# Dschungel: die Piste steigt zum Rand hin leicht an – Felder liegen darauf statt darin zu versinken
func _jrh(x: float) -> float:
	return 0.06 * pow(absf(x) / T.TW, 3.0) if _jungle() else 0.0


func _build_track() -> void:
	var TW = T.TW
	# Fahrbahn: nasser Asphalt (Reihen alle 0,5 Einheiten, 8 Spalten)
	var prev = []
	var z = 20.0
	while z <= 720.0 + 0.001:
		st_z = z - 0.25
		var road = _st("road")
		var f = T.frame(z)
		var row = []
		for i in range(9):
			var x = -TW + 2.0 * TW * i / 8.0
			# Dschungel: Piste wie eine ausgefahrene Rinne – zu den Rändern hin leicht hoch
			row.append(f.c + f.rr * x + (f.uu * 0.06 * pow(absf(x) / TW, 3.0) if _jungle() else Vector3.ZERO))
		if prev.size() > 0 and not T.gap(z - 0.25):
			for i in range(8):
				var u0 = float(i) / 8.0
				var u1 = float(i + 1) / 8.0
				_quad(road, prev[i], row[i], row[i + 1], prev[i + 1], f.uu, Vector2(u0, (z - 0.5) * 0.08), Vector2(u0, z * 0.08), Vector2(u1, z * 0.08), Vector2(u1, (z - 0.5) * 0.08))
		prev = row
		z += 0.5
	# Leitplanken: Metallwand innen, Deckel, Neonband (links Cyan, rechts Magenta)
	for sd in ([] if _jungle() else [-1.0, 1.0]):   # Dschungel: keine Leitplanken, der Erdwall begrenzt die Piste
		_strip("wall", 20.0, 720.0, sd * TW, sd * TW, -0.06, 0.46)
		_strip("wall", 20.0, 720.0, sd * TW, sd * (TW + 0.12), 0.46, 0.46)
		_strip("neonL" if sd < 0 else "neonR", 20.0, 720.0, sd * (TW - 0.012), sd * (TW - 0.012), 0.30, 0.36)
		# Leuchtkante auf der Fahrbahn
		_strip("neonL" if sd < 0 else "neonR", 20.0, 720.0, sd * (TW - 0.16), sd * (TW - 0.11), 0.006, 0.006)
	# Mittellinie, gestrichelt (im Dschungel nicht)
	var zz = 20.0 if not _jungle() else 9999.0
	while zz < 720.0:
		_strip("line", zz, zz + 1.5, -0.012, 0.012, 0.005, 0.005)
		zz += 3.33
	# Startlinie
	_strip("start", 19.5, 20.5, -TW, TW, 0.007, 0.007)
	# Boost-Felder
	for k in range(1, 21):
		var zc = _bzp(k)
		if zc < 25.0 or zc > 715.0 or T.gap(zc + 1.4) or T.gap(zc) or T.gap(zc + 3.0):
			continue
		var bx = _bpx(k)
		_strip("pad", zc, zc + 3.0, bx - PAD_HW, bx + PAD_HW, 0.008 + _jrh(bx - PAD_HW), 0.008 + _jrh(bx + PAD_HW))
	# Waffenfelder: bunter Ring auf jedem zweiten Feld
	for wk in range(0, 21, 2):
		var zw = _wzp(wk)
		if zw < 25.0 or zw > 715.0 or T.gap(zw + 1.0):
			continue
		var wx = _wpx(wk)
		_strip("wpad", zw - 0.25, zw + 2.25, wx - PAD_HW, wx + PAD_HW, 0.009 + _jrh(wx - PAD_HW), 0.009 + _jrh(wx + PAD_HW))
		wpads.append([zw + 1.0, wx])
	# Tore mit Lampen (nicht im Tunnel), Werbetafeln, Stützen
	var gk = 1
	while gk * 28 + 7 < 720:
		var zc = gk * 28.0 + 7.0
		if zc > 20.0 and _jungle():
			lights.append([zc, _neo(gk * 0.29)])   # Dschungel: nur die schwebenden Irrlichter
		elif zc > 20.0 and not T.in_tun(zc, 2.0):
			for sd in [-1.0, 1.0]:
				_box("metal", zc, sd * (TW + 0.25), 0.6, 0.07, 0.72, 0.07)
			_box("metal", zc, 0.0, 1.34, TW + 0.32, 0.08, 0.09)
			var col = _neo(gk * 0.29)
			var key = "gate" + str(col.to_html())
			if not mats.has(key):
				mats[key] = _neon(col, 6.0)
			_box(key, zc, 0.0, 1.245, TW + 0.2, 0.012, 0.05)
			lights.append([zc, col])
		gk += 1
	for k in range(1, 36):
		var zc = k * 20.0 + 10.0
		if zc > 715.0 or T.in_tun(zc, 2.0) or _jungle():
			continue
		var sd = 1.0 if k % 2 == 0 else -1.0
		_box("metal", zc, sd * (TW + 0.42), 0.42, 0.03, 0.3, 1.6)
		_box("board" + str(k % 3), zc, sd * (TW + 0.385), 0.42, 0.006, 0.26, 1.5)
	for k in range(2, 51):
		var zc = k * 14.0 + 7.0
		if zc > 715.0 or T.in_tun(zc, 1.0) or T.gap(zc) or _jungle():
			continue
		_box("metal", zc, 0.0, -3.3, 0.16, 3.1, 0.16)
	# Neonringe in Gruppen (im Dschungel stattdessen Baumwurzeln über der Strecke)
	if _jungle():
		_jungle_track()
	for zr in ([] if _jungle() else T.RINGS):
		_ring("ringC" if int(floor(zr / 150.0)) % 2 == 0 else "ringM", float(zr), TW + 0.55, 0.95, 0.065)
	# Tunnel: Röhre innen, leuchtende Ringe, Deckenband
	for tu in T.tuns():   # Dschungel: ein dunkler Erdtunnel in der Steilkurve
		var R = TW + 0.25
		var am = acos(maxf(-1.0, -0.56 / R))
		var na = 22
		var pr = []
		var z2: float = tu[0]
		while z2 <= tu[1] + 0.001:
			st_z = z2 - 0.5
			var f = T.frame(z2)
			var ring = []
			for i in range(na + 1):
				var ph = -am + 2.0 * am * i / na
				ring.append([f.c + f.uu * 0.4 + (f.rr * sin(ph) + f.uu * cos(ph)) * R, -(f.rr * sin(ph) + f.uu * cos(ph))])
			if pr.size() > 0:
				for i in range(na):
					# Texturkoordinaten: längs der Röhre (z) und rundherum (Bogenlänge)
					var v0 = R * (-am + 2.0 * am * i / na)
					var v1 = R * (-am + 2.0 * am * (i + 1) / na)
					_quad(_st("tube"), pr[i][0], ring[i][0], ring[i + 1][0], pr[i + 1][0], ring[i][1], Vector2(z2 - 1.0, v0), Vector2(z2, v0), Vector2(z2, v1), Vector2(z2 - 1.0, v1))
			pr = ring
			z2 += 1.0
		var zt: float = tu[0] + 1.0 if not _jungle() else 9999.0   # Erdtunnel: keine Leuchtringe
		var ti = 0
		while zt < tu[1]:
			_ring("ringC" if ti % 5 != 4 else "ringM", zt, R - 0.03, 0.4, 0.025, am * 0.98, 30)
			zt += 1.43
			ti += 1
		if not _jungle():
			_strip("tlight", tu[0], tu[1], -0.06, 0.06, 0.4 + R - 0.04, 0.4 + R - 0.04)
	# Materialien zusammenstellen
	mats["road"] = _shader_mat(_nz("""
shader_type spatial;
// Fahrbahn wie bei Wipeout: dunkelgraues, gebürstetes Metall in Platten, feine Fugen, Randmarkierung; glatt, leicht glänzend
float h11(float x){return fract(sin(x*91.7)*4371.3);}
float h21(vec2 p){return fract(sin(dot(p,vec2(12.9898,78.233)))*43758.5453);}
// Bebenwelle: Kamm bei qz, davor ein kleiner Anlauf, dahinter ein Tal und Nachschwingen
uniform float qz=-1000.;uniform float qs=0.;uniform float qz2=-1000.;uniform float qs2=0.;uniform vec3 qc=vec3(1.,.42,.08);uniform float qg=1.;
uniform float rgl=1.;
// Textur „Metal 046 B“ (ambientCG, CC0): Farbe + Rauheit (Alpha) und Oberflächenstruktur
uniform sampler2D tcr:source_color,filter_linear_mipmap,repeat_enable;
uniform sampler2D tn:hint_normal,filter_linear_mipmap,repeat_enable;
uniform float tk=1.;uniform float ts=2.4;uniform float jg=0.;
uniform vec3 ncl=vec3(0.,.78,1.);uniform vec3 ncr=vec3(1.,.06,.42);uniform float nk=1.;   // Neonschein der Leitplanken   // Glanz der Fahrbahn (FX Lab): mehr = glatter, schärfere Spiegelungen
varying float wz;varying float qh;
float qw(float d,float s){return s*(1.6*exp(-pow(abs(d/2.6),2.))-.5*exp(-pow(abs((d+6.)/2.6),2.))+.22*exp(-pow(abs((d+12.)/2.4),2.)));}
float quake(float z){return qw(z-qz,qs)+qw(qz2-z,qs2);}
void vertex(){wz=(MODEL_MATRIX*vec4(VERTEX,1.)).z;qh=quake(wz);VERTEX+=NORMAL*qh;}
void fragment(){
	float x=(UV.x-.5)*4.8,z=UV.y/.08;
	vec2 pl=vec2(x/1.2,z/2.4),f=fract(pl);
	float fw=fwidth(pl.x)*1.5+.004,fz=fwidth(pl.y)*1.5+.002;
	float seam=1.-smoothstep(0.,fw,f.x)*smoothstep(1.,1.-fw,f.x)*smoothstep(0.,fz,f.y)*smoothstep(1.,1.-fz,f.y);
	float id=h21(floor(pl));
	float br=mix(.5,h11(floor(x*140.))*.6+h11(floor(x*31.)+3.)*.4,1.-clamp(fwidth(x*140.)*.5,0.,1.));
	vec3 base=vec3(.12,.125,.14)*(.86+.18*id)*(.93+.12*br);
	float edge=step(2.4-.42,abs(x))*step(abs(x),2.4-.34);
	float hz=step(.5,fract(z*.5));
	base=mix(base,mix(vec3(.75,.62,.08),vec3(.05),hz),edge);
	vec2 tuv=vec2(x,z)/ts;
	vec4 tc=texture(tcr,tuv);
	base*=mix(vec3(1.),clamp(tc.rgb/.05,0.,3.5),.85*tk*(1.-edge));
	base*=1.-seam*.7;
	if(jg>.5){base=tc.rgb*vec3(.75,.58,.42);seam=0.;edge=0.;}   // Dschungel: lehmiger Matsch statt Metallplatten
	// Struktur der Textur auf die Normale (Tangenten aus den Bildableitungen – die Fahrbahn hat keine eigenen)
	vec3 nm=vec3(texture(tn,tuv).xy*2.-1.,0.);nm.z=sqrt(max(1.-dot(nm.xy,nm.xy),0.));   // komprimiert nur x/y
	vec3 N=NORMAL;vec3 dp1=dFdx(VERTEX),dp2=dFdy(VERTEX);vec2 du1=dFdx(tuv),du2=dFdy(tuv);
	vec3 d2=cross(dp2,N),d1=cross(N,dp1);
	vec3 Tn=d2*du1.x+d1*du2.x,Bn=d2*du1.y+d1*du2.y;
	float iv=inversesqrt(max(max(dot(Tn,Tn),dot(Bn,Bn)),1e-20));
	NORMAL=normalize(N*max(nm.z,.2)+(Tn*nm.x+Bn*nm.y)*iv*.7*tk);
	float rf=mix(1.,clamp(tc.a/.35,.4,2.2),.75*tk);
	ALBEDO=base;METALLIC=.8;ROUGHNESS=clamp((.38+.1*br)/(.6+.4*rgl)*rf+seam*.3+edge*.2,.04,1.);SPECULAR=.45;
	if(jg>.5){METALLIC=0.;ROUGHNESS=clamp(tc.a*.8,.2,1.);SPECULAR=.5;}
	float cr=max(qh,0.)/max(max(qs,qs2),.01);   // glühender Kamm, aufgerissene Fugen
	EMISSION=(qc*pow(cr,1.5)*6.+qc*vec3(1.,.6,.62)*seam*cr*14.)*step(.01,qs+qs2)*qg;
	// Spiegelung der Neonbänder auf der glatten Fahrbahn – im Shader gerechnet statt mit teuren Flächenlichtern
	float dl=2.4-abs(x);
	float frn=pow(1.-clamp(dot(NORMAL,VIEW),0.,1.),2.);
	float shn=(exp(-dl*1.6)*.25+exp(-dl*5.)*.75)*(.08+frn*1.8)*(1.-seam*.6)*(1.-edge*.5);
	EMISSION+=(x<0.?ncl:ncr)*shn*nk*.22;
}""", [["vec3(.75,.62,.08)", "vec3(.8,.3,.02)"]]))
	mats.road.set_shader_parameter("tcr", load("res://tex/road_cr.png" if not _jungle() else "res://tex/mud_cr.png"))
	mats.road.set_shader_parameter("tn", load("res://tex/road_n.png" if not _jungle() else "res://tex/mud_n.png"))
	if _jungle():
		mats.road.set_shader_parameter("jg", 1.0)
		mats.road.set_shader_parameter("ts", 3.0)
	# Leitplanken: zerkratzter Stahl „Metal 038“, Tunnel: „Metal Plates 006“ (beide ambientCG, CC0)
	mats["wall"] = _tex_metal("rail", Color(0.36, 0.37, 0.4), 0.7, 0.22, 0.85, 0.07) if not _jungle() else _tex_metal("bark", Color(0.42, 0.38, 0.32), 0.8, 0.85, 0.0)
	mats["metal"] = _metal(Color(0.09, 0.095, 0.11), 0.3)
	mats["tube"] = _tex_metal("tube", Color(0.24, 0.24, 0.27), 0.5, 0.28, 0.9, 0.05, Color(0.35, 0.55, 0.6)) if not _jungle() else _tex_metal("mud", Color(0.38, 0.31, 0.22), 0.35, 0.95, 0.0)
	if _jungle():
		mats["root"] = _tex_metal("bark", Color(0.45, 0.4, 0.33), 0.7, 0.85, 0.0, 0.03, Color(0.3, 0.9, 0.6))
		mats["jfloor"] = _tex_metal("mud", Color(0.62, 0.52, 0.38), 0.33, 0.9, 0.0, 0.07, Color(0.55, 0.42, 0.28))
	mats["neonL"] = _neon(CY, 5.0)
	mats["neonR"] = _neon(MG, 5.0)
	mats["ringC"] = _neon(CY, 7.0 if not _jungle() else 1.2)
	mats["ringM"] = _neon(MG, 7.0 if not _jungle() else 1.2)
	mats["line"] = _neon(Color(0.8, 0.85, 1.0), 0.6)
	mats["tlight"] = _neon(Color(0.9, 0.95, 1.0), 4.0)
	mats["board0"] = _neon(Color(0.8, 0.8, 0.85) if _noir() else Color(0.1, 0.4, 1.0), 2.2)
	mats["board1"] = _neon(OR if _noir() else Color(1.0, 0.2, 0.5), 2.2)
	mats["board2"] = _neon(Color(0.35, 0.35, 0.37) if _noir() else Color(1.0, 0.7, 0.1), 2.2)
	mats["pad"] = _shader_mat(_nz("""
shader_type spatial;
render_mode unshaded,cull_disabled;
void fragment(){
	// Boost: breite Pfeile laufen nach vorn, heller Rahmen – eindeutig „schneller“
	vec2 u=UV;float ch=step(abs(fract(u.x*3.-TIME*2.5)-.5-abs(u.y-.5)*.9),.2);
	float bd=step(.4,abs(u.y-.5))+step(.46,abs(u.x-.5));
	vec3 b2=mix(vec3(.05,.6,1.),vec3(1.,.85,.15),ch);
	ALBEDO=b2*(1.0+ch*2.8)*.9+b2*bd*2.5;
}""", [["vec3(.05,.6,1.),vec3(1.,.85,.15)", "vec3(.8),vec3(1.,.36,.03)"]]))
	mats["wpad"] = _shader_mat(_nz("""
shader_type spatial;
render_mode unshaded,cull_disabled;
void fragment(){
	vec2 q=vec2((UV.x-.5)*2.5,(UV.y-.5)*1.);float r=length(q);
	// Waffe: drehender Ring und eine Raute in der Mitte (wie eine Waffenkiste)
	float an=atan(q.y,q.x)+TIME*2.;float dash=step(.0,sin(an*6.));
	float dm=abs(q.x)+abs(q.y)*1.2;
	float ring=smoothstep(.05,0.,abs(r-.4))*dash+smoothstep(.035,0.,abs(r-.3))*.8+smoothstep(.03,0.,abs(dm-.15))+smoothstep(.05,0.,dm)*.9;
	vec3 c=.5+.5*cos(6.2832*(atan(q.y,q.x)/6.2832+TIME*.4+vec3(0.,.33,.67)));
	ALBEDO=c*(3.5+1.5*sin(TIME*6.));ALPHA=clamp(ring,0.,1.);
}""", [["vec3 c=.5+.5*cos(6.2832*(atan(q.y,q.x)/6.2832+TIME*.4+vec3(0.,.33,.67)));", "vec3 c=mix(vec3(1.,.36,.03),vec3(1.),.5+.5*sin(atan(q.y,q.x)*3.+TIME*4.));"]]))
	mats["start"] = _shader_mat("""
shader_type spatial;
render_mode unshaded,cull_disabled;
void fragment(){vec2 q=floor(vec2(UV.x*2.,UV.y*12.));ALBEDO=vec3(mod(q.x+q.y,2.)*.85+.02);}""")
	# je Abschnitt ein Mesh – so kann der Renderer alles außerhalb des Blickfelds (und des Schattenbereichs) weglassen
	var chunks = {}
	for ck in sts.keys():
		var key: String = ck.get_slice("|", 0)
		var ci = int(ck.get_slice("|", 1))
		var st: SurfaceTool = sts[ck]
		if key == "pad" or key == "start" or key == "wpad":
			st = _fix_uv(st, key)
		if key == "jfloor" or (key == "road" and _jungle()):
			st = _smooth_st(st)
		st.index()
		if key == "wall" or key == "tube" or key == "root" or key == "jfloor":
			st.generate_tangents()   # für die Oberflächenstruktur der Texturen
		if not chunks.has(ci):
			chunks[ci] = ArrayMesh.new()
		var am: ArrayMesh = chunks[ci]
		st.commit(am)
		am.surface_set_material(am.get_surface_count() - 1, mats[key])
	sts.clear()
	lap_meshes = chunks.values()
	# drei Kopien der Runde: hinter dir, unter dir, vor dir – wandern mit
	for i in range(3):
		var n = Node3D.new()
		for cm in lap_meshes:
			var mi = MeshInstance3D.new()
			mi.mesh = cm
			mi.extra_cull_margin = maxf(2.5, 2.2 * float(fx.quake.height))   # Bebenwelle hebt die Fahrbahn an
			n.add_child(mi)
		for l in lights:
			var om = OmniLight3D.new()
			om.light_color = l[1]
			om.light_energy = 2.2
			om.omni_range = 7.0
			om.omni_attenuation = 1.6
			om.position = T.world(l[0], 0.0, 1.1)
			n.add_child(om)
			if _jungle():
				var orb = MeshInstance3D.new()
				orb.mesh = _lowsphere(0.05, 10, 6)
				orb.material_override = _neon(l[1], 6.0)
				orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				orb.position = om.position
				n.add_child(orb)
			lights_nodes.append(om)
		add_child(n)
		# Lichtsäulen über den Waffenfeldern (schon von Weitem zu sehen)
		if beam_mat == null:
			beam_mat = _shader_mat("""
shader_type spatial;
render_mode unshaded,blend_add,cull_disabled,depth_draw_never,shadows_disabled;
uniform float bk=1.;
void fragment(){
	vec3 c=.5+.5*cos(6.2832*(UV.x+TIME*.3+vec3(0.,.33,.67)));
	ALBEDO=c*.55*bk*pow(UV.y,2.)*(.6+.4*sin(TIME*5.+UV.y*12.));
}""")
			if _noir():
				var bsh = Shader.new()
				bsh.code = beam_mat.shader.code
				beam_mat.shader = bsh
				beam_mat.shader.code = beam_mat.shader.code.replace("vec3 c=.5+.5*cos(6.2832*(UV.x+TIME*.3+vec3(0.,.33,.67)));", "vec3 c=vec3(1.,.36,.03);")
		for wp in wpads:
			var bm = _pillar_node()
			var f = T.frame(wp[0])
			bm.transform = Transform3D(Basis(f.rr, f.uu, f.fw), f.c + f.rr * wp[1] + f.uu * 1.1)
			n.add_child(bm)
			beam_n.append(bm)
		laps.append(n)


var mats = {}
var lights = []
var lights_nodes = []
var wpads = []
var beam_mat: ShaderMaterial
var beam_n = []


# Flächen weich schattieren: gleiche Punkte zusammenlegen und Normalen über die Nachbarn mitteln (keine Kanten)
func _smooth_st(st: SurfaceTool) -> SurfaceTool:
	var arr = st.commit_to_arrays()
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var s2 = SurfaceTool.new()
	s2.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(vs.size()):
		s2.set_uv(uvs[i])
		s2.add_vertex(vs[i])
	s2.index()
	s2.generate_normals()
	return s2


# Boost-Felder und Startlinie: UV aus der Lage im Streifen (x längs, y quer)
func _fix_uv(st: SurfaceTool, key: String) -> SurfaceTool:
	var arr = st.commit_to_arrays()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var uv = PackedVector2Array()
	uv.resize(v.size())
	for q in range(v.size() / 6):
		var ids = [q * 6, q * 6 + 1, q * 6 + 2, q * 6 + 3, q * 6 + 4, q * 6 + 5]
		# Reihenfolge aus _quad: a,b,c,a,c,d  (a=prev links, b=prev rechts, c=row rechts, d=row links)
		var la = Vector2(0, 0)
		var lb = Vector2(0, 1)
		var lc = Vector2(1, 1)
		var ld = Vector2(1, 0)
		var seg = floorf(float(q))
		var span = 6.0 if key == "pad" else (5.0 if key == "wpad" else 2.0)
		var x0 = fposmod(seg, span) / span
		var x1 = x0 + 1.0 / span
		la = Vector2(x0, 0); lb = Vector2(x0, 1); lc = Vector2(x1, 1); ld = Vector2(x1, 0)
		uv[ids[0]] = la; uv[ids[1]] = lb; uv[ids[2]] = lc; uv[ids[3]] = la; uv[ids[4]] = lc; uv[ids[5]] = ld
	arr[Mesh.ARRAY_TEX_UV] = uv
	var st2 = SurfaceTool.new()
	st2.create_from_arrays(arr)
	return st2


# ---------------------------------------------------------------- Hochhäuser neben der Strecke (eine Instanz-Liste, Fenster im Shader)
func _build_city() -> void:
	if _jungle():
		_jungle_build()
		return
	var box = BoxMesh.new()
	box.size = Vector3(2, 2, 2)
	city_mat = _shader_mat(_nz("""
shader_type spatial;
uniform float wl=1.;uniform float wh=0.;uniform float eg=1.;
vec3 hr(vec3 c,float a){vec3 k=vec3(.57735);float ca=cos(a);return c*ca+cross(k,c)*sin(a)+k*dot(k,c)*(1.-ca);}
varying vec3 wp;varying vec3 wn;varying vec4 cd;
void vertex(){wp=(MODEL_MATRIX*vec4(VERTEX,1.)).xyz;wn=normalize((MODEL_MATRIX*vec4(NORMAL,0.)).xyz);cd=INSTANCE_CUSTOM;}
float h21(vec2 p){return fract(sin(dot(p,vec2(12.9898,78.233)))*43758.5453);}
void fragment(){
	float side=1.-step(.9,abs(wn.y));float u=abs(wn.x)>.5?wp.z:wp.x;
	vec2 g=vec2(u*.55,wp.y*.42);vec2 gi=floor(g),gf=fract(g);
	float win=step(.22,gf.x)*step(gf.x,.78)*step(.3,gf.y)*step(gf.y,.82)*side;float hh=h21(gi+floor(cd.a*3.));
	vec3 wc=hh>.93?vec3(.4,.85,1.):(hh>.86?vec3(1.,.4,.75):vec3(1.,.78,.5));
	ALBEDO=vec3(.015,.017,.025);METALLIC=.7;ROUGHNESS=.18;
	EMISSION=hr(wc,wh*6.2832)*win*step(1.-.4*wl,hh)*step(.01,wl)*2.2+cd.rgb*smoothstep(cd.a-.8,cd.a-.3,wp.y)*step(wp.y,cd.a)*side*5.*eg;
}""", [["vec3(.4,.85,1.):(hh>.86?vec3(1.,.4,.75):vec3(1.,.78,.5))", "vec3(1.,.36,.03):(hh>.86?vec3(.9):vec3(.7))"]]))
	box.material = city_mat
	bld_mm = MultiMesh.new()
	bld_mm.transform_format = MultiMesh.TRANSFORM_3D
	bld_mm.use_custom_data = true
	bld_mm.mesh = box
	_city_extras_make()
	_city_fill()
	for n in laps:
		var mmi = MultiMeshInstance3D.new()
		mmi.multimesh = bld_mm
		mmi.extra_cull_margin = 60.0
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(mmi)
		for mm in [sign_mm, srch_mm, car_mm]:
			var xi = MultiMeshInstance3D.new()
			xi.multimesh = mm
			xi.extra_cull_margin = 80.0
			xi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			n.add_child(xi)
			city_xi.append(xi)
	_holos_make()
	_city_apply()


var city_mat: ShaderMaterial


# ================================================================ Dschungel (Look „Jungle“)
# Nachthimmel über dem Regenwald: dunkles Blaugrün, wenige Sterne, Mond, Baumkronen am Horizont, Dunst
const JSKY_CODE = """
shader_type sky;
uniform float sb=1.;uniform float st=1.;uniform float sl=1.;uniform float mn=1.;uniform float hu=0.;
uniform float mt=1.;uniform float m3=1.;
float h11(float x){return fract(sin(x*127.1)*43758.5453);}
float h21(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float sdseg(vec2 p,vec2 a,vec2 b){vec2 pa=p-a,ba=b-a;float hh=clamp(dot(pa,ba)/dot(ba,ba),0.,1.);return length(pa-ba*hh);}
void sky(){
	vec3 d=EYEDIR;float h=d.y;float an=atan(d.x,d.z);
	// Himmel etwas heller als in der Stadt: tiefes Nachtblau, zum Horizont hin dunstig aufgehellt
	vec3 c=mix(vec3(.05,.085,.11),vec3(.006,.012,.03),smoothstep(0.,.6,h))*sb;
	vec2 sp=vec2(an*90.,h*160.);vec2 ci=floor(sp);
	c+=vec3(.85,.9,1.)*step(.988,h21(ci))*smoothstep(.06,.35,h)*(1.-step(.3,length(fract(sp)-.5)))*1.4*st;
	vec3 md=normalize(vec3(.5,.32,.8));float mo=dot(d,md);
	c+=(vec3(.85,.95,.95)*smoothstep(.0346,.0245,length(d-md))*4.+vec3(.15,.25,.3)*pow(max(0.,mo),60.)*.35)*mn;
	// ab und zu eine Sternschnuppe: kurzer heller Kopf, feiner Schweif
	float slot=floor(TIME/6.);float ph=fract(TIME/6.)/.16;
	if(ph<1.&&h11(slot)<.55*mt&&h>.08){
		float a0=h11(slot+3.)*6.2832-3.1416;float h0=.35+.35*h11(slot+7.);float sx=h11(slot+11.)<.5?-1.:1.;
		vec2 v=vec2(sx*.55,-.22);vec2 hd=vec2(a0,h0)+v*ph;
		vec2 q=vec2(an,h);q.x=hd.x+mod(q.x-hd.x+3.1416,6.2832)-3.1416;
		float dd=sdseg(q,hd-v*.28,hd);float alng=clamp(dot(q-(hd-v*.28),v)/dot(v,v)/.28,0.,1.);
		c+=vec3(.8,.95,1.)*smoothstep(.0035,0.,dd)*alng*alng*sin(3.1416*ph)*2.2;
	}
	// Berge: schlichte, dunkle Silhouetten in drei Tiefen – hinten heller und dunstiger, vorn fast schwarz
	float m0=(.085+.05*sin(an*1.5+2.3)+.03*sin(an*4.+.9)+.01*sin(an*9.+2.))*sl;
	float m1=(.06+.045*sin(an*2.+.7)+.03*sin(an*5.+2.1)+.012*sin(an*11.+.4))*sl;
	float m2=(.035+.03*sin(an*3.+1.9)+.018*sin(an*7.+.3)+.008*sin(an*17.+1.))*sl;
	if(h<m0&&sl>.01)c=mix(c,vec3(.03,.05,.065),.5*m3);
	if(h<m1&&sl>.01)c=mix(c,vec3(.012,.02,.03),.85);
	if(h<m2&&sl>.01)c=vec3(.004,.008,.012);
	if(h<-.04)c=mix(c,vec3(.003,.006,.008),smoothstep(-.04,-.15,h));
	COLOR=c;
}
"""

# Bildkarten (Bäume, Unterholz): zwei gekreuzte Flächen, Bild aus einem Atlas, Wind in den Spitzen
const JCARD_CODE = """
shader_type spatial;
render_mode unshaded,cull_disabled;
uniform sampler2D at:source_color,filter_linear_mipmap;
uniform float nc=4.;uniform float dk=.2;uniform float wd=.05;uniform float gk=1.;
uniform vec3 g1=vec3(.2,1.,.65);uniform vec3 g2=vec3(.75,.35,1.);
varying float cell;varying vec4 cd;
void vertex(){
	cd=INSTANCE_CUSTOM;
	cell=floor(cd.r*nc+.5)+(cd.b>.5?0.:UV2.x);
	float top=1.-UV.y;
	// leichte Brise: wiegt sich, mit langsamen Böen
	float gust=.75+.5*sin(TIME*.37+cd.a*3.)*sin(TIME*.19);
	VERTEX.x+=(sin(TIME*1.3+cd.a*40.)*.7+sin(TIME*.6+cd.a*9.)*.6)*wd*top*top*gust;
	VERTEX.z+=sin(TIME*1.1+cd.a*23.)*wd*.5*top*top*gust;
}
void fragment(){
	float c=mod(cell,nc);
	vec4 t=texture(at,vec2((c+clamp(UV.x,.004,.996))/nc,UV.y));
	float top=1.-UV.y;
	vec3 col=t.rgb*dk*(.65+.7*cd.g)*(.5+.8*top);
	col=mix(col,mix(g1,g2,cd.g)*3.*pow(t.r,3.)*gk,cd.b);   // Leuchtpilze: Hüte glühen, Stiele kaum
	ALBEDO=col;ALPHA=t.a;ALPHA_SCISSOR_THRESHOLD=.5;
}
"""

# Blatt im Wind: dunkelgrünes Oval mit Mittelrippe, dreht sich frei
const LEAF_CODE = """
shader_type spatial;
render_mode unshaded,cull_disabled,shadows_disabled;
varying float sd;
void vertex(){sd=INSTANCE_CUSTOM.x;MODELVIEW_MATRIX=VIEW_MATRIX*MODEL_MATRIX;}
void fragment(){
	vec2 p=UV*2.-1.;
	float e=p.x*p.x+p.y*p.y*2.6;
	if(e>1.)discard;
	float rib=smoothstep(.06,0.,abs(p.y))*.35;
	vec3 c=mix(vec3(.05,.14,.06),vec3(.13,.26,.08),.5+.5*p.x)*(1.-rib);
	ALBEDO=c*(FRONT_FACING?1.:.7);
}
"""
var jleaf: GPUParticles3D = null

# Glühwürmchen: kleine Lichtpunkte, die schweben und blinken (immer zur Kamera gedreht)
const JFLY_CODE = """
shader_type spatial;
render_mode unshaded,blend_add,cull_disabled,depth_draw_never,shadows_disabled;
uniform vec3 fc=vec3(.75,1.,.3);uniform float fs=1.;
varying float br;
void vertex(){
	vec4 cd=INSTANCE_CUSTOM;float s=cd.r*100.;
	vec3 o=MODEL_MATRIX[3].xyz+vec3(sin(TIME*.7+s)*.3,sin(TIME*1.1+s*2.)*.3,cos(TIME*.6+s*1.3)*.3);
	VERTEX*=fs;
	MODELVIEW_MATRIX=VIEW_MATRIX*mat4(INV_VIEW_MATRIX[0],INV_VIEW_MATRIX[1],INV_VIEW_MATRIX[2],vec4(o,1.));
	br=smoothstep(.15,1.,sin(TIME*(1.5+cd.g*2.)+s*7.));
}
void fragment(){float d=length(UV-.5)*2.;ALBEDO=fc*br*4.*pow(max(0.,1.-d),2.);}
"""

# Bach quer unter der Sprungstelle: dunkles Wasser, Wellen ziehen seitlich durch, leuchtende Glanzlichter
const JWATER_CODE = """
shader_type spatial;
render_mode unshaded,cull_disabled;
uniform vec3 wc=vec3(.2,1.,.65);
varying vec3 wp;
void vertex(){wp=(MODEL_MATRIX*vec4(VERTEX,1.)).xyz;}
void fragment(){
	float r=sin(wp.x*1.7-TIME*3.)*.5+.5;float r2=sin(wp.x*4.1+wp.z*2.3-TIME*5.)*.5+.5;
	float sp=pow(r*r2,6.);
	ALBEDO=vec3(.01,.04,.05)+wc*sp*1.2+vec3(.2,.35,.45)*pow(r2,14.)*.6;
}
"""

# Bodenprofil neben der Strecke: [Abstand hinter der Leitplanke, Höhe]
var JF = _jf_make()
var JF_BANK = 21   # die Punkte der Wanne folgen der Schräglage der Fahrbahn


# Profil neben der Fahrbahn: eine runde Mulde wie eine Halfpipe aus Erde – sanft hoch, runde Kuppe, sanft runter
static func _jf_make() -> Array:
	var a = []
	for i in range(21):
		var la = 3.0 * i / 20.0
		var u = la / 3.0
		a.append([la, 0.06 * (1.0 - u) + 0.68 * pow(sin(PI * u), 1.6)])
	for q in [[3.8, -0.2], [6.0, -0.8], [16.0, -1.4], [40.0, -2.0], [90.0, -2.4]]:
		a.append(q)
	return a   # die ersten Punkte (Wall) folgen der Schräglage der Fahrbahn
const JGAP = 413.5   # Mitte der Sprungstelle – dort fließt der Bach


# Wall auf der Außenseite der Steilkurven höher (bis fast dreifach)
func _jwall(z: float, sd: float) -> float:
	var b = T.bank(z)
	var wk = float(fx.jungle.wall)
	if absf(b) < 0.01 or signf(b) != sd:   # die angehobene (äußere) Seite der Steilkurve
		return wk
	return wk * (1.0 + 1.8 * clampf((absf(b) - 0.12) / 0.35, 0.0, 1.0))


func _jdip(z: float) -> float:
	var d = absf(T.lz(z) - JGAP)
	var k = clampf(1.0 - d / 8.0, 0.0, 1.0)
	return -1.9 * k * k * (3.0 - 2.0 * k)


# Punkt auf dem Waldboden: Seite sd, la = Abstand hinter der Leitplanke
func _jfh(la: float) -> float:
	for i in range(JF.size() - 1):
		if la <= JF[i + 1][0]:
			var u = clampf((la - JF[i][0]) / (JF[i + 1][0] - JF[i][0]), 0.0, 1.0)
			return lerpf(JF[i][1], JF[i + 1][1], u)
	return JF[JF.size() - 1][1]


# Punkt neben der Strecke: die Wanne (bis 3 hinter der Kante) kippt mit der Steilkurve, dahinter läuft der Waldboden weiter
func _jf(z: float, sd: float, la: float) -> Vector3:
	var f = T.frame(z)
	var wm = _jwall(z, sd)
	var dip = Vector3.UP * (_jdip(z) * clampf(la / 1.5, 0.0, 1.0))
	if la <= 3.0:
		# nur der Wall wächst mit (an der Fahrbahnkante bleibt die Höhe gleich – kein Absatz)
		var base = 0.06 * (1.0 - la / 3.0)
		return f.c + f.rr * (sd * (T.TW + la)) + f.uu * (base + (_jfh(la) - base) * wm) + dip
	var pb: Vector3 = f.c + f.rr * (sd * (T.TW + 3.0)) + f.uu * (_jfh(3.0) * wm)
	var r0: Vector3 = f.fw.cross(Vector3.UP).normalized()
	return pb + r0 * (sd * (la - 3.0)) + Vector3.UP * (_jfh(la) - _jfh(3.0)) + dip


func _jungle_track() -> void:
	var TW = T.TW
	var z = 20.0
	var prev = {}
	while z <= 720.0 + 0.001:
		st_z = z - 0.25   # dieselben Reihen und Abschnitte wie die Fahrbahn: gemeinsame Punkte, weiche Naht
		var f = T.frame(z)
		for sd in [-1.0, 1.0]:
			var row = []
			for i in range(JF.size()):
				row.append(_jf(z, sd, JF[i][0]))
			if prev.has(sd):
				var pr: Array = prev[sd]
				for i in range(row.size() - 1):
					var a: Vector3 = pr[i]
					var b: Vector3 = row[i]
					var c: Vector3 = row[i + 1]
					var d: Vector3 = pr[i + 1]
					var n = (b - a).cross(d - a)
					var trough = JF[i + 1][0] <= 3.001
					if n.dot(f.uu if trough else Vector3.UP) < 0.0:
						n = -n
					var la0 = sd * (TW + JF[i][0])
					var la1 = sd * (TW + JF[i + 1][0])
					if trough:
						# die Wanne mit dem Material der Fahrbahn – Piste und Wand gehen nahtlos ineinander über
						_quad(_st("road"), a, b, c, d, n.normalized(), Vector2(la0 / 4.8 + 0.5, (z - 0.5) * 0.08), Vector2(la0 / 4.8 + 0.5, z * 0.08), Vector2(la1 / 4.8 + 0.5, z * 0.08), Vector2(la1 / 4.8 + 0.5, (z - 0.5) * 0.08))
					else:
						_quad(_st("jfloor"), a, b, c, d, n.normalized(), Vector2(la0, z - 0.5), Vector2(la0, z), Vector2(la1, z), Vector2(la1, z - 0.5))
			prev[sd] = row
		z += 0.5
	# Bachbett unter der Fahrbahn (nur an der Sprungstelle zu sehen)
	var zb = JGAP - 10.0
	var pb = []
	while zb <= JGAP + 10.0:
		st_z = zb
		var f = T.frame(zb)
		var r0: Vector3 = f.fw.cross(Vector3.UP).normalized()
		var y = -0.5 + _jdip(zb)
		var rb = [f.c + r0 * (-TW - 0.2) + Vector3.UP * y, f.c + r0 * (TW + 0.2) + Vector3.UP * y]
		if pb.size() > 0:
			_quad(_st("jfloor"), pb[0], rb[0], rb[1], pb[1], Vector3.UP, Vector2(-TW, zb - 1.0), Vector2(-TW, zb), Vector2(TW, zb), Vector2(TW, zb - 1.0))
		pb = rb
		zb += 1.0
	# Riesenwurzeln als Tore über der Strecke
	for rz in [[120.0, 0.0], [300.0, 1.7], [655.0, 3.1]]:
		_jroot(rz[0], TW + 1.5, TW + 1.9, 0.45, rz[1])
		_jroot(rz[0] + 1.7, TW + 1.1, TW + 1.4, 0.26, rz[1] + 2.0)


# eine Wurzel: knorriger Bogen von links nach rechts über die Fahrbahn
func _jroot(z0: float, A: float, B: float, r0: float, sdd: float) -> void:
	st_z = z0
	var f = T.frame(z0)
	var NA = 30
	var NR = 10
	var rings = []
	for i in range(NA + 1):
		var th = lerpf(-0.18, PI + 0.18, float(i) / NA)
		var P: Vector3 = f.c + f.rr * (-cos(th) * A) + f.uu * (sin(th) * B - 0.2) + f.fw * (0.35 * sin(3.0 * th + sdd))
		var r = r0 * (1.0 + 0.45 * (1.0 - clampf(sin(th), 0.0, 1.0))) * (1.0 + 0.15 * sin(7.0 * th + sdd))
		rings.append([P, r, th])
	for i in range(NA):
		var P0: Vector3 = rings[i][0]
		var P1: Vector3 = rings[i + 1][0]
		var Tg = (P1 - P0).normalized()
		var N1: Vector3 = f.fw
		var N2 = Tg.cross(N1).normalized()
		N1 = N2.cross(Tg).normalized()
		var Tg1 = ((rings[mini(i + 2, NA)][0] as Vector3) - P1).normalized() if i + 1 < NA else Tg
		var M2 = Tg1.cross(f.fw).normalized()
		var M1 = M2.cross(Tg1).normalized()
		for j in range(NR):
			var a0 = TAU * j / NR
			var a1 = TAU * (j + 1) / NR
			var o00 = (N1 * cos(a0) + N2 * sin(a0))
			var o01 = (N1 * cos(a1) + N2 * sin(a1))
			var o10 = (M1 * cos(a0) + M2 * sin(a0))
			var o11 = (M1 * cos(a1) + M2 * sin(a1))
			var a = P0 + o00 * float(rings[i][1])
			var b = P1 + o10 * float(rings[i + 1][1])
			var c = P1 + o11 * float(rings[i + 1][1])
			var d = P0 + o01 * float(rings[i][1])
			var u0 = float(i) * 0.35
			var u1 = float(i + 1) * 0.35
			_quad(_st("root"), a, b, c, d, (o00 + o11).normalized(), Vector2(float(j) / NR * 2.0, u0), Vector2(float(j) / NR * 2.0, u1), Vector2(float(j + 1) / NR * 2.0, u1), Vector2(float(j + 1) / NR * 2.0, u0))


# zwei gekreuzte Flächen (Breite 1, Höhe 1, Fuß bei y = 0); UV2.x sagt, welche der beiden es ist
func _xquad_mesh() -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for q in range(2):
		var ax = Vector3(1, 0, 0) if q == 0 else Vector3(0, 0, 1)
		var c = [[-0.5, 0.0, 0.0, 1.0], [0.5, 0.0, 1.0, 1.0], [0.5, 1.0, 1.0, 0.0], [-0.5, 1.0, 0.0, 0.0]]
		var vs = []
		for k in c:
			vs.append([ax * k[0] + Vector3.UP * k[1], Vector2(k[2], k[3])])
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3.UP)
			st.set_uv(vs[idx][1])
			st.set_uv2(Vector2(float(q), 0.0))
			st.add_vertex(vs[idx][0])
	return st.commit()


var jtree_mm: MultiMesh
var jmm_t = []   # [MultiMesh, volle Anzahl] – Regler „Trees“
var jmm_u = []
var jumat: ShaderMaterial
var jfly_mat: ShaderMaterial
var jfly_n = 0


# Regler aus dem Reiter „Jungle“ anwenden (ohne Neubau)
func _jungle_apply() -> void:
	if not _jungle():
		return
	var J: Dictionary = fx.jungle
	for e in jmm_t:
		(e[0] as MultiMesh).visible_instance_count = int(round(float(e[1]) * float(J.trees)))
	for e in jmm_u:
		(e[0] as MultiMesh).visible_instance_count = int(round(float(e[1]) * float(J.under)))
	if jfly_mm != null:
		jfly_mm.visible_instance_count = int(round(jfly_n * float(J.flies)))
		_sp(jfly_mat, "fs", float(J.fsize))
	if jumat != null:
		_sp(jumat, "gk", float(J.mush))
	if sky_m != null:
		sky_m.set_shader_parameter("mt", float(J.meteor))
		sky_m.set_shader_parameter("m3", float(J.far))
var jund_mm: MultiMesh
var jfly_mm: MultiMesh


func _jcard_mat(path: String, dk: float, wd: float) -> ShaderMaterial:
	var m = _shader_mat(JCARD_CODE)
	m.set_shader_parameter("at", load(path))
	m.set_shader_parameter("dk", dk)
	m.set_shader_parameter("wd", wd)
	m.set_shader_parameter("g1", _v3(CY))
	m.set_shader_parameter("g2", _v3(MG))
	return m


func _jungle_build() -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = 4242
	var xq = _xquad_mesh()
	# Bäume in vier Reihen je Seite: nah, mittel, fern, ganz fern (dort größer und lockerer)
	var trees = []
	var rows = [[3.0, 5.0, 2.6, 6.0, 10.0, true], [4.0, 12.0, 3.0, 8.0, 14.0, true], [12.0, 35.0, 4.2, 10.0, 18.0, false], [35.0, 75.0, 6.5, 12.0, 21.0, false]]
	for sd in [-1.0, 1.0]:
		for rw in rows:
			var z = 20.0 + rng.randf() * float(rw[2])
			while z < 720.0:
				var near = bool(rw[5])
				var skip = absf(T.lz(z) - JGAP) < 5.0 or (near and T.in_tun(T.lz(z), 4.0))   # nichts in den Erdtunnel
				if not skip:
					var la = rng.randf_range(float(rw[0]), float(rw[1]))
					var h = rng.randf_range(float(rw[3]), float(rw[4]))
					var p = _jf(z, sd, la) + Vector3.UP * -0.15
					var bs = Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(h * 0.667, h, h * 0.667))
					trees.append([Transform3D(bs, p), Color(float(rng.randi() % 4) / 4.0, rng.randf(), 0.0, rng.randf()), z])
				z += float(rw[2]) * rng.randf_range(0.6, 1.4)
	# Unterholz: Farne, große Blätter, Gräser, dazwischen Leuchtpflanzen
	var und = []
	var mush_p = []
	for sd in [-1.0, 1.0]:
		var z = 20.0
		while z < 720.0:
			if not T.in_tun(T.lz(z), 1.0):
				for k in range(2):
					var la = rng.randf_range(0.4, 5.5) if k == 0 else rng.randf_range(0.4, 2.2)
					var r = rng.randf()
					var cell = 0 if r < 0.4 else (1 if r < 0.7 else (2 if r < 0.9 else 3))
					var glow = 1.0 if cell == 3 else 0.0
					if cell == 3:
						mush_p.append([z, sd, la])
					var sz = rng.randf_range(0.6, 1.9) * (0.7 if cell == 3 else 1.0) * clampf(0.45 + la * 0.3, 0.45, 1.0)   # nah an der Planke kleiner
					var p = _jf(z, sd, la) + Vector3.UP * -0.05
					var bs = Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sz, sz, sz))
					und.append([Transform3D(bs, p), Color(float(cell) / 4.0, rng.randf(), glow, rng.randf()), z])
			z += rng.randf_range(0.35, 0.65)
	# Laub, das im Wind vorbeiweht (folgt der Kamera, siehe _pose_all)
	jleaf = GPUParticles3D.new()
	jleaf.amount = 36
	jleaf.lifetime = 5.0
	jleaf.preprocess = 5.0
	jleaf.visibility_aabb = AABB(Vector3(-30, -20, -30), Vector3(60, 40, 60))
	var lpm = ParticleProcessMaterial.new()
	lpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	lpm.emission_box_extents = Vector3(9, 4, 12)
	lpm.direction = Vector3(1, -0.2, 0.3)
	lpm.spread = 40.0
	lpm.initial_velocity_min = 0.8
	lpm.initial_velocity_max = 2.2
	lpm.gravity = Vector3(0, -0.35, 0)
	lpm.turbulence_enabled = true
	lpm.turbulence_noise_strength = 1.2
	lpm.turbulence_noise_scale = 3.0
	lpm.angular_velocity_min = -160.0
	lpm.angular_velocity_max = 160.0
	lpm.angle_min = -180.0
	lpm.angle_max = 180.0
	lpm.scale_min = 0.6
	lpm.scale_max = 1.3
	jleaf.process_material = lpm
	var lq = QuadMesh.new()
	lq.size = Vector2(0.14, 0.09)
	var lmat = _shader_mat(LEAF_CODE)
	lq.material = lmat
	jleaf.draw_pass_1 = lq
	add_child(jleaf)
	# Glühwürmchen
	var fq = QuadMesh.new()
	fq.size = Vector2(0.05, 0.05)
	jfly_mat = _shader_mat(JFLY_CODE)
	fq.material = jfly_mat
	jfly_mm = MultiMesh.new()
	jfly_mm.transform_format = MultiMesh.TRANSFORM_3D
	jfly_mm.use_custom_data = true
	jfly_mm.mesh = fq
	# nur neben der Fahrbahn (nicht davor), ein Teil schwirrt um die Leuchtpilze
	var nfm = mini(160, mush_p.size())
	jfly_mm.instance_count = 420 + nfm
	for i in range(420 + nfm):
		var p: Vector3
		if i < 420:
			var z = rng.randf_range(20.0, 720.0)
			var sd = -1.0 if rng.randf() < 0.5 else 1.0
			p = _jf(z, sd, rng.randf_range(1.8, 14.0)) + Vector3.UP * rng.randf_range(0.8, 4.0)
		else:
			var mp: Array = mush_p[rng.randi() % mush_p.size()]
			p = _jf(mp[0], mp[1], maxf(1.2, mp[2])) + Vector3.UP * rng.randf_range(0.25, 1.0)
		# nie über der Fahrbahn: in der Steilkurve zeigt „oben“ schräg über die Bahn – dann seitlich nach außen schieben
		var ff = T.frame(p.z)
		var lat = (p - ff.c).dot(ff.rr)
		var sgn = signf(lat) if absf(lat) > 0.01 else 1.0
		var mlat = T.TW + 1.6
		if absf(lat) < mlat:
			p += ff.rr * sgn * (mlat - absf(lat))
		jfly_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, p))
		jfly_mm.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), 0, 0))
	jfly_n = jfly_mm.instance_count
	var tmat = _jcard_mat("res://tex/jungle_tree.png", 0.2, 0.02)
	var umat = _jcard_mat("res://tex/jungle_under.png", 0.22, 0.06)
	# Bach
	var wf = T.frame(JGAP)
	var wr: Vector3 = wf.fw.cross(Vector3.UP).normalized()
	var wfw = Vector3.UP.cross(wr).normalized()
	var wpm = PlaneMesh.new()
	wpm.size = Vector2(200.0, 12.0)
	wpm.material = _shader_mat(JWATER_CODE)
	(wpm.material as ShaderMaterial).set_shader_parameter("wc", _v3(CY))
	# in Abschnitte zerlegt, damit der Renderer alles außerhalb des Blickfelds weglässt
	var groups = []
	for pr in [[trees, tmat], [und, umat]]:
		var by = {}
		for it in pr[0]:
			var ci = clampi(int(floor((float(it[2]) - 20.0) / CHUNK)), 0, int(T.LAP / CHUNK) - 1)
			if not by.has(ci):
				by[ci] = []
			by[ci].append(it)
		for ci in by:
			var lst: Array = by[ci]
			var mm = MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = xq
			mm.instance_count = lst.size()
			for i in range(lst.size()):
				mm.set_instance_transform(i, lst[i][0])
				mm.set_instance_custom_data(i, lst[i][1])
			groups.append([mm, pr[1]])
			(jmm_t if pr[1] == tmat else jmm_u).append([mm, lst.size()])
	groups.append([jfly_mm, null])
	for n in laps:
		for pr in groups:
			var mmi = MultiMeshInstance3D.new()
			mmi.multimesh = pr[0]
			if pr[1] != null:
				mmi.material_override = pr[1]
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.extra_cull_margin = 4.0
			n.add_child(mmi)
		var wm = MeshInstance3D.new()
		wm.mesh = wpm
		wm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wm.transform = Transform3D(Basis(wr, Vector3.UP, wfw), wf.c + Vector3.UP * (-0.5 + _jdip(JGAP) + 0.45))
		n.add_child(wm)
	jumat = umat
	_jungle_apply()
	print("JUNGLE trees=", trees.size(), " under=", und.size())


# Kommt in den nächsten Metern eine Kurve? (für den Autopiloten)
var kmax = -1.0


func _curvy(z: float) -> bool:
	if kmax < 0.0:
		kmax = 0.0
		var zz = 20.0
		while zz < 720.0:
			kmax = maxf(kmax, absf(T.kap(zz)))
			zz += 2.0
	for d in [0.0, 6.0, 12.0]:
		if absf(T.kap(z + d)) > 0.45 * kmax:
			return true
	return false


# Lichtsäule über einem Waffenfeld: Lichtkegel plus zwei Lichtringe, die sich in der Mitte treffen und federnd abstoßen
var pring_m = []
var pill_mesh: CylinderMesh
var ring_mesh: TorusMesh


func _pillar_node() -> MeshInstance3D:
	if pring_m.is_empty():
		pill_mesh = CylinderMesh.new()
		pill_mesh.top_radius = 0.3
		pill_mesh.bottom_radius = 0.3
		pill_mesh.height = 2.2
		pill_mesh.cap_top = false
		pill_mesh.cap_bottom = false
		ring_mesh = TorusMesh.new()
		ring_mesh.inner_radius = 0.33
		ring_mesh.outer_radius = 0.4
		ring_mesh.rings = 32
		ring_mesh.ring_segments = 6
		for wh in [1.0, -1.0]:
			var m = _shader_mat("""
shader_type spatial;
render_mode unshaded,blend_add,cull_disabled,depth_draw_never,shadows_disabled,fog_disabled;
uniform float sp=1.;uniform float sz=1.;uniform float gl=1.;uniform float sq=1.;uniform float sf=1.;uniform float wh=1.;uniform float nr=0.;
varying float im;
void vertex(){
	float u=fract(TIME*sp*.3);
	float tri=1.-abs(1.-2.*u);                 // 0 = Rand (Boden/Spitze), 1 = Mitte (Zusammenstoß)
	float b=mix(tri,tri*tri*(3.-2.*tri),clamp(sf*.5,0.,1.));
	float d=min(tri,1.-tri);
	im=exp(-d*d*160.);                         // kurz vor/nach dem Abprallen: Gummi-Stauchung
	VERTEX.xz*=sz*(1.+.3*sq*im);
	VERTEX.y*=max(.2,1.-.45*sq*im);
	VERTEX.y+=wh*(-1.06+1.03*b);
}
void fragment(){
	vec3 c=nr>.5?vec3(1.,.36,.03):(.5+.5*cos(6.2832*(TIME*.3+vec3(0.,.33,.67))));
	ALBEDO=mix(vec3(1.),c,.55)*gl*(1.6+2.5*im);
}""")
			m.set_shader_parameter("wh", wh)
			m.set_shader_parameter("nr", 1.0 if _noir() else 0.0)
			pring_m.append(m)
		_pillar_apply()
	var bm = MeshInstance3D.new()
	bm.mesh = pill_mesh
	bm.material_override = beam_mat
	bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for m in pring_m:
		var r = MeshInstance3D.new()
		r.mesh = ring_mesh
		r.material_override = m
		r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		r.extra_cull_margin = 3.0
		bm.add_child(r)
	return bm


func _pillar_apply() -> void:
	var X: Dictionary = fx.pillar
	for m in pring_m:
		m.set_shader_parameter("sp", float(X.speed))
		m.set_shader_parameter("sz", float(X.size))
		m.set_shader_parameter("gl", float(X.glow))
		m.set_shader_parameter("sq", float(X.squash))
		m.set_shader_parameter("sf", float(X.soft))
	if beam_mat != null:
		beam_mat.set_shader_parameter("bk", float(fx.env.beams) * float(X.beam))


# Häuser verteilen: Anzahl, Höhe, Breite, Abstand zur Strecke aus dem FX Lab (gleicher Zufall, damit die Stadt gleich bleibt)
func _city_fill() -> void:
	if bld_mm == null:
		return
	var E: Dictionary = fx.env
	var dens = float(E.dens) if float(E.city) > 0.5 else 0.0
	var items = []
	var blds = []
	var rng = RandomNumberGenerator.new()
	rng.seed = 7
	var stepz = 16.0 / maxf(0.05, dens)
	var zc = 28.0
	while dens > 0.02 and zc < 720.0:
		var f = T.frame(zc)
		for sd in [-1.0, 1.0]:
			if rng.randf() < 0.3:
				continue
			var lat: float = sd * (T.TW + (11.0 + rng.randf() * 38.0) * float(E.bd))
			var H = (22.0 + pow(rng.randf(), 1.6) * 80.0) * float(E.bh)
			var w = (3.0 + rng.randf() * 5.0) * float(E.bw)
			var d = (3.0 + rng.randf() * 5.0) * float(E.bw)
			var pos = Vector3(f.c.x - lat, -42.0 + H / 2.0, zc + (rng.randf() - 0.5) * 6.0)
			var c = _neo(rng.randf())
			items.append([Transform3D(Basis.from_scale(Vector3(w / 2.0, H / 2.0, d / 2.0)), pos), c, pos.y + H / 2.0])
			blds.append([pos, w, d, H, f.c.x])
		zc += stepz
	# Mega-Türme: riesige Hochhäuser weit draußen, im Dunst nur als Silhouette mit Fensterlichtern (wie in Blade Runner)
	var mk = float(fx.city.mega) if float(E.city) > 0.5 else 0.0
	if mk > 0.01:
		var rm = RandomNumberGenerator.new()
		rm.seed = 11
		var zm = 30.0
		while zm < 720.0:
			var fm = T.frame(zm)
			for sd in [-1.0, 1.0]:
				if rm.randf() < 0.35:
					continue
				var latm: float = sd * (75.0 + rm.randf() * 90.0)
				var Hm = (130.0 + pow(rm.randf(), 1.3) * 210.0) * (0.55 + 0.45 * mk)
				var wm = 14.0 + rm.randf() * 22.0
				var posm = Vector3(fm.c.x - latm, -42.0 + Hm / 2.0, zm + (rm.randf() - 0.5) * 20.0)
				items.append([Transform3D(Basis.from_scale(Vector3(wm / 2.0, Hm / 2.0, wm / 2.0)), posm), _neo(rm.randf()), posm.y + Hm / 2.0])
			zm += 62.0 / clampf(mk, 0.3, 3.0)
	bld_mm.instance_count = 0
	bld_mm.instance_count = items.size()
	for i in range(items.size()):
		bld_mm.set_instance_transform(i, items[i][0])
		var c: Color = items[i][1]
		bld_mm.set_instance_custom_data(i, Color(c.r, c.g, c.b, items[i][2]))
	_city_extras_fill(blds)


# ---------------------------------------------------------------- Blade-Runner-Stadt: Hologramme, Leuchtschilder, Suchscheinwerfer, fliegende Autos
# Riesige, leicht flackernde Hologramme zwischen den Hochhäusern (eine tanzende Frau, schwebende Koi-Karpfen),
# senkrechte Neon-Schilder an den Häusern, Lichtkegel in den Himmel und Gleiter-Autos über der Stadt.
# Nichts davon wirft Licht, alles zusammen sind nur wenige Zeichenaufrufe – das Handy merkt davon kaum etwas.
var city_root: Node3D
var city_xi = []      # Schilder/Scheinwerfer/Autos je Rundenkopie
var holos = []        # {n, mat, kind, ap, spot}
var sign_mm: MultiMesh
var srch_mm: MultiMesh
var car_mm: MultiMesh
var sign_mat: ShaderMaterial
var srch_mat: ShaderMaterial
var car_mat: ShaderMaterial
# Standorte je Runde: [z, Seite (+1 rechts, -1 links), Art]  – nicht in den Tunneln (160–245, 510–595)
const HOLO_SPOTS = [[80.0, 1.0, "dancer"], [300.0, -1.0, "dancer"], [455.0, 1.0, "dancer"], [655.0, -1.0, "dancer"],
	[128.0, -1.0, "koi"], [392.0, 1.0, "koi"], [615.0, -1.0, "koi"]]
const DANCER_H = 1.66   # Größe der Figur im Modell (m)
# Hologramm-Figuren: [Datei, Höhe im Modell, dreht sich (stehende Figur)]
const HOLO_FIGS = [["res://holo/dancer.glb", 1.66, false], ["res://holo/fig_woman1.glb", 1.0, true], ["res://holo/fig_robot.glb", 1.0, true], ["res://holo/fig_woman2.glb", 1.0, true]]
const HOLO_H = 45.0     # Höhe der Hologramme in der Stadt (m)

const HOLO_CODE = """
shader_type spatial;
// Hologramm: leuchtende Ränder, feine Bildzeilen, ein heller Streifen wandert hoch – und Bildstörungen:
// waagrechte Streifen reißen zur Seite, Farben laufen auseinander, Zeilen fallen aus, die ganze Figur zittert
render_mode unshaded,blend_add,cull_back,depth_draw_never,shadows_disabled,fog_disabled;
uniform vec3 c1=vec3(1.,.3,.75);uniform vec3 c2=vec3(.25,.85,1.);
uniform float hk=1.;uniform float fl=1.;uniform float sd=0.;uniform float by=0.;uniform float hh=40.;uniform float gx=0.;
uniform float gs=1.;   // wie weit Störstreifen zur Seite reißen (Start-Mädel: wenig, damit sie nicht wegrutscht)
varying vec3 wp;varying float my;varying float gb;
float h11(float x){return fract(sin(x*127.1)*43758.5453);}
void vertex(){
	vec3 w=(MODEL_MATRIX*vec4(VERTEX,1.)).xyz;
	my=clamp((w.y-by)/hh,0.,1.);
	float g=fl*.35+gx*4.;                                // Stärke: Regler + Wechsel-Störung
	float tk=floor(TIME*(10.+gx*20.)+sd*7.);
	vec3 off=vec3(0.);gb=0.;
	for(int b=0;b<4;b++){
		float fb=float(b);
		float on=step(1.-min(.95,.05*g+gx*.9),h11(tk+fb*13.1+sd*3.1));
		float ce=h11(tk*1.7+fb*5.3);float wd=.015+.1*h11(tk*2.3+fb*1.9);
		float band=on*step(abs(my-ce),wd);
		off.x+=band*(h11(tk*3.1+fb)-.5)*.35*hh*min(g,6.)/3.;
		gb=max(gb,band);
	}
	off.x+=gx*(h11(floor(TIME*31.))-.5)*.12*hh;          // ganze Figur zittert beim Wechsel
	off.y+=gx*(h11(floor(TIME*23.)+1.)-.5)*.04*hh;
	off*=gs;
	VERTEX+=inverse(mat3(MODEL_MATRIX))*off;
	wp=w+off;
}
void fragment(){
	float fr=clamp(1.-abs(dot(NORMAL,VIEW)),0.,1.);
	float rim=fr*fr*1.7+.05;
	float scan=.72+.28*sin(wp.y*10.-TIME*7.);
	float sweep=exp(-pow(abs(fract(my*.7-TIME*.16)-.5)*12.,2.));
	float fk=1.-min(fl,1.)*.6*step(.93,h11(floor(TIME*15.)+sd*5.));
	// Zeilen fallen aus (mehr bei starker Störung)
	float drop=step(fract(wp.y*.35+h11(floor(TIME*12.))*3.),.04*fl+.35*gx);
	vec3 c=mix(c2,c1,my);
	// in gestörten Streifen laufen die Farben auseinander
	c=mix(c,vec3(c.b,c.r*.6+.4,c.g)*1.4,gb);
	float fd=exp(-length(VERTEX)*.0012);
	ALBEDO=c*((.2+rim*1.6)*scan+sweep*.7*(.3+rim))*fk*hk*fd*(1.-drop*.9)*(1.+gx*1.2+gb*.8);
}"""

const KOI_CODE = """
shader_type spatial;
// Koi-Hologramm: weiß mit orangeroten Flecken, schwimmt mit wedelndem Schwanz durch die Luft
render_mode unshaded,blend_add,cull_disabled,depth_draw_never,shadows_disabled,fog_disabled;
uniform float hk=1.;uniform float fl=1.;uniform float sd=0.;uniform float nr=0.;uniform vec3 ec=vec3(.3,.85,1.);
varying vec3 wp;
float h21(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float vn(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);
	return mix(mix(h21(i),h21(i+vec2(1.,0.)),f.x),mix(h21(i+vec2(0.,1.)),h21(i+vec2(1.,1.)),f.x),f.y);}
void vertex(){
	float t=clamp(.5-VERTEX.z,0.,1.);   // 0 = Kopf … 1 = Schwanz
	VERTEX.x+=sin(VERTEX.z*7.-TIME*3.4+sd)*(.012+.12*t*t);
	wp=(MODEL_MATRIX*vec4(VERTEX,1.)).xyz;
}
void fragment(){
	float fr=clamp(1.-abs(dot(NORMAL,VIEW)),0.,1.);
	float rim=fr*fr*1.5+.08;
	float sp=smoothstep(.42,.62,vn(UV*vec2(7.,4.)+sd*13.));
	vec3 kc=nr>.5?mix(vec3(.85),vec3(1.,.36,.03),sp):mix(vec3(1.,.93,.88),vec3(1.,.3,.07),sp);
	float scan=.72+.28*sin(wp.y*10.-TIME*6.);
	float fk=1.-min(fl,1.)*.5*step(.93,h21(vec2(floor(TIME*13.),sd)));
	float fd=exp(-length(VERTEX)*.0012);
	ALBEDO=(kc*(.22+.9*rim)+ec*rim*.6)*scan*fk*hk*fd;
}"""


func _city_extras_make() -> void:
	city_root = Node3D.new()
	add_child(city_root)
	# senkrechte Leuchtschilder mit erfundenen Schriftzeichen
	var q = QuadMesh.new()
	q.size = Vector2.ONE
	sign_mat = _shader_mat("""
shader_type spatial;
render_mode unshaded,cull_disabled;
uniform float ak=1.;
varying vec4 cd;varying vec2 ar;
void vertex(){cd=INSTANCE_CUSTOM;ar=vec2(length(MODEL_MATRIX[0].xyz),length(MODEL_MATRIX[1].xyz));}
float h21(vec2 p){return fract(sin(dot(p,vec2(12.9898,78.233)))*43758.5453);}
void fragment(){
	float sd=cd.a;
	vec2 uv=UV;
	uv.y+=step(.72,fract(sd*7.3))*TIME*.08;            // manche Schilder laufen durch
	float cols=fract(sd*3.7)>.6?2.:1.;
	vec2 g=vec2(uv.x*cols,uv.y*ar.y/ar.x*cols);         // quadratische Zeichenfelder
	vec2 ci=floor(g),cf=fract(g);
	vec2 sg=cf*3.;vec2 si=floor(sg),sf=fract(sg);
	float r=h21(ci*7.3+si*1.7+sd*13.);
	float bar=r>.62?step(abs(sf.y-.5),.2):(r>.3?step(abs(sf.x-.5),.2):0.);
	float mg=step(.14,cf.x)*step(cf.x,.86)*step(.12,cf.y)*step(cf.y,.88);
	float glyph=bar*mg*step(.18,h21(ci+sd));
	float fw=.035;
	float frame=1.-step(fw,UV.x)*step(UV.x,1.-fw*1.)*step(fw*ar.x/ar.y,UV.y)*step(UV.y,1.-fw*ar.x/ar.y);
	float fk=1.-.85*step(.975,h21(vec2(floor(TIME*9.),sd*31.)));   // kurzes Aussetzen wie bei alten Röhren
	ALBEDO=vec3(.012)+cd.rgb*(glyph*2.4+frame*3.)*fk*ak;
}""")
	q.material = sign_mat
	sign_mm = MultiMesh.new()
	sign_mm.transform_format = MultiMesh.TRANSFORM_3D
	sign_mm.use_custom_data = true
	sign_mm.mesh = q
	# Suchscheinwerfer: Lichtkegel schwenken langsam über den Himmel
	var cy = CylinderMesh.new()
	cy.top_radius = 4.0
	cy.bottom_radius = 0.35
	cy.height = 140.0
	cy.radial_segments = 10
	cy.rings = 1
	cy.cap_top = false
	cy.cap_bottom = false
	srch_mat = _shader_mat("""
shader_type spatial;
render_mode unshaded,blend_add,cull_disabled,depth_draw_never,shadows_disabled,fog_disabled;
uniform float sk=1.;
varying float v;
void vertex(){
	float sd=INSTANCE_CUSTOM.a;
	vec3 p=VERTEX+vec3(0.,70.,0.);                      // Fuß des Kegels auf dem Dach
	v=p.y/140.;
	float a=sin(TIME*(.16+.1*sd)+sd*40.)*.55;
	float b=.2+.2*sin(TIME*.1+sd*17.);
	mat3 rz=mat3(vec3(cos(a),sin(a),0.),vec3(-sin(a),cos(a),0.),vec3(0.,0.,1.));
	mat3 rx=mat3(vec3(1.,0.,0.),vec3(0.,cos(b),sin(b)),vec3(0.,-sin(b),cos(b)));
	VERTEX=rx*rz*p;
	NORMAL=rx*rz*NORMAL;
}
void fragment(){
	float core=pow(abs(dot(NORMAL,VIEW)),3.);
	float fade=(1.-v)*(1.-v)*smoothstep(0.,.03,v);
	ALBEDO=vec3(.7,.82,1.)*core*fade*.3*sk*exp(-length(VERTEX)*.003);
}""")
	cy.material = srch_mat
	srch_mm = MultiMesh.new()
	srch_mm.transform_format = MultiMesh.TRANSFORM_3D
	srch_mm.use_custom_data = true
	srch_mm.mesh = cy
	# fliegende Autos: vorn helle Scheinwerfer, hinten rote Lichter – ziehen über der Stadt ihre Bahnen
	var bx = BoxMesh.new()
	bx.size = Vector3(0.8, 0.32, 2.6)
	car_mat = _shader_mat("""
shader_type spatial;
render_mode unshaded,cull_disabled,shadows_disabled;
uniform float ck=1.;
varying float f;
void vertex(){
	vec4 cd=INSTANCE_CUSTOM;
	float dir=cd.r>.5?1.:-1.;
	float sp=dir*(26.+cd.g*34.);
	f=VERTEX.z*dir/1.3;
	VERTEX.z+=mod(TIME*sp+cd.b*700.,700.);
	VERTEX.y+=sin(TIME*.6+cd.b*30.)*1.2;
}
void fragment(){
	vec3 c=vec3(.03,.035,.05);
	c+=vec3(1.,.95,.85)*smoothstep(.8,1.,f)*7.;
	c+=vec3(1.,.08,.12)*smoothstep(-.8,-1.,f)*6.;
	ALBEDO=c*ck;
}""")
	bx.material = car_mat
	car_mm = MultiMesh.new()
	car_mm.transform_format = MultiMesh.TRANSFORM_3D
	car_mm.use_custom_data = true
	car_mm.mesh = bx


# Schilder an die Häuser, Scheinwerfer auf die Dächer, Autos in die Luft (eine Runde; die Rundenkopien teilen sich das)
func _city_extras_fill(blds: Array) -> void:
	if sign_mm == null:
		return
	var rng = RandomNumberGenerator.new()
	rng.seed = 23
	var pal = [Color(1.0, 0.15, 0.45), Color(0.1, 0.85, 1.0), Color(1.0, 0.62, 0.1), Color(1.0, 0.12, 0.12), Color(0.95, 0.3, 1.0), Color(0.3, 1.0, 0.6)]
	if _noir():
		pal = [OR, Color(0.9, 0.9, 0.92), Color(1.0, 0.5, 0.12)]
	var sg = []
	var sl = []
	for b in blds:
		var pos: Vector3 = b[0]
		var w: float = b[1]
		var H: float = b[3]
		var top = H - 42.0
		if rng.randf() < 0.55 and top > 14.0:
			var sw = 2.2 + rng.randf() * 1.6
			var sh = 8.0 + rng.randf() * 9.0
			var sgn = signf(b[4] - pos.x)
			var y = minf(2.0 + rng.randf() * 24.0, top - sh * 0.5 - 1.0)
			var p = Vector3(pos.x + sgn * (w * 0.5 + sw * 0.5 + 0.15), y, pos.z + (rng.randf() - 0.5) * b[2] * 0.6)
			var c: Color = pal[rng.randi() % pal.size()]
			sg.append([Transform3D(Basis.from_scale(Vector3(sw, sh, 1.0)), p), Color(c.r, c.g, c.b, rng.randf())])
		if top > 45.0 and rng.randf() < 0.22:
			sl.append([Transform3D(Basis.IDENTITY, Vector3(pos.x, top, pos.z)), Color(0, 0, 0, rng.randf())])
	sign_mm.instance_count = 0
	sign_mm.instance_count = sg.size()
	for i in range(sg.size()):
		sign_mm.set_instance_transform(i, sg[i][0])
		sign_mm.set_instance_custom_data(i, sg[i][1])
	srch_mm.instance_count = 0
	srch_mm.instance_count = sl.size()
	for i in range(sl.size()):
		srch_mm.set_instance_transform(i, sl[i][0])
		srch_mm.set_instance_custom_data(i, sl[i][1])
	var nc = 28
	car_mm.instance_count = nc
	# Autos und Lichtkegel bewegen sich im Shader: Sichtbarkeitsbox über die ganze Runde
	car_mm.custom_aabb = AABB(Vector3(-120, -10, 0), Vector3(240, 90, 760))
	srch_mm.custom_aabb = AABB(Vector3(-260, -60, 0), Vector3(520, 420, 760))
	var rc = RandomNumberGenerator.new()
	rc.seed = 31
	for i in range(nc):
		var side = -1.0 if i % 2 == 0 else 1.0
		var x = side * (8.0 + rc.randf() * 70.0)
		car_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(x, 14.0 + rc.randf() * 34.0, 20.0)))
		car_mm.set_instance_custom_data(i, Color(1.0 if rc.randf() < 0.5 else 0.0, rc.randf(), rc.randf(), 0.0))


# Regler aus dem Reiter „City“ auf Schilder, Scheinwerfer und Autos anwenden
func _city_apply() -> void:
	if sign_mat == null:
		return
	var C: Dictionary = fx.city
	var on = float(fx.env.city) > 0.5
	_sp(sign_mat, "ak", float(C.signs))
	_sp(srch_mat, "sk", float(C.search))
	_sp(car_mat, "ck", float(C.cars))
	for i in range(city_xi.size()):
		var xi: MultiMeshInstance3D = city_xi[i]
		var k = [float(C.signs), float(C.search), float(C.cars)][i % 3]
		xi.visible = on and k > 0.01


func _holo_node(kind: String) -> Dictionary:
	var h = {"kind": kind, "spot": -1.0e9}
	var mat: ShaderMaterial
	if kind == "dancer":
		# Hologramm-Platz mit mehreren Figuren, die sich mit einer kräftigen Bildstörung abwechseln
		mat = _shader_mat(HOLO_CODE)
		var root = Node3D.new()
		h.figs = []
		for fd in HOLO_FIGS:
			var n: Node3D = load(fd[0]).instantiate()
			for mi in n.find_children("*", "MeshInstance3D", true, false):
				(mi as MeshInstance3D).material_override = mat
				(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				(mi as MeshInstance3D).extra_cull_margin = 0.6
			var fg = {"n": n, "h": fd[1], "spin": fd[2]}
			var aps = n.find_children("*", "AnimationPlayer", true, false)
			if not aps.is_empty():
				var ap: AnimationPlayer = aps[0]
				var nm = "SambaDance" if ap.has_animation("SambaDance") else ap.get_animation_list()[0]
				ap.get_animation(nm).loop_mode = Animation.LOOP_LINEAR
				ap.play(nm)
				ap.active = false
				fg.ap = ap
			n.visible = false
			root.add_child(n)
			h.figs.append(fg)
		h.fi = 0
		h.swt = 0.0
		h.gx = 0.0
		h.n = root
	else:
		mat = _shader_mat(KOI_CODE)
		var mi = MeshInstance3D.new()
		mi.mesh = _koi_mesh()
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		h.n = mi
	h.mat = mat
	(h.n as Node3D).visible = false
	city_root.add_child(h.n)
	return h


func _holos_make() -> void:
	for kind in ["dancer", "dancer"]:   # Koi-Fische entfernt
		var h = _holo_node(kind)
		_sp(h.mat, "sd", float(holos.size()) * 1.37)
		if kind == "dancer":
			h.fi = (holos.size() * 2) % HOLO_FIGS.size()   # die zwei Plätze starten mit verschiedenen Figuren
			h.swt = 4.0 * holos.size()
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--holofig="):
					h.fi = int(a.substr(10)) % HOLO_FIGS.size()
				if a.begins_with("--holoswt="):
					h.swt = float(a.substr(10))
		holos.append(h)


# Start-Mädel: großes Hologramm über der Strecke vor dem Feld – Arme hoch bei 3‑2‑1, bei GO runter, dann zack weg mit Glitch
var starter = {}
const ST_H = 15.5   # Größe in m (so groß, dass sie mit Flagge im Hochformat ganz ins Bild passt)


const ST_MH = 0.955   # Höhe des Start-Mädel-Modells (Kopf oben) in Modell-Einheiten
const FLAG_CODE = """
shader_type spatial;
render_mode unshaded,cull_disabled,shadows_disabled;
uniform sampler2D tex:source_color,filter_linear_mipmap;
uniform float sw=1.;uniform float k=1.;
varying float ed;
void vertex(){
	// Welle läuft vom Mast weg, außen stärker; „sw“ = Wind/Schwung
	float u=UV.x;
	float w=sin(u*7.5-TIME*(6.+5.*sw)+UV.y*1.7)*.06+sin(u*13.-TIME*9.)*.02;
	VERTEX.z+=w*u*(.6+sw)*.5;
	VERTEX.y-=u*u*.04*(1.4-sw*.4);
}
void fragment(){
	vec3 c=texture(tex,UV).rgb;
	float e=max(max(smoothstep(.965,1.,UV.x),smoothstep(.04,0.,UV.y)),smoothstep(.96,1.,UV.y));
	ALBEDO=c*k+vec3(1.,.08,.12)*e*2.2*k;
}"""


func _starter_make() -> void:
	var root = Node3D.new()
	var m: Node3D = load("res://art/starter/starter.glb").instantiate()
	# Modell steht mit z nach oben und schaut nach +x: aufrichten
	m.transform = Transform3D.IDENTITY
	root.add_child(m)
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var mm = mi as MeshInstance3D
		var src = mm.mesh.surface_get_material(0) as StandardMaterial3D
		var um = StandardMaterial3D.new()
		um.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED   # Manga-Look: flach und gut sichtbar bei Nacht
		if src != null:
			um.albedo_texture = src.albedo_texture
		um.albedo_color = Color(0.92, 0.9, 0.92)
		mm.material_override = um
		mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mm.extra_cull_margin = 0.6
	var sk: Skeleton3D = m.find_children("*", "Skeleton3D", true, false)[0]
	root.visible = false
	add_child(root)
	var d = {"n": root, "sk": sk, "arms": []}
	for b in [["mixamorig_LeftArm", 1.0], ["mixamorig_RightArm", -1.0]]:
		var ia = sk.find_bone(b[0])
		var ifa = sk.find_bone(b[0].replace("Arm", "ForeArm"))
		var ih = sk.find_bone(b[0].replace("Arm", "Hand"))
		if ia < 0 or ifa < 0 or ih < 0:
			continue
		d.arms.append({"ia": ia, "ifa": ifa, "ih": ih, "s": b[1], "hg": sk.get_bone_global_rest(ih).basis,
			"pg": sk.get_bone_global_rest(sk.get_bone_parent(ia)).basis, "bg": sk.get_bone_global_rest(ia).basis, "fg": sk.get_bone_global_rest(ifa).basis})
	# Drachenflagge in der rechten Hand: Mast entlang der Finger, Tuch weht nach außen
	var ba = Node3D.new()   # folgt jedes Bild der Hand, Mast bleibt dabei eher senkrecht (siehe _starter_live)
	ba.top_level = true
	root.add_child(ba)
	d.fp = ba
	var pole = MeshInstance3D.new()
	var cy = CylinderMesh.new()
	cy.top_radius = 0.006
	cy.bottom_radius = 0.006
	cy.height = 0.34
	cy.radial_segments = 8
	cy.rings = 1
	pole.mesh = cy
	var pm = StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.albedo_color = Color(0.12, 0.12, 0.14)
	pole.material_override = pm
	pole.position = Vector3(0, 0.13, 0)
	ba.add_child(pole)
	var tip = MeshInstance3D.new()
	tip.mesh = _lowsphere(0.012, 8, 4)
	var tm = StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.albedo_color = Color(1.0, 0.15, 0.2)
	tip.material_override = tm
	tip.position = Vector3(0, 0.3, 0)
	ba.add_child(tip)
	var fl = MeshInstance3D.new()
	var pl = PlaneMesh.new()
	pl.size = Vector2(0.3, 0.2)
	pl.subdivide_width = 18
	pl.subdivide_depth = 8
	pl.orientation = PlaneMesh.FACE_Z
	pl.center_offset = Vector3(0.15, -0.1, 0)
	fl.mesh = pl
	var fm = _shader_mat(FLAG_CODE)
	fm.set_shader_parameter("tex", load("res://art/starter/flag.jpg"))
	fl.material_override = fm
	fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Tuch-x zeigt von der Hand weg (Hand-z), Tuch-y entlang des Masts
	fl.transform = Transform3D(Basis.IDENTITY, Vector3(0, 0.29, 0))
	ba.add_child(fl)
	d.flag = fm
	d.fln = fl
	starter = d


# Start-Mädel: Arme einzeln stellen (Grad über waagrecht, Grad nach vorn); Skelettraum: oben +z, vorn +x
func _st_arms(d: Dictionary, upL: float, upR: float, fwdL := 0.0, fwdR := 0.0) -> void:
	var sk: Skeleton3D = d.sk
	for a in d.arms:
		var sg = float(a.s)
		var up = upL if sg > 0.0 else upR
		var fw = fwdL if sg > 0.0 else fwdR
		var ra = Basis(Vector3(0, 0, 1), deg_to_rad(fw) * -sg) * Basis(Vector3(1, 0, 0), deg_to_rad(up) * sg)
		var ag: Basis = ra * (a.bg as Basis)
		sk.set_bone_pose_rotation(a.ia, ((a.pg as Basis).inverse() * ag).get_rotation_quaternion())
		var fgp: Basis = ra * (a.fg as Basis)
		sk.set_bone_pose_rotation(a.ifa, (ag.inverse() * fgp).get_rotation_quaternion())
		var rh: Basis = ra * (a.hg as Basis)
		sk.set_bone_pose_rotation(a.ih, (fgp.inverse() * rh).get_rotation_quaternion())


# eigene Hologramm-Figur (Michelle) mit Skelett, dessen Arme wir selbst stellen
func _hfig_make() -> Dictionary:
	var n: Node3D = load(HOLO_FIGS[0][0]).instantiate()
	var mat = _shader_mat(HOLO_CODE)
	_sp(mat, "sd", randf() * 10.0)
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = mat
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(mi as MeshInstance3D).extra_cull_margin = 0.6
	for ap in n.find_children("*", "AnimationPlayer", true, false):
		(ap as AnimationPlayer).stop()
		(ap as AnimationPlayer).active = false
	var sk: Skeleton3D = n.find_children("*", "Skeleton3D", true, false)[0]
	n.visible = false
	add_child(n)
	var d = {"n": n, "mat": mat, "sk": sk, "arms": []}
	# je Seite Oberarm + Unterarm; Drehungen im Skelettraum (Hochachse -z, Seitachse x, Blickachse y)
	for b in [["mixamorig_LeftArm", "mixamorig_LeftForeArm", 1.0], ["mixamorig_RightArm", "mixamorig_RightForeArm", -1.0]]:
		var ia = sk.find_bone(b[0])
		var ifa = sk.find_bone(b[1])
		var ih = sk.find_bone(b[0].replace("Arm", "Hand"))
		if ia < 0 or ifa < 0 or ih < 0:
			continue
		d.arms.append({"ia": ia, "ifa": ifa, "ih": ih, "s": b[2], "hg": sk.get_bone_global_rest(ih).basis,
			"pg": sk.get_bone_global_rest(sk.get_bone_parent(ia)).basis, "bg": sk.get_bone_global_rest(ia).basis, "fg": sk.get_bone_global_rest(ifa).basis})
	return d


# Arme stellen: hoch = Grad über waagrecht, vor = Grad nach vorn; Unterarm eigene Werte (relativ zum Körper)
func _hfig_arms(d: Dictionary, up: float, fwd: float, fup: float, ffwd: float, hb := 0.0) -> void:
	var sk: Skeleton3D = d.sk
	for a in d.arms:
		var sg = float(a.s)
		var ra = Basis(Vector3(0, 0, 1), deg_to_rad(fwd) * sg * HF_FWD) * Basis(Vector3(0, 1, 0), deg_to_rad(up) * sg)
		var rf = Basis(Vector3(0, 0, 1), deg_to_rad(ffwd) * sg * HF_FWD) * Basis(Vector3(0, 1, 0), deg_to_rad(fup) * sg)
		var ag: Basis = ra * (a.bg as Basis)
		sk.set_bone_pose_rotation(a.ia, ((a.pg as Basis).inverse() * ag).get_rotation_quaternion())
		var fgp: Basis = rf * (a.fg as Basis)
		sk.set_bone_pose_rotation(a.ifa, (ag.inverse() * fgp).get_rotation_quaternion())
		# Hand nach hinten abknicken (hb 0…1): offene Handfläche nach vorn wie ein Stoppzeichen
		var rh = Basis(Vector3(0, 0, 1), deg_to_rad(ffwd - 40.0 * hb) * sg * HF_FWD) * Basis(Vector3(0, 1, 0), deg_to_rad(fup + 60.0 * hb) * sg)
		sk.set_bone_pose_rotation(a.ih, (fgp.inverse() * rh * (a.hg as Basis)).get_rotation_quaternion())


func _hfig_look(d: Dictionary, base_y: float, H: float, gx: float, hk := 1.3, gs := 0.15) -> void:
	var mat: ShaderMaterial = d.mat
	_sp(mat, "gs", gs)
	var hue = float(fx.city.hhue)
	var c1 = _hs(Color(1.0, 0.3, 0.75), hue)
	var c2 = _hs(Color(0.25, 0.85, 1.0), hue)
	if _noir():
		c1 = OR
		c2 = Color(0.9, 0.9, 0.95)
	_sp(mat, "c1", _v3(c1))
	_sp(mat, "c2", _v3(c2))
	_sp(mat, "hk", hk)
	_sp(mat, "fl", float(fx.city.hflick))
	_sp(mat, "gx", gx)
	_sp(mat, "by", base_y)
	_sp(mat, "hh", H)


const HF_FWD = 1.0   # Vorzeichen „nach vorn“ im Skelettraum


# Winkel der Arme (Grad, 0 = waagrecht, + = hoch) und Glitch-Stärke über die Startphase
func _starter_pose() -> Array:
	var ang = -72.0    # Flaggenarm (rechts)
	var al = -72.0     # freier Arm (links)
	var sw = 0.4       # Schwung fürs Tuch
	var vis = true
	if state == "intro":
		ang = -62.0 + sin(t_state * 2.0) * 4.0
		al = -70.0 + sin(t_state * 1.6) * 3.0
	elif state == "count":
		var c = 3 - int(floor(t_state))
		var u = t_state - floor(t_state)
		var e = 1.0 - pow(1.0 - clampf(u / 0.22, 0.0, 1.0), 3.0)
		var tg = [-62.0, 62.0, 42.0, 20.0][clampi(c, 0, 3)]       # 3: schräg hoch · 2: höher · 1: Flagge hoch
		var pv = [-62.0, 62.0, 42.0, 20.0][clampi(c + 1, 0, 3)] if c < 3 else -62.0
		ang = lerpf(pv, tg, e)
		var tl = [-70.0, 20.0, 8.0, -5.0][clampi(c, 0, 3)]       # anderer Arm geht zur Seite raus
		var pl = [-70.0, 20.0, 8.0, -5.0][clampi(c + 1, 0, 3)] if c < 3 else -70.0
		al = lerpf(pl, tl, e)
		if c == 1:
			ang += sin(u * 40.0) * 2.0 * u        # zittert vor Spannung
		sw = 0.6 + 1.2 * (1.0 - e)
	elif state == "race" and t_state < 1.4:
		# GO: Flagge runterreißen, das Tuch schlägt nach
		var a = clampf(t_state / 0.14, 0.0, 1.0)
		ang = lerpf(62.0, -50.0, a * a)
		al = lerpf(20.0, -45.0, a)
		sw = 2.0 - t_state
	else:
		vis = false
	return [vis, ang, al, sw]


func _starter_live() -> void:
	if not ships.is_empty() and starter.is_empty() and not laps.is_empty():
		_starter_make()
	if starter.is_empty():
		return
	var ps = _starter_pose()
	var n: Node3D = starter.n
	if state == "replay" or ships.is_empty():
		ps[0] = false
	if n.visible != ps[0]:
		n.visible = ps[0]
	if not ps[0]:
		return
	var f = T.frame(T.ZST + 36.0)
	var fw: Vector3 = (f.fw * Vector3(1, 0, 1)).normalized()
	n.global_transform = Transform3D(Basis.looking_at(fw, Vector3.UP).scaled(Vector3.ONE * (ST_H / ST_MH)), f.c + Vector3.UP * -0.2)
	_st_arms(starter, float(ps[2]), float(ps[1]), 8.0, 10.0)
	_sp(starter.flag, "sw", float(ps[3]))
	# Flaggenmast: an der Hand, Richtung halb Arm, halb senkrecht (beim Runterreißen ganz mit dem Arm)
	var sk1: Skeleton3D = starter.sk
	var hx: Transform3D = sk1.global_transform * sk1.get_bone_global_pose(sk1.find_bone("mixamorig_RightHand"))
	var sx: Transform3D = sk1.global_transform * sk1.get_bone_global_pose(sk1.find_bone("mixamorig_RightArm"))
	var adir: Vector3 = (hx.origin - sx.origin).normalized()
	var wv = 0.72 if state != "race" else clampf(0.72 - t_state * 6.0, 0.0, 0.72)
	var pdir: Vector3 = adir.lerp(Vector3.UP, wv).normalized()
	var nrm: Vector3 = -fw
	var outv: Vector3 = (adir - pdir * adir.dot(pdir))
	if outv.length() < 0.05:
		outv = nrm.cross(pdir)
	outv = outv.normalized()
	nrm = outv.cross(pdir).normalized()
	var sc = ST_H / ST_MH
	(starter.fp as Node3D).global_transform = Transform3D(Basis(outv * sc, pdir * sc, nrm * sc), hx.origin)


# Koi aus einem gebogenen Rumpf mit Schwanz-, Rücken- und Brustflossen (Länge 1, Kopf bei +z)
var koi_m: ArrayMesh


func _koi_mesh() -> ArrayMesh:
	if koi_m != null:
		return koi_m
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var NS = 14
	var NA = 12
	var rings = []
	for i in range(NS + 1):
		var u = float(i) / NS
		var w = 0.12 * pow(sin(PI * (0.06 + 0.9 * u)), 0.75) * (1.0 - 0.55 * u) + 0.012
		var z = 0.5 - u * 0.8
		var ring = []
		for a in range(NA + 1):
			var an = TAU * a / NA
			ring.append([Vector3(cos(an) * w, sin(an) * w * 0.85, z), Vector2(u, float(a) / NA)])
		rings.append(ring)
	for i in range(NS):
		for a in range(NA):
			var p0 = rings[i][a]
			var p1 = rings[i + 1][a]
			var p2 = rings[i + 1][a + 1]
			var p3 = rings[i][a + 1]
			for qv in [p0, p2, p1, p0, p3, p2]:
				st.set_uv(qv[1])
				st.add_vertex(qv[0])
	var fins = [
		[Vector3(0, 0, -0.27), Vector3(0, 0.19, -0.58), Vector3(0, 0, -0.44)],    # Schwanz oben
		[Vector3(0, 0, -0.27), Vector3(0, 0, -0.44), Vector3(0, -0.19, -0.58)],   # Schwanz unten
		[Vector3(0, 0.08, 0.16), Vector3(0, 0.16, 0.0), Vector3(0, 0.07, -0.12)],  # Rückenflosse
		[Vector3(0.07, -0.04, 0.24), Vector3(0.22, -0.1, 0.1), Vector3(0.06, -0.05, 0.12)],
		[Vector3(-0.07, -0.04, 0.24), Vector3(-0.06, -0.05, 0.12), Vector3(-0.22, -0.1, 0.1)]]
	for fn in fins:
		for v in fn:
			st.set_uv(Vector2(0.5, 0.5))
			st.add_vertex(v)
	st.generate_normals()
	koi_m = st.commit()
	return koi_m


# jedes Bild: Hologramme an die nächsten Standorte vor der Kamera setzen (2 Tänzerinnen, 2 Koi)
func _city_live() -> void:
	if holos.is_empty() or cam == null:
		return
	var C: Dictionary = fx.city
	var city_on = float(fx.env.city) > 0.5
	var hk = float(C.holo) if city_on else 0.0
	var kk = 0.0
	var hs = float(C.hsize)
	var cz = cam.global_position.z
	var base = floor((cz - 20.0) / T.LAP) * T.LAP
	var cands = {"dancer": [], "koi": []}
	for sp in HOLO_SPOTS:
		for k in [-1.0, 0.0, 1.0]:
			var zz: float = sp[0] + base + k * T.LAP
			var d = zz - cz
			if d > -80.0 and d < 520.0:
				cands[sp[2]].append([d, zz, sp[1]])
	for kd in cands:
		cands[kd].sort_custom(_by_first)
	var used = {"dancer": 0, "koi": 0}
	var hue = float(C.hhue)
	var c1 = _hs(Color(1.0, 0.3, 0.75), hue)
	var c2 = _hs(Color(0.25, 0.85, 1.0), hue)
	if _noir():
		c1 = OR
		c2 = Color(0.9, 0.9, 0.95)
	var tt = Time.get_ticks_msec() / 1000.0
	for h in holos:
		var kind: String = h.kind
		var lst: Array = cands[kind]
		var i: int = used[kind]
		used[kind] = i + 1
		var vis = (hk if kind == "dancer" else kk) > 0.01 and i < lst.size()
		var nd: Node3D = h.n
		if nd.visible != vis:
			nd.visible = vis
		if not vis:
			if h.has("figs"):
				for fg in h.figs:
					if fg.has("ap") and (fg.ap as AnimationPlayer).active:
						(fg.ap as AnimationPlayer).active = false
			continue
		var c: Array = lst[i]
		var f = T.frame(c[1])
		var mat: ShaderMaterial = h.mat
		_sp(mat, "fl", float(C.hflick))
		if kind == "dancer":
			var H = HOLO_H * hs
			if h.spot != c[1] or h.get("H", 0.0) != H:
				h.spot = c[1]
				h.H = H
				var p: Vector3 = f.c + f.rr * (c[2] * (T.TW + 22.0 + 8.0 * hs)) + Vector3.UP * (-14.0)
				var dir: Vector3 = (f.c - f.fw * 40.0 - p) * Vector3(1, 0, 1)
				nd.global_transform = Transform3D(Basis.looking_at(-dir.normalized(), Vector3.UP), p)
				_sp(mat, "by", p.y)
				_sp(mat, "hh", H)
			# alle paar Sekunden: kräftige Bildstörung, dabei wechselt die Figur
			var dt2 = get_process_delta_time()
			h.swt += dt2
			var per = 9.0
			var gx = 0.0
			if h.swt > per - 0.3:
				gx = clampf((h.swt - (per - 0.3)) / 0.3, 0.0, 1.0)
			if h.swt > per:
				h.swt = -0.4 * randf()
				h.fi = (int(h.fi) + 1 + randi() % maxi(1, HOLO_FIGS.size() - 1)) % HOLO_FIGS.size()
			if h.swt < 0.0:
				gx = maxf(gx, clampf(-h.swt / 0.4 + 0.5, 0.0, 1.0))
			if h.swt >= 0.0 and h.swt < 0.45:
				gx = maxf(gx, 1.0 - h.swt / 0.45)
			_sp(mat, "gx", gx)
			for k in range(h.figs.size()):
				var fg: Dictionary = h.figs[k]
				var on = k == int(h.fi)
				var fn: Node3D = fg.n
				if fn.visible != on:
					fn.visible = on
				if fg.has("ap") and (fg.ap as AnimationPlayer).active != on:
					(fg.ap as AnimationPlayer).active = on
				if on:
					var s0 = H / float(fg.h)
					var yaw = tt * 0.35 if fg.spin else 0.0
					var bob = sin(tt * 0.6 + float(k)) * 1.2 if fg.spin else 0.0
					fn.transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s0), Vector3(0, bob, 0))
			_sp(mat, "hk", hk)
			_sp(mat, "c1", _v3(c1))
			_sp(mat, "c2", _v3(c2))
		else:
			# Koi zieht weite Kreise über den Dächern neben der Strecke
			var R = 16.0 * hs
			var ctr: Vector3 = f.c + f.rr * (c[2] * (T.TW + 18.0 + R * 0.6)) + Vector3.UP * (26.0 + 6.0 * hs)
			var a = tt * 0.28 + float(h.mat.get_shader_parameter("sd"))
			var pos = ctr + Vector3(cos(a), 0.0, sin(a)) * R + Vector3.UP * sin(tt * 0.5 + a) * 2.0
			var tg = Vector3(-sin(a), 0.12 * cos(tt * 0.5 + a), cos(a)).normalized()
			var bx = Vector3.UP.cross(tg).normalized()
			var by = tg.cross(bx).normalized()
			nd.global_transform = Transform3D(Basis(bx, by, tg).rotated(tg, -0.25).scaled(Vector3.ONE * 21.0 * hs), pos)
			_sp(mat, "hk", kk)
			_sp(mat, "nr", 1.0 if _noir() else 0.0)
			_sp(mat, "ec", _v3(c2))


# ---------------------------------------------------------------- Gleiter
func _ship_node(idx: int) -> Node3D:
	var root = Node3D.new()
	var piv = Node3D.new()
	root.add_child(piv)
	if SHIPS[idx][2]:
		piv.rotation.y = PI
	var m: Node3D = load(SHIPS[idx][0]).instantiate()
	piv.add_child(m)
	var jets = []
	# Ständer aus dem Modell entfernen, Boost-Strahlen merken
	for n in m.find_children("*", "", true, false):
		var nm = str(n.name)
		if nm.contains("Base"):
			n.queue_free()
		elif nm.contains("Boost"):
			jets.append(n)
	# Größe: Länge 1,5, Unterkante auf 0, mittig
	var bb = AABB()
	var first = true
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var nm2 = str(mi.name) + str(mi.get_parent().name)
		if nm2.contains("Base") or nm2.contains("Boost"):
			continue
		var a: AABB = (m.global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb() if mi.is_inside_tree() else _rel_xf(m, mi) * mi.get_aabb()
		bb = a if first else bb.merge(a)
		first = false
	var s = 1.5 / maxf(0.01, bb.size.z)
	m.scale = Vector3(s, s, s)
	m.position = -Vector3(bb.get_center().x, bb.position.y, bb.get_center().z) * s
	root.set_meta("bb", AABB(Vector3(-bb.size.x * 0.5, 0.0, -bb.size.z * 0.5) * s, bb.size * s))
	# Positionslichter wie am Flugzeug: rot links, grün rechts, kurzer Blitz (FX Lab „Ship“: Nav lights)
	for sd in [-1.0, 1.0]:
		var nl = MeshInstance3D.new()
		nl.mesh = _lowsphere(0.022, 8, 4)
		nl.material_override = nav_mat(sd)
		nl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		nl.position = Vector3(sd * bb.size.x * s * 0.47, bb.size.y * s * 0.45, bb.size.z * s * 0.05)
		root.add_child(nl)
	var lt = OmniLight3D.new()
	lt.light_color = Color(0.6, 0.4, 1.0)
	lt.light_energy = 1.4
	lt.omni_range = 4.0
	lt.position = Vector3(0, 0.15, -0.95)
	root.add_child(lt)
	root.set_meta("jets", jets)
	for j in jets:
		(j as Node3D).visible = false   # die Boost-Flammen des Modells ersetzt der Plasmastrahl
	# Plasmastrahl aus jeder Düse: läuft immer (Triebwerk an), wird mit dem Tempo länger und beim Boost groß
	var jm = _shader_mat(JET_CODE)
	var gm = _shader_mat(JETGLOW_CODE)
	var jn = []
	for jd in JETS[idx]:
		var cone = MeshInstance3D.new()
		cone.mesh = _jet_mesh()
		cone.material_override = jm
		cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(cone)
		var gl = MeshInstance3D.new()
		var gq = QuadMesh.new()
		gq.size = Vector2.ONE
		gl.mesh = gq
		gl.material_override = gm
		gl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gl.position = Vector3(jd[0], jd[1], jd[2] - 0.01)
		gl.scale = Vector3.ONE * jd[3] * 6.0
		root.add_child(gl)
		jn.append([cone, jd])
	root.set_meta("pj", jn)
	root.set_meta("pjm", [jm, gm])
	# Hitzeflimmern: zwei kleine Flächen direkt hinter der Düse, im Raum verankert.
	# Sie verzerren nur, was dahinter liegt; steht das Schiff davor (Blick von vorn), bleibt es scharf.
	var hz = []
	var hzn = []
	for k in range(2):
		var q = QuadMesh.new()
		q.size = Vector2.ONE
		var hm = MeshInstance3D.new()
		hm.mesh = q
		var mat = _shader_mat(HAZE_CODE)
		# vor allen anderen durchsichtigen Dingen zeichnen: das Flimmern liest das Bild ohne Durchsichtiges –
		# sonst würde es die Düsenflammen und Funken dahinter einfach überdecken
		mat.render_priority = -2   # auch vor der Nass-Spiegelung der Fahrbahn (die liegt sonst als Fleck im Flimmern)
		hm.material_override = mat
		hm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var zr = -1.5 * 0.5 - (0.28 if k == 0 else 0.85)
		hm.position = Vector3(0, 0.2, zr)
		hm.scale = Vector3.ONE * (0.75 if k == 0 else 1.1)
		root.add_child(hm)
		hz.append(mat)
		hzn.append(hm)
	root.set_meta("haze", hz)
	root.set_meta("hazen", hzn)
	root.set_meta("light", lt)
	root.set_meta("dg", _dangle_build(root, idx))
	root.set_meta("rings", _rings_build(root, idx))
	add_child(root)
	return root


# ---------------------------------------------------------------- Antigrav-Ringe: dunkles Gehäuse, leuchtender Ring, Lichtschein auf der Fahrbahn
const RING_CODE = """
shader_type spatial;
render_mode unshaded,blend_add,cull_disabled,depth_draw_never,shadows_disabled,fog_disabled;
uniform vec3 c=vec3(.2,.95,1.);uniform float k=1.;
void fragment(){ALBEDO=c*k*1.8;}"""
const POOL_CODE = """
shader_type spatial;
render_mode unshaded,blend_add,cull_disabled,depth_draw_never,shadows_disabled,fog_disabled;
uniform vec3 c=vec3(.2,.95,1.);uniform float k=1.;
void fragment(){
	float d=length(UV-.5)*2.;
	float a=smoothstep(1.,0.,d)*.55+exp(-pow((d-.42)*7.,2.))*.9;
	ALBEDO=c*k*a*.55;
}"""


func _rings_build(root: Node3D, idx: int) -> Array:
	var out = []
	var hm = StandardMaterial3D.new()
	hm.albedo_color = Color(0.05, 0.05, 0.06)
	hm.metallic = 1.0
	hm.roughness = 0.35
	for r in RINGS.get(idx, []):
		var p: Vector3 = r[0]
		var rad: float = r[1]
		var hs = MeshInstance3D.new()
		var cy = CylinderMesh.new()
		cy.top_radius = rad * 0.95
		cy.bottom_radius = rad * 1.02
		cy.height = 0.022
		cy.radial_segments = 16
		cy.rings = 1
		hs.mesh = cy
		hs.material_override = hm
		hs.position = p + Vector3(0, 0.012, 0)
		root.add_child(hs)
		var rg = MeshInstance3D.new()
		var tm = TorusMesh.new()
		tm.inner_radius = rad * 0.72
		tm.outer_radius = rad * 0.92
		tm.rings = 20
		tm.ring_segments = 6
		rg.mesh = tm
		var rm = _shader_mat(RING_CODE)
		rg.material_override = rm
		rg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rg.position = p - Vector3(0, 0.008, 0)
		rg.scale = Vector3(1.0, 0.35, 1.0)
		root.add_child(rg)
		var pl = MeshInstance3D.new()
		var q = QuadMesh.new()
		q.size = Vector2.ONE * rad * 4.5
		q.orientation = PlaneMesh.FACE_Y
		pl.mesh = q
		var pm = _shader_mat(POOL_CODE)
		pl.material_override = pm
		pl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pl.position = Vector3(p.x, -0.15, p.z)
		root.add_child(pl)
		out.append([rm, pm, pl, signf(p.x)])
	if not out.is_empty():
		var ol = OmniLight3D.new()
		ol.light_color = Color(0.25, 0.9, 1.0)
		ol.omni_range = 1.4
		ol.light_energy = 0.8
		ol.position = Vector3(0, -0.05, -0.08)
		ol.shadow_enabled = false
		root.add_child(ol)
		root.set_meta("rlight", ol)
	return out


func _rings_step(nd: Node3D, s: Dictionary, hov: float) -> void:
	var rs: Array = nd.get_meta("rings", [])
	if rs.is_empty():
		return
	var tt = Time.get_ticks_msec() / 1000.0
	var bo = clampf(s.boost, 0.0, 1.0)
	var sum = 0.0
	for i in range(rs.size()):
		var r: Array = rs[i]
		var k = (0.78 + 0.22 * sin(tt * 7.0 + i * 1.7)) * (1.0 + 1.4 * bo) * (1.0 + 0.8 * maxf(0.0, r[3] * float(s.u)))
		_sp(r[0], "k", k)
		_sp(r[1], "k", k)
		(r[2] as Node3D).position.y = -hov + 0.012
		sum += k
	var ol: OmniLight3D = nd.get_meta("rlight")
	ol.light_energy = 0.35 * sum / rs.size() * _newr("ship", 1.0)


# ---------------------------------------------------------------- Behang: Ketten, Knoten, Quasten
var _dg_mats = {}
func _dg_mat(k: String) -> StandardMaterial3D:
	if _dg_mats.has(k):
		return _dg_mats[k]
	var m = StandardMaterial3D.new()
	match k:
		"chain":
			m.albedo_color = Color(0.06, 0.06, 0.07)
			m.metallic = 1.0
			m.roughness = 0.28
		"gold":
			m.albedo_color = Color(0.95, 0.68, 0.28)
			m.metallic = 1.0
			m.roughness = 0.25
		"red":
			m.albedo_color = Color(0.62, 0.02, 0.05)
			m.roughness = 0.85
			m.emission_enabled = true
			m.emission = Color(0.5, 0.0, 0.03)
			m.emission_energy_multiplier = 0.35
		"gem":
			m.albedo_color = Color(1.0, 0.05, 0.1)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.04, 0.12)
			m.emission_energy_multiplier = 3.0
	_dg_mats[k] = m
	return m


func _dangle_build(root: Node3D, idx: int) -> Array:
	var out = []
	for d in DANG.get(idx, []):
		var segs: Array = d[1]
		var ms = []
		for k in range(segs.size()):
			var kind: String = segs[k][0]
			var ln: float = segs[k][1]
			var parts = []
			match kind:
				"link":
					var t = TorusMesh.new()
					t.inner_radius = ln * 0.32
					t.outer_radius = ln * 0.5
					t.rings = 8
					t.ring_segments = 5
					parts.append([t, "chain", 0])
				"knot":
					var t2 = TorusMesh.new()
					t2.inner_radius = ln * 0.22
					t2.outer_radius = ln * 0.5
					t2.rings = 10
					t2.ring_segments = 5
					parts.append([t2, "gold", 0])
					parts.append([_lowsphere(ln * 0.28, 8, 4), "gold", 1])
				"tassel":
					var c = CylinderMesh.new()
					c.top_radius = ln * 0.3
					c.bottom_radius = ln * 0.09
					c.height = 1.0
					c.radial_segments = 8
					c.rings = 1
					parts.append([c, "red", 2])
				"spike":
					var c2 = CylinderMesh.new()
					c2.top_radius = 0.0
					c2.bottom_radius = ln * 0.22
					c2.height = 1.0
					c2.radial_segments = 4
					c2.rings = 1
					parts.append([c2, "chain", 2])
					parts.append([_lowsphere(ln * 0.12, 8, 4), "gem", 1])
			var mis = []
			for pt in parts:
				var mi = MeshInstance3D.new()
				mi.mesh = pt[0]
				mi.material_override = _dg_mat(pt[1])
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mi.top_level = true
				root.add_child(mi)
				mis.append([mi, pt[2]])
			ms.append(mis)
		out.append({"a": d[0], "segs": segs, "ms": ms, "p": [], "pp": [], "la": Vector3.ZERO})
	return out


# Verlet: Punkte in Weltkoordinaten, Aufhängung folgt dem Schiff. Schwerkraft zeigt zur Fahrbahn,
# Fahrtwind zieht die Quasten nach hinten, Trägheit lässt sie beim Lenken und Bremsen ausschwingen.
func _dangle_step(nd: Node3D, dt: float) -> void:
	var dg: Array = nd.get_meta("dg", [])
	if dg.is_empty() or dt <= 0.0:
		return
	var SX: Dictionary = fx.ship
	var xf: Transform3D = nd.global_transform
	var sc = xf.basis.get_scale().x
	var dn: Vector3 = -xf.basis.y.normalized()
	var g: Vector3 = dn * 9.0 * float(SX.get("weight", 1.0))
	# leichte, böige Brise, die immer weht (auch im Stand): Richtung dreht langsam, Stärke pulsiert
	var tt = Time.get_ticks_msec() / 1000.0
	var gust = 0.55 + 0.45 * sin(tt * 1.3) * sin(tt * 0.71 + 1.0) + 0.25 * sin(tt * 3.7)
	var breeze: Vector3 = Vector3(sin(tt * 0.23), 0.0, cos(tt * 0.17)).normalized() * gust * 3.2 * float(SX.get("breeze", 1.0))
	var fw: Vector3 = xf.basis.z.normalized()
	var xi: Transform3D = xf.affine_inverse()
	for d in dg:
		var a: Vector3 = xf * d.a
		var segs: Array = d.segs
		var n = segs.size()
		if d.p.is_empty() or a.distance_to(d.la) > 4.0:
			d.p = [a]
			for k in range(n):
				d.p.append(d.p[k] + (dn - fw * 0.3).normalized() * float(segs[k][1]) * sc)
			d.pp = d.p.duplicate()
			d.la = a
		var sv: Vector3 = (a - d.la) / dt
		d.la = a
		var wind: Vector3 = -sv * 0.25 * float(SX.wind) + breeze
		# „Tassel swing“: wie lange sie nachschwingen (1 = nach 1 s noch 4 % Schwung, 3 = deutlich länger)
		var damp = pow(0.04, dt / maxf(0.05, float(SX.swing)))
		var p: Array = d.p
		var pp: Array = d.pp
		p[0] = a
		for k in range(1, n + 1):
			var v: Vector3 = p[k] - pp[k]
			var vr: Vector3 = v - sv * dt
			v = sv * dt + vr * damp
			pp[k] = p[k]
			p[k] = p[k] + v + (g + wind) * dt * dt
		for _it in range(2):
			for k in range(1, n + 1):
				var e: Vector3 = p[k] - p[k - 1]
				var l = e.length()
				var ln = float(segs[k - 1][1]) * sc
				p[k] = p[k - 1] + (e / l * ln if l > 1e-6 else dn * ln)
				# nicht durch die Fahrbahn: unter dem Schiff bleibt eine Handbreit Luft
				var lp: Vector3 = xi * p[k]
				if lp.y < -0.1:
					lp.y = -0.1
					p[k] = xf * lp
		# Darstellung: jedes Glied zwischen zwei Punkten, Kettenglieder abwechselnd um 90° gedreht
		for k in range(n):
			var p0: Vector3 = p[k]
			var p1: Vector3 = p[k + 1]
			var e2: Vector3 = p1 - p0
			var l2 = maxf(e2.length(), 1e-5)
			var y: Vector3 = e2 / l2
			var ref: Vector3 = fw if absf(y.dot(fw)) < 0.9 else xf.basis.x.normalized()
			var x: Vector3 = y.cross(ref).normalized()
			if k % 2 == 1:
				x = x.rotated(y, PI * 0.5)
			var z: Vector3 = x.cross(y)
			for mm in d.ms[k]:
				var mi: MeshInstance3D = mm[0]
				match mm[1]:
					0:   # Ring: liegt in der Ebene von Glied-Richtung und x, Ringachse = z
						mi.global_transform = Transform3D(Basis(y * sc * 1.3, z * sc, x * sc * 0.6), (p0 + p1) * 0.5)
					1:   # Kugel am unteren Ende
						mi.global_transform = Transform3D(Basis(x * sc, y * sc, z * sc), p1)
					2:   # Kegel/Quaste: Mesh-Achse y von p0 nach p1, Höhe 1 auf die Gliedlänge
						mi.global_transform = Transform3D(Basis(x * sc, y * l2, z * sc), (p0 + p1) * 0.5)


# Plasmastrahl: heller blauweißer Kern, violetter Rand, wandernde Schockringe, schnelles Flackern
const JET_CODE = """
shader_type spatial;
render_mode unshaded,blend_add,cull_disabled,depth_draw_never,shadows_disabled,fog_disabled;
uniform vec3 jc=vec3(.55,.38,1.);uniform vec3 jc2=vec3(.78,.93,1.);
uniform float jk=1.;uniform float jd=1.;uniform float jl=.5;
varying float v;
void vertex(){v=.5-VERTEX.y;}
void fragment(){
	float fr=abs(dot(NORMAL,VIEW));
	float core=fr*fr;
	float fade=exp(-v*2.)*smoothstep(1.,.7,v)*smoothstep(0.,.04,v);
	float ph=v*jl*30.-TIME*42.;
	float dia=1.+jd*1.1*pow(.5+.5*cos(ph),10.)*(1.-v);
	float fl=.86+.14*sin(TIME*83.+v*11.);
	vec3 c=mix(jc,jc2,core*core);
	ALBEDO=c*(core*1.7+.12)*fade*dia*fl*jk;
}"""
# Düsenglühen: weicher Lichtfleck direkt an der Düse (sieht man von hinten immer)
const JETGLOW_CODE = """
shader_type spatial;
render_mode unshaded,blend_add,cull_disabled,depth_draw_never,shadows_disabled,fog_disabled;
uniform vec3 jc=vec3(.55,.38,1.);uniform float jk=1.;
void vertex(){
	float s=length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX=VIEW_MATRIX*mat4(INV_VIEW_MATRIX[0]*s,INV_VIEW_MATRIX[1]*s,INV_VIEW_MATRIX[2]*s,MODEL_MATRIX[3]);
}
void fragment(){
	float d=length(UV-.5)*2.;
	float g=exp(-d*d*6.)*.7+exp(-d*d*45.)*1.6;
	ALBEDO=mix(jc,vec3(1.),exp(-d*d*25.))*g*jk;
}"""
var jet_m: CylinderMesh


func _jet_mesh() -> CylinderMesh:
	if jet_m == null:
		jet_m = CylinderMesh.new()
		jet_m.top_radius = 1.0
		jet_m.bottom_radius = 0.2
		jet_m.height = 1.0
		jet_m.radial_segments = 12
		jet_m.rings = 3
		jet_m.cap_top = false
		jet_m.cap_bottom = false
	return jet_m


const HAZE_CODE = """
shader_type spatial;
render_mode unshaded,blend_mix,depth_draw_never,cull_disabled,shadows_disabled,fog_disabled;
uniform sampler2D scr:hint_screen_texture,filter_linear;
uniform float k=.6;uniform float hs=1.;uniform float hv=1.;uniform float hf=1.;
uniform vec3 shc=vec3(0.,-1000.,0.);uniform float shr=.5;
float h21(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float vn(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);
	return mix(mix(h21(i),h21(i+vec2(1.,0.)),f.x),mix(h21(i+vec2(0.,1.)),h21(i+vec2(1.,1.)),f.x),f.y);}
void vertex(){
	float s=length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX=VIEW_MATRIX*mat4(INV_VIEW_MATRIX[0]*s,INV_VIEW_MATRIX[1]*s,INV_VIEW_MATRIX[2]*s,MODEL_MATRIX[3]);
}
void fragment(){
	vec2 q=UV-.5;
	float m=smoothstep(.5,.1,length(q*vec2(1.,.85)))*k;
	// feines Flimmern: hohe Frequenz, schnell aufsteigend, kleiner Ausschlag
	vec2 p=UV*9.*hf+vec2(0.,TIME*7.*hv);
	vec2 o=vec2(vn(p)-.5,vn(p*1.6+vec2(4.1,TIME*2.5*hv))-.5)+.5*vec2(vn(p*2.3+vec2(9.,0.))-.5,vn(p*2.3+vec2(2.,5.))-.5);
	// liegt das eigene Schiff hinter diesem Pixel (Blick durch die Abgase aufs Heck), kaum verzerren:
	// heiße Luft verbiegt vor allem, was weiter weg ist – das Schiff bleibt scharf
	vec3 wq=(INV_VIEW_MATRIX*vec4(VERTEX,1.)).xyz;
	vec3 ro=CAMERA_POSITION_WORLD;vec3 rd=normalize(wq-ro);vec3 oc=ro-shc;
	float bq=dot(oc,rd);float cq=dot(oc,oc)-shr*shr;float hq=bq*bq-cq;
	float hit=hq>0.&&(-bq-sqrt(max(hq,0.)))>length(wq-ro)?1.:0.;
	m*=1.-.8*hit;
	ALBEDO=texture(scr,SCREEN_UV+o*.009*m*hs).rgb;
	ALPHA=smoothstep(0.,.25,m);
}"""
var shield_mat: ShaderMaterial
const GB_R = 9.0


func _shield_for(root: Node3D) -> Node3D:
	if shield_mat == null:
		shield_mat = _shader_mat("""
shader_type spatial;
// Schutzschild: durchsichtige blaue Hülle, Ränder leuchten, ruhiges Schimmern
render_mode unshaded,blend_add,cull_disabled,depth_draw_never,shadows_disabled;
uniform vec3 sc=vec3(.12,.45,1.);uniform float sg=1.;uniform float sf=1.;uniform float se=1.;
void fragment(){
	float fr=pow(max(1.-abs(dot(NORMAL,VIEW)),0.),2.6*se);
	float sh=1.-.15*sf+.15*sf*sin(TIME*3.*max(sf,.3)+VERTEX.y*6.);
	float scan=smoothstep(.96,1.,fract(UV.y*1.-TIME*.4))*.35*min(sf,2.);
	ALBEDO=sc*(.012+fr*1.1*sh+scan*.15)*sg;
}""")
	var bb: AABB = root.get_meta("bb")
	var sp = SphereMesh.new()
	sp.radius = 1.0
	sp.height = 2.0
	sp.radial_segments = 48
	sp.rings = 24
	var c = MeshInstance3D.new()
	c.mesh = sp
	c.material_override = shield_mat
	c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	c.scale = bb.size * 0.5 * Vector3(1.22, 1.6, 1.12) + Vector3.ONE * 0.12
	c.set_meta("bs", c.scale)
	c.position = bb.get_center()
	root.add_child(c)
	root.set_meta("shield", c)
	return c


func _shield_vis(o: Dictionary) -> void:
	var nd: Node3D = o.node
	var shn: Node3D = nd.get_meta("shield") if nd.has_meta("shield") else null
	if o.shield > 0.0 and shn == null and not o.out:
		shn = _shield_for(nd)
	if shn != null:
		shn.visible = o.shield > 0.0 and (o.shield > 1.2 or fmod(o.shield, 0.25) < 0.15)
		var shf = float(o.get("shf", 0.0))
		if shf > 0.0:
			o.shf = maxf(0.0, shf - get_process_delta_time() * 4.0)
		if shn.visible:
			var X: Dictionary = fx.shield
			shn.scale = (shn.get_meta("bs") as Vector3) * float(X.size) * (1.0 + 0.18 * shf)
			_sp(shield_mat, "sc", _v3(_hs(Color(0.12, 0.45, 1.0), float(X.hue))))
			_sp(shield_mat, "sg", float(X.glow))
			_sp(shield_mat, "sf", float(X.flicker))
			_sp(shield_mat, "se", float(X.edge))


func _rel_xf(top: Node3D, n: Node) -> Transform3D:
	var xf = Transform3D.IDENTITY
	var c: Node = n
	while c != null and c != top:
		if c is Node3D:
			xf = (c as Node3D).transform * xf
		c = c.get_parent()
	return xf


func _spawn_ships() -> void:
	var z0 = T.ZST
	var starts = [[z0, 0.0], [z0 + 3.2, -0.5], [z0 + 6.4, 0.5], [z0 + 9.6, 0.0]]
	var others = []
	for i in range(SHIPS.size()):
		if i != int(cfg.ship):
			others.append(i)
	others.shuffle()
	for i in range(4):
		var sm = int(cfg.ship) if i == 0 else others[(i - 1) % others.size()]
		if not rpf.is_empty():
			var rsm: Array = rpf.get("sm", [])
			if i < rsm.size():
				sm = clampi(int(rsm[i]), 0, SHIPS.size() - 1)
		var s = {"z": starts[i][0], "lat": starts[i][1], "psi": 0.0, "vpsi": 0.0, "u": 0.0, "spd": 0.0, "boost": 0.0, "slow": 1.0,
			"h": 0.0, "vy": 0.0, "air": false, "padK": -1, "hitT": -9.0, "sk": (1.0 + (i - 1) * 0.035) * float(cfg.ai) if i > 0 else 1.0, "sk0": 0.0, "lane": randf_range(-0.7, 0.7), "tl": 0.0, "wT": 0.0, "orbs": 0.0,
			"ai": randf() * 100.0, "node": _ship_node(sm), "sm": sm, "fin": 0.0, "roll": 0.0,
			"en": 1.0, "out": false, "dealt": 0.0, "outT": 0.0, "wpn": "", "wpK": -1, "shield": 0.0, "auto": 0.0, "turbo": 0.0, "slowT": 0.0, "enL": 0, "idx": i, "sup": false, "sorb": false, "sauto": false}
		s.sk0 = s.sk
		s.lane = s.lat
		s.tl = s.lat
		ships.append(s)


# ---------------------------------------------------------------- Anzeige: Platz, Runde, Zeit, Lenkknöpfe
# Kill-Cam-Bild wie ein Überwachungsmonitor: REC-Punkt, Sucherwinkel, Zeitstempel, feine Bildzeilen
func _kc_overlay() -> void:
	var cl = CanvasLayer.new()
	cl.layer = 6
	cl.visible = false
	add_child(cl)
	kco.layer = cl
	var sl = ColorRect.new()
	sl.set_anchors_preset(Control.PRESET_FULL_RECT)
	sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sl.material = _shader_mat("""
shader_type canvas_item;
void fragment(){
	vec2 uv=SCREEN_UV;
	float line=step(.5,fract(FRAGCOORD.y*.25))*.10;
	float vig=smoothstep(.45,.95,length((uv-.5)*vec2(.8,1.)));
	float roll=smoothstep(.0,.02,abs(fract(uv.y-TIME*.12)-.5))*.0+exp(-pow(abs((fract(uv.y-TIME*.12)-.5)*40.),2.))*.05;
	COLOR=vec4(vec3(roll),line+vig*.55);
}""")
	cl.add_child(sl)
	var c = Color(1, 1, 1, 0.85)
	for corner in range(4):
		for k in range(2):
			var r = ColorRect.new()
			r.color = c
			r.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var right = corner % 2 == 1
			var bottom = corner >= 2
			r.anchor_left = 1.0 if right else 0.0
			r.anchor_right = r.anchor_left
			r.anchor_top = 1.0 if bottom else 0.0
			r.anchor_bottom = r.anchor_top
			var w = 90.0 if k == 0 else 6.0
			var h = 6.0 if k == 0 else 90.0
			var x0 = -40.0 - w if right else 40.0
			var y0 = -150.0 - h if bottom else 150.0
			r.offset_left = x0
			r.offset_right = x0 + w
			r.offset_top = y0
			r.offset_bottom = y0 + h
			cl.add_child(r)
	var dot = ColorRect.new()
	dot.color = Color(1, 0.12, 0.1)
	dot.position = Vector2(62, 182)
	dot.size = Vector2(22, 22)
	cl.add_child(dot)
	kco.dot = dot
	var t1 = _lbl("REC   KILL CAM", 30)
	t1.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	t1.position = Vector2(98, 172)
	cl.add_child(t1)
	kco.title = t1
	var t2 = _lbl("", 26)
	t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	t2.anchor_left = 1.0
	t2.anchor_right = 1.0
	t2.offset_left = -400
	t2.offset_right = -64
	t2.offset_top = 176
	cl.add_child(t2)
	kco.who = t2
	var t3 = _lbl("", 26)
	t3.anchor_right = 1.0
	t3.anchor_top = 1.0
	t3.anchor_bottom = 1.0
	t3.offset_top = -205
	t3.modulate = Color(1, 1, 1, 0.85)
	cl.add_child(t3)
	kco.ts = t3
	var t4 = _lbl("tap to skip", 22)
	t4.anchor_right = 1.0
	t4.anchor_top = 1.0
	t4.anchor_bottom = 1.0
	t4.offset_top = -120
	t4.modulate = Color(1, 1, 1, 0.45)
	cl.add_child(t4)


var kco = {}


func _hud() -> void:
	var cl = CanvasLayer.new()
	add_child(cl)
	hud.layer = cl
	# Lenkzonen: weicher weißer Schein vom linken und rechten Rand nach innen (keine Knöpfe, nur Licht)
	var sg = GradientTexture2D.new()
	sg.fill = GradientTexture2D.FILL_RADIAL
	sg.fill_from = Vector2(0.0, 0.5)
	sg.fill_to = Vector2(1.0, 0.5)
	var sgr = Gradient.new()
	sgr.set_color(0, Color(1, 1, 1, 0.5))
	sgr.set_color(1, Color(1, 1, 1, 0.0))
	sgr.add_point(0.15, Color(1, 1, 1, 0.26))
	sgr.add_point(0.32, Color(1, 1, 1, 0.08))
	sgr.add_point(0.48, Color(1, 1, 1, 0.0))
	sg.gradient = sgr
	sg.width = 128
	sg.height = 256
	hud.sglow = []
	for sd in [0, 1]:
		var tr = TextureRect.new()
		tr.texture = sg
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.flip_h = sd == 1
		tr.anchor_left = 0.0 if sd == 0 else 0.4
		tr.anchor_right = 0.6 if sd == 0 else 1.0
		tr.anchor_top = 0.0
		tr.anchor_bottom = 1.0
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.modulate.a = 0.0
		cl.add_child(tr)
		hud.sglow.append(tr)
	var mk = func(sz: int, al: int) -> Label:
		var l = Label.new()
		l.add_theme_font_size_override("font_size", sz)
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
		l.add_theme_constant_override("shadow_offset_y", 2)
		l.horizontal_alignment = al
		cl.add_child(l)
		return l
	# Pause: kleiner Knopf oben in der Mitte (nur Anzeige – der Tipp wird in _input abgefangen, bevor er lenkt)
	var pzb = Button.new()
	pzb.text = "II"
	pzb.add_theme_font_size_override("font_size", 34)
	pzb.add_theme_stylebox_override("normal", _style(Color(0, 0, 0, 0.35), Color(1, 1, 1, 0.3)))
	pzb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pzb.focus_mode = Control.FOCUS_NONE
	pzb.anchor_left = 0.5
	pzb.anchor_right = 0.5
	pzb.offset_left = -44
	pzb.offset_right = 44
	pzb.offset_top = 26
	pzb.offset_bottom = 106
	pzb.visible = false
	cl.add_child(pzb)
	hud.pausebtn = pzb
	hud.top = mk.call(34, HORIZONTAL_ALIGNMENT_CENTER)
	hud.top.anchor_right = 1.0
	hud.top.offset_top = 70
	# Platzierung groß oben rechts: „2nd“ und klein „/4“ (Ausgeschiedene zählen nicht mit)
	var pb = HBoxContainer.new()
	pb.anchor_left = 1.0
	pb.anchor_right = 1.0
	pb.offset_left = -380
	pb.offset_right = -34
	pb.offset_top = 100
	pb.offset_bottom = 250
	pb.alignment = BoxContainer.ALIGNMENT_END
	pb.add_theme_constant_override("separation", 6)
	cl.add_child(pb)
	hud.pl = Label.new()
	hud.pl.add_theme_font_size_override("font_size", 124)
	hud.pl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	hud.pl.add_theme_constant_override("outline_size", 12)
	hud.pl.size_flags_vertical = Control.SIZE_SHRINK_END
	pb.add_child(hud.pl)
	hud.pln = Label.new()
	hud.pln.add_theme_font_size_override("font_size", 52)
	hud.pln.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	hud.pln.add_theme_constant_override("outline_size", 8)
	hud.pln.modulate = Color(1, 1, 1, 0.7)
	hud.pln.size_flags_vertical = Control.SIZE_SHRINK_END
	hud.pln.offset_bottom = -14
	pb.add_child(hud.pln)
	hud.plbox = pb
	hud.mid = mk.call(120, HORIZONTAL_ALIGNMENT_CENTER)
	hud.mid.anchor_right = 1.0
	hud.mid.anchor_top = 0.3
	hud.mid.anchor_bottom = 0.3
	# Warnung, wenn gegnerische Minen vor dir liegen
	hud.mw = mk.call(34, HORIZONTAL_ALIGNMENT_CENTER)
	hud.mw.text = "▲  MINES AHEAD  ▲"
	hud.mw.anchor_right = 1.0
	hud.mw.anchor_top = 0.62
	hud.mw.anchor_bottom = 0.62
	hud.mw.add_theme_color_override("font_color", Color(1.0, 0.25, 0.2))
	hud.mw.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	hud.mw.add_theme_constant_override("outline_size", 8)
	hud.mw.visible = false
	hud.msg = mk.call(32, HORIZONTAL_ALIGNMENT_CENTER)
	hud.big = mk.call(72, HORIZONTAL_ALIGNMENT_CENTER)
	hud.big.anchor_right = 1.0
	hud.big.anchor_top = 0.34
	hud.big.anchor_bottom = 0.34
	hud.big.add_theme_color_override("font_outline_color", Color(0.25, 0.05, 0.0, 0.9))
	hud.big.add_theme_constant_override("outline_size", 10)
	hud.big.pivot_offset = Vector2(360, 80)
	hud.msg.anchor_right = 1.0
	hud.msg.offset_top = 280
	hud.en_bg = ColorRect.new()
	hud.en_bg.color = Color(1, 1, 1, 0.15)
	hud.en_bg.position = Vector2(36, 140)
	hud.en_bg.size = Vector2(300, 20)
	cl.add_child(hud.en_bg)
	hud.en = ColorRect.new()
	hud.en.color = Color(0.36, 1.0, 0.6)
	hud.en.size = Vector2(300, 20)
	hud.en_bg.add_child(hud.en)
	# Fortschritt über die ganze Strecke: drei Abschnitte (= drei Runden), füllt sich live
	var pg = Control.new()
	pg.position = Vector2(36, 112)
	pg.size = Vector2(300, 10)
	cl.add_child(pg)
	hud.pg = pg
	hud.pgf = []
	for k in range(T.LAPS):
		var w = (300.0 - 2 * 6.0) / T.LAPS
		var bg = ColorRect.new()
		bg.color = Color(1, 1, 1, 0.15)
		bg.position = Vector2(k * (w + 6.0), 0)
		bg.size = Vector2(w, 10)
		pg.add_child(bg)
		var fl = ColorRect.new()
		fl.color = Color(0.85, 0.92, 1.0)
		fl.size = Vector2(0, 10)
		bg.add_child(fl)
		hud.pgf.append([fl, w])
	var el = mk.call(16, HORIZONTAL_ALIGNMENT_LEFT)
	el.text = "ENERGY"
	el.position = Vector2(36, 164)
	el.add_theme_font_size_override("font_size", 22)
	hud.el = el
	el.modulate = Color(1, 1, 1, 0.7)
	# Cyber-Gothic-Anzeige: Tempo als Bogen aus Drachenschuppen, Energie in Spitzbogen-Fenstern
	var gh = Control.new()
	gh.set_anchors_preset(Control.PRESET_FULL_RECT)
	gh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(gh)
	gh.draw.connect(func(): _gh_draw(gh))
	hud.gh = gh
	hud.gs = 0.0   # geglättetes Tempo für die Anzeige
	# Gothic-Altar-HUD (Rahmen von John): oben Platz/Runde/Zeit, unten Tempo, Waffenrad mit FIRE, Energie
	var gac = Control.new()
	gac.set_anchors_preset(Control.PRESET_FULL_RECT)
	gac.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(gac)
	gac.draw.connect(func(): _ga_draw(gac))
	hud.ga = gac
	# Spur-Anzeige: drei Rauten über dem Waffenrad, die aktuelle leuchtet, blitzt beim Einrasten
	var lni = Control.new()
	lni.set_anchors_preset(Control.PRESET_FULL_RECT)
	lni.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(lni)
	lni.draw.connect(func(): _lane_draw(lni))
	hud.lanei = lni
	# Waffenknopf: runder Knopf, geladen = orange mit drehendem, pulsierendem Ring
	var ring = Control.new()
	ring.anchor_left = 0.5
	ring.anchor_right = 0.5
	ring.anchor_top = 1.0
	ring.anchor_bottom = 1.0
	ring.offset_left = -125
	ring.offset_right = 125
	ring.offset_top = -330
	ring.offset_bottom = -80
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(ring)
	ring.draw.connect(func():
		# Autopilot: Restzeit als Bogen um den Knopf (leert sich im Uhrzeigersinn); wartet er auf eine Gerade, pulsiert er
		var ga: Dictionary = ships[0]
		if ga.auto > 0.0 and state == "race":
			var cc = ring.size * 0.5
			var fr = clampf(ga.auto / 5.0, 0.0, 1.0)
			var ac = Color(1.0, 0.78, 0.2) if ga.get("sauto", false) else Color(0.4, 0.95, 1.0)
			ring.draw_arc(cc, 118.0, 0.0, TAU, 64, Color(ac.r, ac.g, ac.b, 0.15), 8.0, true)
			if ga.get("ahold", false):
				var pz = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 8.0)
				ring.draw_arc(cc, 118.0, 0.0, TAU, 64, Color(ac.r, ac.g, ac.b, 0.3 + 0.5 * pz), 8.0, true)
			else:
				ring.draw_arc(cc, 118.0, -PI / 2.0, -PI / 2.0 + TAU * fr, 64, Color(ac.r, ac.g, ac.b, 0.95), 8.0, true)
		if not hud.get("armed", false):
			return
		var t = Time.get_ticks_msec() / 1000.0
		var c = ring.size * 0.5
		var pu = 0.5 + 0.5 * sin(t * 5.0)
		var oc: Color = hud.get("wc", Color(1.0, 0.55, 0.15))
		if int(cfg.get("hud", 2)) == 2:
			return
		if int(cfg.get("hud", 2)) == 1:
			_gh_medal(ring, c, t, oc)
			_wicon(ring, c + Vector2(0, -42), 30.0, str(ships[0].wpn), Color(1, 1, 1, 0.95))
			return
		# pulsierender Außenring
		ring.draw_arc(c, 112.0 + 9.0 * pu, 0.0, TAU, 64, Color(oc.r, oc.g, oc.b, 0.55 * (1.0 - pu) + 0.15), 3.0, true)
		# drei drehende Bogenstücke
		for k in range(3):
			var a0 = t * 2.2 + k * TAU / 3.0
			ring.draw_arc(c, 104.0, a0, a0 + 1.2, 24, Color(oc.r, oc.g, oc.b, 0.95), 6.0, true)
		# Symbol der Waffe über dem Namen
		_wicon(ring, c + Vector2(0, -42), 30.0, str(ships[0].wpn), Color(1, 1, 1, 0.95)))
	hud.ring = ring
	hud.fire = mk.call(30, HORIZONTAL_ALIGNMENT_CENTER)
	hud.fire.anchor_left = 0.5
	hud.fire.anchor_right = 0.5
	hud.fire.anchor_top = 1.0
	hud.fire.anchor_bottom = 1.0
	hud.fire.offset_left = -95
	hud.fire.offset_right = 95
	hud.fire.offset_top = -300
	hud.fire.offset_bottom = -110
	hud.fire.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	hud.fire.offset_bottom = -150
	hud.fire.add_theme_font_size_override("font_size", 30)
	var fsb = StyleBoxFlat.new()
	fsb.bg_color = Color(1, 1, 1, 0.05)
	fsb.border_color = Color(1, 1, 1, 0.25)
	fsb.set_border_width_all(3)
	fsb.set_corner_radius_all(95)
	hud.fire.add_theme_stylebox_override("normal", fsb)
	hud.fire_sb = fsb
	# dunkler Schleier hinter Ergebnis und Tafel
	var rdim = ColorRect.new()
	rdim.color = Color(0, 0, 0, 0.6)
	rdim.set_anchors_preset(Control.PRESET_FULL_RECT)
	rdim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rdim.visible = false
	cl.add_child(rdim)
	hud.rdim = rdim
	hud.res = mk.call(34, HORIZONTAL_ALIGNMENT_CENTER)
	hud.res.anchor_left = 0.04
	hud.res.anchor_right = 0.96
	hud.res.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud.res.grow_vertical = Control.GROW_DIRECTION_BEGIN   # mehr Zeilen wachsen nach oben, nicht in die Tabelle
	hud.res.anchor_top = 0.36
	hud.res.anchor_bottom = 0.36
	# Knöpfe nach dem Rennen: Wiederholung oder neues Rennen
	var bx = VBoxContainer.new()
	bx.anchor_left = 0.5
	bx.anchor_right = 0.5
	bx.anchor_top = 0.66
	bx.anchor_bottom = 0.66
	bx.offset_left = -230
	bx.offset_right = 230
	bx.offset_top = 0
	bx.offset_bottom = 380
	bx.add_theme_constant_override("separation", 22)
	bx.visible = false
	cl.add_child(bx)
	var b1 = _btn("REPLAY", true)
	b1.pressed.connect(_replay_start)
	bx.add_child(b1)
	var b2 = _btn("RACE AGAIN")
	b2.pressed.connect(func(): _race_again())
	bx.add_child(b2)
	var b3 = _btn("MENU")
	b3.pressed.connect(func(): _to_menu())
	bx.add_child(b3)
	_fit(bx)
	# Leistungsbericht in die Zwischenablage – zum Einfügen im Chat
	var b4 = _btn("COPY PERFORMANCE REPORT")
	b4.add_theme_font_size_override("font_size", 22)
	b4.custom_minimum_size = Vector2(0, 64)
	b4.pressed.connect(func():
		DisplayServer.clipboard_set(bench.get("txt", "") if state == "bench" else _perf_text())
		b4.text = "REPORT COPIED ✓")
	bx.add_child(b4)
	bx.offset_bottom = 470
	hud.perfbtn = b4
	hud.resb = bx
	hud.resbtn = [b1, b2, b3, b4]
	# Ergebnistafel: alle vier Fahrer – erst Zeiten, dann abwechselnd ausgeteilter Schaden
	var bd = VBoxContainer.new()
	bd.anchor_left = 0.08
	bd.anchor_right = 0.92
	bd.anchor_top = 0.43
	bd.anchor_bottom = 0.43
	bd.add_theme_constant_override("separation", 8)
	bd.visible = false
	cl.add_child(bd)
	hud.board = bd
	var bt = mk.call(24, HORIZONTAL_ALIGNMENT_CENTER)
	bt.reparent(bd)
	bt.modulate = Color(1, 0.75, 0.4)
	hud.boardt = bt
	hud.rows = []
	for i in range(4):
		var row = HBoxContainer.new()
		bd.add_child(row)
		var cols = []
		for c in range(3):
			var l = mk.call(32, [HORIZONTAL_ALIGNMENT_LEFT, HORIZONTAL_ALIGNMENT_LEFT, HORIZONTAL_ALIGNMENT_RIGHT][c])
			l.reparent(row)
			l.custom_minimum_size = Vector2([90, 0, 0][c], 0)
			if c > 0:
				l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cols.append(l)
		hud.rows.append(cols)
	var rb = _btn("EXIT REPLAY")
	rb.anchor_left = 0.5
	rb.anchor_right = 0.5
	rb.anchor_top = 1.0
	rb.anchor_bottom = 1.0
	rb.offset_left = -200
	rb.offset_right = 200
	rb.offset_top = -200
	rb.offset_bottom = -88
	rb.visible = false
	rb.pressed.connect(_replay_end)
	cl.add_child(rb)
	hud.rpx = rb
	# Kamerawahl im Replay
	var cr = HBoxContainer.new()
	cr.anchor_left = 0.0
	cr.anchor_right = 1.0
	cr.anchor_top = 1.0
	cr.anchor_bottom = 1.0
	cr.offset_left = 20
	cr.offset_right = -20
	cr.offset_top = -320
	cr.offset_bottom = -232
	cr.add_theme_constant_override("separation", 8)
	cr.visible = false
	cl.add_child(cr)
	hud.camrow = cr
	hud.cambtn = []
	# Pause / weiter
	var pz = _btn("II")
	pz.add_theme_font_size_override("font_size", 22)
	pz.custom_minimum_size = Vector2(76, 76)
	pz.pressed.connect(func():
		if rp.is_empty():
			return
		rp.paused = not rp.get("paused", false)
		pz.text = "▶" if rp.paused else "II")
	cr.add_child(pz)
	hud.rppause = pz
	for it in [["AUTO", -1], ["CHASE", 0], ["TRACK", 1], ["COCKPIT", 2], ["AERIAL", 4], ["FRONT", 5], ["FREE", 6]]:
		var b = _btn(it[0])
		b.add_theme_font_size_override("font_size", 15)
		b.custom_minimum_size = Vector2(0, 76)
		b.clip_text = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var ci: int = it[1]
		b.pressed.connect(func(): _rp_cam_pick(ci))
		cr.add_child(b)
		hud.cambtn.append([b, ci])
	# Replay speichern
	var sv = _btn("SAVE REPLAY", true)
	sv.add_theme_font_size_override("font_size", 24)
	sv.anchor_left = 1.0
	sv.anchor_right = 1.0
	sv.offset_left = -300
	sv.offset_right = -30
	sv.offset_top = 120
	sv.offset_bottom = 200
	sv.visible = false
	sv.pressed.connect(_rp_save)
	cl.add_child(sv)
	hud.rpsave = sv
	# Fahrer wählen, dem die Kamera folgt
	var fr = HBoxContainer.new()
	fr.anchor_left = 0.5
	fr.anchor_right = 0.5
	fr.offset_left = -170
	fr.offset_right = 170
	fr.offset_top = 215
	fr.offset_bottom = 295
	fr.alignment = BoxContainer.ALIGNMENT_CENTER
	fr.add_theme_constant_override("separation", 10)
	fr.visible = false
	cl.add_child(fr)
	hud.flwrow = fr
	var fl = _btn("◀")
	fl.custom_minimum_size = Vector2(80, 76)
	fl.pressed.connect(func(): _rp_follow(-1))
	fr.add_child(fl)
	var fn = _lbl("YOU", 30)
	fn.custom_minimum_size = Vector2(150, 0)
	fr.add_child(fn)
	hud.flw = fn
	var frb = _btn("▶")
	frb.custom_minimum_size = Vector2(80, 76)
	frb.pressed.connect(func(): _rp_follow(1))
	fr.add_child(frb)
	# Foto: nur das reine Bild, ohne Knöpfe, in die Galerie (Bilder › AntiGrav)
	var ph = _btn("PHOTO", true)
	ph.add_theme_font_size_override("font_size", 24)
	ph.offset_left = 30
	ph.offset_right = 250
	ph.offset_top = 120
	ph.offset_bottom = 200
	ph.visible = false
	ph.pressed.connect(_rp_photo)
	cl.add_child(ph)
	hud.rpphoto = ph
	# Replay als Video (MP4) in die Galerie
	var vb = _btn("SAVE VIDEO", true)
	vb.add_theme_font_size_override("font_size", 24)
	vb.anchor_left = 1.0
	vb.anchor_right = 1.0
	vb.offset_left = -300
	vb.offset_right = -30
	vb.offset_top = 215
	vb.offset_bottom = 295
	vb.visible = false
	vb.pressed.connect(_vx_start)
	cl.add_child(vb)
	hud.vxb = vb
	# Hinweis während des Erstellens / Fertig-Dialog mit Teilen
	var vd = VBoxContainer.new()
	vd.anchor_left = 0.08
	vd.anchor_right = 0.92
	vd.anchor_top = 0.3
	vd.anchor_bottom = 0.3
	vd.add_theme_constant_override("separation", 18)
	vd.visible = false
	cl.add_child(vd)
	hud.vxd = vd
	var vl = _lbl("", 34)
	vl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vd.add_child(vl)
	hud.vxl = vl
	var vs = _btn("SHARE", true)
	vs.pressed.connect(func():
		if vx.has("p") and vx.get("uri", "") != "":
			vx.p.share(vx.uri))
	vd.add_child(vs)
	hud.vxs = vs
	var vo = _btn("OK")
	vo.pressed.connect(_vx_close)
	vd.add_child(vo)
	hud.vxo = vo


# ---------------------------------------------------------------- Menü: Gleiterwahl, Start, Einstellungen (Tempo, Grafik)
# Lenkzonen-Schein: beim Start kurz pulsieren (zeigt, wo gelenkt wird), beim Lenken leuchtet die gedrückte Seite auf
var sg_a = [0.0, 0.0]


func _steer_glow(dt: float, steer: float) -> void:
	var intro = 0.0
	if state == "intro":
		intro = clampf(t_state / 1.0, 0.0, 1.0) * 0.55
	elif state == "count":
		intro = 0.3 + 0.25 * (0.5 + 0.5 * sin(t_state * TAU * 1.2))
	elif state == "race" and t_state < 1.2:
		intro = 0.6 * (1.0 - t_state / 1.2)
	for sd in [0, 1]:
		var on = (steer < 0.0 and sd == 0) or (steer > 0.0 and sd == 1)
		var tg = maxf(intro, (0.25 + 0.45 * absf(steer)) if on and state == "race" and ships[0].auto <= 0.0 else 0.0)
		sg_a[sd] += (tg - sg_a[sd]) * (1.0 - exp(-dt / (0.06 if tg > sg_a[sd] else 0.25)))
		hud.sglow[sd].modulate.a = sg_a[sd]


# Ergebnis-Knöpfe zeigen – aber erst nach kurzer Pause und erst, wenn kein Finger mehr auf dem Bildschirm liegt.
# So löst ein Finger, der noch vom Lenken liegt, nichts aus: man muss neu antippen.
var resb_t = 0.0
var resb_armed = false
var fingers = {}


func _show_resb() -> void:
	if hud.has("perfbtn"):
		hud.perfbtn.visible = int(cfg.perf) == 1 or state == "bench"
	if not hud.resb.visible:
		resb_t = 0.0
		resb_armed = false
	hud.resb.visible = true
	_resb_arm(0.0)


func _resb_arm(dt: float) -> void:
	if not hud.resb.visible:
		if hud.has("ga") and hud.ga != null:
			(hud.ga as CanvasItem).modulate.a = 1.0
		return
	resb_t += dt
	if not resb_armed and resb_t > 1.3 and fingers.is_empty():
		resb_armed = true
	var a = clampf((resb_t - 1.3) / 0.35, 0.0, 1.0) if resb_armed else 0.0
	hud.resb.modulate.a = a
	# Altar-Anzeige unten ausblenden, solange die Ergebnis-Knöpfe da sind (sonst liegen sie übereinander)
	if hud.has("ga") and hud.ga != null:
		(hud.ga as CanvasItem).modulate.a = 1.0 - a
	for b in hud.resbtn:
		(b as Control).mouse_filter = Control.MOUSE_FILTER_STOP if resb_armed else Control.MOUSE_FILTER_IGNORE


func _style(bg: Color, br: Color) -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = br
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(26)
	sb.content_margin_top = 18
	sb.content_margin_bottom = 18
	return sb


func _btn(txt: String, pri := false) -> Button:
	var b = Button.new()
	b.text = txt
	b.add_theme_font_size_override("font_size", 38)
	b.custom_minimum_size = Vector2(0, 112)
	var n = _style(Color(0.93, 0.41, 0.18) if pri else Color(1, 1, 1, 0.08), Color(1, 0.7, 0.54) if pri else Color(1, 1, 1, 0.22))
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", n)
	b.add_theme_stylebox_override("focus", n)
	b.add_theme_stylebox_override("pressed", _style(Color(0.8, 0.33, 0.12) if pri else Color(1, 1, 1, 0.18), Color(1, 1, 1, 0.4)))
	return b


func _lbl(txt: String, sz: int) -> Label:
	var l = Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", sz)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l


func _menu() -> void:
	var cl = CanvasLayer.new()
	cl.layer = 5
	add_child(cl)
	var root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	cl.add_child(root)
	ui.root = root
	var title = _lbl("ANTIGRAV", 96)
	title.add_theme_color_override("font_color", Color(0.75, 0.95, 1.0))
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 170
	root.add_child(title)
	var sub = _lbl("3D  ·  NEON NIGHT", 28)
	sub.modulate = Color(1, 1, 1, 0.6)
	sub.set_anchors_preset(Control.PRESET_TOP_WIDE)
	sub.offset_top = 290
	root.add_child(sub)
	ui.title = [title, sub]
	# dunkler Schleier hinter den Einstellungen, damit alles gut lesbar ist
	var dim = ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.visible = false
	root.add_child(dim)
	ui.dim = dim
	# weicher dunkler Verlauf unter den Knöpfen: der Boden darf leuchten, die Schrift bleibt lesbar
	var grad = Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0.0))
	grad.set_color(1, Color(0, 0, 0, 0.72))
	var gt = GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 0.45)
	gt.width = 4
	gt.height = 256
	var shade = TextureRect.new()
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.anchor_left = 0.0
	shade.anchor_right = 1.0
	shade.anchor_top = 0.48
	shade.anchor_bottom = 1.0
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)
	root.move_child(shade, dim.get_index())
	# Hauptseite
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	box.anchor_left = 0.06
	box.anchor_right = 0.94
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_top = -60
	box.offset_bottom = -60
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN   # wächst nach oben, steht nie unten über den Rand
	root.add_child(box)
	ui.main = box
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	var bp = _btn("‹")
	bp.custom_minimum_size = Vector2(112, 112)
	row.add_child(bp)
	var mid = VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(mid)
	var sl = _lbl("SHIP", 22)
	sl.modulate = Color(1, 1, 1, 0.6)
	mid.add_child(sl)
	ui.ship = _lbl("", 46)
	mid.add_child(ui.ship)
	var bn = _btn("›")
	bn.custom_minimum_size = Vector2(112, 112)
	row.add_child(bn)
	bp.pressed.connect(func(): _pick_ship(-1))
	bn.pressed.connect(func(): _pick_ship(1))
	var go = _btn("START RACE", true)
	go.pressed.connect(_start)
	box.add_child(go)
	var frow = HBoxContainer.new()
	frow.add_theme_constant_override("separation", 16)
	box.add_child(frow)
	var bfr = _btn("Free ride")
	bfr.add_theme_font_size_override("font_size", 28)
	bfr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bfr.pressed.connect(func():
		free_ride = true
		_start())
	frow.add_child(bfr)
	var bst = _btn("Steering test")
	bst.add_theme_font_size_override("font_size", 28)
	bst.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bst.pressed.connect(func():
		pending_test = true
		_reload())
	frow.add_child(bst)
	var rrow = HBoxContainer.new()
	rrow.add_theme_constant_override("separation", 16)
	box.add_child(rrow)
	var brl = _btn("Replays")
	brl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brl.pressed.connect(func(): _show_replays(true))
	rrow.add_child(brl)
	var bhp = _btn("How to play")
	bhp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bhp.pressed.connect(func(): _show_help(true))
	rrow.add_child(bhp)
	var brc = _btn("Records")
	brc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brc.pressed.connect(func(): _show_records(true))
	rrow.add_child(brc)
	var srow = HBoxContainer.new()
	srow.add_theme_constant_override("separation", 16)
	box.add_child(srow)
	var bs = _btn("Settings")
	bs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	srow.add_child(bs)
	var blab = _btn("FX Lab")
	blab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	blab.pressed.connect(_lab_open)
	srow.add_child(blab)
	var bq = _btn("Quit")
	bq.modulate = Color(1, 1, 1, 0.75)
	bq.pressed.connect(func(): get_tree().quit())
	box.add_child(bq)
	ui.credit = _lbl("", 18)
	ui.credit.modulate = Color(1, 1, 1, 0.4)
	ui.credit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(ui.credit)
	# einheitliche Nebenknöpfe: gleiche Schrift, gleiche Höhe
	for b in [bfr, bst, brl, bhp, brc, bs, blab, bq]:
		(b as Button).add_theme_font_size_override("font_size", 30)
		(b as Button).custom_minimum_size = Vector2(0, 88)
	_fit(box)
	# Einstellungen
	# scrollbar, damit auch die unteren Einträge auf jedem Bildschirm erreichbar sind
	var setsc = ScrollContainer.new()
	setsc.anchor_left = 0.06
	setsc.anchor_right = 0.94
	setsc.anchor_top = 0.03
	setsc.anchor_bottom = 0.97
	setsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	setsc.scroll_deadzone = 14
	setsc.visible = false
	root.add_child(setsc)
	ui.setp = setsc
	# eigene, gut greifbare Scrollleiste mit Abstand zum Inhalt (nichts überlappt)
	var vsb: VScrollBar = setsc.get_v_scroll_bar()
	var sbg = StyleBoxFlat.new()
	sbg.bg_color = Color(1, 1, 1, 0.06)
	sbg.set_corner_radius_all(8)
	sbg.content_margin_left = 14
	var sgr = StyleBoxFlat.new()
	sgr.bg_color = Color(1.0, 0.55, 0.2, 0.75)
	sgr.set_corner_radius_all(8)
	sgr.content_margin_left = 14
	var sgh = sgr.duplicate()
	sgh.bg_color = Color(1.0, 0.65, 0.3, 0.95)
	vsb.add_theme_stylebox_override("scroll", sbg)
	vsb.add_theme_stylebox_override("grabber", sgr)
	vsb.add_theme_stylebox_override("grabber_highlight", sgh)
	vsb.add_theme_stylebox_override("grabber_pressed", sgh)
	vsb.custom_minimum_size = Vector2(16, 0)
	var smg = MarginContainer.new()
	smg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	smg.add_theme_constant_override("margin_right", 22)
	smg.add_theme_constant_override("margin_bottom", 40)
	setsc.add_child(smg)
	var sp = VBoxContainer.new()
	sp.add_theme_constant_override("separation", 14)
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	smg.add_child(sp)
	sp.add_theme_constant_override("separation", 8)
	var top = HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	var bk = _btn("‹ Back")
	bk.add_theme_font_size_override("font_size", 30)
	bk.custom_minimum_size = Vector2(170, 80)
	bk.pressed.connect(func(): _show_settings(false))
	top.add_child(bk)
	var stl = _lbl("SETTINGS", 40)
	stl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(stl)
	var spc = Control.new()
	spc.custom_minimum_size = Vector2(170, 0)
	top.add_child(spc)
	sp.add_child(top)
	ui.sl = {}
	for it in [["speed", 0.5, 4.0], ["ai", 0.7, 1.4], ["res", 0.5, 1.0], ["glow", 0.0, 1.5], ["neon", 0.2, 1.5], ["vol", 0.0, 1.0]]:
		var k: String = it[0]
		var lb = _lbl("", 30)
		sp.add_child(lb)
		var hs = HSlider.new()
		hs.min_value = it[1]
		hs.max_value = it[2]
		hs.step = 0.05
		hs.value = float(cfg[k])
		hs.custom_minimum_size = Vector2(0, 64)
		hs.add_theme_icon_override("grabber", _dot(40))
		hs.add_theme_icon_override("grabber_highlight", _dot(46))
		var track_sb = StyleBoxFlat.new()
		track_sb.bg_color = Color(1, 1, 1, 0.25)
		track_sb.content_margin_top = 6
		track_sb.content_margin_bottom = 6
		track_sb.set_corner_radius_all(6)
		hs.add_theme_stylebox_override("slider", track_sb)
		hs.value_changed.connect(func(v): cfg[k] = v; _refresh_ui(); _apply_cfg(); _save_cfg())
		sp.add_child(hs)
		ui.sl[k] = lb
	sp.add_child(_lbl("Graphics", 32))
	var gr = HBoxContainer.new()
	gr.add_theme_constant_override("separation", 12)
	sp.add_child(gr)
	ui.gfx = []
	for q in range(3):
		var b = _btn(["Low", "Medium", "High"][q])
		b.add_theme_font_size_override("font_size", 30)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.toggle_mode = true
		b.pressed.connect(func(): cfg.gfx = q; _refresh_ui(); _apply_cfg(); _save_cfg(); _rewarm())
		gr.add_child(b)
		ui.gfx.append(b)
	var twin = VBoxContainer.new()   # Look und Fields untereinander: volle Breite, nichts gequetscht
	twin.add_theme_constant_override("separation", 8)
	sp.add_child(twin)
	var lcol = VBoxContainer.new()
	lcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	twin.add_child(lcol)
	lcol.add_child(_lbl("Look", 32))
	var lr = HBoxContainer.new()
	lr.add_theme_constant_override("separation", 10)
	lcol.add_child(lr)
	ui.look = []
	for q in range(3):
		var b = _btn(["Color", "Noir", "Jungle"][q])
		b.add_theme_font_size_override("font_size", 30)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.toggle_mode = true
		b.pressed.connect(func():
			if int(cfg.look) != q:
				cfg.look = q
				_save_cfg()
				_reload())
		lr.add_child(b)
		ui.look.append(b)
	# Boost- und Waffenfelder: feste Positionen oder bei jedem Rennen neu verteilt
	var pcol = VBoxContainer.new()
	pcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	twin.add_child(pcol)
	pcol.add_child(_lbl("Fields", 32))
	var pr = HBoxContainer.new()
	pr.add_theme_constant_override("separation", 10)
	pcol.add_child(pr)
	ui.pads = []
	for q in range(2):
		var b = _btn(["Fixed", "Random"][q])
		b.add_theme_font_size_override("font_size", 30)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.toggle_mode = true
		b.pressed.connect(func():
			if int(cfg.pads) != q:
				cfg.pads = q
				_save_cfg()
				_reload())
		pr.add_child(b)
		ui.pads.append(b)
	# Bildrate anzeigen (mit Zeit für Grafikkarte/Prozessor) und auf 60 begrenzen (gleichmäßiger, Handy bleibt kühler)
	var twin2 = HBoxContainer.new()
	twin2.add_theme_constant_override("separation", 24)
	sp.add_child(twin2)
	ui.fpsb = []
	ui.capb = []
	ui.perfb = []
	for grp in [["FPS display", ["Off", "On"], "fps", ui.fpsb], ["Frame rate", ["Max", "60"], "cap", ui.capb], ["Perf. report", ["Off", "On"], "perf", ui.perfb]]:
		var col = VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		twin2.add_child(col)
		col.add_child(_lbl(grp[0], 32))
		var rr = HBoxContainer.new()
		rr.add_theme_constant_override("separation", 10)
		col.add_child(rr)
		for q in range(2):
			var b = _btn(grp[1][q])
			b.add_theme_font_size_override("font_size", 30)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var ck: String = grp[2]
			b.pressed.connect(func():
				cfg[ck] = q
				_save_cfg()
				_apply_cfg()
				_refresh_ui())
			rr.add_child(b)
			grp[3].append(b)
	# Leistungstest: misst 30 Sekunden lang, was auf diesem Handy wie viel Rechenzeit kostet
	var bbn = _btn("Performance test (30 s)")
	bbn.add_theme_font_size_override("font_size", 30)
	bbn.pressed.connect(func():
		bench_req = true
		_reload())
	sp.add_child(bbn)
	var trow = HBoxContainer.new()
	trow.add_theme_constant_override("separation", 12)
	sp.add_child(trow)
	var btp = _btn("Tips: " + ("On" if int(cfg.tips) == 1 else "Off"))
	btp.add_theme_font_size_override("font_size", 30)
	btp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btp.pressed.connect(func():
		cfg.tips = 1 - int(cfg.tips)
		_save_cfg()
		btp.text = "Tips: " + ("On" if int(cfg.tips) == 1 else "Off"))
	trow.add_child(btp)
	var btr = _btn("Show all tips again")
	btr.add_theme_font_size_override("font_size", 30)
	btr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btr.pressed.connect(func():
		cfg.tseen = ""
		cfg.tips = 1
		_save_cfg()
		btp.text = "Tips: On"
		_toast("Tips will show again"))
	trow.add_child(btr)
	var bcm = _btn("Comic intro: " + ("On" if int(cfg.get("comic", 1)) == 1 else "Off"))
	bcm.add_theme_font_size_override("font_size", 30)
	bcm.pressed.connect(func():
		cfg.comic = 1 - int(cfg.get("comic", 1))
		_save_cfg()
		bcm.text = "Comic intro: " + ("On" if int(cfg.comic) == 1 else "Off"))
	sp.add_child(bcm)
	var HN = ["Classic", "Dragon gauge", "Gothic altar"]
	var bhd = _btn("HUD style: " + HN[clampi(int(cfg.get("hud", 2)), 0, 2)])
	bhd.add_theme_font_size_override("font_size", 30)
	bhd.pressed.connect(func():
		cfg.hud = (int(cfg.get("hud", 2)) + 1) % 3
		_save_cfg()
		bhd.text = "HUD style: " + HN[int(cfg.hud)])
	sp.add_child(bhd)
	# Knopf mit kurzem Namen, Erklärung darunter (bricht um, kann nie breiter als der Bildschirm werden)
	var CH = ["Tap left or right to steer", "Swipe to steer, double-tap to fire", "Swipe to shift, returns to the middle", "Move your thumb like a mouse", "Swipe to pick left, middle or right lane", "Tap left / right: one lane over · tap middle: fire"]
	var bct = _btn("Steering: " + CTRL_N[clampi(int(cfg.get("ctrl", 1)), 0, 5)])
	bct.add_theme_font_size_override("font_size", 30)
	var cth = _lbl(CH[clampi(int(cfg.get("ctrl", 1)), 0, 5)], 22)
	cth.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cth.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cth.modulate = Color(1, 1, 1, 0.65)
	bct.pressed.connect(func():
		_set_ctrl((int(cfg.get("ctrl", 1)) + 1) % 6)
		bct.text = "Steering: " + CTRL_N[int(cfg.ctrl)]
		cth.text = CH[int(cfg.ctrl)])
	sp.add_child(bct)
	sp.add_child(cth)
	var blv = _btn("Live tuning from PC: " + ("On" if int(cfg.live) == 1 else "Off"))
	blv.add_theme_font_size_override("font_size", 30)
	blv.pressed.connect(func():
		cfg.live = 1 - int(cfg.live)
		_save_cfg()
		blv.text = "Live tuning from PC: " + ("On" if int(cfg.live) == 1 else "Off")
		if int(cfg.live) == 1:
			_toast("Open " + _live_addr() + " in the PC browser (same Wi-Fi)"))
	sp.add_child(blv)
	var back = _btn("Done", true)
	back.pressed.connect(func(): _show_settings(false))
	sp.add_child(back)
	bs.pressed.connect(func(): _show_settings(true))
	# Bildrate oben links (zum Prüfen, ob es flüssig läuft)
	var fl = CanvasLayer.new()
	fl.layer = 9
	add_child(fl)
	ui.fps = _lbl("", 20)
	ui.fps.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	ui.fps.position = Vector2(24, 24)
	ui.fps.modulate = Color(1, 1, 1, 0.55)
	ui.fps.visible = false
	fl.add_child(ui.fps)
	hud.layer.visible = false
	_refresh_ui()


# Gespeicherte Replays: Liste, antippen = abspielen, ✕ = löschen
func _show_replays(on: bool) -> void:
	if ui.has("rpl"):
		ui.rpl.queue_free()
		ui.erase("rpl")
	ui.main.visible = not on
	ui.dim.visible = on
	for t in ui.title:
		t.visible = not on
	if not on:
		return
	var pnl = VBoxContainer.new()
	pnl.anchor_left = 0.06
	pnl.anchor_right = 0.94
	pnl.anchor_top = 0.08
	pnl.anchor_bottom = 0.95
	pnl.add_theme_constant_override("separation", 16)
	ui.root.add_child(pnl)
	ui.rpl = pnl
	pnl.add_child(_lbl("REPLAYS", 40))
	var sc = ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pnl.add_child(sc)
	var lst = VBoxContainer.new()
	lst.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lst.add_theme_constant_override("separation", 12)
	sc.add_child(lst)
	var files = []
	var d = DirAccess.open("user://replays")
	if d != null:
		for f in d.get_files():
			if f.ends_with(".dat"):
				files.append(f)
	files.sort()
	files.reverse()
	if files.is_empty():
		var e = _lbl("No saved replays yet.\nAfter a race: Replay → Save replay.", 26)
		e.modulate = Color(1, 1, 1, 0.6)
		lst.add_child(e)
	for f in files:
		var path = "user://replays/" + f
		var info = f.trim_prefix("rp_").trim_suffix(".dat")
		var fa = FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
		if fa != null:
			var dd = fa.get_var()
			if dd is Dictionary:
				info = "%s\n%s" % [dd.get("res", ""), dd.get("date", "")]
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		lst.add_child(row)
		var b = _btn(info)
		b.add_theme_font_size_override("font_size", 26)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func():
			pending_rp = path
			_reload())
		row.add_child(b)
		var x = _btn("✕")
		x.custom_minimum_size = Vector2(100, 0)
		x.pressed.connect(func():
			DirAccess.remove_absolute(path)
			_show_replays(true))
		row.add_child(x)
	var back = _btn("Back", true)
	back.pressed.connect(func(): _show_replays(false))
	pnl.add_child(back)


func _show_settings(on: bool) -> void:
	if on:
		_fit(ui.setp)
	ui.setp.visible = on
	if on:
		_scr_prep(ui.setp)
	ui.main.visible = not on
	ui.dim.visible = on
	for t in ui.title:
		t.visible = not on


func _dot(r: int) -> ImageTexture:
	var im = Image.create(r, r, false, Image.FORMAT_RGBA8)
	for y in range(r):
		for x in range(r):
			var d = Vector2(x - r / 2.0 + 0.5, y - r / 2.0 + 0.5).length()
			im.set_pixel(x, y, Color(0.93, 0.41, 0.18, clampf(r / 2.0 - d, 0.0, 1.0)))
	return ImageTexture.create_from_image(im)


func _refresh_ui() -> void:
	ui.ship.text = SHIPS[int(cfg.ship)][1].to_upper()
	ui.credit.text = "Ship: " + SHIPS[int(cfg.ship)][3] + " · Holograms: Mixamo (Adobe), robotic girl by suddel, “Sexy Woman” and “Sexy Wet T-Shirt Babe” (Sketchfab), CC BY 4.0 · Textures: ambientCG (CC0) · Voices: Kokoro TTS (Apache 2.0) · Characters & start girl: John, 3D via Tripo AI · “Jungle Tree” by gelmi.com.br, CC BY 4.0 · private use only"
	ui.sl.speed.text = "Speed  %d %%" % int(round(float(cfg.speed) * 100.0))
	ui.sl.ai.text = "Rivals speed  %d %%" % int(round(float(cfg.ai) * 100.0))
	ui.sl.res.text = "Resolution  %d %%" % int(round(float(cfg.res) * 100.0))
	for q in range(3):
		ui.look[q].button_pressed = int(cfg.look) == q
	ui.sl.glow.text = "Glow  %d %%" % int(round(float(cfg.glow) * 100.0))
	ui.sl.neon.text = "Neon lights  %d %%" % int(round(float(cfg.neon) * 100.0))
	ui.sl.vol.text = "Volume  %d %%" % int(round(float(cfg.vol) * 100.0))
	for q in range(3):
		ui.gfx[q].button_pressed = int(cfg.gfx) == q
		var on = int(cfg.gfx) == q
		ui.gfx[q].add_theme_stylebox_override("normal", _style(Color(0.93, 0.41, 0.18) if on else Color(1, 1, 1, 0.08), Color(1, 0.7, 0.54) if on else Color(1, 1, 1, 0.22)))
		ui.gfx[q].add_theme_stylebox_override("pressed", ui.gfx[q].get_theme_stylebox("normal"))
		ui.gfx[q].add_theme_stylebox_override("hover", ui.gfx[q].get_theme_stylebox("normal"))
	for q in range(2):
		for pair in [[ui.get("fpsb", []), "fps"], [ui.get("capb", []), "cap"], [ui.get("perfb", []), "perf"]]:
			if q < pair[0].size():
				var on4 = int(cfg[pair[1]]) == q
				var st4 = _style(Color(0.93, 0.41, 0.18) if on4 else Color(1, 1, 1, 0.08), Color(1, 0.7, 0.54) if on4 else Color(1, 1, 1, 0.22))
				for k in ["normal", "pressed", "hover"]:
					pair[0][q].add_theme_stylebox_override(k, st4)
	for q in range(2):
		var on3 = int(cfg.pads) == q
		var st3 = _style(Color(0.93, 0.41, 0.18) if on3 else Color(1, 1, 1, 0.08), Color(1, 0.7, 0.54) if on3 else Color(1, 1, 1, 0.22))
		for k in ["normal", "pressed", "hover"]:
			ui.pads[q].add_theme_stylebox_override(k, st3)
	for q in range(3):
		var on2 = int(cfg.look) == q
		var st2 = _style(Color(0.93, 0.41, 0.18) if on2 else Color(1, 1, 1, 0.08), Color(1, 0.7, 0.54) if on2 else Color(1, 1, 1, 0.22))
		for k in ["normal", "pressed", "hover"]:
			ui.look[q].add_theme_stylebox_override(k, st2)


func _pick_ship(d: int) -> void:
	cfg.ship = (int(cfg.ship) + d + SHIPS.size()) % SHIPS.size()
	_save_cfg()
	for s in ships:
		s.node.queue_free()
	ships.clear()
	_spawn_ships()
	_ship_sounds()
	_refresh_ui()
	if not race0.is_empty():
		ships0 = []
		for o in ships:
			ships0.append((o as Dictionary).duplicate(true))   # neuer Gleiter: Startstand für „Race again“ mitnehmen


var free_ride = false   # freies Fahren: keine Gegner, kein Schaden, keine Rundenzahl – zum Einstellen in Ruhe


func _start() -> void:
	race_kids = get_children()
	if free_ride:
		for i in range(1, ships.size()):
			ships[i].out = true
			(ships[i].node as Node3D).visible = false
			ships[i].z = -9999.0
		hud.plbox.visible = false
	for i in range(1, ships.size()):
		ships[i].sk = (1.0 + (i - 1) * 0.035) * float(cfg.ai)
		ships[i].sk0 = ships[i].sk
	state = "intro"
	t_state = 0.0
	ptr_lat = 0.0
	lane_cur = 0
	ui.root.visible = false
	hud.layer.visible = true
	if int(cfg.get("comic", 1)) == 1 and not free_ride and rpf.is_empty() and (shot_s in ["", "?"] or shot_s.contains("comic")):
		_comic_start("start")


var rtouch = {}


# Replay-Gesten: ein Finger wischen = spulen (läuft nach dem Loslassen weiter), zwei Finger = freie Kamera drehen und zoomen
func _rp_input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch:
		if ev.pressed:
			rtouch[ev.index] = ev.position
		else:
			rtouch.erase(ev.index)
		if rtouch.size() != 1:
			rp.scrub = false
		if rtouch.size() < 2:
			rp.erase("pinch")
	elif ev is InputEventScreenDrag:
		if not rtouch.has(ev.index):
			return
		rtouch[ev.index] = ev.position
		var w = maxf(1.0, get_viewport().get_visible_rect().size.x)
		if rtouch.size() == 1:
			# über die ganze Bildschirmbreite wischen = 8 Sekunden
			if absf(ev.relative.x) > 0.0:
				rp.scrub = true
				_rp_seek(rp.t + ev.relative.x / w * 8.0)
		elif rtouch.size() >= 2 and RP_CAMS[rp.ci][0] == "free":
			var k = rtouch.keys()
			var a: Vector2 = rtouch[k[0]]
			var b: Vector2 = rtouch[k[1]]
			var d = a.distance_to(b)
			if rp.has("pinch") and rp.pinch > 1.0:
				rp.fdist = clampf(rp.fdist * rp.pinch / maxf(1.0, d), 2.0, 40.0)
			rp.pinch = d
			# beide Finger melden sich einzeln: Hälfte der Bewegung je Finger
			rp.fyaw -= ev.relative.x / w * PI * 0.5
			rp.fpitch = clampf(rp.fpitch + ev.relative.y / w * PI * 0.5, -0.15, 1.45)


func _rp_seek(t: float) -> void:
	var F = rec
	rp.t = clampf(t, F[0].t, F[F.size() - 1].t)
	# binäre Suche: auch spät in langen Replays ruckelfrei spulen
	var lo = 0
	var hi = F.size() - 2
	while lo < hi:
		var mid = (lo + hi + 1) >> 1
		if F[mid].t <= rp.t:
			lo = mid
		else:
			hi = mid - 1
	var i = lo
	rp.i = i
	rp.sp = null   # Streckenkamera nach dem Spulen neu aufstellen
	rp.ei = i
	rp.dirty = true   # Effekte passend zur neuen Zeit neu aufbauen


# wie lange ein Effekt sichtbar bleibt (fürs Neuaufbauen beim Spulen) – hängt von den FX-Lab-Reglern ab
func _fx_dur(k: String) -> float:
	match k:
		"boom":
			return maxf(4.0, 10.0 * float(fx.boom.slife) + 0.5)
		"gb":
			return float(fx.gb.time) * maxf(1.25, 0.55 + 0.9 / maxf(0.1, float(fx.gb.wspeed))) + 0.3
		"zap":
			return 2.6
	return 0.0


# alle Effekte so aufbauen, wie sie zur Replay-Zeit rp.t aussehen (Explosionen mittendrin, Rauch, schwarze Löcher …)
func _rp_rebuild_fx() -> void:
	var keep = rp.get("base", [])
	var pools = []
	for k in ["shots", "mines", "walls", "swalls"]:
		pools.append_array(rp.get(k, []))
	for n in get_children():
		if (n is GPUParticles3D or n is MeshInstance3D or n is OmniLight3D) and not keep.has(n) and not pools.has(n) and not tun_l.has(n) and not n.has_meta("keep"):
			n.queue_free()
	for e in zaps:
		e.mi.queue_free()
		e.l.queue_free()
	zaps.clear()
	fxs.clear()
	var F = rec
	var j = rp.i
	fx_gen += 1
	warm = true   # kein Ton, kein Blitz beim Aufbauen
	fx_rebuild = true
	live_bursts = 0
	var durs = {"boom": _fx_dur("boom"), "gb": _fx_dur("gb"), "zap": _fx_dur("zap")}
	var win = maxf(durs.boom, durs.gb)
	while j >= 0 and F[j].t >= rp.t - win:
		for ev in F[j].ev:
			var age: float = rp.t - F[j].t
			if age < 0.0 or age > durs.get(ev[0], 0.0):
				continue
			fx_age = age
			match ev[0]:
				"boom":
					_explode(ev[1], ev[2], ev[3], ev[4] if ev.size() > 4 else 1.0)
				"gb":
					_gbomb(ev[1], ev[2], -2, -1, ev[3] if ev.size() > 3 else 1.0)
				"zap":
					_zap_ship(ships[ev[1]])
		j -= 1
	_fx_update(0.0)
	fx_age = 0.0
	fx_rebuild = false
	warm = false
	shake = 0.0
	rp.dirty = false
	rp.rbt = Time.get_ticks_msec()
	rp.fr = 2   # neue Partikel erst ein, zwei Bilder rechnen lassen (Vorlauf), dann einfrieren


# angehalten oder beim Spulen: alle Partikel einfrieren
func _rp_freeze(on: bool) -> void:
	if rp.get("fr", 0) > 0:
		rp.fr -= 1
		on = false
	elif rp.get("frz", false) == on and rp.get("frc", -1) == get_child_count():
		return   # nichts geändert (auch keine neuen Funken/Rauchwolken): nicht jedes Bild alle Knoten durchgehen
	rp.frz = on
	rp.frc = get_child_count()
	for n in get_children():
		if n is GPUParticles3D:
			n.speed_scale = 0.0 if on else 1.0


func _input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo and (ev.keycode == KEY_BACK or ev.keycode == KEY_ESCAPE):
		get_viewport().set_input_as_handled()
		_go_back()
		return
	if ev is InputEventScreenTouch:
		if ev.pressed:
			fingers[ev.index] = true
		else:
			fingers.erase(ev.index)
	if not stt.is_empty() and stt.get("open", false) and stt.has("sc") and is_instance_valid(stt.sc) and _scr_input(ev, stt.sc):
		get_viewport().set_input_as_handled()
		return
	if ui.has("setp") and (ui.setp as Control).is_visible_in_tree() and _scr_input(ev, ui.setp):
		get_viewport().set_input_as_handled()
		return
	if state == "lab":
		_lab_input(ev)
		return
	if state == "replay" and vx.is_empty() and not rp.is_empty():
		_rp_input(ev)
	if ev is InputEventScreenTouch:
		if ev.pressed and state == "done" and hud.board.visible and (hud.board as Control).get_global_rect().grow(30).has_point(ev.position):
			# Tafel antippen: zwischen Ergebnis und Schaden umschalten, danach kein automatischer Wechsel mehr
			var cur_dmg = fmod(board_t, 9.0) > 5.0 if board_man < 0 else board_man == 1
			board_man = 0 if cur_dmg else 1
		if ev.pressed:
			if state == "kill":
				_kc_end()
				return
			if hud.has("pausebtn") and (hud.pausebtn as Control).visible and (hud.pausebtn as Control).get_global_rect().grow(24).has_point(ev.position):
				_pause(true)
				return
			if state == "race" and fire_rect.has_point(ev.position):
				fire_req = true
				return
			if not stt.is_empty() and _stt_hit(ev.position):
				return
			touches[ev.index] = ev.position.x
			_sw_down(ev.index, ev.position)
		else:
			if touches.has(ev.index):
				_sw_up(ev.index, ev.position)
			touches.erase(ev.index)
	elif ev is InputEventScreenDrag:
		if touches.has(ev.index):
			touches[ev.index] = ev.position.x
			_sw_drag(ev.index, ev.position, ev.velocity)
	elif ev is InputEventKey and ev.pressed and ev.keycode == KEY_SPACE:
		fire_req = true


func _steer_input() -> int:
	var w = get_viewport().get_visible_rect().size.x
	var l = false
	var r = false
	for k in touches:
		if touches[k] < w * 0.5:
			l = true
		else:
			r = true
	if Input.is_key_pressed(KEY_LEFT):
		l = true
	if Input.is_key_pressed(KEY_RIGHT):
		r = true
	return (1 if r else 0) - (1 if l else 0)


# ---------------------------------------------------------------- Waffen und Energie
# ---------------------------------------------------------------- Boost- und Waffenfelder: fest oder zufällig mit Regeln
var pad_seed = 0
var pb_lat = []
var pb_off = []
var pw_lat = []
var pw_off = []


func _pads_gen() -> void:
	pb_lat.clear()
	pb_off.clear()
	pw_lat.clear()
	pw_off.clear()
	if pad_seed == 0:
		return
	var rng = RandomNumberGenerator.new()
	rng.seed = pad_seed
	var lim = 0.8   # nicht zu nah an den Rand
	var prev_b = 99.0
	for k in range(20):
		# Boost-Feld: etwas vor/zurück, gern auf der Innenseite der kommenden Kurve, nie direkt hinter dem vorigen
		pb_off.append(rng.randf_range(-5.0, 5.0))
		var c = signf(T.d2px(k * 35.0 + 6.0))
		var lat = 0.0
		for _t in range(12):
			lat = c * rng.randf_range(0.4, lim) if rng.randf() < 0.5 and c != 0.0 else rng.randf_range(-lim, lim)
			if absf(lat - prev_b) >= 0.5:
				break
		pb_lat.append(lat)
		prev_b = lat
	var prev_w = 99.0
	for k in range(20):
		pw_off.append(rng.randf_range(-6.0, 6.0))
		var lat = 0.0
		for _t in range(12):
			lat = rng.randf_range(-lim, lim)
			# nicht genau hinter dem Boost-Feld davor und nicht in derselben Spur wie die vorige Waffensäule
			if absf(lat - pb_lat[k]) >= 0.5 and absf(lat - prev_w) >= 0.4:
				break
		pw_lat.append(lat)
		if k % 2 == 0:
			prev_w = lat


func _bpx(k: int) -> float:
	return _lane_snap(_bpx0(k))


func _wpx(k: int) -> float:
	return _lane_snap(_wpx0(k))


# Felder und Säulen liegen immer genau auf einer der drei Spuren
func _lane_snap(v: float) -> float:
	return clampi(int(roundf(v / 0.5)), -1, 1) * LANE_W


func _bpx0(k: int) -> float:
	return T.bpx(k) if pad_seed == 0 else pb_lat[posmod(k, 20)]


func _bzp(k: int) -> float:
	return k * 35.0 + (0.0 if pad_seed == 0 else pb_off[posmod(k, 20)])


func _wzp(k: int) -> float:
	return k * 35.0 + 17.0 + (0.0 if pad_seed == 0 else pw_off[posmod(k, 20)])


# gibt es das Feld auf der Strecke wirklich? (nicht am Start, nicht über der Sprunglücke)
func _pad_ok(z: float) -> bool:
	var zl = fposmod(z - 20.0, 700.0) + 20.0
	return zl >= 25.0 and zl <= 715.0 and not T.gap(zl + 1.0)


func _wpx0(k: int) -> float:
	if pad_seed != 0:
		return pw_lat[posmod(k, 20)]
	return -0.55 * sin(posmod(k, 20) * 1.3 + 0.4) * T.TW / 1.6


func _pick_w() -> String:
	var r = randf()
	for w in WP:
		r -= w[1]
		if r < 0.0:
			return w[0]
	return "rak"


# Kugelnetz mit wenigen Dreiecken, einmal je Größe gebaut und wiederverwendet
var lowsph = {}


func _lowsphere(r: float, seg: int, rings: int) -> SphereMesh:
	var key = "%.3f_%d_%d" % [r, seg, rings]
	if not lowsph.has(key):
		var sp = SphereMesh.new()
		sp.radius = r
		sp.height = r * 2.0
		sp.radial_segments = seg
		sp.rings = rings
		lowsph[key] = sp
	return lowsph[key]


func _glow_node(mesh: Mesh, c: Color, e: float, alpha := 1.0) -> MeshInstance3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi = MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _msg(t: String, c: Color) -> void:
	if big_t > 0.4 and t.begins_with("HIT"):
		return   # große Meldung läuft gerade: kleine Trefferzeile weglassen
	hud.msg.text = t
	hud.msg.modulate = c
	msg_t = 1.4


var msg_t = 0.0
var last_place = 0
var pl_flash = 0.0
var pl_col = Color(1, 1, 1)
var big_t = 0.0


func _big(t: String, c: Color) -> void:
	_rev(["big", t, c])
	hud.big.text = t
	hud.big.modulate = c
	big_t = 2.4


var fxr = {}
var flash_rect: ColorRect


func _flash(c: Color, a: float) -> void:
	if warm:
		return
	if flash_rect == null:
		var cl = CanvasLayer.new()
		cl.layer = 4
		add_child(cl)
		flash_rect = ColorRect.new()
		flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		flash_rect.color = Color(0, 0, 0, 0)
		cl.add_child(flash_rect)
	# starker Blitz: von der Effektfarbe ins grelle Weiß (sonst bleibt ein voller Blitz nur orange)
	var w = clampf((a - 0.35) / 0.45, 0.0, 1.0)
	var cc = c.lerp(Color(1, 1, 1), w * w)
	if flash_rect.color.a > a:
		cc = Color(flash_rect.color.r, flash_rect.color.g, flash_rect.color.b).lerp(cc, a / maxf(0.001, flash_rect.color.a))
	flash_rect.color = Color(cc.r, cc.g, cc.b, minf(1.0, maxf(flash_rect.color.a, a)))
	flash_rect.visible = true
	# neuer Renderer: zusätzlich kurz die ganze Szene überbelichten, damit helle Stellen weiß ausbrennen
	expo_v = maxf(expo_v, minf(1.5, a * 1.2) * _newr("expo", 0.0))

var shake = 0.0


func _fx_res() -> void:
	if not fxr.is_empty():
		return
	var gt = GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	var gr = Gradient.new()
	gr.set_color(0, Color(1, 1, 1, 1))
	gr.set_color(1, Color(1, 1, 1, 0))
	gr.add_point(0.45, Color(1, 1, 1, 0.55))
	gt.gradient = gr
	gt.width = 64
	gt.height = 64
	var mk = func(add: bool) -> StandardMaterial3D:
		var m = StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if add else BaseMaterial3D.BLEND_MODE_MIX
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.vertex_color_use_as_albedo = true
		m.albedo_texture = gt
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.disable_receive_shadows = true
		return m
	var q = QuadMesh.new()
	q.size = Vector2(1, 1)
	var fn = FastNoiseLite.new()
	fn.frequency = 0.06
	fn.fractal_octaves = 4
	var ft = NoiseTexture2D.new()
	ft.noise = fn
	ft.seamless = true
	ft.width = 128
	ft.height = 128
	var fm = _shader_mat("""
shader_type spatial;
render_mode unshaded,blend_add,cull_disabled,depth_draw_never,shadows_disabled;
uniform sampler2D nz:repeat_enable;
varying float seed;
void vertex(){
	float s=length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX=VIEW_MATRIX*mat4(INV_VIEW_MATRIX[0]*s,INV_VIEW_MATRIX[1]*s,INV_VIEW_MATRIX[2]*s,MODEL_MATRIX[3]);
	seed=fract(MODEL_MATRIX[3].x*3.17+MODEL_MATRIX[3].z*1.73);
}
void fragment(){
	vec2 q=UV-.5;float d=length(q)*2.;
	float n=texture(nz,UV*.7+vec2(seed,seed*1.3)+vec2(0.,TIME*.35)).r;
	float n2=texture(nz,UV*1.6-vec2(seed*.7,TIME*.6)).r;
	float m=smoothstep(1.,.25,d+(n-.5)*.9+(n2-.5)*.35);
	float core=smoothstep(.55,0.,d+(n-.5)*.5);
	ALBEDO=COLOR.rgb*(m*.9+core*1.4)*COLOR.a;
}""")
	fm.set_shader_parameter("nz", ft)
	q.material = fm
	fxr.fire = q
	var q2 = QuadMesh.new()
	q2.size = Vector2(1, 1)
	var smm = _shader_mat("""
shader_type spatial;
// Rauch: echte Beleuchtung (Explosionslicht färbt ihn orange), wabernde Ränder
render_mode blend_mix,cull_disabled,depth_draw_never,shadows_disabled,specular_disabled;
uniform sampler2D nz:repeat_enable;
varying float seed;
void vertex(){
	float s=length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX=VIEW_MATRIX*mat4(INV_VIEW_MATRIX[0]*s,INV_VIEW_MATRIX[1]*s,INV_VIEW_MATRIX[2]*s,MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX=mat3(MODELVIEW_MATRIX);
	seed=fract(MODEL_MATRIX[3].x*2.31+MODEL_MATRIX[3].y*1.17+MODEL_MATRIX[3].z*3.7);
}
void fragment(){
	vec2 q=UV-.5;float d=length(q)*2.;
	float n=texture(nz,UV*.55+vec2(seed,seed*1.7)+vec2(TIME*.015,TIME*.03)).r;
	float n2=texture(nz,UV*1.3-vec2(seed*.5,TIME*.045)).r;
	float m=smoothstep(1.,.15,d+(n-.5)*1.2+(n2-.5)*.5);
	ALBEDO=COLOR.rgb*(.55+.9*n*n2);
	ROUGHNESS=1.;
	BACKLIGHT=vec3(.2);
	ALPHA=clamp(m*COLOR.a,0.,1.);
}""")
	smm.set_shader_parameter("nz", ft)
	q2.material = smm
	fxr.smoke = q2
	var sp = CapsuleMesh.new()
	sp.radius = 0.018
	sp.height = 0.42
	sp.radial_segments = 4
	sp.rings = 1
	var sm = StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.vertex_color_use_as_albedo = true
	sp.material = sm
	fxr.spark = sp
	# Metallsplitter: dünne, unregelmäßige Scherbe; glüht weiß-orange und kühlt beim Fliegen ab (Farbe kommt vom Partikel)
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rim = [Vector3(0.0, 0.0, 0.13), Vector3(-0.035, 0.004, 0.02), Vector3(-0.05, -0.003, -0.07), Vector3(0.01, 0.0, -0.06), Vector3(0.045, 0.006, 0.01)]
	var top = Vector3(-0.004, 0.018, 0.0)
	var bot = Vector3(0.003, -0.014, 0.004)
	for i in range(rim.size()):
		var a0: Vector3 = rim[i]
		var a1: Vector3 = rim[(i + 1) % rim.size()]
		st.add_vertex(top)
		st.add_vertex(a1)
		st.add_vertex(a0)
		st.add_vertex(bot)
		st.add_vertex(a0)
		st.add_vertex(a1)
	st.generate_normals()
	var shard = st.commit()
	shard.surface_set_material(0, _shader_mat("""
shader_type spatial;
render_mode cull_disabled;
void fragment(){ALBEDO=vec3(.09,.09,.1);METALLIC=.9;ROUGHNESS=.3;EMISSION=COLOR.rgb;}"""))
	fxr.debris = shard
	var hg = GradientTexture2D.new()
	hg.fill = GradientTexture2D.FILL_RADIAL
	hg.fill_from = Vector2(0.5, 0.5)
	hg.fill_to = Vector2(1.0, 0.5)
	var hgr = Gradient.new()
	hgr.set_color(0, Color(1, 1, 1, 1))
	hgr.set_color(1, Color(1, 1, 1, 0))
	hgr.add_point(0.25, Color(1, 1, 1, 0.55))
	hg.gradient = hgr
	hg.width = 64
	hg.height = 64
	fxr.halo = hg
	var ring = QuadMesh.new()
	ring.size = Vector2(2, 2)
	ring.orientation = PlaneMesh.FACE_Y
	fxr.ring = ring
	fxr.ring_code = """
shader_type spatial;
render_mode unshaded,blend_add,cull_disabled,depth_draw_never,shadows_disabled;
uniform float u=0.;uniform vec3 rc=vec3(1.,.7,.4);uniform float rk=1.;
void fragment(){float r=length(UV-.5)*2.;float w=smoothstep(.12,0.,abs(r-.85))*(1.-u);ALBEDO=rc*w*3.*rk;}"""


var tex_cache = {}


func _ramp(cols: Array, hdr := true) -> GradientTexture1D:
	var key = var_to_str(cols) + str(hdr)
	if tex_cache.has(key):
		return tex_cache[key]
	var g = Gradient.new()
	g.offsets = PackedFloat32Array(cols.map(func(c): return c[0]))
	g.colors = PackedColorArray(cols.map(func(c): return c[1]))
	var t = GradientTexture1D.new()
	t.gradient = g
	t.use_hdr = hdr
	tex_cache[key] = t
	return t


func _curve(pts: Array) -> CurveTexture:
	var key = var_to_str(pts)
	if tex_cache.has(key):
		return tex_cache[key]
	var c = Curve.new()
	c.max_value = 4.0
	for p in pts:
		c.add_point(Vector2(p[0], p[1]))
	var t = CurveTexture.new()
	t.curve = c
	tex_cache[key] = t
	return t


var live_bursts = 0


# Alter, mit dem neue Effekte entstehen (im Replay beim Spulen: Effekt startet schon „mittendrin“)
var fx_age = 0.0
var fx_rebuild = false
var fx_gen = 0


# später ausführen – oder sofort, wenn der Effekt schon älter ist als die Verzögerung
func _later(d: float, f: Callable) -> void:
	if fx_age >= d:
		var old = fx_age
		fx_age = fx_age - d
		f.call()
		fx_age = old
	else:
		# Spulen/Neuaufbau im Replay macht alte, verzögerte Effekte ungültig
		var gen = fx_gen
		get_tree().create_timer(d - fx_age).timeout.connect(func():
			if gen == fx_gen:
				f.call())


func _burst(pos: Vector3, mesh: Mesh, amount: int, life: float, vmin: float, vmax: float, spread: float, grav: Vector3, damp: float, smin: float, smax: float, ramp: GradientTexture1D, scurve: CurveTexture, align := false, spin := false, rad := 0.25) -> void:
	if fx_age > life:
		return
	# Budget: je nach Grafikstufe und wie viel gerade schon los ist
	var q = [0.45, 0.7, 1.0][clampi(int(cfg.gfx), 0, 2)]
	if live_bursts > 10 and not fx_rebuild:
		q *= 0.5
	if live_bursts > 22 and not fx_rebuild:
		return
	amount = clampi(int(amount * q), 3, 900)
	live_bursts += 1
	get_tree().create_timer(life + 0.6).timeout.connect(func(): live_bursts = maxi(0, live_bursts - 1))
	var p = GPUParticles3D.new()
	var m = ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = rad
	m.direction = Vector3(0, 1, 0)
	m.spread = spread
	m.initial_velocity_min = vmin
	m.initial_velocity_max = vmax
	m.gravity = grav
	m.damping_min = damp
	m.damping_max = damp
	m.scale_min = smin
	m.scale_max = smax
	if scurve != null:
		m.scale_curve = scurve
	if ramp != null:
		m.color_ramp = ramp
	if align:
		m.particle_flag_align_y = true
	if spin:
		m.angular_velocity_min = -720.0
		m.angular_velocity_max = 720.0
		m.particle_flag_rotate_y = true
	p.process_material = m
	p.draw_pass_1 = mesh
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 1.0
	p.randomness = 0.5
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-12, -12, -12), Vector3(24, 24, 24))
	p.position = pos
	add_child(p)
	if fx_age > 0.0:
		# Vorlauf beim Spulen: begrenzt und in groben Schritten, damit der Grafikchip nicht überlastet
		p.fixed_fps = 12
		p.preprocess = minf(fx_age, 3.0)
	p.emitting = true
	get_tree().create_timer(life + 0.6 - fx_age).timeout.connect(p.queue_free)


# Feuerball aus vielen wabernden Flammen: grell weiß-gelb → orange → dunkelrot, steigt etwas auf
# Farbverlauf der Splitter: glühend → rot → dunkles Metall
func _deb_ramp(gl: float, hu := 0.0) -> GradientTexture1D:
	return _ramp(_rh([[0.0, Color(7, 3.5, 1.2, 1) * gl], [0.3, Color(3, 0.8, 0.12, 1) * gl], [0.7, Color(0.5, 0.08, 0.01, 1) * gl], [1.0, Color(0, 0, 0, 1)]], hu))


func _fire_ball(pos: Vector3, k: float, am := 1.0, hu := 0.0) -> void:
	if am < 0.01:
		return
	_burst(pos, fxr.fire, int(16 * k * am), 1.0, 2.0 * k, 5.5 * k, 180.0, Vector3(0, 1.6, 0), 4.0, 1.1 * k, 1.9 * k,
		_ramp(_rh([[0.0, Color(12, 10, 7, 1)], [0.1, Color(9, 4.5, 1.2, 1)], [0.35, Color(4, 1.1, 0.15, 0.85)], [0.7, Color(1.0, 0.2, 0.04, 0.45)], [1.0, Color(0.1, 0.02, 0.01, 0)]], hu)),
		_curve([[0.0, 0.5], [0.2, 1.25], [1.0, 1.6]]), false, false, 0.5 * k)


# Gravitationsbombe: schwarzes Loch saugt Licht und Funken an, schnappt dann mit einer Welle zurück
func _gbomb(z: float, lat: float, own := -1, hit := -1, sc := 1.0, sup := false) -> void:
	_pev("hole")
	_rev(["gb", z, lat, sc])
	_fx_res()
	var f = T.frame(z)
	var pos: Vector3 = f.c + f.rr * lat + f.uu * 0.6
	var X: Dictionary = fx.gb
	var hu = float(X.hue)
	var gsc = float(X.scale) * sc   # Gesamtgröße: alles zusammen
	var gz = float(X.size) * gsc
	var core = MeshInstance3D.new()
	core.mesh = _lowsphere(1.0, 24, 12)
	var cm = StandardMaterial3D.new()
	cm.albedo_color = Color(0, 0, 0, float(X.dark))
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if float(X.dark) < 0.99:
		cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	core.material_override = cm
	core.position = pos
	core.scale = Vector3.ONE * 0.05
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(core)
	var ring = MeshInstance3D.new()
	var tm = TorusMesh.new()
	tm.inner_radius = 0.9
	tm.outer_radius = 0.9 + 0.22 * float(X.rimw)
	tm.rings = 48
	ring.mesh = tm
	var rmt = StandardMaterial3D.new()
	rmt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmt.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	rmt.albedo_color = _hs(Color(1.6, 1.2, 3.0) * float(X.rimb), hu + float(X.rimh))
	ring.material_override = rmt
	ring.position = pos
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	# Funken werden ins Loch gezogen
	var p = GPUParticles3D.new()
	var m = ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	m.emission_sphere_radius = 4.5 * gz
	m.radial_accel_min = -45.0 * gz
	m.radial_accel_max = -30.0 * gz
	m.gravity = Vector3.ZERO
	m.particle_flag_align_y = true
	m.color_ramp = _ramp(_rh([[0.0, Color(0.6, 0.4, 2.5, 0)], [0.3, Color(1.5, 1.0, 4.0, 1)], [1.0, Color(3, 2.5, 5, 1)]], hu))
	p.process_material = m
	p.draw_pass_1 = fxr.spark
	p.amount = maxi(1, int(50 * float(X.sparks)))
	p.visible = float(X.sparks) > 0.01
	p.lifetime = 0.55
	p.one_shot = true
	p.explosiveness = 0.85
	p.position = pos
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-8, -8, -8) * gz, Vector3(16, 16, 16) * gz)
	add_child(p)
	if fx_age > 0.0:
		p.preprocess = minf(fx_age, 0.55)
	p.emitting = true
	get_tree().create_timer(maxf(0.1, 1.2 - fx_age)).timeout.connect(p.queue_free)
	var lt = OmniLight3D.new()
	lt.light_color = _hs(Color(0.65, 0.5, 1.0), hu)
	lt.omni_range = 12.0 * sqrt(gz)
	lt.light_energy = 0.0
	lt.position = pos
	add_child(lt)
	fxs.append({"gb": true, "pos": pos, "core": core, "ring": ring, "l": lt, "t": fx_age / maxf(0.05, float(X.time)), "f": f, "z": z, "lat": lat, "snap": false, "own": own, "hit": hit,
		"sz": gz, "ps": gsc, "ts": float(X.time), "wt": float(X.wthick), "ws": float(X.wspeed), "wz": float(X.wsize), "whu": hu + float(X.whue), "gr": float(X.gring),
		"rimw": float(X.rimw), "rimb": float(X.rimb), "rimh": hu + float(X.rimh), "dark": float(X.dark), "cs": float(X.core) * sqrt(float(X.size)) * gsc, "sp": float(X.sparks), "wv": float(X.wave), "lk": float(X.light), "lens": float(X.lens), "sh": float(X.shake), "hu": hu, "sup": sup})
	_snd("gbomb", 3.0, 1.0, pos)


func _gb_damage(e: Dictionary) -> void:
	for o in ships:
		if o.out or o.idx == e.own:
			continue
		var dd = Vector2(o.z - e.z, o.lat - e.lat).length()
		var kk = clampf(1.0 - dd / (GB_R * e.get("sz", 1.0)), 0.0, 1.0)
		if kk > 0.0:
			_dmg(o, (0.45 * pow(kk, 1.2)) * (0.5 if o.idx == e.hit else 1.0), e.own, "rocket", e.get("sup", false))
			if not _prot(o):   # mit Schild: kein Abbremsen
				o.slow = minf(o.slow, 0.4)


func _glow_mat(c: Color, e: float) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _gb_update(e: Dictionary, dt: float) -> bool:
	e.t += dt / e.get("ts", 1.0)
	var gz: float = e.get("sz", 1.0)
	var t: float = e.t
	var cr: MeshInstance3D = e.core
	var rg: MeshInstance3D = e.ring
	# Sog: Gegner in der Nähe werden zur Mitte des Lochs gezogen und abgebremst (der Schütze nicht)
	if t < 0.62 and e.own != -2:
		for o in ships:
			if o.out or o.idx == e.own or _prot(o):
				continue
			var dd = Vector2(o.z - e.z, o.lat - e.lat).length()
			var kk = clampf(1.0 - dd / (GB_R * gz), 0.0, 1.0)
			if kk > 0.0:
				o.lat += (e.lat - o.lat) * minf(1.0, dt * 5.0 * kk)
				o.slow = minf(o.slow, 1.0 - 0.75 * kk)
				o.vpsi *= 1.0 - minf(1.0, dt * 6.0 * kk)
	if t < 0.55:
		var u = t / 0.55
		cr.scale = Vector3.ONE * (0.1 + 0.9 * pow(u, 1.5)) * e.get("cs", 1.0)
		rg.scale = Vector3.ONE * (2.6 - 1.4 * u) * e.get("cs", 1.0)
		e.l.light_energy = 6.0 * u * e.get("lk", 1.0)
	elif not e.snap:
		e.snap = true
		if e.own != -2:
			_gb_damage(e)
		cr.visible = false
		rg.visible = false
		_fx_res()
		var f = e.f
		# Rückstoß: Funken und Lichtblitz nach außen, Ring über die Fahrbahn
		var old_age = fx_age
		fx_age = maxf(0.0, (t - 0.55) * e.get("ts", 1.0)) if fx_rebuild else 0.0
		var sp: float = e.get("sp", 1.0)
		var hu: float = e.get("hu", 0.0)
		if sp > 0.01:
			_burst(e.pos, fxr.spark, int(60 * sp), 1.0, 10.0 * sqrt(gz), 22.0 * sqrt(gz), 180.0, Vector3(0, -6, 0), 0.8, 0.8, 1.6,
				_ramp(_rh([[0.0, Color(5, 4, 9, 1)], [0.6, Color(1.6, 1.0, 4.0, 1)], [1.0, Color(0.4, 0.2, 1.0, 0)]], hu)), null, true, false, 0.3)
			_burst(e.pos - f.uu * 0.4, fxr.debris, int(12 * sp), 1.8, 5.0, 12.0, 60.0, Vector3(0, -15, 0), 0.2, 0.8, 2.4, _deb_ramp(float(fx.boom.dglow), hu), null, false, true, 0.3)
		fx_age = old_age
		var ring = MeshInstance3D.new()
		ring.mesh = fxr.ring
		var rm = _shader_mat(fxr.ring_code)
		rm.set_shader_parameter("rc", _v3(_hs(Color(0.7, 0.5, 1.0), e.get("whu", hu))))
		rm.set_shader_parameter("rk", e.get("gr", 1.0))
		ring.material_override = rm
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.visible = e.get("gr", 1.0) > 0.01
		add_child(ring)
		e.sw = ring
		e.swm = rm
		# Druckwelle als Kugel: dehnt sich in alle Richtungen aus, leuchtet am Rand (Fresnel), wird dabei dünner
		if fxr.get("wsph") == null:
			var sm2 = SphereMesh.new()
			sm2.radius = 1.0
			sm2.height = 2.0
			sm2.radial_segments = 32
			sm2.rings = 16
			fxr.wsph = sm2
		var sph = MeshInstance3D.new()
		sph.mesh = fxr.wsph
		var smt = _shader_mat("""
shader_type spatial;
render_mode unshaded,blend_add,cull_disabled,depth_draw_never,shadows_disabled,fog_disabled;
uniform vec3 wc=vec3(.7,.5,1.);uniform float u=0.;uniform float th=1.;uniform float br=1.;
void fragment(){
	float fr=clamp(1.-abs(dot(NORMAL,VIEW)),0.,1.);
	float shell=pow(fr,mix(7.,1.3,clamp(th*.35,0.,1.)));
	float f=(1.-u);
	ALBEDO=wc*(shell*2.4+.05*th)*br*f*f;
}""")
		smt.set_shader_parameter("wc", _v3(_hs(Color(0.7, 0.5, 1.0), e.get("whu", hu))))
		smt.set_shader_parameter("th", e.get("wt", 1.0))
		smt.set_shader_parameter("br", e.get("wv", 1.0))
		sph.material_override = smt
		sph.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sph.extra_cull_margin = 20.0
		sph.visible = e.get("wv", 1.0) > 0.01 and e.get("ps", 1.0) >= 0.75 * float(fx.gb.scale)
		sph.position = e.pos
		sph.scale = Vector3.ONE * 0.3
		add_child(sph)
		e.sph = sph
		e.sphm = smt
		e.l.light_energy = 9.0 * e.get("lk", 1.0)
		var d = (e.pos - cam.global_position).length()
		var near = clampf(1.0 - d / 40.0, 0.0, 1.0)
		shake = maxf(shake, 1.6 * near * e.get("sh", 1.0))
		_flash(_hs(Color(0.75, 0.6, 1.0), hu), 0.22 * near * minf(1.0, e.get("lk", 1.0)))
	else:
		var u = clampf((t - 0.55) / 0.7, 0.0, 1.0)
		var uw = clampf((t - 0.55) * e.get("ws", 1.0) / 0.9, 0.0, 1.0)
		rg.visible = false
		e.l.light_energy = 9.0 * pow(1.0 - u, 2.0) * e.get("lk", 1.0)
		var f = e.f
		var sc = (0.6 + 9.0 * pow(u, 0.5)) * gz
		e.sw.global_transform = Transform3D(Basis(f.rr * sc, f.uu, f.fw * sc), f.c + f.rr * e.lat + f.uu * 0.03)
		e.swm.set_shader_parameter("u", u)
		if e.has("sph"):
			e.sph.scale = Vector3.ONE * (0.4 + 6.5 * pow(uw, 0.6)) * gz * e.get("wz", 1.0)
			e.sphm.set_shader_parameter("u", uw)
		if u >= 1.0 and uw >= 1.0:
			for k in ["core", "ring", "l", "sw", "sph"]:
				if e.has(k):
					e[k].queue_free()
			return true
	# Ring zeigt zur Kamera (nur solange er sichtbar ist; nicht, wenn die Kamera genau darüber steht)
	if not e.snap:
		var dv: Vector3 = cam.global_position - rg.global_position
		if dv.length() > 0.01 and absf(dv.normalized().y) < 0.999:
			rg.look_at(cam.global_position, Vector3.UP)
			rg.rotate_object_local(Vector3(1, 0, 0), PI / 2.0)
	return false


func _explode(z: float, lat: float, big := false, sc := 1.0) -> void:
	_pev("boom" if not big else "BOOM")
	_rev(["boom", z, lat, big, sc])
	_fx_res()
	var X: Dictionary = fx.boom
	var hu = float(X.hue)
	var sz = float(X.size) * sc
	var k = (2.2 if big else 1.5) * sz
	var f = T.frame(z)
	var pos: Vector3 = f.c + f.rr * lat + f.uu * 0.35
	# Nachexplosionen: zwei, drei kleinere Feuerbälle rundherum, kurz versetzt
	var fa = float(X.fire)
	for j in range(int(round((2 if big else 1) * float(X.after)))):
		var off = (f.rr * randf_range(-1.2, 1.2) + f.uu * randf_range(0.2, 1.4) + f.fw * randf_range(-1.0, 1.5)) * sz
		_later(0.08 + j * 0.11, func(): _fire_ball(pos + off, k * 0.5, maxf(fa, 0.3), hu))
	# Feuerball: grell weiß-gelb → orange → dunkelrot
	_fire_ball(pos, k, fa, hu)
	# Rauch: steigt langsam auf, wird größer
	var sm = float(X.smoke)
	var sl = float(X.slife)
	if sm > 0.01:
		var smr = _ramp([[0.0, Color(0.16, 0.14, 0.13, 0)], [0.04, Color(0.14, 0.12, 0.11, 0.9)], [0.35, Color(0.1, 0.1, 0.11, 0.7)], [1.0, Color(0.08, 0.08, 0.09, 0)]], false)
		var smc = _curve([[0.0, 0.35], [0.25, 1.0], [1.0, 1.7]])
		_burst(pos + f.uu * 0.5, fxr.smoke, int(10 * k * sm), 8.0 * sl, 0.8, 2.6 * k, 80.0, Vector3(0, 0.35, 0), 1.6, 1.4 * k, 2.8 * k, smr, smc, false, false, 0.6 * k)
		# zweite, dichtere Wolke dicht über der Fahrbahn, hängt noch länger
		_later(0.25, func(): _burst(pos + f.uu * 0.2, fxr.smoke, int(6 * k * sm), 10.0 * sl, 0.3, 1.4 * k, 100.0, Vector3(0, 0.15, 0), 1.2, 1.8 * k, 3.2 * k, smr, smc, false, false, 0.9 * k))
	# Funkenregen
	if float(X.sparks) > 0.01:
		_burst(pos, fxr.spark, int(45 * k * float(X.sparks)), 1.3, 7.0 * k, 18.0 * k, 180.0, Vector3(0, -10, 0), 0.6, 0.7, 1.4,
			_ramp(_rh([[0.0, Color(9, 6, 2.5, 1)], [0.6, Color(4, 1.2, 0.2, 1)], [1.0, Color(1, 0.2, 0.05, 0)]], hu)), null, true, false, 0.2)
	# Trümmer: Stücke der Fahrbahn fliegen weg
	if float(X.debris) > 0.01:
		_burst(pos - f.uu * 0.2, fxr.debris, int(12 * k * float(X.debris)), 2.0, 5.0 * k, 12.0 * k, 60.0, Vector3(0, -15, 0), 0.2, 0.8, 2.6, _deb_ramp(float(X.dglow), hu), null, false, true, 0.3)
	# Druckwelle auf der Fahrbahn
	var ring = null
	var rm = null
	if float(X.ring) > 0.01:
		ring = MeshInstance3D.new()
		ring.mesh = fxr.ring
		rm = _shader_mat(fxr.ring_code)
		rm.set_shader_parameter("rc", _v3(_hs(Color(1.0, 0.7, 0.4), hu)))
		rm.set_shader_parameter("rk", float(X.ring))
		ring.material_override = rm
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.global_transform = Transform3D(Basis(f.rr, f.uu, f.fw), f.c + f.rr * lat + f.uu * 0.03)
		add_child(ring)
	# Lichtblitz
	var lt = OmniLight3D.new()
	lt.light_color = _hs(Color(1.0, 0.92, 0.8), hu)
	var rg0 = (16.0 if int(cfg.gfx) >= 2 else 10.0) * k
	lt.omni_range = rg0
	lt.omni_attenuation = 0.7
	lt.light_energy = 38.0 * float(X.light)
	lt.position = pos + f.uu * 0.9
	add_child(lt)
	fxs.append({"ring": ring, "rm": rm, "l": lt, "t": fx_age, "big": big, "f": f, "lat": lat, "rg": rg0, "sz": sz, "lk": float(X.light), "hu": hu})
	_snd("boom", 4.0 if big else 2.0, randf_range(0.85, 1.0), pos)
	_snd("boom", 2.0, 0.55, pos)   # tiefer Wumms darunter
	# Kamera rüttelt, je näher, desto stärker
	var d = (pos - cam.global_position).length()
	var near = clampf(1.0 - d / 35.0, 0.0, 1.0)
	shake = maxf(shake, (2.0 if big else 1.3) * near * float(X.shake))
	_flash(_hs(Color(1.0, 0.7, 0.4), hu), (0.55 if big else 0.35) * near * float(X.flash))


# Schaden: Schild schützt; leer = ausgeschieden; Meldung oben
# Schild fängt etwas ab: kurzes Aufleuchten und ein dumpfes Schlucken
func _shield_ping(o: Dictionary) -> void:
	o.shf = 1.0
	if race_t - o.get("shpT", -9.0) > 0.25:
		o.shpT = race_t
		_snd("shield", -6.0 if o.idx == 0 else 0.0, 1.9, null if o.idx == 0 else (o.node as Node3D).global_position)


# Schild zerbricht: Funkenregen, Meldung, Schutz weg
func _shield_break(o: Dictionary) -> void:
	o.shield = 0.0
	o.shh = 0
	_shield_vis(o)
	var pos: Vector3 = (o.node as Node3D).global_position + Vector3(0, 0.2, 0)
	_fx_res()
	_burst(pos, fxr.spark, 90, 0.8, 4.0, 10.0, 180.0, Vector3(0, -5, 0), 0.5, 0.6, 1.3,
		_ramp([[0.0, Color(2, 5, 9, 1)], [1.0, Color(0.2, 0.5, 1, 0)]]), null, true, false, 0.4)
	_snd("zap", 2.0, 0.7, null if o.idx == 0 else pos)
	if o.idx == 0:
		_msg("SHIELD BROKEN", Color(0.5, 0.75, 1.0))
		shake = maxf(shake, 0.6)
	else:
		_msg("SHIELD BROKEN · %s" % NAMES[o.idx], Color(0.5, 0.75, 1.0))


func _prot(o: Dictionary) -> bool:
	return o.shield > 0.0 or o.orbs > 0.0 or (o.idx == 0 and o.auto > 0.0)


func _dmg(o: Dictionary, a: float, src := -1, kind := "", sup := false) -> void:
	if free_ride:
		return
	if o.out or state != "race":
		return
	if o.shield > 0.0 and float(o.get("mshield", 0.0)) > 0.0:
		_shield_ping(o)   # Mega-Schild: hält alles aus
		return
	if o.shield > 0.0:
		# Schild: hält einen Waffentreffer aus (Rakete, Orb, Mine, Wand, Beben …), beim zweiten ist er weg;
		# Superwaffen zerschlagen ihn sofort. Rempeln schluckt er einfach.
		if sup or kind != "ram":
			o.shh = int(o.get("shh", 0)) + (2 if sup else 1)
			if o.shh >= 2:
				_shield_break(o)
			else:
				_shield_ping(o)
		else:
			_shield_ping(o)
		return
	if _prot(o):
		return
	var before: float = o.en
	o.en = maxf(0.0, o.en - a)
	if src >= 0 and src < ships.size() and src != o.idx:
		ships[src].dealt += before - o.en
	# wer austeilt, heilt sich: abgezogene Energie wird dir gutgeschrieben
	if src == 0 and o.idx != 0:
		ships[0].en = minf(1.0, ships[0].en + (before - o.en))
	var nm = NAMES[o.idx]
	if o.en <= 0.0:
		o.out = true
		o.outT = race_t
		_explode(o.z, o.lat, true)
		(o.node as Node3D).visible = false
		if (o.node as Node3D).has_meta("eng"):
			((o.node as Node3D).get_meta("eng") as AudioStreamPlayer3D).stop()
		_big("ELIMINATED" if o.idx == 0 else "CONTENDER\nELIMINATED", Color(1, 0.3, 0.25) if o.idx == 0 else Color(1, 0.82, 0.25))
		if o.idx != 0:
			_msg(nm.to_upper(), Color(1, 0.85, 0.5))
			_snd("boom", 4.0, 0.42)
			_snd("vo_elim", 4.0)
	elif o.idx == 0:
		_msg("−%d %% ENERGY" % int(round(a * 100.0)), Color(1, 0.48, 0.35))
	else:
		_msg("HIT · %s %d %%" % [nm, int(round(o.en * 100.0))], Color(1, 0.75, 0.5))


func _add_shot(from: Dictionary, at_player := false, homing := false, dir := 1.0, cl := false, sp := false) -> void:
	var X: Dictionary = fx.rak
	var cap = CapsuleMesh.new()
	cap.radius = 0.06 * float(X.size)
	cap.height = 0.5 * float(X.size)
	var mi = _glow_node(cap, _hs(Color(1.0, 0.6, 0.2), float(X.hue)), 8.0)
	var lt = OmniLight3D.new()
	lt.light_color = _hs(Color(1.0, 0.55, 0.2), float(X.hue))
	lt.omni_range = 4.0 * sqrt(float(X.size))
	lt.light_energy = 3.0 * float(X.light)
	mi.add_child(lt)
	var tg = null
	if homing and from.idx == 0 and dir > 0.0 and lk_k >= 1.0 and lk_tg != null and not lk_tg.out:
		tg = lk_tg   # eingerastetes Ziel
	elif homing:
		var bd = 220.0
		for o in ships:
			if o.idx != from.idx and not o.out and (o.z - from.z) * dir > 0.0 and (o.z - from.z) * dir < bd:
				bd = (o.z - from.z) * dir
				tg = o
	shots.append({"z": from.z + 1.0 * dir, "lat": from.lat, "t": 0.0, "pl": at_player, "hm": homing, "tg": tg, "dl": tan(from.psi) * dir if not at_player else 0.0, "n": mi, "own": from.idx, "dir": dir, "cl": cl, "sup": sp or cl})
	if cl or sp:
		# Superwaffe: gold, größer, heller
		(mi.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.78, 0.2)
		(mi.material_override as StandardMaterial3D).emission = Color(1.0, 0.78, 0.2)
		(mi.material_override as StandardMaterial3D).emission_energy_multiplier = 16.0
		cap.radius *= 1.6
		cap.height *= 1.6
		lt.light_color = Color(1.0, 0.75, 0.25)
		lt.light_energy *= 2.5
	_snd("rak", -2.0, 1.0, (from.node as Node3D).global_position if from.idx != 0 else null)


# Rakete geht hoch: normal ein schwarzes Loch, Super-Rakete (Streubombe) zerplatzt in fünf kleine über die ganze Breite
func _shot_boom(sh: Dictionary, z: float, lat: float, hit: int) -> void:
	if not sh.get("cl", false):
		_gbomb(z, lat, sh.own, hit, 1.0, sh.get("sup", false))
		return
	for i in range(5):
		var la = lerpf(-T.TW * 0.8, T.TW * 0.8, i / 4.0)
		var zz = z + 1.0 + randf() * 2.5
		get_tree().create_timer(0.05 * i + 0.01).timeout.connect(func(): _gbomb(zz, la, sh.own, -1, 0.5, true))
	_snd("boom", 0.0, 1.3)


# Minen fallen nacheinander hinten aus dem Schiff: „dupp, dupp, dupp“; Super-Minen: Teppich über die ganze Breite
var mine_grp = 0


func _drop_mines(o: Dictionary, sup := false) -> void:
	mine_grp += 1   # ein Teppich = eine Gruppe: wer hineinfliegt, bekommt nur einmal Schaden
	var gid = mine_grp
	if sup:
		for k in range(9):
			var la = lerpf(-T.TW + 0.35, T.TW - 0.35, k / 8.0)
			get_tree().create_timer(k * 0.05).timeout.connect(func(): _drop_one(o, k, la, 0.6 * (k % 2), gid))
		return
	for k in range(3):
		get_tree().create_timer(k * 0.14).timeout.connect(func(): _drop_one(o, k, 999.0, 0.0, gid))


func _drop_one(o: Dictionary, k: int, lat_o := 999.0, back := 0.0, gid := 0) -> void:
	if o.out or not (state == "race" or state == "done" or state == "lab"):
		return
	var X: Dictionary = fx.mine
	var mi = _glow_node(_lowsphere(0.12 * float(X.size), 12, 6), _hs(Color(1, 0.15, 0.1), float(X.hue)), 6.0 * float(X.glow))
	var z = o.z - 0.9 - back
	var lat = o.lat + (k - 1) * 0.22 if lat_o > 99.0 else lat_o
	mi.position = T.world(z, lat, 0.45)
	mines.append({"z": z, "lat": lat, "t": 0.0, "n": mi, "own": o.idx, "sup": lat_o < 99.0, "g": gid})
	_snd("minedrop", -1.0 if o.idx == 0 else 2.0, randf_range(0.92, 1.08), (o.node as Node3D).global_position if o.idx != 0 else null)


# Gegner sammeln an den Waffenfeldern auch etwas ein und setzen es klug ein
func _ai_weapons(o: Dictionary, dt: float, racing: bool) -> void:
	o.shield = maxf(0.0, o.shield - dt)
	if not racing or o.out:
		return
	if o.turbo > 0.0:
		o.turbo -= dt
		o.boost = maxf(o.boost, 1.5)
	var wk = int(round((o.z - 17.0) / 35.0))
	var wz = (o.z - _wzp(wk)) / 35.0
	if wz < 0.0 or not _pad_ok(_wzp(wk)):
		wz = 9.0
	var wwin = maxf(2.8, o.spd * dt * 1.3) / 35.0
	if posmod(wk, 2) == 0 and wz < wwin and wk != o.wpK and o.wpn != "" and not o.get("sup", false):
		o.wpK = wk
		if randf() < 0.4:   # Gegner: Superwaffe nur mit etwas Glück
			o.sup = true
	if posmod(wk, 2) == 0 and wz < wwin and wk != o.wpK and o.wpn == "":
		o.wpK = wk
		if randf() < 0.65:
			var r = randf()
			for w in WP_AI:
				r -= w[1]
				if r <= 0.0:
					o.wpn = w[0]
					o.wpc = 1
					break
			o.wT = randf_range(0.6, 2.5)
	if o.wpn == "":
		return
	o.wT -= dt
	if o.wT > 0.0:
		return
	var sup: bool = o.get("sup", false)
	match o.wpn:
		"schild":
			o.shield = 6.0
			o.shh = 0
			if sup:
				o.en = minf(1.0, o.en + 0.5)
			o.wpn = ""
		"turbo":
			o.turbo = 3.0 if sup else 2.2
			o.boost = 2.6 if sup else 2.0
			if sup:
				_backwave(o)
			o.wpn = ""
		"mine":
			for x in ships:
				if x.idx != o.idx and not x.out and o.z - x.z > 2.0 and o.z - x.z < 14.0:
					_drop_mines(o, sup)
					o.wpn = ""
					break
		_:
			for x in ships:
				if x.idx != o.idx and not x.out and x.z - o.z > 3.0 and x.z - o.z < 30.0:
					_add_shot(o, false, o.wpn == "lenk", 1.0, sup and o.wpn == "rak", sup)
					if sup and o.wpn == "lenk":
						_add_shot(o, false, true, -1.0, false, true)
					o.wpn = ""
					break
	if o.wpn == "":
		o.sup = false


# Orbs: zwei Kugeln kreisen um dich, schützen dich und rammen Gegner
var orb_n = []


var orb_key = Vector4(-1, -1, -1, -1)


func _orbs_update(dt: float, live: bool) -> void:
	var g: Dictionary = ships[0]
	if live:
		g.orbs = maxf(0.0, g.orbs - dt)
	var on = g.orbs > 0.0 and not g.out and (g.orbs > 1.2 or fmod(g.orbs, 0.25) < 0.15)
	if orb_n.is_empty():
		if not on:
			return
		_fx_res()
		orb_key = Vector4(-1, -1, -1, -1)   # neue Materialien: Farben sicher setzen
		for j in range(6):
			var sp = _lowsphere(0.11, 16, 8)
			var c = Color(1.0, 0.5, 0.12) if _noir() else Color(0.35, 0.85, 1.0)
			var mi = _glow_node(sp, Color(c.r * 4.0, c.g * 4.0, c.b * 4.0), 3.0)
			var l = OmniLight3D.new()
			l.light_color = c
			l.omni_range = 3.0
			l.light_energy = 1.5
			mi.add_child(l)
			mi.set_meta("l", l)
			# Schweif: kleiner werdende Kugeln auf der Bahn dahinter
			var tr = []
			for k in range(6):
				var sp2 = _lowsphere(0.09 * (1.0 - k * 0.14), 12, 6)
				var tn = _glow_node(sp2, Color(c.r * 1.5, c.g * 1.5, c.b * 1.5), 2.5, 0.45 * (1.0 - k * 0.15))
				(tn.material_override as StandardMaterial3D).blend_mode = BaseMaterial3D.BLEND_MODE_ADD
				tn.set_meta("keep", true)
				tr.append(tn)
			mi.set_meta("tr", tr)
			mi.set_meta("keep", true)
			orb_n.append(mi)
	if not on and not (orb_n[0] as Node3D).visible:
		return   # aus und schon versteckt: nichts zu tun
	var nd: Node3D = g.node
	var tt = Time.get_ticks_msec() / 1000.0
	var bb: AABB = nd.get_meta("bb")
	var ctr: Vector3 = nd.global_transform * (bb.get_center() + Vector3(0, 0.05, 0))
	var bx = nd.global_transform.basis
	var X: Dictionary = fx.orbs
	if g.orbs <= 0.0:
		g.sorb = false
		g.morb = false
	var so: bool = g.get("sorb", false)
	var no = 6 if g.get("morb", false) else (4 if so else 2)
	var oc = _hs(Color(1.0, 0.5, 0.12) if _noir() else Color(0.35, 0.85, 1.0), float(X.hue))
	if so:
		oc = _hs(Color(1.0, 0.72, 0.18), float(X.shue))
	var orad = float(X.radius)
	var osz = float(X.size)
	var ogl = float(X.glow) * (float(X.sglow) if so else 1.0)
	var otr = float(X.trail)
	# Farben/Leuchtkraft nur neu setzen, wenn sich ein Regler oder die Art der Kugeln ändert
	var okey = Vector4(oc.r, oc.g, oc.b, ogl)
	var orecol = okey != orb_key
	orb_key = okey
	for j in range(orb_n.size()):
		var mi: MeshInstance3D = orb_n[j]
		var jon = on and j < no
		mi.visible = jon
		var a = tt * 5.5 * float(X.speed) + j * TAU / no
		var opos = func(aa: float) -> Vector3:
			return ctr + (bx.x.normalized() * cos(aa) * 1.0 * orad + bx.z.normalized() * sin(aa) * 1.15 * orad) + bx.y.normalized() * (0.08 * sin(aa * 2.0))
		mi.global_position = opos.call(a)
		if jon:
			# Regler wirken sofort
			mi.scale = Vector3.ONE * osz
		if jon and orecol:
			var om: StandardMaterial3D = mi.material_override
			om.albedo_color = Color(oc.r * 4.0, oc.g * 4.0, oc.b * 4.0)
			om.emission = om.albedo_color
			om.emission_energy_multiplier = 3.0 * ogl
			var ol: OmniLight3D = mi.get_meta("l")
			ol.light_color = oc
			ol.light_energy = 1.5 * ogl
		var tr: Array = mi.get_meta("tr")
		for k in range(tr.size()):
			tr[k].visible = jon and otr > 0.01
			tr[k].global_position = opos.call(a - (k + 1) * 0.075 * otr)
			if jon:
				tr[k].scale = Vector3.ONE * osz
			if jon and orecol:
				var tm: StandardMaterial3D = tr[k].material_override
				tm.albedo_color = Color(oc.r * 1.5, oc.g * 1.5, oc.b * 1.5, tm.albedo_color.a)
				tm.emission = Color(oc.r * 1.5, oc.g * 1.5, oc.b * 1.5)
				tm.emission_energy_multiplier = 2.5 * ogl
		if not jon or not live or state != "race":
			continue
		for o in ships:
			if o.idx == 0 or o.out:
				continue
			var op: Vector3 = (o.node as Node3D).global_position + Vector3(0, 0.15, 0)
			if mi.global_position.distance_to(op) < 0.75 and race_t - o.get("orbT", -9.0) > 0.8:
				o.orbT = race_t
				var away = signf(o.lat - g.lat) if o.lat != g.lat else 1.0
				if not _prot(o):
					o.slow = minf(o.slow, 0.55)
					o.lat += away * 0.35
					o.vpsi += away * 0.15
				_dmg(o, 0.3 if so else 0.15, 0, "orbs", so)
				_burst(mi.global_position, fxr.spark, 50, 0.6, 5.0, 11.0, 180.0, Vector3(0, -6, 0), 0.6, 0.6, 1.2,
					_ramp([[0.0, Color(6, 6, 8, 1)], [1.0, Color(1, 0.5, 0.2, 0)]]), null, true, false, 0.1)
				_snd("zap", 2.0, 1.4, op)
				shake = maxf(shake, 0.4)


func _fire() -> void:
	var g: Dictionary = ships[0]
	var w: String = g.wpn
	# Super: dieselbe Waffe doppelt eingesammelt – oder Orbs, während die Orbs noch laufen
	var sup: bool = g.get("sup", false) or (w == "orbs" and g.orbs > 0.0 and state == "race")
	g.wpn = ""
	g.sup = false
	if g.get("mega", false):
		g.mega = false
		_fire_mega(g, w)
		return
	_fire_w(g, w, sup)


func _fire_w(g: Dictionary, w: String, sup: bool) -> void:
	match w:
		"rak":
			_add_shot(g, false, false, 1.0, sup)
		"lenk":
			_add_shot(g, false, true, 1.0, false, sup)
			if sup:
				_add_shot(g, false, true, -1.0, false, true)   # zweite Lenkrakete nach hinten zum Verfolger
		"mine":
			_drop_mines(g, sup)
		"orbs":
			g.orbs = 10.0
			g.sorb = sup
			_snd("shield", 0.0, 1.0 if sup else 1.3)
		"schild":
			g.shield = 6.0
			g.shh = 0
			_snd("shield")
			if sup:
				g.en = minf(1.0, g.en + 0.5)
				if g.idx == 0:
					_msg("+50 % ENERGY", Color(0.4, 1.0, 0.55))
		"turbo":
			g.turbo = 3.0 if sup else 2.2
			g.boost = 2.6 if sup else 2.0
			_snd("boost")
			if sup:
				_backwave(g)
		"beben":
			quake = _quake_make(g.z + 3.0, 1.0, quake)
			quake.sup = sup
			if sup:
				quake2 = _quake_make(g.z - 3.0, -1.0, quake2)
				quake2.sup = true
			_snd("boom", 3.0, 0.6)
			_snd("boom", 0.0, 0.8)
			shake = maxf(shake, 1.5 * float(fx.quake.shake))
			_flash(_hs(Color(1.0, 0.5, 0.15), float(fx.quake.hue)), 0.45 * minf(1.0, float(fx.quake.glow)))
		"wand":
			var mi = _wall_node(sup)
			var z = g.z + 20.0
			_wall_pose(mi, z, 0.0, 0.0)
			walls.append({"z": z, "age": 0.0, "hit": [], "n": mi, "hf": 0.0, "sup": sup, "own": g.idx})
			_snd("wallon")
		"auto":
			g.auto = 5.0
			g.ahold = false
			g.sauto = sup
			_snd("shield")


# MEGA: jede Waffe hat ihre eigene, große Wirkung – stark, aber kein Sofortsieg (höchstens ~40 % Schaden je Gegner)
func _fire_mega(g: Dictionary, w: String) -> void:
	_flash(Color(1.0, 0.45, 0.95), 0.3)
	shake = maxf(shake, 0.8)
	match w:
		"rak":
			# drei Raketen im Fächer
			var grp = {}
			for d in [-0.16, 0.0, 0.16]:
				_add_shot(g, false, false, 1.0)
				shots[shots.size() - 1].dl = tan(g.psi) + d
				shots[shots.size() - 1].grp = grp   # jeder Gegner wird von der Salve nur einmal getroffen
				shots[shots.size() - 1].mega = true
		"lenk":
			# eine Lenkrakete für jeden Gegner vor dir (bis zu drei)
			var n = 0
			var grp = {}
			for o in ships:
				if o.idx != g.idx and not o.out and o.z > g.z and o.z - g.z < 220.0 and n < 3:
					_add_shot(g, false, true, 1.0)
					shots[shots.size() - 1].tg = o
					shots[shots.size() - 1].grp = grp
					shots[shots.size() - 1].only = true   # trifft nur sein eigenes Ziel
					shots[shots.size() - 1].mega = true
					n += 1
			if n == 0:
				_add_shot(g, false, true, 1.0)
		"mine":
			# zwei Minenteppiche hintereinander über die ganze Breite
			_drop_mines(g, true)
			get_tree().create_timer(0.35).timeout.connect(func(): _drop_mines(g, true))
		"schild":
			# 10 s unzerstörbarer Schild und 30 % Energie
			g.shield = 10.0
			g.shh = 0
			g.mshield = 10.0
			g.en = minf(1.0, g.en + 0.3)
			_snd("shield", 2.0, 0.8)
			if g.idx == 0:
				_msg("+30 % ENERGY", Color(0.4, 1.0, 0.55))
		"turbo":
			# langer Turbo, dabei geschützt, zwei Druckwellen nach hinten
			g.turbo = 4.5
			g.boost = 3.0
			g.shield = maxf(g.shield, 4.5)
			g.mshield = 4.5
			_backwave(g)
			get_tree().create_timer(0.8).timeout.connect(func(): _backwave(g))
			_snd("boost", 2.0, 0.85)
		"beben":
			# Super-Quake in beide Richtungen, dazu eine zweite Welle nach vorn
			_fire_w(g, "beben", true)
			get_tree().create_timer(0.8).timeout.connect(func():
				if state == "race":
					quake = _quake_make(g.z + 3.0, 1.0, quake)
					quake.sup = true
					_snd("boom", 3.0, 0.55))
		"auto":
			# 8 s Autopilot, dabei geschützt
			g.auto = 8.0
			g.ahold = false
			g.sauto = true
			g.shield = maxf(g.shield, 8.0)
			g.mshield = 8.0
			_snd("shield")
		"wand":
			# zwei Barrieren hintereinander: bremsen deutlich, je 20 % Schaden (zusammen 40 %)
			for dz in [20.0, 30.0]:
				var mi = _wall_node(true)
				var z = g.z + dz
				_wall_pose(mi, z, 0.0, 0.0)
				walls.append({"z": z, "age": 0.0, "hit": [], "n": mi, "hf": 0.0, "sup": true, "mega": true, "own": g.idx})
			_snd("wallon", 2.0, 0.8)
		"orbs":
			# sechs Kugeln, länger
			g.orbs = 14.0
			g.sorb = true
			g.morb = true
			_snd("shield", 0.0, 0.85)
		_:
			_fire_w(g, w, true)


# Bebenwelle bauen: dir 1 = nach vorn, -1 = nach hinten (Super-Quake)
func _quake_make(z: float, dir: float, old) -> Dictionary:
	_fx_res()
	if old != null:
		old.n.queue_free()
	var crest = Node3D.new()
	add_child(crest)
	# Funken und Brocken spritzen vom Kamm, so lange die Welle rollt
	for kind in [0, 1]:
		var p = GPUParticles3D.new()
		var m = ParticleProcessMaterial.new()
		m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		m.emission_box_extents = Vector3(T.TW, 0.1, 0.4)
		m.direction = Vector3(0, 1, -0.4)
		m.spread = 35.0
		m.initial_velocity_min = 4.0 if kind == 0 else 3.0
		m.initial_velocity_max = 10.0 if kind == 0 else 7.0
		m.gravity = Vector3(0, -14, 0)
		if kind == 0:
			m.particle_flag_align_y = true
			m.color_ramp = _ramp(_rh([[0.0, Color(9, 5, 2, 1)], [1.0, Color(2, 0.4, 0.05, 0)]], float(fx.quake.hue)))
		else:
			m.angular_velocity_min = -600.0
			m.angular_velocity_max = 600.0
			m.particle_flag_rotate_y = true
			m.scale_min = 0.7
			m.scale_max = 2.2
			m.color_ramp = _deb_ramp(float(fx.boom.dglow), float(fx.quake.hue))
		p.process_material = m
		p.draw_pass_1 = fxr.spark if kind == 0 else fxr.debris
		p.amount = maxi(1, int((160 if kind == 0 else 60) * float(fx.quake.sparks)))
		p.visible = float(fx.quake.sparks) > 0.01
		p.lifetime = 0.9
		p.local_coords = false
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.visibility_aabb = AABB(Vector3(-20, -10, -20), Vector3(40, 30, 40))
		crest.add_child(p)
	var lt = OmniLight3D.new()
	lt.light_color = _hs(Color(1.0, 0.45, 0.12), float(fx.quake.hue))
	lt.omni_range = 10.0
	lt.light_energy = 8.0
	lt.position = Vector3(0, 1.0, 0)
	crest.add_child(lt)
	_rset("qc", _v3(_hs(Color(1.0, 0.42, 0.08), float(fx.quake.hue))))
	_rset("qg", float(fx.quake.glow))
	return {"z": z, "age": 0.0, "hit": [], "n": crest, "l": lt, "dir": dir}


# eine Bebenwelle weiterrollen lassen; null, wenn sie ausgelaufen ist
func _quake_step(q, dt: float) -> Variant:
	var g: Dictionary = ships[0]
	var QX: Dictionary = fx.quake
	var dir: float = q.get("dir", 1.0)
	var qd = float(QX.dur)
	var qmax = (60.0 if state == "lab" else 560.0) * qd * (0.35 if dir < 0.0 else 1.0)
	q.z += base_spd * 3.2 * float(QX.speed) * dt * dir
	q.age += dt
	for o in ships:
		if o.idx != 0 and not o.out and not q.hit.has(o.idx) and absf(o.z - q.z) < 2.6:
			q.hit.append(o.idx)
			_dmg(o, 0.2, 0, "quake", q.get("sup", false))
			if not o.out and not _prot(o):   # mit Schild: wird nicht hochgeworfen
				o.air = true
				o.vy = 5.8 * sqrt(float(QX.height))
				o.h = maxf(o.h, 0.6)
				o.slow = minf(o.slow, 0.25)
	var f = T.frame(q.z)
	var dist = (q.z - g.z) * dir
	var qs = 1.3 * float(QX.height) * clampf(q.age / 0.25, 0.0, 1.0) * clampf((16.0 * qd - q.age) / 1.5, 0.0, 1.0) * clampf((qmax - dist) / (12.0 if state == "lab" else 40.0), 0.0, 1.0)
	q.n.global_transform = Transform3D(Basis(f.rr * dir, f.uu, f.fw * dir), f.c + f.uu * (qs * 1.6))
	q.l.light_energy = 8.0 * qs * float(QX.glow)
	q.qs = qs
	var sfx = "" if dir > 0.0 else "2"
	_rset("qz" + sfx, q.z)
	_rset("qs" + sfx, qs)
	shake = maxf(shake, 0.35 * clampf(1.0 - absf(q.z - g.z) / 40.0, 0.0, 1.0) * float(QX.shake))
	if dist > qmax or q.age > 16.0 * qd:
		q.n.queue_free()
		_rset("qs" + sfx, 0.0)
		return null
	return q


# Super-Turbo: Druckwelle rollt nach hinten und bremst alle Verfolger aus
func _backwave(o: Dictionary) -> void:
	var mi = _wall_node()
	var m: ShaderMaterial = mi.material_override
	m.set_shader_parameter("wc", Vector3(0.25, 0.75, 1.0))
	(mi.get_meta("l") as OmniLight3D).light_color = Color(0.4, 0.8, 1.0)
	bwaves.append({"z": o.z - 1.5, "age": 0.0, "hit": [], "n": mi, "own": o.idx})
	_snd("wallon", 0.0, 1.4)
	if o.idx == 0:
		shake = maxf(shake, 0.6)


func _bwaves_clear() -> void:
	for w in bwaves:
		if is_instance_valid(w.n):
			w.n.queue_free()
	bwaves.clear()
	for w in megaw:
		if is_instance_valid(w.n):
			w.n.queue_free()
	megaw.clear()


# MEGA: zwei leuchtende Schockwellen rasen von dir aus nach vorn und hinten über die ganze Strecke;
# jeder Gegner, den sie erreichen (spätestens am Ende: alle), verliert 75 % Energie – Schild hilft nicht
var megaw = []
const MEGA_V = 260.0


func _mega(g: Dictionary) -> void:
	var hit = {"ids": []}
	for dir in [1.0, -1.0]:
		var mi = _wall_node(true)
		var m: ShaderMaterial = mi.material_override
		m.set_shader_parameter("wc", Vector3(1.0, 0.35, 0.9))
		m.set_shader_parameter("gk", 2.5)
		(mi.get_meta("l") as OmniLight3D).light_color = Color(1.0, 0.4, 0.9)
		(mi.get_meta("l") as OmniLight3D).omni_range = 14.0
		megaw.append({"z": g.z + dir * 2.0, "dir": dir, "age": 0.0, "n": mi, "own": g.idx, "hit": hit})
	_snd("boom", 4.0, 0.45)
	_snd("wallon", 2.0, 0.7)
	_snd("zap", 0.0, 0.6)
	_flash(Color(1.0, 0.45, 0.95), 0.3)
	shake = maxf(shake, 1.4)


func _mega_hit(o: Dictionary, own: int) -> void:
	if o.out or o.idx == own:
		return
	if o.shield > 0.0:
		_shield_break(o)
	_dmg(o, 0.75, own, "mega")
	_zap_ship(o)
	if o.idx != 0:
		_snd("zap", 3.0, 0.8, (o.node as Node3D).global_position)


func _megaw_update(dt: float) -> void:
	for i in range(megaw.size() - 1, -1, -1):
		var w = megaw[i]
		w.age += dt
		var z0: float = w.z
		# erst sichtbar langsam, dann immer schneller über die halbe Runde
		var st = (40.0 + MEGA_V * 2.0 * float(w.age)) * dt
		w.d = float(w.get("d", 0.0)) + st
		w.z += float(w.dir) * st
		var done = float(w.d) > T.LAP * 0.5
		var lo = minf(z0, w.z) - 1.0
		var hi = maxf(z0, w.z) + 1.0
		for o in ships:
			if w.hit.ids.has(o.idx):
				continue
			# Strecke ist ein Rundkurs: Gegner auf der Nachbarrunde ebenfalls finden
			for k in [-1.0, 0.0, 1.0]:
				var oz: float = o.z + k * T.LAP
				if oz >= lo and oz <= hi:
					w.hit.ids.append(o.idx)
					_mega_hit(o, int(w.own))
					break
		var mi: MeshInstance3D = w.n
		var f = T.frame(w.z)
		mi.global_transform = Transform3D(Basis(f.rr, f.uu, f.fw).scaled(Vector3(1.15, 2.2, 1.0)), f.c + f.uu * 1.4)
		var a = clampf(minf(w.age / 0.08, (T.LAP * 0.5 - float(w.d)) / 60.0), 0.0, 1.0)
		(mi.material_override as ShaderMaterial).set_shader_parameter("a", a)
		(mi.material_override as ShaderMaterial).set_shader_parameter("hit", 0.6 + 0.4 * sin(w.age * 40.0))
		(mi.get_meta("l") as OmniLight3D).light_energy = 8.0 * a
		if done:
			if w.dir > 0.0:
				for o in ships:   # wer nicht erreicht wurde, bekommt es jetzt ab
					if not w.hit.ids.has(o.idx):
						w.hit.ids.append(o.idx)
						_mega_hit(o, int(w.own))
			mi.queue_free()
			megaw.remove_at(i)


func _bwaves_update(dt: float) -> void:
	for i in range(bwaves.size() - 1, -1, -1):
		var w = bwaves[i]
		w.age += dt
		var step = base_spd * 2.6 * dt
		w.z -= step
		for o in ships:
			if o.idx != w.own and not o.out and not w.hit.has(o.idx) and o.z <= w.z + 0.6 and o.z >= w.z - step - o.spd * dt - 0.6:
				w.hit.append(o.idx)
				if not _prot(o):
					o.slow = minf(o.slow, 0.4)
					o.slowT = 1.6
				_dmg(o, 0.06, w.own, "wave", true)
				_zap_ship(o)
		var mi: MeshInstance3D = w.n
		var f = T.frame(w.z)
		mi.global_transform = Transform3D(Basis(f.rr, f.uu, f.fw), f.c + f.uu * 0.72)
		var a = clampf(minf(w.age / 0.12, (1.8 - w.age) / 0.5), 0.0, 1.0)
		(mi.material_override as ShaderMaterial).set_shader_parameter("a", a)
		(mi.get_meta("l") as OmniLight3D).light_energy = 3.0 * a
		if w.age > 1.8:
			mi.queue_free()
			bwaves.remove_at(i)


# ================================================================ Hinweise für Neulinge (jeder nur einmal)
var tipq = []
var tip_t = 0.0
var tip_box: PanelContainer
var tip_lbl: Label
var tip_w = {}


func _tip(id: String, text: String) -> void:
	if int(cfg.get("tips", 1)) != 1 or state != "race" or not rpf.is_empty() or free_ride:
		return
	var seen: PackedStringArray = str(cfg.get("tseen", "")).split(",", false)
	if seen.has(id):
		return
	for q in tipq:
		if q[0] == id:
			return
	tipq.append([id, text])


# Titel und Symbol je Hinweis
const TIPH = {"steer": ["STEERING", "steer"], "boost": ["BOOST PAD", "boost"], "wpad": ["WEAPON PAD", "wpad"], "energy": ["ENERGY", "energy"],
	"lap": ["LAP 2", "goal"], "mines": ["MINES", "mine"], "sup1": ["SUPER  2 / 3", "super"], "sup2": ["SUPER WEAPON", "super"], "mega": ["MEGA WEAPON", "mega"]}
var tip_tt: Label
var tip_ic: Control
var tip_key = ""


func _tips_check(g: Dictionary, racing: bool, dt: float) -> void:
	if tip_box == null:
		# Neon-Kachel: dunkles Glas, leuchtender Rand mit Schein, Symbol links, Titel und Text rechts
		tip_box = PanelContainer.new()
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(0.01, 0.02, 0.06, 0.8)
		sb.border_color = Color(CY.r, CY.g, CY.b, 0.95)
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(26)
		sb.shadow_color = Color(CY.r, CY.g, CY.b, 0.4)
		sb.shadow_size = 22
		sb.content_margin_left = 22
		sb.content_margin_right = 28
		sb.content_margin_top = 18
		sb.content_margin_bottom = 18
		tip_box.add_theme_stylebox_override("panel", sb)
		tip_box.anchor_left = 0.06
		tip_box.anchor_right = 0.94
		tip_box.anchor_top = 0.19
		tip_box.anchor_bottom = 0.19
		tip_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var hb = HBoxContainer.new()
		hb.add_theme_constant_override("separation", 22)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tip_box.add_child(hb)
		tip_ic = Control.new()
		tip_ic.custom_minimum_size = Vector2(84, 84)
		tip_ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tip_ic.draw.connect(func():
			var cc = tip_ic.size * 0.5
			var pu = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 4.0)
			tip_ic.draw_circle(cc, 42.0, Color(CY.r, CY.g, CY.b, 0.1 + 0.06 * pu))
			tip_ic.draw_arc(cc, 41.0, 0.0, TAU, 40, Color(CY.r, CY.g, CY.b, 0.6), 2.0, true)
			_wicon(tip_ic, cc, 26.0, tip_key, Color(1, 1, 1, 0.95)))
		hb.add_child(tip_ic)
		var vb = VBoxContainer.new()
		vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vb.add_theme_constant_override("separation", 2)
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(vb)
		tip_tt = Label.new()
		tip_tt.add_theme_font_size_override("font_size", 30)
		tip_tt.add_theme_color_override("font_color", CY.lightened(0.35))
		tip_tt.add_theme_color_override("font_outline_color", Color(CY.r, CY.g, CY.b, 0.35))
		tip_tt.add_theme_constant_override("outline_size", 6)
		vb.add_child(tip_tt)
		tip_lbl = Label.new()
		tip_lbl.add_theme_font_size_override("font_size", 28)
		tip_lbl.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
		tip_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(tip_lbl)
		tip_box.visible = false
		(hud.fire as Control).get_parent().add_child(tip_box)
	if racing:
		if t_state > 0.9:
			_tip("steer", _steer_help())
		# Boost- und Waffenfeld voraus?
		var k0 = int(round(g.z / 35.0))
		for k in [k0, k0 + 1]:
			var bz = _bzp(k)
			if _pad_ok(bz) and bz - g.z > 4.0 and bz - g.z < 32.0 and t_state > 3.0:
				_tip("boost", "Ahead! Fly over the arrows for a burst of speed.")
		var w0 = int(round((g.z - 17.0) / 35.0))
		for k in [w0, w0 + 1, w0 + 2]:
			var wz = _wzp(k)
			if posmod(k, 2) == 0 and _pad_ok(wz) and wz - g.z > 4.0 and wz - g.z < 32.0 and t_state > 6.0:
				_tip("wpad", "Ahead! Fly through the ring to pick up a weapon.")
		if WN.has(g.wpn) and not tip_w.has(g.wpn):
			tip_w[g.wpn] = true
			_tip("w_" + g.wpn, "%s Tap the FIRE button to use it." % WD.get(g.wpn, ""))
		if g.en < 0.6:
			_tip("energy", "Hits cost energy – at 0 % you are out! Hitting rivals refills yours, every new lap adds 25 %.")
		if int(floor((g.z - T.ZST) / T.LAP)) >= 1:
			_tip("lap", "3 laps in total – finish first or be the last one still flying.")
		if hud.get("mlamp") != null and (hud.mlamp as Control).visible:
			_tip("mines", "Ahead on the track – steer around them!")
	# anzeigen: einer nach dem anderen, je ~4 s
	if tip_t > 0.0:
		tip_t -= dt
		var ain = clampf((4.8 - tip_t) / 0.35, 0.0, 1.0)
		var aout = clampf(tip_t / 0.45, 0.0, 1.0)
		var ee = 1.0 - pow(1.0 - ain, 3.0)
		tip_box.modulate.a = minf(ee, aout)
		tip_box.offset_top = -30.0 * (1.0 - ee) - 12.0 * (1.0 - aout)
		tip_box.offset_bottom = tip_box.offset_top
		tip_ic.queue_redraw()
		if tip_t <= 0.0:
			tip_box.visible = false
	elif not tipq.is_empty() and state == "race":
		var q = tipq.pop_front()
		var id: String = q[0]
		var hd = TIPH.get(id, ["", ""])
		if id.begins_with("w_"):
			hd = [WN.get(id.substr(2), ""), id.substr(2)]
		tip_tt.text = hd[0]
		tip_key = hd[1]
		tip_lbl.text = q[1]
		tip_box.visible = true
		tip_t = 4.8
		var seen = str(cfg.get("tseen", ""))
		cfg.tseen = (seen + "," if seen != "" else "") + q[0]
		_save_cfg()
	if state != "race" and tip_box.visible:
		tip_box.visible = false
		tip_t = 0.0


# Waffensymbole (einfache Neon-Striche), s = halbe Größe
func _wicon(c: CanvasItem, p: Vector2, s: float, w: String, col: Color) -> void:
	var lw = maxf(2.0, s * 0.13)
	match w:
		"rak":
			c.draw_polyline(PackedVector2Array([p + Vector2(0, -s), p + Vector2(s * 0.35, -s * 0.4), p + Vector2(s * 0.35, s * 0.6), p + Vector2(-s * 0.35, s * 0.6), p + Vector2(-s * 0.35, -s * 0.4), p + Vector2(0, -s)]), col, lw, true)
			c.draw_line(p + Vector2(-s * 0.35, s * 0.2), p + Vector2(-s * 0.7, s * 0.8), col, lw, true)
			c.draw_line(p + Vector2(s * 0.35, s * 0.2), p + Vector2(s * 0.7, s * 0.8), col, lw, true)
		"lenk":
			c.draw_arc(p, s * 0.7, 0.0, TAU, 32, col, lw, true)
			for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				c.draw_line(p + d * s * 0.35, p + d * s, col, lw, true)
			c.draw_circle(p, lw * 0.8, col)
		"mine":
			c.draw_arc(p, s * 0.5, 0.0, TAU, 24, col, lw, true)
			for i in range(8):
				var d = Vector2(cos(i * TAU / 8.0), sin(i * TAU / 8.0))
				c.draw_line(p + d * s * 0.5, p + d * s * 0.9, col, lw, true)
		"schild":
			c.draw_polyline(PackedVector2Array([p + Vector2(0, -s), p + Vector2(s * 0.8, -s * 0.6), p + Vector2(s * 0.65, s * 0.3), p + Vector2(0, s), p + Vector2(-s * 0.65, s * 0.3), p + Vector2(-s * 0.8, -s * 0.6), p + Vector2(0, -s)]), col, lw, true)
		"turbo":
			for o in [-0.35, 0.35]:
				c.draw_polyline(PackedVector2Array([p + Vector2(-s * 0.7, s * (o + 0.45)), p + Vector2(0, s * (o - 0.25)), p + Vector2(s * 0.7, s * (o + 0.45))]), col, lw, true)
		"beben":
			var pts = PackedVector2Array()
			for i in range(9):
				pts.append(p + Vector2(-s + i * s * 0.25, (s * 0.45 if i % 2 == 0 else -s * 0.45) * (1.0 - absf(i - 4) / 5.0)))
			c.draw_polyline(pts, col, lw, true)
		"auto":
			c.draw_arc(p, s * 0.8, 0.0, TAU, 32, col, lw, true)
			c.draw_arc(p, s * 0.2, 0.0, TAU, 16, col, lw, true)
			for a in [PI * 0.5, PI * 1.17, PI * 1.83]:
				c.draw_line(p + Vector2(cos(a), sin(a)) * s * 0.2, p + Vector2(cos(a), sin(a)) * s * 0.8, col, lw, true)
		"wand":
			for i in range(4):
				var x = -s * 0.75 + i * s * 0.5
				c.draw_line(p + Vector2(x, -s * 0.8), p + Vector2(x, s * 0.8), col, lw, true)
			c.draw_line(p + Vector2(-s * 0.9, -s * 0.8), p + Vector2(s * 0.9, -s * 0.8), col, lw, true)
		"orbs":
			c.draw_arc(p, s * 0.7, 0.0, TAU, 32, Color(col.r, col.g, col.b, col.a * 0.5), lw * 0.7, true)
			for i in range(3):
				var a = i * TAU / 3.0 - PI * 0.5
				c.draw_circle(p + Vector2(cos(a), sin(a)) * s * 0.7, s * 0.2, col)
		"boost":
			for o in [-0.3, 0.3]:
				c.draw_polyline(PackedVector2Array([p + Vector2(-s * 0.7, s * (o + 0.35)), p + Vector2(0, s * (o - 0.35)), p + Vector2(s * 0.7, s * (o + 0.35))]), Color(1.0, 0.85, 0.2), lw * 1.3, true)
			c.draw_rect(Rect2(p - Vector2(s * 0.9, s), Vector2(s * 1.8, s * 2.0)), Color(0.2, 0.7, 1.0), false, lw)
		"wpad":
			c.draw_arc(p, s * 0.9, 0.0, TAU, 32, Color(1.0, 0.4, 0.9), lw, true)
			c.draw_polyline(PackedVector2Array([p + Vector2(0, -s * 0.45), p + Vector2(s * 0.4, 0), p + Vector2(0, s * 0.45), p + Vector2(-s * 0.4, 0), p + Vector2(0, -s * 0.45)]), Color(0.4, 0.9, 1.0), lw, true)
		"fire":
			c.draw_arc(p, s * 0.9, 0.0, TAU, 32, Color(1.0, 0.55, 0.15), lw * 1.2, true)
			c.draw_arc(p, s * 0.7, 0.4, 1.6, 12, Color(1.0, 0.55, 0.15), lw, true)
		"steer":
			c.draw_polyline(PackedVector2Array([p + Vector2(-s * 0.2, -s * 0.5), p + Vector2(-s * 0.8, 0), p + Vector2(-s * 0.2, s * 0.5)]), col, lw, true)
			c.draw_polyline(PackedVector2Array([p + Vector2(s * 0.2, -s * 0.5), p + Vector2(s * 0.8, 0), p + Vector2(s * 0.2, s * 0.5)]), col, lw, true)
		"goal":
			for i in range(4):
				for j in range(3):
					if (i + j) % 2 == 0:
						c.draw_rect(Rect2(p + Vector2(-s * 0.8 + i * s * 0.4, -s * 0.6 + j * s * 0.4), Vector2(s * 0.4, s * 0.4)), col)
			c.draw_rect(Rect2(p + Vector2(-s * 0.8, -s * 0.6), Vector2(s * 1.6, s * 1.2)), col, false, lw * 0.6)
		"super":
			for i in range(3):
				c.draw_circle(p + Vector2(-s * 0.6 + i * s * 0.6, 0), s * 0.22, Color(1.0, 0.8, 0.25))
		"mega":
			c.draw_arc(p, s * 0.35, 0.0, TAU, 24, Color(1.0, 0.45, 0.95), lw, true)
			c.draw_arc(p, s * 0.65, 0.0, TAU, 32, Color(1.0, 0.45, 0.95, 0.75), lw, true)
			c.draw_arc(p, s * 0.95, 0.0, TAU, 40, Color(1.0, 0.45, 0.95, 0.45), lw, true)
		"energy":
			c.draw_rect(Rect2(p - Vector2(s * 0.9, s * 0.3), Vector2(s * 1.8, s * 0.6)), col, false, lw * 0.7)
			c.draw_rect(Rect2(p - Vector2(s * 0.8, s * 0.2), Vector2(s * 1.1, s * 0.4)), Color(0.36, 1.0, 0.6))


# „How to play“: alles auf einer Seite, mit Symbolen
func _show_help(on: bool) -> void:
	if ui.has("helpp"):
		if is_instance_valid(ui.helpp):
			ui.helpp.queue_free()
		ui.erase("helpp")
	if not on:
		return
	var cl = CanvasLayer.new()
	cl.layer = 12
	add_child(cl)
	ui.helpp = cl
	var bg = ColorRect.new()
	bg.color = Color(0.01, 0.01, 0.04, 0.98)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	cl.add_child(bg)
	var vb = VBoxContainer.new()
	vb.anchor_left = 0.05
	vb.anchor_right = 0.95
	vb.anchor_top = 0.05
	vb.anchor_bottom = 0.95
	vb.add_theme_constant_override("separation", 14)
	cl.add_child(vb)
	vb.add_child(_lbl("HOW TO PLAY", 48))
	var sc = ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)
	var lst = VBoxContainer.new()
	lst.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lst.add_theme_constant_override("separation", 18)
	sc.add_child(lst)
	var rows = [
		["goal", "Goal", "Race 3 laps. Finish first – or be the last one still flying."],
		["steer", "Steering", _steer_help()],
		["boost", "Boost pad", "Arrows on the track. Fly over them for a burst of speed."],
		["wpad", "Weapon pad", "A spinning ring. Fly through it to pick up a random weapon."],
		["fire", "Fire", "Tap the round FIRE button at the bottom to use your weapon."],
		["#", "Weapons", ""]]
	for w in ["rak", "lenk", "mine", "orbs", "wand", "beben", "schild", "turbo", "auto"]:
		rows.append([w, WN[w].capitalize(), WD[w]])
	rows += [["#", "Power-ups", ""],
		["super", "Super", "Keep your weapon and fly over 2 more weapon pads – it turns SUPER: stronger and gold."],
		["mega", "Mega", "One more pad with a Super weapon → MEGA: rockets fly in a fan, homing hits every rival ahead, two mine carpets, two force fields, six orbs, an unbreakable shield …"],
		["energy", "Energy", "Hits cost energy – at 0 % you are out. Damage you deal refills you, every new lap adds 25 %."]]
	for r in rows:
		if r[0] == "#":
			var hd = _lbl(r[1], 34)
			hd.add_theme_color_override("font_color", Color(1.0, 0.75, 0.35))
			lst.add_child(hd)
			continue
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 22)
		var ic = Control.new()
		ic.custom_minimum_size = Vector2(96, 96)
		var key: String = r[0]
		ic.draw.connect(func(): _wicon(ic, ic.size * 0.5, 36.0, key, Color(0.85, 0.95, 1.0)))
		row.add_child(ic)
		var tx = VBoxContainer.new()
		tx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var t1 = _lbl(r[1], 32)
		t1.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		t1.add_theme_color_override("font_color", Color(0.55, 0.9, 1.0))
		tx.add_child(t1)
		var t2 = _lbl(r[2], 27)
		t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		t2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tx.add_child(t2)
		row.add_child(tx)
		lst.add_child(row)
	var bb = _btn("Back", true)
	bb.pressed.connect(func(): _show_help(false))
	vb.add_child(bb)


# Welche Regler in welchem Lenkmodus gebraucht werden (0 Tippen, 1 Wischen, 2 Gleiten, 3 Touchpad, 4 Spuren);
# nicht genannte gelten immer. Die Live-Seite und die Einstellleiste zeigen nur die passenden.
const CTRL_N = ["Tap", "Swipe", "Glide", "Touchpad", "Lanes", "Lane tap"]
const FX_MODES = {
	"steer.ptime": [0], "steer.delay": [0], "steer.rtime": [0, 1],
	"steer.swrange": [1, 2], "steer.velk": [1], "steer.velmin": [1], "steer.revmode": [1], "steer.revbuf": [1], "steer.hold": [1, 2],
	"steer.glide": [2, 3, 4], "steer.gwidth": [2, 3], "steer.gpull": [2, 3],
	"steer.psens": [3, 4], "steer.paccel": [3, 4], "steer.vib": [4, 5], "steer.ltime": [5], "steer.lhold": [5], "steer.lbeep": [4, 5], "steer.dtap": [1, 2, 3, 4],
	"ship.steer": [0, 1], "ship.steerk": [0, 1], "ship.grip": [0, 1], "ship.drift": [0, 1], "ship.center": [0, 1], "ship.spdst": [0, 1]}
const CTRL_CURVES = [["press", "release"], ["swipe", "swvel", "release"], ["swipe"], [], [], []]
# Fahrbahn in drei gleich breite Drittel geteilt (bis knapp an die Leuchtkante); jede Spur liegt mittig in ihrem Drittel
const LANE_W = (2.4 - 0.1) * 2.0 / 3.0   # ≈ 1,53: Abstand der drei Spuren (links −1, Mitte 0, rechts 1)
const PAD_HW = LANE_W * 0.5 - 0.03       # Boost- und Waffenfelder füllen ihr Drittel ganz aus

# Erklärungen zu den Reglern (Tooltip auf der Live-Seite am PC)
const FX_INFO = {
	"boom.size": "Größe der ganzen Explosion. Höher = größerer Feuerball.",
	"boom.fire": "Menge und Helligkeit des Feuers. Höher = mehr Flammen.",
	"boom.after": "Kleine Nach-Explosionen rund um den Knall. Höher = mehr Feuerbälle.",
	"boom.smoke": "Wie viel Rauch aufsteigt. 0 = gar kein Rauch.",
	"boom.slife": "Wie lange der Rauch stehen bleibt. Höher = Rauch hält länger.",
	"boom.sparks": "Anzahl der Funken. Höher = mehr Funkenregen.",
	"boom.debris": "Metallsplitter, die herumfliegen. 0 = keine Splitter.",
	"boom.dglow": "Wie stark die Splitter glühen. Höher = hellere Splitter.",
	"boom.ring": "Leuchtender Druckwellen-Ring am Boden. 0 = kein Ring.",
	"boom.light": "Lichtblitz, der die Umgebung beleuchtet. Höher = heller.",
	"boom.flash": "Weißer Blitz über dem ganzen Bildschirm. 0 = kein Blitz.",
	"boom.shake": "Wie stark die Kamera wackelt. 0 = ruhig.",
	"boom.hue": "Dreht die Farbe der Explosion im Farbkreis.",
	"mine.size": "Größe der Minen auf der Strecke.",
	"mine.glow": "Wie hell die Minen leuchten. Höher = besser sichtbar.",
	"mine.blink": "Wie schnell die Minen blinken.",
	"mine.life": "Wie viele Sekunden eine Mine liegen bleibt.",
	"mine.boom": "Größe der Explosion, wenn man eine Mine trifft.",
	"mine.hue": "Dreht die Farbe der Minen.",
	"quake.height": "Höhe der Erdbebenwelle. Höher = Schiffe fliegen höher.",
	"quake.speed": "Wie schnell die Welle über die Strecke läuft.",
	"quake.dur": "Wie weit die Welle läuft, bevor sie verebbt.",
	"quake.glow": "Wie hell die Welle leuchtet.",
	"quake.sparks": "Funken und Splitter an der Welle.",
	"quake.shake": "Kamerawackeln beim Beben. 0 = ruhig.",
	"quake.hue": "Dreht die Farbe der Welle.",
	"gb.scale": "Größe des ganzen Schwarzen Lochs auf einmal.",
	"gb.size": "Wie weit das Loch Schiffe anzieht. Höher = zieht von weiter her.",
	"gb.time": "Wie lange das Schwarze Loch bestehen bleibt.",
	"gb.core": "Größe des schwarzen Kerns.",
	"gb.dark": "Wie schwarz der Kern ist. Niedriger = durchscheinender.",
	"gb.rimw": "Breite des leuchtenden Rands.",
	"gb.rimb": "Helligkeit des leuchtenden Rands.",
	"gb.rimh": "Farbe des Rands.",
	"gb.wave": "Stärke der Schockkugel beim Entstehen. 0 = keine Kugel.",
	"gb.wthick": "Dicke der Schockkugel.",
	"gb.wspeed": "Wie schnell sich die Schockkugel ausbreitet.",
	"gb.wsize": "Wie groß die Schockkugel wird.",
	"gb.whue": "Farbe der Schockkugel.",
	"gb.gring": "Leuchtring am Boden unter dem Loch.",
	"gb.sparks": "Funken, die ins Loch gesaugt werden.",
	"gb.light": "Licht, das vom Loch ausgeht.",
	"gb.lens": "Wie stark das Loch den Raum dahinter verzerrt.",
	"gb.shake": "Kamerawackeln. 0 = ruhig.",
	"gb.hue": "Dreht alle Farben des Schwarzen Lochs zusammen.",
	"rak.size": "Größe der Raketen.",
	"rak.speed": "Wie schnell die Raketen fliegen.",
	"rak.light": "Wie hell der Antrieb der Rakete leuchtet.",
	"rak.hue": "Dreht die Farbe der Raketen.",
	"jungle.trees": "Wie viele Bäume am Rand stehen. Weniger = schneller auf dem Handy.",
	"jungle.under": "Menge an Büschen und Farnen. Weniger = schneller.",
	"jungle.flies": "Anzahl der Glühwürmchen.",
	"jungle.fsize": "Größe der Glühwürmchen.",
	"jungle.mush": "Wie stark die Pilze leuchten.",
	"jungle.wall": "Höhe der Erdwände an der Strecke. Wirkt erst nach Neustart.",
	"jungle.meteor": "Wie oft Sternschnuppen am Himmel erscheinen.",
	"jungle.far": "Sichtbarkeit der fernen Berge.",
	"lock.shape": "Form der Zielmarkierung um den Gegner.",
	"lock.size": "Größe der Zielmarkierung.",
	"lock.thick": "Linienstärke der Markierung.",
	"lock.glow": "Wie hell die Markierung leuchtet.",
	"lock.spin": "Wie schnell sich die Markierung dreht.",
	"lock.hue": "Farbe, solange noch nicht eingerastet.",
	"lock.lhue": "Farbe, sobald das Ziel erfasst ist.",
	"lock.time": "Wie lange es dauert, bis das Ziel erfasst ist. Höher = länger warten.",
	"lock.vol": "Lautstärke des Piepsens.",
	"lock.pitch": "Tonhöhe des Piepsens.",
	"wall.height": "Höhe des Kraftfelds.",
	"wall.dur": "Wie lange das Kraftfeld steht.",
	"wall.bolts": "Blitze im Kraftfeld. 0 = keine Blitze.",
	"wall.glow": "Helligkeit des Kraftfelds.",
	"wall.hue": "Dreht die Farbe des Kraftfelds.",
	"shield.size": "Größe der Schutzblase ums Schiff.",
	"shield.glow": "Wie hell der Schild leuchtet.",
	"shield.edge": "Wie scharf der Rand der Blase ist.",
	"shield.flicker": "Wie stark der Schild flackert.",
	"shield.hue": "Dreht die Farbe des Schilds.",
	"orbs.shue": "Farbe der Super-Kugeln.",
	"orbs.sglow": "Helligkeit der Super-Kugeln.",
	"orbs.size": "Größe der Kugeln.",
	"orbs.radius": "Wie weit die Kugeln um das Schiff kreisen.",
	"orbs.speed": "Wie schnell die Kugeln kreisen.",
	"orbs.trail": "Länge der Leuchtspur hinter den Kugeln.",
	"orbs.glow": "Helligkeit der Kugeln.",
	"orbs.hue": "Dreht die Farbe der Kugeln.",
	"haze.jglow": "Helligkeit des Plasmastrahls hinter den Düsen.",
	"haze.jlen": "Länge des Plasmastrahls.",
	"haze.jwid": "Breite des Plasmastrahls.",
	"haze.jboost": "Wie viel größer der Strahl beim Boost wird.",
	"haze.jdia": "Leuchtende Ringe im Strahl. 0 = keine Ringe.",
	"haze.jhue": "Dreht die Farbe des Plasmas.",
	"haze.amp": "Stärke des Hitzeflimmerns hinter dem Schiff. 0 = aus.",
	"haze.fine": "Feinheit des Flimmerns. Höher = feiner.",
	"haze.speed": "Wie schnell das Flimmern wabert.",
	"haze.size": "Größe der flimmernden Fläche.",
	"haze.len": "Wie weit hinter dem Schiff es flimmert.",
	"haze.boost": "Wie viel stärker es beim Boost flimmert.",
	"pillar.speed": "Wie schnell sich die Ringe der Waffensäule drehen.",
	"pillar.size": "Größe der Ringe.",
	"pillar.glow": "Helligkeit der Ringe.",
	"pillar.squash": "Wie stark die Säule beim Durchfliegen gummiartig nachgibt.",
	"pillar.soft": "Wie weich die Säule zurückfedert.",
	"pillar.beam": "Lichtsäule, die nach oben leuchtet.",
	"ship.height": "Wie hoch das Schiff über der Strecke schwebt.",
	"ship.bob": "Leichtes Auf und Ab beim Schweben. 0 = ganz ruhig.",
	"ship.bank": "Wie stark sich das Schiff in Kurven zur Seite neigt (nur Optik).",
	"ship.pitch": "Wie stark die Nase beim Gasgeben hochgeht (nur Optik).",
	"ship.wobble": "Wie lange Neigen und Nicken nachfedern. 0 = kein Nachfedern.",
	"ship.stiff": "Wie schnell das Schiff seine Neigung annimmt. Höher = straffer.",
	"ship.steer": "Trägheit der Lenkung: wie lange das Schiff braucht, um auf deinen Finger zu reagieren. Niedriger = reagiert sofort, höher = träger und weicher.",
	"ship.steerk": "Lenkkraft bei vollem Einschlag: wie schnell sich das Schiff dreht. Höher = engere Kurven, aber nervöser.",
	"ship.grip": "Wie stark das Schiff in die Richtung fliegt, in die die Nase zeigt. Höher = folgt der Nase sofort, niedriger = rutscht weiter geradeaus.",
	"ship.drift": "Wie stark das Schiff in Kurven seitlich wegdriftet. 0 = kein Driften.",
	"ship.nav": "Helligkeit der roten und grünen Positionslichter.",
	"ship.navb": "Wie schnell die Positionslichter blinken.",
	"ship.trim": "Grundhaltung: plus = Nase zeigt mehr zum Boden, minus = Nase höher.",
	"ship.weight": "Gewicht der Ketten und Quasten. Höher = hängen straff nach unten.",
	"ship.swing": "Wie lange Ketten und Quasten nachschwingen. Höher = pendeln länger.",
	"ship.wind": "Wie stark der Fahrtwind die Quasten nach hinten zieht.",
	"ship.center": "Beim Loslassen dreht sich die Nase von selbst wieder gerade. 0 = bleibt schräg (man muss gegenlenken), höher = stellt sich schneller gerade, Säulen lassen sich leichter anvisieren.",
	"ship.spdst": "Bei hohem Tempo und Boost lenkt das Schiff sanfter, damit es nicht zur Seite schießt. 0 = immer gleich stark, höher = bei Tempo deutlich ruhiger.",
	"pillar.hitw": "Wie nah du an der Waffensäule vorbeifliegen musst, damit sie zählt (nur die Trefferzone, die Säule sieht gleich aus). Höher = leichter zu treffen.",
	"ship.breeze": "Leichte Brise, die immer weht, auch im Stand. 0 = windstill.",
	"steer.ptime": "Wie lange du halten musst, bis die Lenkung voll greift (die Drück-Kurve läuft über diese Zeit). Kürzer = schnell volle Kraft, länger = feiner dosierbar.",
	"steer.rtime": "Wie lange die Lenkung nach dem Loslassen noch nachwirkt (die Loslass-Kurve läuft über diese Zeit). 0 = stoppt sofort.",
	"steer.swrange": "Wisch-Lenkung: wie weit (Anteil der Bildschirmbreite) du den Daumen schieben musst, bis voll gelenkt wird. Kleiner = schon kurze Wischer lenken stark, größer = feiner dosierbar.",
	"steer.velk": "Wisch-Lenkung: wie viel extra gelenkt wird, wenn du schnell wischst (Form über die Kurve „Wischtempo“). 0 = nur der Wischweg zählt.",
	"steer.hold": "Wisch-Lenkung: wie lange die Lenkung festgehalten wird, wenn du den Daumen kurz abhebst (z. B. zum Doppeltippen). Setzt du in der Zeit wieder auf, lenkst du nahtlos weiter.",
	"steer.glide": "Gleit-Modus: wie schnell das Schiff zur Stelle rutscht, die dein Daumen vorgibt (und beim Loslassen zurück zur Mitte). Kleiner = flink, größer = weich und träge.",
	"steer.gwidth": "Gleit-Modus: wie weit du das Schiff bei vollem Wisch zum Rand schieben kannst. 1 = bis kurz vor die Bande.",
	"steer.gpull": "Gleit- und Touchpad-Modus: wie stark Kurven das Schiff leicht nach außen ziehen (Boost zieht nicht extra). 0 = Schiff bleibt immer genau dort, wo du es hinschiebst.",
	"steer.revmode": "1 = Wischst du zurück, lenkt das Schiff sofort sanft in die Gegenrichtung (die Mitte springt unter deinen Daumen). 0 = wie ein Joystick: erst wenn du über die Mitte zurück bist, lenkst du in die andere Richtung.",
	"steer.revbuf": "Wie weit (Anteil der Bildschirmbreite) du zurückwischen musst, bis es als Richtungswechsel zählt. Schluckt Daumenzittern. Klein halten, sonst fühlt sich der Wechsel verzögert an.",
	"steer.velmin": "Ab welchem Wischtempo der Extra-Schub überhaupt greift. Höher = nur ein klarer, schneller Ruck gibt Extra, normale Bewegungen bleiben immer sanft.",
	"steer.psens": "Touchpad- und Spur-Modus: wie weit das Schiff pro Daumenweg rutscht. 3 = ein Drittel Bildschirmbreite schiebt es von der Mitte bis an den Rand. Höher = weniger Daumenweg nötig.",
	"steer.paccel": "Touchpad-Modus: Mausbeschleunigung. Schnelle Bewegungen schieben weiter, langsame bleiben fein. Gilt nur im Moment der Bewegung – abbremsen und sanft zurück ist sofort wieder fein. 0 = immer gleich.",
	"steer.vib": "Spur-Modus: kurze Vibration, wenn das Schiff in eine neue Spur einrastet. 0 = aus.",
	"steer.dtap": "Wie schnell zwei Tipper aufeinander folgen müssen, damit die Waffe feuert. Größer = leichter auszulösen, aber eher aus Versehen.",
	"steer.delay": "Verzögerung zwischen Tippen und Lenken. Normalerweise 0 lassen, höher fühlt sich schwammig an.",
	"env.city": "Hochhäuser neben der Strecke an oder aus.",
	"env.dens": "Wie viele Gebäude stehen. Weniger = schneller auf dem Handy.",
	"env.bh": "Höhe der Gebäude.",
	"env.bw": "Breite der Gebäude.",
	"env.bd": "Wie weit die Gebäude von der Strecke entfernt stehen.",
	"env.win": "Wie viele Fenster leuchten.",
	"env.hue_w": "Dreht die Farbe der Fenster.",
	"env.edge": "Neonkanten an den Gebäuden.",
	"env.hue_s": "Dreht die Farbe des Himmels.",
	"env.skyb": "Helligkeit des Himmels.",
	"env.stars": "Wie viele Sterne zu sehen sind.",
	"env.skyline": "Ferne Skyline am Horizont.",
	"env.skyl": "Ferne Skyline am Horizont.",
	"env.fog": "Wie dicht der Nebel in der Ferne ist.",
	"env.hue_f": "Dreht die Farbe des Nebels.",
	"env.moon": "Größe bzw. Helligkeit des Mondes. 0 = kein Mond.",
	"env.beams": "Lichtsäulen, die in den Himmel strahlen.",
	"env.lamps": "Lichter entlang der Strecke.",
	"env.nlight": "Wie stark sich die Neonlichter auf der Fahrbahn spiegeln.",
	"env.gloss": "Glanz der Fahrbahn.",
	"env.wet": "Nasse, spiegelnde Fahrbahn. 0 = trocken.",
	"city.holo": "Riesige Hologramm-Figuren in der Stadt an oder aus.",
	"city.hsize": "Größe der Hologramme.",
	"city.hflick": "Wie stark die Hologramme flackern und glitchen.",
	"city.hhue": "Dreht die Farbe der Hologramme.",
	"city.signs": "Neon-Schilder an den Häusern.",
	"city.search": "Suchscheinwerfer am Himmel.",
	"city.cars": "Fliegende Autos über der Stadt.",
	"city.mega": "Besonders hohe Mega-Türme.",
	"sound.vol": "Lautstärke dieses Geräuschs.",
	"sound.pitch": "Tonhöhe. Höher = heller, niedriger = tiefer.",
	"sound.bass": "Tiefe Töne verstärken.",
	"sound.treble": "Hohe Töne verstärken.",
	"sound.grit": "Rauheit, Verzerrung. 0 = sauber.",
	"sound.echo": "Stärke des Echos.",
	"sound.etime": "Abstand zwischen den Echos.",
	"sound.reverb": "Hall wie in einem großen Raum.",
	"sound.room": "Wie groß der Raum für den Hall klingt.",
	"sound.rumble": "Tiefes Grollen des Triebwerks.",
	"sound.beeps": "Lautstärke der ursprünglichen Countdown-Pieptöne.",
	"sound.synth": "Lautstärke der Synthesizer-Pieptöne.",
	"sound.spitch": "Tonhöhe der Synthesizer-Töne.",
	"sound.sshape": "Klangfarbe der Synthesizer-Töne (weich bis kantig).",
	"sound.sweep": "Aufsteigender Ton beim GO."
}
# Lenk-Voreinstellungen zum Vergleichen: [Name, Anlaufzeit, Ausklingzeit, Steering lag, Steering strength, Grip, Drück-Kurve]
const STEER_PRE = [
	["Ruhig", 0.9, 0.2, 1.8, 0.85, 0.9, [[0.0, 0.3, 0.0, 0.0, 0.35, 0.0], [1.0, 1.0, -0.35, -0.2, 0.0, 0.0]]],
	["Mittel", 0.56, 0.12, 1.0, 1.0, 1.0, [[0.0, 0.55, 0.0, 0.0, 0.4, 0.0], [1.0, 1.0, -0.3, -0.25, 0.0, 0.0]]],
	["Scharf", 0.25, 0.05, 0.45, 1.3, 1.3, [[0.0, 0.8, 0.0, 0.0, 0.3, 0.12], [1.0, 1.0, -0.3, 0.0, 0.0, 0.0]]]]


# ================================================================ Lenkkurven (Bézier, am PC einstellbar)
# Jede Kurve: Ankerpunkte [x, y, Griff-ein dx, dy, Griff-aus dx, dy] von x = 0 bis 1.
# press: x = Haltedauer / Anlaufzeit → Lenkkraft · release: x = Zeit seit Loslassen / Ausklingzeit → Rest der Lenkung
const CURVE_PATH = "user://curves.json"
const CURVE_DEF = {
	"press": [[0.0, 0.55, 0.0, 0.0, 0.4, 0.0], [1.0, 1.0, -0.3, -0.25, 0.0, 0.0]],
	"release": [[0.0, 1.0, 0.0, 0.0, 0.35, 0.0], [1.0, 0.0, -0.35, 0.0, 0.0, 0.0]],
	"swipe": [[0.0, 0.0, 0.0, 0.0, 0.35, 0.12], [1.0, 1.0, -0.35, -0.05, 0.0, 0.0]],
	"swvel": [[0.0, 0.0, 0.0, 0.0, 0.4, 0.0], [1.0, 1.0, -0.3, -0.3, 0.0, 0.0]]}
var curves = {}
var curve_lut = {}


func _curves_load() -> void:
	curves = CURVE_DEF.duplicate(true)
	if FileAccess.file_exists(CURVE_PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(CURVE_PATH))
		if d is Dictionary:
			for k in ["press", "release", "swipe", "swvel"]:
				if d.get(k) is Array and (d[k] as Array).size() >= 2:
					curves[k] = d[k]
	for k in curves:
		curve_lut[k] = _curve_bake(curves[k])


func _curves_save() -> void:
	var f = FileAccess.open(CURVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(curves))


# Bézier-Pfad in eine Tabelle mit 129 Werten umrechnen (x muss nach rechts laufen)
func _curve_bake(pts: Array) -> PackedFloat32Array:
	var xs = PackedFloat32Array()
	var ys = PackedFloat32Array()
	for i in range(pts.size() - 1):
		var a: Array = pts[i]
		var b: Array = pts[i + 1]
		var p0 = Vector2(a[0], a[1])
		var p1 = p0 + Vector2(a[4], a[5])
		var p3 = Vector2(b[0], b[1])
		var p2 = p3 + Vector2(b[2], b[3])
		for j in range(33):
			var t = j / 32.0
			var u = 1.0 - t
			var q = p0 * u * u * u + p1 * 3.0 * u * u * t + p2 * 3.0 * u * t * t + p3 * t * t * t
			xs.append(maxf(q.x, xs[xs.size() - 1] if xs.size() > 0 else 0.0))
			ys.append(clampf(q.y, 0.0, 1.0))
	var lut = PackedFloat32Array()
	lut.resize(129)
	var k = 0
	for i in range(129):
		var x = i / 128.0
		while k < xs.size() - 2 and xs[k + 1] < x:
			k += 1
		var dx = xs[k + 1] - xs[k]
		var f = clampf((x - xs[k]) / dx, 0.0, 1.0) if dx > 1e-6 else 1.0
		lut[i] = lerpf(ys[k], ys[k + 1], f)
	return lut


func _curve_at(k: String, x: float) -> float:
	var lut: PackedFloat32Array = curve_lut.get(k, PackedFloat32Array())
	if lut.is_empty():
		return 1.0
	var f = clampf(x, 0.0, 1.0) * 128.0
	var i = mini(int(f), 127)
	return lerpf(lut[i], lut[i + 1], f - i)


# ================================================================ Live-Regler vom PC (gleiches WLAN)
# Das Spiel öffnet einen kleinen Webserver (Port 8080). Im PC-Browser erscheinen alle FX-Lab-Regler;
# jede Änderung wirkt sofort im laufenden Rennen und wird auf dem Handy gespeichert.
const LIVE_PORT = 8080
var live_srv: TCPServer
var live_cons = []
var live_lbl: Label
var live_sv = 0.0
var live_seen = 99.0
var fx_ver = 0          # zählt jede Änderung hoch: die PC-Seite zieht dann Regler und Kurven nach
const LIVE_WS_PORT = 8081   # Dauerverbindung (WebSocket) für die Live-Linie, ~60 Werte pro Sekunde
var live_ws_srv: TCPServer
var live_ws = []   # Sekunden seit der letzten Anfrage vom PC (die Seite meldet sich alle 2 s)


# PC hat die Regler-Seite offen: am Handy alles ausblenden, nur die Szene im Vollbild
func _live_pc() -> bool:
	return live_srv != null and live_seen < 5.0


func _live_addr() -> String:
	var best = ""
	for a in IP.get_local_addresses():
		if a.contains(":"):
			continue
		if a.begins_with("192.168.") or a.begins_with("10.") or a.begins_with("172."):
			best = a
			if a.begins_with("192.168."):
				break
	return "http://%s:%d" % [best if best != "" else "?", LIVE_PORT]


func _live_poll(dt: float) -> void:
	var on = int(cfg.get("live", 0)) == 1
	if not on:
		if live_srv != null:
			live_srv.stop()
			live_srv = null
			live_cons.clear()
		if live_ws_srv != null:
			live_ws_srv.stop()
			live_ws_srv = null
			live_ws.clear()
		if live_lbl != null:
			live_lbl.visible = false
		return
	if live_srv == null:
		live_srv = TCPServer.new()
		if live_srv.listen(LIVE_PORT) != OK:
			live_srv = null
			return
	_live_ws_poll()
	# kleine Adresse oben links, damit man sie am PC eintippen kann
	if live_lbl == null and hud.has("fire"):
		live_lbl = Label.new()
		live_lbl.add_theme_font_size_override("font_size", 20)
		live_lbl.modulate = Color(0.6, 1.0, 0.8, 0.8)
		live_lbl.position = Vector2(36, 430)
		(hud.fire as Control).get_parent().add_child(live_lbl)
	live_seen += dt
	var pc = _live_pc()
	if live_lbl != null:
		live_lbl.visible = not pc
		live_lbl.text = "LIVE  " + _live_addr()
	if state == "lab" and lab.has("cl") and is_instance_valid(lab.cl):
		var cl: CanvasLayer = lab.cl
		if cl.visible == pc:
			cl.visible = not pc
	while live_srv.is_connection_available():
		var c = live_srv.take_connection()
		if c != null:
			live_cons.append({"c": c, "b": PackedByteArray(), "t": 0.0})
	for i in range(live_cons.size() - 1, -1, -1):
		var e = live_cons[i]
		var c: StreamPeerTCP = e.c
		c.poll()
		e.t += dt
		if c.get_status() != StreamPeerTCP.STATUS_CONNECTED or e.t > 3.0:
			live_cons.remove_at(i)
			continue
		var n = c.get_available_bytes()
		if n > 0:
			var r = c.get_data(n)
			if r[0] == OK:
				e.b.append_array(r[1])
		var txt = e.b.get_string_from_utf8()
		if txt.contains("\r\n\r\n"):
			var line = txt.get_slice("\r\n", 0)
			var path = line.get_slice(" ", 1)
			live_seen = 0.0
			_live_answer(c, path)
			c.disconnect_from_host()
			live_cons.remove_at(i)
	if live_sv > 0.0:
		live_sv -= dt
		if live_sv <= 0.0:
			_fx_save()


# Dauerverbindung: jedes Bild Lenkzustand an alle offenen PC-Seiten schicken
func _live_ws_poll() -> void:
	if live_ws_srv == null:
		live_ws_srv = TCPServer.new()
		if live_ws_srv.listen(LIVE_WS_PORT) != OK:
			live_ws_srv = null
			return
	while live_ws_srv.is_connection_available():
		var tcp = live_ws_srv.take_connection()
		if tcp != null:
			var ws = WebSocketPeer.new()
			if ws.accept_stream(tcp) == OK:
				live_ws.append(ws)
	if live_ws.is_empty():
		return
	var g: Dictionary = ships[0] if not ships.is_empty() else {}
	var SD: Dictionary = fx.steer
	var swc = int(cfg.get("ctrl", 1)) >= 1
	var msg = JSON.stringify({"ver": fx_ver, "b": steer_btn, "c": 1 if swc else 0, "sx": float(sw.m) if swc and sw.idx >= 0 else -1.0, "vx": float(sw.vm) if swc and sw.idx >= 0 else -1.0,
		"px": clampf(btn_t / maxf(0.05, float(SD.ptime)), 0.0, 1.0) if steer_btn != 0 else -1.0,
		"rx": clampf(rel_t / maxf(0.001, float(SD.rtime)), 0.0, 1.0) if steer_btn == 0 and rel_t < float(SD.rtime) else -1.0,
		"s": last_steer, "u": float(g.get("u", 0.0)), "psi": float(g.get("psi", 0.0)), "t": Time.get_ticks_msec()})
	for i in range(live_ws.size() - 1, -1, -1):
		var ws: WebSocketPeer = live_ws[i]
		ws.poll()
		var st = ws.get_ready_state()
		if st == WebSocketPeer.STATE_OPEN:
			live_seen = 0.0
			ws.send_text(msg)
			while ws.get_available_packet_count() > 0:
				ws.get_packet()
		elif st == WebSocketPeer.STATE_CLOSED:
			live_ws.remove_at(i)


func _live_send(c: StreamPeerTCP, ctype: String, body: String) -> void:
	var b = body.to_utf8_buffer()
	var h = "HTTP/1.1 200 OK\r\nContent-Type: %s; charset=utf-8\r\nContent-Length: %d\r\nCache-Control: no-store\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n" % [ctype, b.size()]
	c.put_data(h.to_utf8_buffer())
	c.put_data(b)


func _live_answer(c: StreamPeerTCP, path: String) -> void:
	if path.begins_with("/fx"):
		# alle Reiter mit Reglern und aktuellen Werten
		var tabs = []
		for t in FXT:
			var its = []
			for it in FXS[t[0]]:
				its.append({"k": it[0], "n": it[1], "lo": it[2], "hi": it[3], "d": it[4], "v": float(fx[t[0]][it[0]]), "i": FX_INFO.get(t[0] + "." + it[0], ""), "m": FX_MODES.get(t[0] + "." + it[0], [])})
			tabs.append({"g": t[0], "n": t[1], "it": its})
		_live_send(c, "application/json", JSON.stringify({"ver": fx_ver, "tabs": tabs, "ctrl": int(cfg.get("ctrl", 1)), "cn": CTRL_N, "cc": CTRL_CURVES}))
	elif path.begins_with("/tab?") or path.begins_with("/fire?") or path.begins_with("/drive"):
		var q2 = {}
		var qi = path.find("?")
		if qi >= 0:
			for kv in path.substr(qi + 1).split("&"):
				q2[kv.get_slice("=", 0)] = kv.get_slice("=", 1).uri_decode()
		if path.begins_with("/tab?"):
			_live_view(str(q2.get("g", "")))
		elif path.begins_with("/fire?"):
			_live_fire(str(q2.get("g", "")), str(q2.get("s", "0")) == "1", str(q2.get("m", "0")) == "1")
		else:
			# weiterfahren: FX Lab schließen und direkt wieder ins Free ride
			if state == "lab":
				pending_free = true
				_lab_close.call_deferred()
			elif state == "menu":
				free_ride = true
				_start()
		_live_send(c, "text/plain", "ok")
	elif path.begins_with("/mode?"):
		_set_ctrl(clampi(int(path.get_slice("=", 1)), 0, 5))
		_live_send(c, "text/plain", "ok")
	elif path.begins_with("/ping"):
		_live_send(c, "text/plain", "ok")
	elif path.begins_with("/sst"):
		# wo du gerade auf den Lenkkurven bist (für die Live-Linie im Editor)
		var SD: Dictionary = fx.steer
		_live_send(c, "application/json", JSON.stringify({"b": steer_btn, "px": clampf(btn_t / maxf(0.05, float(SD.ptime)), 0.0, 1.0) if steer_btn != 0 else -1.0,
			"rx": clampf(rel_t / maxf(0.001, float(SD.rtime)), 0.0, 1.0) if steer_btn == 0 and rel_t < float(SD.rtime) else -1.0, "s": last_steer}))
	elif path.begins_with("/preset?"):
		_steer_preset(int(path.get_slice("=", 1)))
		for k in ["steer", "steerk", "grip"]:
			_live_sync_lab("ship", k)
		_live_send(c, "text/plain", "ok")
	elif path.begins_with("/curve"):
		var qi2 = path.find("?d=")
		if qi2 >= 0:
			var d = JSON.parse_string(path.substr(qi2 + 3).uri_decode())
			if d is Dictionary:
				for k in ["press", "release", "swipe", "swvel"]:
					if d.get(k) is Array and (d[k] as Array).size() >= 2:
						curves[k] = d[k]
						curve_lut[k] = _curve_bake(curves[k])
				_curves_save()
				fx_ver += 1
		_live_send(c, "application/json", JSON.stringify({"cur": curves, "def": CURVE_DEF, "ctrl": int(cfg.get("ctrl", 1))}))
	elif path.begins_with("/set?"):
		var q = {}
		for kv in path.substr(5).split("&"):
			q[kv.get_slice("=", 0)] = kv.get_slice("=", 1).uri_decode()
		var g = str(q.get("g", ""))
		var k = str(q.get("k", ""))
		if FXS.has(g) and fx[g].has(k):
			for it in FXS[g]:
				if it[0] == k:
					fx[g][k] = clampf(float(q.get("v", "0")), it[2], it[3])
			_fx_changed(g, k)
			_live_sync_lab(g, k)
			live_sv = 0.8
		_live_send(c, "text/plain", "ok")
	else:
		_live_send(c, "text/html", LIVE_HTML)


# Vorschau am Handy: passende FX-Lab-Ansicht zum Reiter öffnen
func _live_view(t: String) -> void:
	if not FXS.has(t) or state == "kill" or state == "replay":
		return
	if state != "lab":
		_settings_close_all()
		_lab_open()
	_lab_tab(t)


func _settings_close_all() -> void:
	if ui.has("setp") and (ui.setp as Control).visible:
		_show_settings(false)


# Auslösen vom PC: im FX Lab den Test des Reiters, im Rennen/Free ride die passende Waffe direkt vor dem Schiff
const LIVE_W = {"boom": "rak", "rak": "rak", "gb": "rak", "lock": "lenk", "mine": "mine", "quake": "beben", "wall": "wand",
	"shield": "schild", "orbs": "orbs", "haze": "turbo", "ship": "turbo"}


func _live_fire(t: String, sup: bool, mega: bool) -> void:
	var g: Dictionary = ships[0]
	if state == "lab":
		if lab.get("tab", "") != t and FXS.has(t):
			_lab_tab(t)
		lab.sup = sup or mega
		if mega and LIVE_W.has(t):
			g.wpn = LIVE_W[t]
			g.sup = true
			g.mega = true
			_fire()
		else:
			_lab_fire()
	elif state == "race" and LIVE_W.has(t):
		g.wpn = LIVE_W[t]
		g.sup = sup or mega
		g.mega = mega
		_fire()
	elif t == "sound":
		_start_play(false)


# nach einer Regleränderung (FX Lab oder PC): Wirkung sofort sichtbar machen
func _fx_changed(t: String, key: String) -> void:
	fx_ver += 1
	if t == "env":
		if key in ["city", "dens", "bh", "bw", "bd"]:
			_city_fill()
		_env_apply()
	if t == "pillar":
		_pillar_apply()
	if t == "jungle":
		_jungle_apply()
	if t == "ship":
		_nav_apply()
	if t == "city":
		if key == "mega":
			_city_fill()
		_city_apply()
	if t == "sound":
		_start_bus_apply()
		if state == "lab":
			lab.sndre = 0.45


# Regler im offenen FX Lab mitziehen, wenn am PC verstellt
func _live_sync_lab(t: String, k: String) -> void:
	if state != "lab" or lab.get("tab", "") != t or not lab.has("sls"):
		return
	var i = 0
	for it in FXS[t]:
		if it[0] == k and i < lab.sls.size():
			(lab.sls[i] as HSlider).set_value_no_signal(float(fx[t][k]))
		i += 1


const LIVE_HTML = """<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>AntiGrav Live</title><style>
body{margin:0;background:#07080d;color:#e8ecf5;font:15px system-ui,sans-serif}
header{position:sticky;top:0;background:#0b0d16ee;padding:12px 16px;border-bottom:1px solid #223}
h1{margin:0 0 8px;font-size:18px;letter-spacing:.08em;color:#5ee8ff}
#tabs{display:flex;flex-wrap:wrap;gap:6px}
#tabs button{background:#151a2a;color:#cfd8ea;border:1px solid #2a3350;border-radius:8px;padding:6px 10px;cursor:pointer}
#tabs button.on{background:#ef6a2e;border-color:#ffb08a;color:#fff}
main{padding:12px 16px;max-width:900px}
.r{display:grid;grid-template-columns:200px 1fr 70px 34px;gap:10px;align-items:center;padding:7px 0;border-bottom:1px solid #141a28}
.r input{width:100%;accent-color:#ef6a2e}.v{text-align:right;font-variant-numeric:tabular-nums;color:#9fb0cc}
.r button{background:#151a2a;color:#9fb0cc;border:1px solid #2a3350;border-radius:6px;cursor:pointer}
#st{font-size:12px;color:#6c7a96;margin-top:6px}
#bar{display:flex;flex-wrap:wrap;gap:8px;align-items:center;margin:8px 0}
#bar button{background:#151a2a;color:#e8ecf5;border:1px solid #2a3350;border-radius:8px;padding:7px 12px;cursor:pointer}
#bar button.on{background:#2a6;border-color:#7fe0b0}#bar #fire{background:#ef6a2e;border-color:#ffb08a;font-weight:600}
#bar label{display:flex;gap:6px;align-items:center;color:#cfd8ea}
.ii{display:inline-flex;width:17px;height:17px;border-radius:50%;border:1px solid #5ee8ff;color:#5ee8ff;font-size:11px;align-items:center;justify-content:center;cursor:help;position:relative;margin-left:7px;font-style:italic;font-weight:600;vertical-align:middle}
.ii:hover::after,.ii.show::after{content:attr(data-t);position:absolute;left:24px;top:-8px;width:320px;background:#151a2a;border:1px solid #5ee8ff;color:#e8ecf5;padding:9px 11px;border-radius:8px;font-size:13px;font-style:normal;font-weight:400;line-height:1.4;z-index:20;white-space:normal;box-shadow:0 6px 20px #0008}
#pre{display:flex;gap:8px;margin:4px 0 14px;align-items:center;flex-wrap:wrap}
#pre button{background:#151a2a;color:#e8ecf5;border:1px solid #2a3350;border-radius:8px;padding:8px 16px;cursor:pointer;font-size:14px}
#pre button:hover{border-color:#ef6a2e}
</style></head><body><header><h1>ANTIGRAV · LIVE TUNING</h1><div id="tabs"></div>
<div id="bar"><label><input type="checkbox" id="pv"> Vorschau am Handy</label>
<button id="fire">Auslösen</button><button id="bs">Super</button><button id="bm">Mega</button><button id="drive">Weiterfahren (Free ride)</button></div>
<div id="st">verbinde …</div></header><main id="m"></main>
<script>
let D=[],cur=0,tm={};
const st=document.getElementById('st');
function fmt(it,v){if(it.k.indexOf('hue')>=0)return Math.round(v*360)+'°';if(['ptime','rtime','delay'].includes(it.k))return (+v).toFixed(2)+' s';return Math.round(v*100)+' %';}
function send(g,k,v){lastSend=Date.now();clearTimeout(tm[g+k]);tm[g+k]=setTimeout(()=>{fetch('/set?g='+g+'&k='+k+'&v='+v).then(()=>st.textContent='gesendet: '+k+' = '+v).catch(()=>st.textContent='keine Verbindung');},40);}
let sup=false,mega=false;
const pv=document.getElementById('pv');pv.checked=localStorage.getItem('pv')=='1';
pv.onchange=()=>{localStorage.setItem('pv',pv.checked?'1':'0');if(pv.checked)fetch('/tab?g='+D[cur].g);};
document.getElementById('bs').onclick=e=>{sup=!sup;if(sup)mega=false;upd();};
document.getElementById('bm').onclick=e=>{mega=!mega;if(mega)sup=false;upd();};
function upd(){document.getElementById('bs').className=sup?'on':'';document.getElementById('bm').className=mega?'on':'';}
document.getElementById('fire').onclick=()=>fetch('/fire?g='+D[cur].g+'&s='+(sup?1:0)+'&m='+(mega?1:0)).then(()=>st.textContent='ausgelöst: '+D[cur].n);
setInterval(()=>fetch('/ping').catch(()=>{}),2000);
document.getElementById('drive').onclick=()=>fetch('/drive').then(()=>st.textContent='weiter im Free ride');
let ssT=null,SS=null,EDS=[];
function show(i){cur=i;clearInterval(ssT);EDS=[];if(pv.checked)fetch('/tab?g='+D[i].g);document.querySelectorAll('#tabs button').forEach((b,j)=>b.className=j==i?'on':'');
 const m=document.getElementById('m');m.innerHTML='';const T=D[i];
 if(T.g=='steer'){const pr=document.createElement('div');pr.id='pre';const lb=document.createElement('span');lb.textContent='Voreinstellung zum Vergleichen:';lb.style.color='#9fb0cc';pr.append(lb);
  ['Ruhig','Mittel','Scharf'].forEach((n,k)=>{const b=document.createElement('button');b.textContent=n;b.onclick=()=>fetch('/preset?n='+k).then(()=>reloadAll(n));pr.append(b);});
  const ii=document.createElement('span');ii.className='ii';ii.textContent='i';ii.dataset.t='Setzt Lenkkurve, Anlaufzeit, Ausklingzeit und im Reiter Ship auch Steering lag, Steering strength und Grip auf einen festen Satz. Fahr mit jeder Voreinstellung eine Runde und sag, welche am nächsten dran ist.';pr.append(ii);m.append(pr);
  ssT=setInterval(()=>{if(SS&&SS.t&&Date.now()-lastWs<1000)return;fetch('/sst').then(r=>r.json()).then(d=>{SS=d;dirty=true;}).catch(()=>{});},150);}
 T.it.forEach(it=>{if(it.m&&it.m.length&&!it.m.includes(CTRL))return;const r=document.createElement('div');r.className='r';r.dataset.k=it.k;
  const l=document.createElement('div');l.textContent=it.n;
  if(it.i){const ii=document.createElement('span');ii.className='ii';ii.textContent='i';ii.dataset.t=it.i;ii.onclick=e=>{ii.classList.toggle('show');};l.append(ii);}const s=document.createElement('input');s.type='range';
  s.min=it.lo;s.max=it.hi;s.step=(it.k=='shape'||it.k=='city'||it.k=='life'||it.k=='revmode')?1:0.001;s.value=it.v;
  const v=document.createElement('div');v.className='v';v.textContent=fmt(it,it.v);
  const z=document.createElement('button');z.textContent='↺';z.title='Standard';
  s.oninput=()=>{it.v=+s.value;v.textContent=fmt(it,it.v);send(T.g,it.k,s.value);};
  z.onclick=()=>{s.value=it.d;s.oninput();};
  r.append(l,s,v,z);m.append(r);});
 if(T.g=='steer')curveUI(m);}
let CV=null,CD=null;
function reloadAll(n){fetch('/fx').then(r=>r.json()).then(dd=>{D=dd.tabs;VER=dd.ver;CTRL=dd.ctrl;CN=dd.cn;CC=dd.cc;modeBar();fetch('/curve').then(r=>r.json()).then(c=>{CV=c.cur;CD=c.def;show(cur);st.textContent='Voreinstellung: '+n;});});}
function sendCurve(){lastSend=Date.now();clearTimeout(tm.cv);tm.cv=setTimeout(()=>fetch('/curve?d='+encodeURIComponent(JSON.stringify(CV))).then(()=>st.textContent='Lenkkurve gesendet').catch(()=>st.textContent='keine Verbindung'),60);}
function curveUI(m){
 if(!CV){fetch('/curve').then(r=>r.json()).then(d=>{CV=d.cur;CD=d.def;curveUI(m);});return;}
 const L={swipe:['Wischweg','Wischweg (bis „Swipe: full-lock distance“)','Lenkkraft'],swvel:['Wischtempo','langsam … schnell gewischt','Extra-Lenkung (× „Swipe: speed boost“)'],
  release:['Lenkung nach dem Loslassen','Zeit seit dem Loslassen (bis „Release: fade time“)','Restlenkung'],press:['Lenkung beim Halten','Haltedauer (bis „Press: ramp time“)','Lenkkraft']};
 (CC[CTRL]||[]).forEach(k=>cvEd(m,k,L[k][0],L[k][1],L[k][2]));
 if(!(CC[CTRL]||[]).length){const p=document.createElement('p');p.style.color='#9fb0cc';p.textContent='Dieser Lenkmodus braucht keine Kurven – nur die Regler oben.';m.append(p);}}
function cvEd(m,name,title,xl,yl){
 const w=document.createElement('div');const h3=document.createElement('h3');h3.textContent=title;h3.style.cssText='color:#5ee8ff;margin:22px 0 6px;font-size:16px';w.append(h3);
 const c=document.createElement('canvas');c.width=720;c.height=330;c.style.cssText='width:100%;max-width:720px;background:#0b0e18;border:1px solid #2a3350;border-radius:8px;touch-action:none;cursor:crosshair';w.append(c);
 const hint=document.createElement('div');hint.style.cssText='font-size:12px;color:#6c7a96;margin-top:4px';
 hint.textContent='Punkte ziehen · Doppelklick auf freie Stelle = neuer Punkt · Doppelklick auf Punkt = löschen · kleine Kreise = Bézier-Griffe';w.append(hint);
 const rb=document.createElement('button');rb.textContent='↺ Standardkurve';rb.style.cssText='margin-top:6px;background:#151a2a;color:#cfd8ea;border:1px solid #2a3350;border-radius:6px;padding:5px 10px;cursor:pointer';w.append(rb);
 m.append(w);
 const g=c.getContext('2d'),L=58,R=30,T=30,B=48,W=c.width-L-R,H=c.height-T-B;
 const X=x=>L+x*W,Y=y=>T+(1-y)*H,IX=px=>(px-L)/W,IY=py=>1-(py-T)/H;
 let drag=null;
 const P=()=>CV[name];
 function yAt(x){const p=P();let best=null;for(let i=0;i<p.length-1;i++){const a=p[i],b=p[i+1];
  for(let j=0;j<=40;j++){const t=j/40,u=1-t;const qx=u*u*u*a[0]+3*u*u*t*(a[0]+a[4])+3*u*t*t*(b[0]+b[2])+t*t*t*b[0];
   const qy=u*u*u*a[1]+3*u*u*t*(a[1]+a[5])+3*u*t*t*(b[1]+b[3])+t*t*t*b[1];if(best===null||Math.abs(qx-x)<Math.abs(best[0]-x))best=[qx,qy];}}return best?Math.max(0,Math.min(1,best[1])):0;}
 function draw(){g.clearRect(0,0,c.width,c.height);g.strokeStyle='#1a2236';g.lineWidth=1;
  for(let i=0;i<=10;i++){g.beginPath();g.moveTo(X(i/10),Y(0));g.lineTo(X(i/10),Y(1));g.stroke();g.beginPath();g.moveTo(X(0),Y(i/10));g.lineTo(X(1),Y(i/10));g.stroke();}
  g.fillStyle='#6c7a96';g.font='12px system-ui';g.fillText(xl,L,c.height-12);g.save();g.translate(14,T+H);g.rotate(-Math.PI/2);g.fillText(yl+'  0 … 100 %',0,0);g.restore();
  const p=P();g.strokeStyle='#ef6a2e';g.lineWidth=3;g.beginPath();g.moveTo(X(p[0][0]),Y(p[0][1]));
  for(let i=0;i<p.length-1;i++){const a=p[i],b=p[i+1];g.bezierCurveTo(X(a[0]+a[4]),Y(a[1]+a[5]),X(b[0]+b[2]),Y(b[1]+b[3]),X(b[0]),Y(b[1]));}g.stroke();
  p.forEach((a,i)=>{g.strokeStyle='#5ee8ff88';g.lineWidth=1;
   [[2,3],[4,5]].forEach(([u,v])=>{if((u==2&&i==0)||(u==4&&i==p.length-1))return;g.beginPath();g.moveTo(X(a[0]),Y(a[1]));g.lineTo(X(a[0]+a[u]),Y(a[1]+a[v]));g.stroke();
    g.beginPath();g.arc(X(a[0]+a[u]),Y(a[1]+a[v]),5,0,7);g.fillStyle='#0b0e18';g.fill();g.strokeStyle='#5ee8ff';g.stroke();});
   g.beginPath();g.arc(X(a[0]),Y(a[1]),7,0,7);g.fillStyle='#ef6a2e';g.fill();g.strokeStyle='#fff';g.lineWidth=1.5;g.stroke();});
  // Live-Linie: wo du beim Fahren gerade auf dieser Kurve bist
  const lx=!SS?-1:(name=='press'?(SS.c?-1:SS.px):name=='swipe'?(SS.sx??-1):name=='swvel'?(SS.vx??-1):SS.rx);
  if(lx>=0){g.strokeStyle='#7fe0b0';g.lineWidth=2;g.setLineDash([5,4]);g.beginPath();g.moveTo(X(lx),Y(0));g.lineTo(X(lx),Y(1));g.stroke();g.setLineDash([]);
   const ly=yAt(lx);g.beginPath();g.arc(X(lx),Y(ly),9,0,7);g.fillStyle='#7fe0b0';g.fill();
   g.fillStyle='#7fe0b0';g.font='bold 13px system-ui';g.fillText(Math.round(ly*100)+' %',X(lx)+12,Y(ly)-10);}}
 EDS.push(draw);
 function pos(e){const r=c.getBoundingClientRect();return [(e.clientX-r.left)*c.width/r.width,(e.clientY-r.top)*c.height/r.height];}
 function hit(px,py){const p=P();for(let i=0;i<p.length;i++){const a=p[i];
   if(i>0&&Math.hypot(X(a[0]+a[2])-px,Y(a[1]+a[3])-py)<9)return [i,'in'];
   if(i<p.length-1&&Math.hypot(X(a[0]+a[4])-px,Y(a[1]+a[5])-py)<9)return [i,'out'];}
  for(let i=0;i<p.length;i++){const a=p[i];if(Math.hypot(X(a[0])-px,Y(a[1])-py)<11)return [i,'a'];}return null;}
 const cl=(v,a,b)=>Math.max(a,Math.min(b,v));
 c.onpointerdown=e=>{const [px,py]=pos(e);const h=hit(px,py);if(h){drag=h;EDS.dragging=true;c.setPointerCapture(e.pointerId);}};
 c.onpointermove=e=>{if(!drag)return;const [px,py]=pos(e);const p=P(),i=drag[0],a=p[i];const x=IX(px),y=IY(py);
  if(drag[1]=='a'){if(i>0&&i<p.length-1)a[0]=cl(x,p[i-1][0]+0.01,p[i+1][0]-0.01);a[1]=cl(y,0,1);
   a[2]=Math.max(-a[0],a[2]);a[4]=Math.min(1-a[0],a[4]);a[3]=cl(a[1]+a[3],-0.08,1.08)-a[1];a[5]=cl(a[1]+a[5],-0.08,1.08)-a[1];}
  else if(drag[1]=='in'){a[2]=Math.min(0,Math.max(-a[0],x-a[0]));a[3]=cl(y,-0.08,1.08)-a[1];}
  else{a[4]=Math.max(0,Math.min(1-a[0],x-a[0]));a[5]=cl(y,-0.08,1.08)-a[1];}
  draw();sendCurve();};
 c.onpointerup=()=>{drag=null;EDS.dragging=false;};
 c.ondblclick=e=>{const [px,py]=pos(e);const h=hit(px,py);const p=P();
  if(h&&h[1]=='a'){if(h[0]>0&&h[0]<p.length-1){p.splice(h[0],1);draw();sendCurve();}return;}
  const x=cl(IX(px),0.02,0.98);let k=1;while(k<p.length&&p[k][0]<x)k++;
  const y=yAt(x),ex=0.02,sl=(yAt(Math.min(1,x+ex))-yAt(Math.max(0,x-ex)))/(2*ex);
  const hl=Math.max(0.03,Math.min(0.14,(x-p[k-1][0])*0.45,(p[k][0]-x)*0.45));
  p.splice(k,0,[x,y,-hl,-hl*sl,hl,hl*sl]);draw();sendCurve();};
 rb.onclick=()=>{CV[name]=JSON.parse(JSON.stringify(CD[name]));draw();sendCurve();};
 draw();}
let VER=-1,lastSend=0,lastWs=0,dirty=false,mdown=false;
document.addEventListener('pointerdown',()=>mdown=true,true);document.addEventListener('pointerup',()=>{mdown=false;lastSend=Date.now();},true);
// Neu zeichnen nur bei Änderung und höchstens einmal pro Bildschirmbild
(function loop(){if(dirty&&EDS.length&&!EDS.dragging){dirty=false;EDS.forEach(f=>f());}requestAnimationFrame(loop);})();
function syncFrom(ver){if(ver==VER||mdown||Date.now()-lastSend<800)return;VER=ver;
 fetch('/fx').then(r=>r.json()).then(d=>{if(d.ctrl!=CTRL){D=d.tabs;CTRL=d.ctrl;modeBar();show(cur);return;}const T=d.tabs;T.forEach((t,i)=>{if(D[i])D[i].it=t.it;});
  document.querySelectorAll('#m .r').forEach(r=>{const it=D[cur].it.find(x=>x.k==r.dataset.k);if(!it)return;const s=r.querySelector('input');if(s&&document.activeElement!==s){s.value=it.v;r.querySelector('.v').textContent=fmt(it,it.v);}});
  if(D[cur].g=='steer')fetch('/curve').then(r=>r.json()).then(c=>{if(!EDS.dragging){CV=c.cur;EDS.forEach(f=>f());}});});}
function wsConnect(){try{const ws=new WebSocket('ws://'+location.hostname+':8081');
 ws.onmessage=e=>{lastWs=Date.now();const d=JSON.parse(e.data);
  const ch=!SS||SS.px!=d.px||SS.rx!=d.rx||SS.sx!=d.sx||SS.vx!=d.vx;SS=d;if(ch)dirty=true;syncFrom(d.ver);};
 ws.onclose=()=>setTimeout(wsConnect,1000);ws.onerror=()=>{};}catch(e){setTimeout(wsConnect,2000);}}
wsConnect();
let CTRL=1,CN=[],CC=[];
function modeBar(){let mb=document.getElementById('mb');if(!mb){mb=document.createElement('div');mb.id='mb';mb.style.cssText='display:flex;gap:6px;flex-wrap:wrap;align-items:center;margin:6px 0';document.querySelector('header').insertBefore(mb,document.getElementById('st'));}
 mb.innerHTML='<span style="color:#9fb0cc">Lenkmodus:</span>';CN.forEach((n,i)=>{const b=document.createElement('button');b.textContent=n;b.style.cssText='background:'+(i==CTRL?'#ef6a2e':'#151a2a')+';color:#fff;border:1px solid #2a3350;border-radius:8px;padding:5px 10px;cursor:pointer';b.onclick=()=>fetch('/mode?n='+i).then(()=>reloadAll(n));mb.append(b);});}
fetch('/fx').then(r=>r.json()).then(dd=>{const d=dd.tabs;VER=dd.ver;D=d;CTRL=dd.ctrl;CN=dd.cn;CC=dd.cc;modeBar();const t=document.getElementById('tabs');
 d.forEach((T,i)=>{const b=document.createElement('button');b.textContent=T.n;b.onclick=()=>show(i);t.append(b);});
 const ship=d.findIndex(T=>T.g=='ship');show(ship>=0?ship:0);st.textContent='verbunden – Änderungen wirken sofort';})
 .catch(()=>st.textContent='keine Verbindung zum Spiel');
</script></body></html>"""


# Zielerfassung der Lenkrakete: ein Neon-Zeichen in der 3D-Welt um den Gegner (leuchtet wie die Leitplanken),
# zieht sich zusammen, Piepsen wird schneller, eingerastet = andere Farbe, Dauersirren, „LOCKED“.
# Aussehen im FX Lab, Reiter „Lock“ (Form, Größe, Dicke, Leuchten, Drehung, Farben, Einrastzeit, Ton).
const LK_SHAPES = ["Neon rings", "Brackets", "Diamond", "Crosshair", "Chevrons"]
const LK_CODE = """
shader_type spatial;
render_mode unshaded,blend_add,cull_disabled,depth_draw_never,depth_test_disabled,shadows_disabled,fog_disabled;
uniform vec3 c=vec3(1.,.7,.2);uniform float gl=1.;
void fragment(){ALBEDO=c*(.6+gl*1.6)*(.85+.15*sin(TIME*20.));}
"""
var lk_tg = null
var lk_k = 0.0
var lk_bt = 0.0
var lk_t = 0.0
var lk_n: MeshInstance3D
var lk_im: ImmediateMesh
var lk_mat: ShaderMaterial
var lk_txt: Label
const LK_T = 1.3     # Sekunden bis zum Einrasten (× Regler)
const LK_R = 90.0    # Reichweite


func _lock_update(dt: float, racing: bool) -> void:
	var g: Dictionary = ships[0]
	var demo = state == "lab" and lab.get("tab", "") == "lock"
	if state == "lab":
		var o1: Dictionary = ships[1]
		if demo:
			# Vorschau im FX Lab: ein Gegner steht vor dir, die Erfassung läuft immer wieder durch
			o1.z = LZ + 9.0
			o1.lat = 0.0
			o1.out = false
			(o1.node as Node3D).visible = true
		elif absf(o1.z - (LZ + 9.0)) < 0.01:
			o1.z = LZ - 120.0
	var tg = null
	if demo:
		tg = ships[1]
	elif racing and g.wpn == "lenk" and not g.out and lk_tg != null and not lk_tg.out and lk_tg.z - g.z > 1.0 and lk_tg.z - g.z < LK_R * 1.2:
		tg = lk_tg   # einmal erfasst, bleibt das Ziel, solange es vor dir und in Reichweite ist
	elif racing and g.wpn == "lenk" and not g.out:
		var bd = LK_R
		for o in ships:
			if o.idx != 0 and not o.out and o.z - g.z > 2.0 and o.z - g.z < bd:
				bd = o.z - g.z
				tg = o
	if tg != lk_tg:
		lk_tg = tg
		lk_k = 0.0
		lk_bt = 0.0
		lk_t = 0.0
	if tg == null:
		if lk_n != null and lk_n.visible:
			lk_n.visible = false
			lk_txt.visible = false
		return
	var L: Dictionary = fx.lock
	lk_t += dt
	if demo and lk_t > 1.3 * float(L.time) + 1.6:
		lk_t = 0.0   # Vorschau: von vorn
	lk_k = clampf(lk_t / maxf(0.05, LK_T * float(L.time)), 0.0, 1.0)
	_lock_vis(tg, dt)
	# Piepsen: immer schneller, eingerastet ein schnelles Dauersirren
	lk_bt -= dt
	var vol = float(L.vol)
	if lk_bt <= 0.0 and vol > 0.01:
		var db = linear_to_db(vol)
		if lk_k >= 1.0:
			_snd("beep", db - 9.0, 1.55 * float(L.pitch))
			lk_bt = 0.06
		else:
			_snd("beep", db - 12.0, (1.1 + lk_k * 0.25) * float(L.pitch))
			lk_bt = lerpf(0.42, 0.1, lk_k)


func _lock_vis(tg: Dictionary, dt: float) -> void:
	var L: Dictionary = fx.lock
	if lk_n == null:
		lk_im = ImmediateMesh.new()
		lk_mat = _shader_mat(LK_CODE)
		lk_n = MeshInstance3D.new()
		lk_n.mesh = lk_im
		lk_n.material_override = lk_mat
		lk_n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lk_n.extra_cull_margin = 8.0
		add_child(lk_n)
		lk_txt = Label.new()
		lk_txt.add_theme_font_size_override("font_size", 30)
		lk_txt.add_theme_constant_override("outline_size", 6)
		lk_txt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
		lk_txt.text = "LOCKED"
		lk_txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lk_txt.custom_minimum_size = Vector2(200, 0)
		(hud.fire as Control).get_parent().add_child(lk_txt)
	var on = lk_k >= 1.0
	var col = _hs(Color(1.0, 0.1, 0.12), float(L.lhue)) if on else _hs(Color(1.0, 0.72, 0.2), float(L.hue))
	var wp: Vector3 = (tg.node as Node3D).global_position + Vector3.UP * 0.12
	var dist = cam.global_position.distance_to(wp)
	# Größe in der Welt; weit weg etwas größer, damit es lesbar bleibt
	var r = lerpf(2.4, 0.75, pow(lk_k, 0.7)) * 0.45 * float(L.size) * maxf(1.0, dist / 14.0)
	if on:
		r *= 1.0 + 0.06 * sin(lk_t * 18.0)   # eingerastet: pulsiert
	var w = 0.035 * float(L.thick) * maxf(1.0, dist / 14.0)
	var rot = (lk_t * 1.6 + (1.0 - lk_k) * 2.4) * float(L.spin) * (0.25 if on else 1.0)
	lk_n.visible = true
	lk_n.global_transform = Transform3D(cam.global_transform.basis, wp)
	lk_mat.set_shader_parameter("c", _v3(col))
	lk_mat.set_shader_parameter("gl", float(L.glow) * (1.4 if on else 1.0))
	lk_im.clear_surfaces()
	lk_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var sh = clampi(int(round(float(L.shape))), 0, LK_SHAPES.size() - 1)
	match sh:
		0:   # zwei gegenläufige, unterbrochene Neonringe; eingerastet geschlossen
			var gp = 0.0 if on else 0.45
			for i in range(3):
				var a = rot + i * TAU / 3.0
				_lk_arc(Vector2.ZERO, r, a + gp * 0.5, a + TAU / 3.0 - gp * 0.5, w)
			for i in range(2):
				var a = -rot * 1.5 + i * PI
				_lk_arc(Vector2.ZERO, r * 0.62, a + gp * 0.4, a + PI - gp * 0.4, w * 0.8)
		1:   # vier Eckklammern, drehen sich beim Zusammenziehen gerade
			for i in range(4):
				var a = rot * 0.3 + i * PI * 0.5 + PI * 0.25
				var c = Vector2(cos(a), sin(a)) * r * 1.2
				var d1 = Vector2(cos(a + PI * 0.75), sin(a + PI * 0.75)) * r * 0.55
				var d2 = Vector2(cos(a - PI * 0.75), sin(a - PI * 0.75)) * r * 0.55
				_lk_seg(c, c + d1, w)
				_lk_seg(c, c + d2, w)
		2:   # Raute, eingerastet mit zweiter, innerer Raute
			for q in ([1.0, 0.55] if on else [1.0]):
				var pts = []
				for i in range(4):
					var a = rot + i * PI * 0.5
					pts.append(Vector2(cos(a), sin(a)) * r * 1.15 * q)
				for i in range(4):
					_lk_seg(pts[i], pts[(i + 1) % 4], w)
		3:   # klassisches Fadenkreuz: Kreis und vier Striche
			_lk_arc(Vector2.ZERO, r, 0.0, TAU, w)
			for i in range(4):
				var a = rot + i * PI * 0.5
				var dv = Vector2(cos(a), sin(a))
				_lk_seg(dv * r * 0.55, dv * r * 1.35, w)
		4:   # drei Pfeilspitzen zeigen auf das Ziel
			for i in range(3):
				var a = rot + i * TAU / 3.0
				var dv = Vector2(cos(a), sin(a))
				var pv = Vector2(-dv.y, dv.x)
				var tip = dv * r * 0.7
				_lk_seg(tip, tip + dv * r * 0.5 + pv * r * 0.35, w)
				_lk_seg(tip, tip + dv * r * 0.5 - pv * r * 0.35, w)
	if on:
		# Mittelpunkt
		_lk_arc(Vector2.ZERO, w * 1.2, 0.0, TAU, w * 2.0)
	lk_im.surface_end()
	# Schriftzug unter dem Zeichen
	var sp = cam.unproject_position(wp - cam.global_transform.basis.y * r * 1.5)
	lk_txt.visible = on and not cam.is_position_behind(wp)
	if lk_txt.visible:
		lk_txt.position = sp - Vector2(100, 0)
		lk_txt.add_theme_color_override("font_color", col.lightened(0.25))


# Linie als schmales Band in der Ebene des Zeichens
func _lk_seg(a: Vector2, b: Vector2, w: float) -> void:
	var d = (b - a).normalized()
	var n = Vector2(-d.y, d.x) * w * 0.5
	var A = Vector3(a.x + n.x, a.y + n.y, 0)
	var B = Vector3(b.x + n.x, b.y + n.y, 0)
	var C = Vector3(b.x - n.x, b.y - n.y, 0)
	var D = Vector3(a.x - n.x, a.y - n.y, 0)
	for v in [A, B, C, A, C, D]:
		lk_im.surface_add_vertex(v)


func _lk_arc(c: Vector2, r: float, a0: float, a1: float, w: float) -> void:
	var n = maxi(3, int(abs(a1 - a0) / 0.2))
	for i in range(n):
		var u0 = lerpf(a0, a1, float(i) / n)
		var u1 = lerpf(a0, a1, float(i + 1) / n)
		var p0i = c + Vector2(cos(u0), sin(u0)) * (r - w * 0.5)
		var p0o = c + Vector2(cos(u0), sin(u0)) * (r + w * 0.5)
		var p1i = c + Vector2(cos(u1), sin(u1)) * (r - w * 0.5)
		var p1o = c + Vector2(cos(u1), sin(u1)) * (r + w * 0.5)
		for v in [p0i, p0o, p1o, p0i, p1o, p1i]:
			lk_im.surface_add_vertex(Vector3(v.x, v.y, 0))


func _weapons(dt: float, racing: bool) -> void:
	var g: Dictionary = ships[0]
	msg_t -= dt
	if msg_t <= 0.0:
		hud.msg.text = ""
	# Waffenfeld: jedes zweite Feld (alle 70 Einheiten)
	var zz = g.z
	var wk = int(round((zz - 17.0) / 35.0))
	var wz = (zz - _wzp(wk)) / 35.0
	if wz < 0.0 or not _pad_ok(_wzp(wk)):
		wz = 9.0
	if racing and posmod(wk, 2) == 0 and wz < maxf(1.75, g.spd * dt * 1.3) / 35.0 and not g.air and absf(g.lat - _wpx(wk)) < float(fx.pillar.get("hitw", 0.5)) and wk != g.wpK and (g.wpn == "" or not g.get("mega", false)):
		g.wpK = wk
		if g.wpn == "":
			g.wpn = _pick_w()
			g.wpc = 1
			_snd("pick", -4.0)
			_snd("vo_" + g.wpn, 3.0)   # Ansage, was du eingesammelt hast
			if g.wpn == "orbs" and g.orbs > 0.0:
				g.sup = true
				get_tree().create_timer(0.75).timeout.connect(func(): _snd("vo_super", 3.0))
		else:
			# Waffe behalten und noch zwei Waffenfelder überfahren → deine Waffe wird zur Superwaffe
			g.wpc = int(g.get("wpc", 1)) + 1
			if g.wpc == 2:
				_tip("sup1", "Keep your weapon! One more weapon pad and it turns SUPER – stronger and gold.")
			elif g.wpc == 3:
				_tip("sup2", "Keep it for one more pad and it becomes MEGA.")
			if g.wpc >= 4:
				_tip("mega", "Every weapon has its own huge effect – fire it!")
				# noch ein Feld mit der Superwaffe → MEGA: Schockwelle zieht jedem Gegner 75 % Energie ab
				g.mega = true
				g.sup = true
				_snd("pick", 0.0, 1.6)
				_snd("vo_mega", 3.0)
				_flash(Color(1.0, 0.35, 0.9), 0.45)
				_msg("MEGA " + WN.get(g.wpn, ""), Color(1.0, 0.45, 0.95))
			elif g.wpc >= 3:
				g.sup = true
				_snd("pick", -2.0, 1.35)
				_snd("vo_super", 3.0)
				_flash(Color(1.0, 0.8, 0.3), 0.35)
			else:
				_snd("pick", -6.0, 1.2)
				_msg("SUPER %d / 3" % g.wpc, Color(1.0, 0.82, 0.35))
	_tips_check(g, racing, dt)
	if fire_req:
		fire_req = false
		if g.wpn != "" and racing:
			_fire()
	# Namen aus zwei Wörtern (FORCE FIELD) untereinander, damit sie in den runden Knopf passen
	var fn: String = str(WN.get(g.wpn, "empty")).replace(" ", "\n")
	var pre = (("MEGA\n" if g.get("mega", false) else "SUPER\n") if g.get("sup", false) and g.wpn != "" else "")
	hud.fire.text = pre + fn
	var nl = (pre + fn).count("\n") + 1
	var fsz = (30 if fn.length() <= 7 else 26) if nl <= 2 else 22
	if hud.get("fsz", 0) != fsz:
		hud.fsz = fsz
		hud.fire.add_theme_font_size_override("font_size", fsz)
	if g.auto > 0.0 and g.wpn == "":
		hud.fire.text = ("SUPER\n" if g.get("sauto", false) else "") + "AUTO" + (" …" if g.get("ahold", false) else " %.1f" % g.auto)
	_lock_update(dt, racing)
	var armed = g.wpn != ""
	hud.armed = armed
	hud.fire.modulate = Color(1, 1, 1, 1.0 if armed or g.auto > 0.0 else 0.4)
	var wc: Color = WC.get(g.wpn, Color(1, 1, 1)) if not g.get("sup", false) else Color(1.0, 0.78, 0.2)
	hud.wc = wc
	hud.fire_sb.border_color = Color(wc.r, wc.g, wc.b, 1.0) if armed else Color(1, 1, 1, 0.25)
	hud.fire_sb.bg_color = Color(wc.r, wc.g, wc.b, 0.22 + 0.08 * sin(Time.get_ticks_msec() / 200.0)) if armed else Color(1, 1, 1, 0.05)
	hud.ring.queue_redraw()

	var vp = get_viewport().get_visible_rect().size
	var r = (hud.fire as Control).get_global_rect()
	fire_rect = r.grow(20) if r.size.x > 0 else Rect2(vp.x * 0.5 - 130, vp.y - 270, 260, 200)
	hud.pausebtn.visible = state in ["intro", "count", "race"] and fin.is_empty()
	for o in ships:
		if o.idx > 0 and (o.node as Node3D).has_meta("bar"):
			var bar: MeshInstance3D = (o.node as Node3D).get_meta("bar")
			bar.set_instance_shader_parameter("fill", o.en)
			bar.visible = state == "race" and o.z - g.z > 1.5 and o.z - g.z < 40.0
	var hs = int(cfg.get("hud", 2))
	var goth = hs == 1
	var alt = hs == 2
	if hud.en_bg.visible == (hs != 0):
		hud.en_bg.visible = hs == 0
		hud.el.visible = hs == 0
	hud.pg.visible = not alt
	hud.gh.visible = goth
	hud.ga.visible = alt
	if alt:
		_ga_frame(g, dt)
	if goth:
		hud.gs = lerpf(float(hud.gs), g.spd, 1.0 - exp(-get_process_delta_time() / 0.15))
		hud.gh.queue_redraw()
	hud.en.size.x = 300.0 * g.en
	hud.el.text = "ENERGY  %d %%" % int(round(g.en * 100.0))
	hud.en.color = Color(0.36, 1.0, 0.6) if g.en > 0.5 else (Color(1.0, 0.85, 0.25) if g.en > 0.25 else Color(1.0, 0.35, 0.3))
	# Warnung bei wenig Energie: Ansage beim Unterschreiten von 25 %, Balken blinkt rot
	if g.en <= 0.25 and not g.out and state == "race":
		if not en_low:
			en_low = true
			_snd("vo_enlow", 3.0)
		var bl = fmod(Time.get_ticks_msec() / 1000.0, 0.5) < 0.25
		hud.en.color = Color(1.0, 0.2, 0.15) if bl else Color(0.5, 0.08, 0.06)
		hud.en_bg.color = Color(1, 0.2, 0.15, 0.35 if bl else 0.15)
	else:
		if g.en > 0.35:
			en_low = false
		hud.en_bg.color = Color(1, 1, 1, 0.15)
	# Neue Runde: 25 % Energie zurück
	for o in ships:
		var ln = int(floor((o.z - T.ZST) / T.LAP))
		if ln > o.enL and not o.out:
			o.enL = ln
			o.en = minf(1.0, o.en + 0.25)
	var spd = base_spd * 2.8 * float(fx.rak.speed)
	# Geschosse
	for i in range(shots.size() - 1, -1, -1):
		var sh = shots[i]
		sh.t += dt
		var sdir: float = sh.get("dir", 1.0)
		var z0: float = sh.z
		sh.z += spd * dt * sdir
		if sh.pl:
			sh.lat += (g.lat - sh.lat) * minf(1.0, dt * 3.0)
		elif sh.hm:
			if sh.tg == null or sh.tg.out or (sh.tg.z - sh.z) * sdir < -1.5:
				sh.tg = null
				var bd = 200.0
				for o in ships:
					if o.idx != sh.own and not o.out and (o.z - sh.z) * sdir > -1.0 and (o.z - sh.z) * sdir < bd:
						bd = (o.z - sh.z) * sdir
						sh.tg = o
			if sh.tg != null:
				# je näher, desto härter auf die Spur des Ziels – die Lenkrakete schlägt direkt ein
				var dzt = absf(sh.tg.z - sh.z)
				sh.lat += (sh.tg.lat - sh.lat) * minf(1.0, dt * (5.0 + 60.0 / maxf(1.0, dzt)))
		else:
			sh.lat += sh.dl * spd * dt
		# Treffer: Weg der Rakete in diesem Bild (von z0 nach z) kreuzt das Schiff
		var hit = null
		var zlo = minf(z0, sh.z) - 0.6
		var zhi = maxf(z0, sh.z) + 0.6
		for o in ships:
			if o.out or o.idx == sh.own or (sh.pl and o.idx != 0):
				continue
			if sh.has("grp") and sh.grp.has(o.idx):
				continue
			if sh.get("only", false) and sh.tg != null and o != sh.tg:
				continue
			var lw = 0.4 if sh.pl else (0.75 if sh.hm and sh.tg == o else 0.6)
			if o.z > zlo and o.z < zhi and absf(sh.lat - o.lat) < lw:
				hit = o
				if sh.has("grp"):
					sh.grp[o.idx] = true
				break
		var dead = false
		if hit != null:
			if not _prot(hit):
				hit.slow = minf(hit.slow, 0.35)
				hit.vpsi += randf_range(-0.25, 0.25)
			if sh.get("mega", false):
				# Mega-Salve: fester Schaden (40 %), Explosion ohne schwarzes Loch – sonst summiert es sich im Pulk
				_dmg(hit, 0.4, sh.own, "rocket", true)
				_explode(hit.z, hit.lat, false, 1.2)
			else:
				_dmg(hit, 0.3 if sh.pl else 0.35, sh.own, "rocket", sh.get("sup", false) or sh.get("cl", false))
				_shot_boom(sh, hit.z, hit.lat, hit.idx)   # Explosion genau am getroffenen Schiff
			dead = true
		elif absf(sh.lat) > T.TW - 0.05 or sh.t > 6.0 or (sh.cl and sh.t > 0.42) or (state == "lab" and absf(sh.z - LZ) > 18.0):
			if sh.get("mega", false):
				_explode(sh.z, clampf(sh.lat, -T.TW, T.TW), false, 0.8)   # Mega-Salve: daneben = nur ein Knall, kein Loch
			else:
				_shot_boom(sh, sh.z, clampf(sh.lat, -T.TW, T.TW), -1)
			dead = true
		else:
			# Annäherungszünder: fliegt die Rakete dicht an einem Gegner vorbei, geht sie sofort hoch
			for o in ships:
				if o.out or o.idx == sh.own or sh.pl or (sh.hm and sh.tg != null) or sh.get("mega", false):
					continue   # Lenkrakete mit Ziel und Mega-Salve: kein Vorbeiflug-Zünder
				if o.z > zlo and o.z < zhi and absf(sh.lat - o.lat) < 1.6:
					_shot_boom(sh, o.z, sh.lat, -1)
					dead = true
					break
		if dead:
			sh.n.queue_free()
			shots.remove_at(i)
		else:
			var f = T.frame(sh.z)
			sh.n.global_transform = Transform3D(Basis(f.rr, f.fw, -f.uu), f.c + f.rr * sh.lat + f.uu * 0.25)
	# Minen
	for i in range(mines.size() - 1, -1, -1):
		var m = mines[i]
		m.t += dt
		var bl = float(fx.mine.blink)
		(m.n as MeshInstance3D).visible = fmod(m.t, 0.5 / bl) < 0.35 / bl or m.t < 0.3
		if m.t < 0.25:
			# kurz herunterfallen und auf der Fahrbahn aufsetzen
			var u = clampf(m.t / 0.18, 0.0, 1.0)
			(m.n as Node3D).position = T.world(m.z, m.lat, 0.12 + 0.33 * (1.0 - u * u))
		var boom = false
		for o in ships:
			if o.idx != m.get("own", 0) and not o.out and absf(o.z - m.z) < 0.5 + o.spd * dt * 1.3 and absf(o.lat - m.lat) < 0.38:
				var mg = int(m.get("g", 0))
				var mh: Dictionary = o.get("mh", {})
				if mg == 0 or not mh.has(mg):
					mh[mg] = true
					o.mh = mh
					if not _prot(o):
						o.slow = minf(o.slow, 0.35)
					_dmg(o, 0.12, m.get("own", 0), "mine", m.get("sup", false))
				boom = true
		# Quake-Welle räumt Minen ab (egal von wem), Minen verschwinden nach 25 s von selbst
		if not boom and ((quake != null and absf(m.z - quake.z) < 2.6) or (quake2 != null and absf(m.z - quake2.z) < 2.6)):
			boom = true
		if state == "lab" and m.t > 1.8:
			boom = true
		if boom or m.t > float(fx.mine.life):
			if boom:
				_explode(m.z, m.lat, false, float(fx.mine.boom))
			m.n.queue_free()
			mines.remove_at(i)
	# Wall: Gegner, die durchfliegen, werden 1 s gebremst und verlieren 10 %
	for i in range(walls.size() - 1, -1, -1):
		var w = walls[i]
		w.age += dt
		for o in ships:
			if o.idx != 0 and not o.out and not w.hit.has(o.idx) and o.z >= w.z and o.z - o.spd * dt * 1.5 < w.z + 0.01:
				w.hit.append(o.idx)
				var ws: bool = w.get("sup", false)
				var wm: bool = w.get("mega", false)
				if not _prot(o):   # mit Schild: fliegt einfach durch
					o.slowT = 4.0 if ws else 2.5
				if ws and not _prot(o):
					o.slow = minf(o.slow, 0.3 if wm else 0.35)
				w.hf = 1.0
				_dmg(o, 0.2 if wm else (0.25 if ws else 0.1), 0, "wall", ws)
				_zap_ship(o)
				_snd("zap", 2.0, 1.0, (o.node as Node3D).global_position)
		w.hf = maxf(0.0, w.hf - dt * 2.5)
		_wall_pose(w.n, w.z, w.age, w.hf)
		_wall_fig(w)
		if w.age > 5.3 * float(fx.wall.dur):
			w.n.queue_free()
			if w.has("fig"):
				(w.fig.n as Node3D).visible = false
				w.fig.busy = false
			walls.remove_at(i)
	# Beben: rollt nach vorn (Super: zweite Welle nach hinten), wirft Gegner hoch
	if quake != null:
		quake = _quake_step(quake, dt)
	if quake2 != null:
		quake2 = _quake_step(quake2, dt)
	_bwaves_update(dt)
	_megaw_update(dt)
	_fx_update(dt)
	# Schild: blaue Hülle (für alle Schiffe)
	for o in ships:
		_shield_vis(o)
	_orbs_update(dt, true)


# ---------------------------------------------------------------- Energiewand: Wabengitter, Lauflicht, zuckende Blitze
var wall_code = """
shader_type spatial;
render_mode unshaded,blend_add,cull_disabled,depth_draw_never,shadows_disabled;
uniform float a=1.;
uniform float hit=0.;
uniform float sd=0.;
uniform vec3 wc=vec3(1.,.5,.1);
uniform float bk=1.;
uniform float gk=1.;
float h11(float x){return fract(sin(x*127.1)*43758.5453);}
float h21(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float n1(float x){float i=floor(x),f=fract(x);return mix(h11(i),h11(i+1.),f*f*(3.-2.*f));}
void fragment(){
	vec2 uv=UV;vec2 p=vec2(uv.x*4.8,uv.y*1.4)*5.;
	vec2 r=vec2(1.,1.732),hh=r*.5;vec2 ga=mod(p,r)-hh,gb=mod(p-hh,r)-hh;vec2 gv=dot(ga,ga)<dot(gb,gb)?ga:gb;
	vec2 ag=abs(gv);float he=max(dot(ag,normalize(vec2(1.,1.732))),ag.x);
	vec2 id=floor((p-gv)*2.+.5);
	float fl=step(.55,h21(id+floor(TIME*10.)+sd));
	float edge=smoothstep(.4,.5,he);
	float cell=fl*(1.-he*1.4)*.35;
	vec3 o=wc*gk;
	vec3 c=o*(.06+.12*pow(n1(uv.x*26.+TIME*3.+sd),4.));
	c+=o*edge*(.35+.6*fl)+o*cell;
	c+=o*1.5*exp(-pow(abs((fract(uv.y*.999-TIME*.8+sd)-.5)*9.),2.))*.35;
	c+=(wc+vec3(0.,.15,.15))*gk*smoothstep(.07,0.,min(uv.y,1.-uv.y))*2.8;
	c+=(wc+vec3(0.,.15,.15))*gk*smoothstep(.025,0.,min(uv.x,1.-uv.x))*2.2;
	for(int i=0;i<4;i++){
		float fi=float(i);float tq=floor(TIME*(11.+fi*2.)+fi*3.7+sd*5.);
		float on=step(.4-hit*.4,h11(tq*1.31+fi*9.1));
		if(on<.5||bk<.001)continue;
		float y0=.15+.7*h11(tq+fi*2.3);
		float pth=y0+(n1(uv.x*6.+tq*3.1)-.5)*.42+(n1(uv.x*21.+tq*5.7)-.5)*.14+(n1(uv.x*60.+tq)-.5)*.04;
		float d=abs(uv.y-pth);
		c+=(vec3(.75,.9,1.)*exp(-d*170.)*4.+vec3(.5,.6,1.)*exp(-d*28.)*.45)*on*bk;
	}
	ALBEDO=c*a*(1.+hit*2.5);
}"""


func _swall_node() -> MeshInstance3D:
	return _wall_node(true)


# Stopp-Hologramm hinter dem Force field (nur bei deinen eigenen): Arme halb ausgebreitet, halb abwehrend nach vorn
var wall_figs = []
const WF_H = 7.5


func _wall_fig(w: Dictionary) -> void:
	if int(w.get("own", -1)) != 0 or state == "replay":
		return
	if not w.has("fig"):
		var fg = null
		for c in wall_figs:
			if not c.busy:
				fg = c
		if fg == null:
			if wall_figs.size() >= 2:
				return
			fg = _hfig_make()
			wall_figs.append(fg)
		fg.busy = true
		w.fig = fg
	var d: Dictionary = w.fig
	var life = 5.3 * float(fx.wall.dur)
	var age = float(w.age)
	var gx = maxf(clampf(1.0 - age / 0.35, 0.0, 1.0), clampf((age - (life - 0.5)) / 0.4, 0.0, 1.0) * 1.6)
	var vis = age < life - 0.08 and (age < life - 0.25 or randf() < 0.4)
	var n: Node3D = d.n
	if n.visible != vis:
		n.visible = vis
	if not vis:
		return
	var f = T.frame(float(w.z) + 5.0)
	var fw: Vector3 = (f.fw * Vector3(1, 0, 1)).normalized()
	n.global_transform = Transform3D(Basis.looking_at(fw, Vector3.UP).scaled(Vector3.ONE * (WF_H / float(HOLO_FIGS[0][1]))), f.c + Vector3.UP * -0.2)
	# Geste baut sich in 0,25 s auf, dann leichtes Nachdrücken
	var k = 1.0 - pow(1.0 - clampf(age / 0.25, 0.0, 1.0), 3.0)
	var push = sin(age * 6.0) * 3.0
	_hfig_arms(d, lerpf(-72.0, 0.0, k), lerpf(0.0, 30.0, k) + push, lerpf(-72.0, 35.0, k), lerpf(0.0, 55.0, k) + push, k)
	_hfig_look(d, f.c.y, WF_H, gx, 1.1)


func _wall_node(sup := false) -> MeshInstance3D:
	_pev("wall")
	var X: Dictionary = fx.wall
	var q = QuadMesh.new()
	q.size = Vector2(T.TW * 2.0, 1.4 * float(X.height))
	var mi = MeshInstance3D.new()
	mi.mesh = q
	# Super-Wand: kräftiger und kaum durchsichtig
	var m = _shader_mat(wall_code if not sup else wall_code.replace("render_mode unshaded,blend_add,", "render_mode unshaded,blend_mix,").replace("	ALBEDO=c*a*(1.+hit*2.5);", "	ALBEDO=c*a*(1.+hit*2.5);\n	ALPHA=clamp(.55+dot(c,vec3(.25)),0.,1.)*a;"))
	m.set_shader_parameter("sd", randf() * 10.0)
	m.set_shader_parameter("wc", _v3(_hs(Color(1.0, 0.5, 0.1), float(X.hue))))
	m.set_shader_parameter("bk", float(X.bolts))
	m.set_shader_parameter("gk", float(X.glow))
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var l = OmniLight3D.new()
	l.light_color = _hs(Color(1.0, 0.55, 0.15), float(X.hue))
	l.omni_range = 6.0
	l.position = Vector3(0, -0.2, 0)
	mi.add_child(l)
	mi.set_meta("l", l)
	mi.set_meta("sup", sup)
	add_child(mi)
	return mi


func _wall_pose(mi: MeshInstance3D, z: float, age: float, hf: float) -> void:
	var f = T.frame(z)
	var X: Dictionary = fx.wall
	mi.global_transform = Transform3D(Basis(f.rr, f.uu, f.fw), f.c + f.uu * (0.72 * float(X.height)))
	var wkey = Vector4(float(X.height), float(X.hue), float(X.bolts), float(X.glow))
	if mi.get_meta("wkey", Vector4(-1, -1, -1, -1)) != wkey:
		mi.set_meta("wkey", wkey)
		(mi.mesh as QuadMesh).size = Vector2(T.TW * 2.0, 1.4 * float(X.height))
		var wm: ShaderMaterial = mi.material_override
		wm.set_shader_parameter("wc", _v3(_hs(Color(1.0, 0.5, 0.1), float(X.hue))))
		wm.set_shader_parameter("bk", float(X.bolts))
		wm.set_shader_parameter("gk", float(X.glow) * (1.8 if mi.get_meta("sup", false) else 1.0))
		(mi.get_meta("l") as OmniLight3D).light_color = _hs(Color(1.0, 0.55, 0.15), float(X.hue))
	var a = clampf(minf(age / 0.3, (5.3 * float(X.dur) - age) / 0.4), 0.0, 1.0)
	var m: ShaderMaterial = mi.material_override
	m.set_shader_parameter("a", a)
	m.set_shader_parameter("hit", hf)
	var l: OmniLight3D = mi.get_meta("l")
	l.light_energy = (2.2 * float(X.glow) + randf() * 1.2 * float(X.bolts) + hf * 6.0) * a


# Blitze, die um ein Schiff zucken, nachdem es durch die Wand geflogen ist
var zaps = []
var zap_mat: StandardMaterial3D


func _zap_ship(o: Dictionary) -> void:
	_pev("zap")
	_rev(["zap", o.idx])
	if zap_mat == null:
		zap_mat = StandardMaterial3D.new()
		zap_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		zap_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		zap_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		zap_mat.albedo_color = Color(2.2, 2.8, 4.0)
		zap_mat.no_depth_test = false
	var nd: Node3D = o.node
	for z0 in zaps:
		if z0.o == o:
			z0.t = 0.0
			return
	var mi = MeshInstance3D.new()
	mi.mesh = ImmediateMesh.new()
	mi.material_override = zap_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	nd.add_child(mi)
	var l = OmniLight3D.new()
	l.light_color = Color(0.55, 0.75, 1.0)
	l.omni_range = 4.5
	l.position = Vector3(0, 0.3, 0)
	nd.add_child(l)
	zaps.append({"o": o, "t": fx_age, "mi": mi, "l": l, "rt": 0.0})


func _zap_update(dt: float) -> void:
	for i in range(zaps.size() - 1, -1, -1):
		var e = zaps[i]
		e.t += dt
		e.rt -= dt
		var nd: Node3D = e.o.node
		var life = 2.5
		if e.t > life or not nd.visible:
			e.mi.queue_free()
			e.l.queue_free()
			zaps.remove_at(i)
			continue
		var fade = clampf((life - e.t) / 0.8, 0.0, 1.0)
		e.l.light_energy = (randf() * 4.0 + 1.0) * fade if randf() < 0.75 else 0.0
		if e.rt > 0.0:
			continue
		e.rt = 0.045
		var im: ImmediateMesh = e.mi.mesh
		im.clear_surfaces()
		var bb: AABB = nd.get_meta("bb")
		var rad = bb.size * 0.5 * Vector3(1.15, 1.5, 1.05) + Vector3.ONE * 0.08
		var ctr = bb.get_center()
		var cd = (nd.global_transform.affine_inverse() * cam.global_position).normalized()
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		var na = 2 + int(randf() * 3.0 * fade + 0.5)
		for a in range(na):
			if randf() > fade + 0.2:
				continue
			var d0 = Vector3(randf_range(-1, 1), randf_range(-0.6, 1), randf_range(-1, 1)).normalized()
			var d1 = (d0 + Vector3(randf_range(-1.4, 1.4), randf_range(-0.8, 0.8), randf_range(-1.4, 1.4))).normalized()
			var pts = []
			var ns = 9
			for k in range(ns + 1):
				var u = float(k) / ns
				var d = d0.slerp(d1, u) if d0.dot(d1) > -0.95 else d0.lerp(d1, u).normalized()
				var j = 1.0 + (randf_range(-0.22, 0.22) if k > 0 and k < ns else 0.0)
				pts.append(ctr + d * rad * j)
			for k in range(ns):
				var pa: Vector3 = pts[k]
				var pb: Vector3 = pts[k + 1]
				var sd = (pb - pa).cross(cd).normalized() * 0.018
				im.surface_add_vertex(pa - sd)
				im.surface_add_vertex(pa + sd)
				im.surface_add_vertex(pb + sd)
				im.surface_add_vertex(pa - sd)
				im.surface_add_vertex(pb + sd)
				im.surface_add_vertex(pb - sd)
		# immer mindestens ein Dreieck, sonst meckert Godot über eine leere Fläche
		im.surface_add_vertex(ctr)
		im.surface_add_vertex(ctr)
		im.surface_add_vertex(ctr)
		im.surface_end()


# Explosionen, schwarze Löcher, Blitze: laufen im Rennen und in der Wiederholung
func _fx_update(dt: float) -> void:
	for i in range(fxs.size() - 1, -1, -1):
		var e = fxs[i]
		if e.get("gb", false):
			if _gb_update(e, dt):
				fxs.remove_at(i)
			continue
		e.t += dt
		var u = clampf(e.t / (0.7 if e.big else 0.5), 0.0, 1.0)
		var sc = (0.6 + (8.0 if e.big else 5.5) * pow(u, 0.5)) * e.get("sz", 1.0)
		var f = e.f
		if e.ring != null:
			e.ring.global_transform = Transform3D(Basis(f.rr * sc, f.uu, f.fw * sc), f.c + f.rr * e.lat + f.uu * 0.03)
			e.rm.set_shader_parameter("u", u)
			if u >= 1.0:
				e.ring.queue_free()
				e.ring = null
		# Licht: greller Blitz, dann langes oranges Nachglühen
		var lt2: OmniLight3D = e.l
		var tl = e.t
		lt2.light_energy = (38.0 * exp(-tl * 7.0) + 7.0 * pow(clampf(1.0 - tl / 2.2, 0.0, 1.0), 1.6) * (1.0 + 0.15 * sin(tl * 37.0))) * e.get("lk", 1.0)
		lt2.light_color = _hs(Color(1.0, 0.92, 0.8).lerp(Color(1.0, 0.4, 0.08), clampf(tl * 2.2, 0.0, 1.0)), e.get("hu", 0.0))
		lt2.omni_range = e.rg * (0.7 + 0.5 * exp(-tl * 3.0))
		if tl >= 2.2:
			lt2.queue_free()
			fxs.remove_at(i)
	_zap_update(dt)
	big_t -= dt
	if big_t <= 0.0:
		hud.big.text = ""
	else:
		var bu = 2.4 - big_t
		hud.big.size.x = get_viewport().get_visible_rect().size.x
		hud.big.pivot_offset = Vector2(hud.big.size.x * 0.5, hud.big.size.y * 0.5)
		hud.big.scale = Vector2.ONE * (1.0 + 0.6 * exp(-bu * 9.0))
		hud.big.modulate.a = clampf(minf(bu / 0.08, big_t / 0.4), 0.0, 1.0)


# ---------------------------------------------------------------- Wiederholung: Aufzeichnung (30 Bilder/s) und Abspielen mit Fernsehkameras
var rec = []
var rec_ev = []
var rec_clk = 0.0
var rec_acc = 0.0
var rec_pl = ""   # Platzierungszeile beim letzten Aufzeichnungsbild (fürs Ergebnis nach dem Replay)
var rp = {}
const RP_CAMS = [["chase", "Chase", 6.0], ["side", "Trackside", 7.0], ["cock", "Cockpit", 6.0], ["side", "Trackside", 7.0], ["heli", "Aerial", 6.0], ["front", "Front", 5.0], ["free", "Free", 9999.0]]


func _rev(ev: Array) -> void:
	if state == "race" or state == "done":
		rec_ev.append(ev)


func _record(dt: float) -> void:
	if free_ride or not (state == "race" or (state == "done" and t_state < 5.0)):
		return
	rec_clk += dt
	rec_acc += dt
	if rec_acc < 1.0 / 30.0 and not rec.is_empty() and rec_ev.is_empty():
		return
	rec_acc = maxf(0.0, minf(rec_acc - 1.0 / 30.0, 1.0 / 30.0))
	rec_pl = hud.top.text
	var sh = []
	for o in ships:
		sh.append([o.z, o.lat, o.h, o.psi, o.roll, o.boost, o.spd, 0 if o.out else 1, o.shield])
	var w = []
	for x in shots:
		w.append([x.z, x.lat])
	var m = []
	for x in mines:
		m.append([x.z, x.lat])
	var wl = []
	for x in walls:
		wl.append([x.z, x.age, x.hf, 1 if x.get("sup", false) else 0])
	rec.append({"t": rec_clk, "s": sh, "w": w, "m": m, "wl": wl, "q": [quake.z, quake.get("qs", 0.0)] if quake != null else null, "q2": [quake2.z, quake2.get("qs", 0.0)] if quake2 != null else null, "so": ships[0].get("sorb", false),
		"sh": ships[0].shield, "ob": ships[0].orbs, "ev": rec_ev})
	rec_ev = []


func _pool(key: String, n: int, mk: Callable) -> Array:
	if not rp.has(key):
		rp[key] = []
	var a: Array = rp[key]
	while a.size() < n:
		a.append(mk.call())
	for i in range(a.size()):
		a[i].visible = i < n
	return a


func _replay_start() -> void:
	if rec.size() < 10 or state == "replay":
		return
	rp = {"t": 0.0, "i": 0, "ei": -1, "ci": 0, "ct": 0.0, "sp": null, "sk": 1.0, "fix": -1, "paused": false, "scrub": false,
		"fyaw": 0.6, "fpitch": 0.45, "fdist": 7.0, "follow": 0}
	hud.rppause.text = "II"
	rtouch = {}
	# Effekte aus dem laufenden Rennen weg – im Replay entstehen sie aus der Aufzeichnung
	for n in get_children():
		if n is GPUParticles3D:
			n.queue_free()
	for e in fxs:
		for k in ["ring", "l", "core", "sw", "sph"]:
			if e.has(k) and e[k] != null and is_instance_valid(e[k]):
				e[k].queue_free()
	fxs.clear()
	for e in zaps:
		e.mi.queue_free()
		e.l.queue_free()
	zaps.clear()
	_bwaves_clear()
	if quake != null:
		quake.n.queue_free()
		quake = null
	if quake2 != null:
		quake2.n.queue_free()
		quake2 = null
	fx_gen += 1
	# was gerade gelöscht wird, nicht als „gehört zur Szene“ merken
	rp.base = get_children().filter(func(n): return not n.is_queued_for_deletion())
	_rp_follow_lbl()
	state = "replay"
	hud.resb.visible = false
	hud.res.visible = false
	hud.rpx.visible = true
	hud.camrow.visible = true
	hud.rpsave.visible = rpf.is_empty()
	hud.rpphoto.visible = true
	hud.rpphoto.text = "PHOTO"
	hud.flwrow.visible = true
	hud.board.visible = false
	hud.rdim.visible = false
	hud.vxb.visible = false   # Video-Export vorerst aus (zu langsam); Baustein bleibt für später im Code
	hud.rpsave.text = "SAVE REPLAY"
	hud.rpsave.disabled = false
	_rp_cam_style()
	hud.fire.visible = false
	hud.en_bg.visible = false
	hud.el.visible = false
	hud.pg.visible = false
	hud.plbox.visible = false
	for x in walls:
		x.n.queue_free()
	walls.clear()
	for x in shots:
		x.n.queue_free()
	shots.clear()
	for x in mines:
		x.n.queue_free()
	mines.clear()


func _replay_end() -> void:
	if state != "replay":
		return
	if vx.get("on", false):
		_vx_finish()
		return
	if not vx.is_empty():
		return
	for k in ["shots", "mines", "walls", "swalls"]:
		for n in rp.get(k, []):
			n.queue_free()
	# eingefrorene Partikel (Pause/Spulen) wieder laufen lassen
	for n in get_children():
		if n is GPUParticles3D:
			n.speed_scale = 1.0
	rp = {}
	fx_gen += 1
	if not rpf.is_empty():
		# Replay aus der Liste: zurück ins Menü
		_reload()
		return
	state = "done"
	t_state = 5.0
	_show_resb()
	hud.res.visible = true
	hud.rpx.visible = false
	hud.camrow.visible = false
	hud.rpsave.visible = false
	hud.rpphoto.visible = false
	hud.flwrow.visible = false
	hud.vxb.visible = false
	_rset("qs", 0.0)
	_rset("qs2", 0.0)
	hud.fire.visible = true
	hud.en_bg.visible = true
	hud.el.visible = true
	hud.pg.visible = true
	hud.plbox.visible = true
	hud.top.text = rec_pl if rec_pl != "" else str(rec[rec.size() - 1].get("pl", ""))
	for o in ships:
		(o.node as Node3D).visible = not o.out


func _replay(dt: float) -> void:
	if rp.is_empty():
		return
	rp.t += dt
	var F = rec
	while rp.i < F.size() - 2 and F[rp.i + 1].t <= rp.t:
		rp.i += 1
	# Ereignisse der überflogenen Bilder auslösen
	while rp.ei < rp.i:
		rp.ei += 1
		for ev in F[rp.ei].ev:
			match ev[0]:
				"boom":
					_explode(ev[1], ev[2], ev[3], ev[4] if ev.size() > 4 else 1.0)
				"gb":
					_gbomb(ev[1], ev[2], -2, -1, ev[3] if ev.size() > 3 else 1.0)
				"zap":
					_zap_ship(ships[ev[1]])
					_snd("zap", 0.0, 1.0, (ships[ev[1]].node as Node3D).global_position)
				"big":
					_big(ev[1], ev[2])
				"vo":
					_snd(ev[1], ev[2])
	if rp.t > F[F.size() - 1].t + 0.4:
		_replay_end()
		return
	var f0 = F[rp.i]
	var f1 = F[mini(F.size() - 1, rp.i + 1)]
	var u = clampf((rp.t - f0.t) / maxf(0.001, f1.t - f0.t), 0.0, 1.0)
	for k in range(ships.size()):
		var a: Array = f0.s[k]
		var b: Array = f1.s[k]
		var o: Dictionary = ships[k]
		o.z = lerpf(a[0], b[0], u)
		o.lat = lerpf(a[1], b[1], u)
		o.h = lerpf(a[2], b[2], u)
		o.psi = lerpf(a[3], b[3], u)
		o.roll = lerpf(a[4], b[4], u)
		o.boost = lerpf(a[5], b[5], u)
		o.spd = lerpf(a[6], b[6], u)
		(o.node as Node3D).visible = a[7] == 1 and not (k == rp.get("follow", 0) and RP_CAMS[rp.ci][0] == "cock")
		o.shield = a[8]
		_shield_vis(o)
	var g: Dictionary = ships[0]
	g.orbs = f0.ob
	g.sorb = f0.get("so", false)
	g.auto = 0.0
	_orbs_update(dt, false)
	var ps = _pool("shots", f0.w.size(), func():
		var cap = CapsuleMesh.new()
		cap.radius = 0.06
		cap.height = 0.5
		return _glow_node(cap, Color(1.0, 0.6, 0.2), 8.0))
	for i in range(f0.w.size()):
		var fr = T.frame(f0.w[i][0])
		ps[i].global_transform = Transform3D(Basis(fr.rr, fr.fw, -fr.uu), fr.c + fr.rr * f0.w[i][1] + fr.uu * 0.25)
	var pm = _pool("mines", f0.m.size(), func():
		return _glow_node(_lowsphere(0.12, 12, 6), Color(1, 0.15, 0.1), 6.0))
	for i in range(f0.m.size()):
		pm[i].position = T.world(f0.m[i][0], f0.m[i][1], 0.12)
	# normale und Super-Wände getrennt (Super-Wände sehen anders aus)
	var wn = []
	var ws = []
	for x in f0.wl:
		if x.size() > 3 and x[3] == 1:
			ws.append(x)
		else:
			wn.append(x)
	var pw = _pool("walls", wn.size(), _wall_node)
	for i in range(wn.size()):
		_wall_pose(pw[i], wn[i][0], wn[i][1], wn[i][2])
	var pws = _pool("swalls", ws.size(), _swall_node)
	for i in range(ws.size()):
		_wall_pose(pws[i], ws[i][0], ws[i][1], ws[i][2])
	if f0.q != null:
		_rset("qz", f0.q[0])
		_rset("qs", f0.q[1])
	else:
		_rset("qs", 0.0)
	var q2 = f0.get("q2")
	_rset("qz2", q2[0] if q2 != null else -1000.0)
	_rset("qs2", q2[1] if q2 != null else 0.0)
	# Kamera-Regie wie im Fernsehen
	rp.ct += dt
	var cm = RP_CAMS[rp.ci]
	if rp.get("fix", -1) >= 0:
		# feste Kamera: Streckenkamera nur neu aufstellen, wenn der Gleiter vorbei ist
		if cm[0] == "side" and ((rp.sp != null and _focus().z > rp.sp + 9.0 and rp.ct > 2.5) or rp.ct > cm[2] * 1.6):
			rp.sp = null
			rp.ct = 0.0
	elif cm[0] == "side":
		if (rp.sp != null and _focus().z > rp.sp + 9.0 and rp.ct > 2.5) or rp.ct > cm[2] * 1.6:
			_rp_next()
	elif rp.ct > cm[2]:
		_rp_next()
	hud.top.text = "REPLAY · %s     %s" % [RP_CAMS[rp.ci][1], _fmt(minf(rp.t, F[F.size() - 1].t))]
	_fx_update(dt)


func _rp_photo() -> void:
	# alle Anzeigen kurz weg, ein Bild abwarten, dann aufnehmen
	hud.layer.visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img = get_viewport().get_texture().get_image()
	hud.layer.visible = true
	if img == null:
		return
	var ok = false
	if Engine.has_singleton("VideoExport"):
		ok = str(Engine.get_singleton("VideoExport").savePng(img.save_png_to_buffer())) != ""
	else:
		DirAccess.make_dir_recursive_absolute("user://photos")
		ok = img.save_png("user://photos/antigrav_%d.png" % int(Time.get_unix_time_from_system())) == OK
	_flash(Color(1, 1, 1), 0.5)
	_snd("pick", -6.0, 1.6)
	hud.rpphoto.text = "SAVED ✓" if ok else "ERROR"
	get_tree().create_timer(1.5).timeout.connect(func(): hud.rpphoto.text = "PHOTO")


# wem die Kamera folgt: im Replay der gewählte Fahrer, sonst du
func _focus() -> Dictionary:
	if state == "replay" and not rp.is_empty():
		return ships[clampi(int(rp.get("follow", 0)), 0, ships.size() - 1)]
	return ships[0]


func _rp_follow(d: int) -> void:
	if rp.is_empty():
		return
	rp.follow = posmod(int(rp.get("follow", 0)) + d, ships.size())
	rp.sp = null
	rp.ct = 0.0
	_rp_follow_lbl()


func _rp_follow_lbl() -> void:
	var k = int(rp.get("follow", 0))
	hud.flw.text = "YOU" if k == 0 else NAMES[k].to_upper()


func _rp_cam_pick(ci: int) -> void:
	if rp.is_empty():
		return
	rp.fix = ci
	if ci >= 0:
		rp.ci = ci
		rp.ct = 0.0
		rp.sp = null
	elif RP_CAMS[rp.ci][0] == "free":
		_rp_next()   # AUTO: weg von der freien Kamera, sonst bliebe die Regie dort hängen
	_rp_cam_style()


func _rp_cam_style() -> void:
	for it in hud.cambtn:
		var on = it[1] == rp.get("fix", -1)
		var st = _style(Color(0.93, 0.41, 0.18) if on else Color(1, 1, 1, 0.08), Color(1, 0.7, 0.54) if on else Color(1, 1, 1, 0.22))
		for k in ["normal", "hover", "focus", "pressed"]:
			it[0].add_theme_stylebox_override(k, st)


func _rp_save() -> void:
	DirAccess.make_dir_recursive_absolute("user://replays")
	var t = Time.get_datetime_dict_from_system()
	var fname = "user://replays/rp_%04d%02d%02d_%02d%02d%02d.dat" % [t.year, t.month, t.day, t.hour, t.minute, t.second]
	var sm = []
	for o in ships:
		sm.append(o.sm)
	var fa = FileAccess.open_compressed(fname, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if fa == null:
		hud.rpsave.text = "ERROR"
		return
	fa.store_var({"v": 1, "rec": rec, "sm": sm, "ps": pad_seed, "res": hud.res.text.replace("\n", " · "),
		"date": "%02d.%02d.%04d  %02d:%02d" % [t.day, t.month, t.year, t.hour, t.minute]})
	fa.close()
	hud.rpsave.text = "SAVED ✓"
	hud.rpsave.disabled = true


# ---------------------------------------------------------------- Video-Export: Replay einmal Bild für Bild abspielen, jedes Bild an den
# Android-Baustein „VideoExport“ geben (H.264, MP4), danach liegt das Video in der Galerie (Filme/AntiGrav)
const VX_W = 720
const VX_H = 1600
const VX_FPS = 30.0
var vx = {}


func _vx_start() -> void:
	if not Engine.has_singleton("VideoExport"):
		hud.vxl.text = "Video export is not available on this device."
		hud.vxs.visible = false
		hud.vxo.visible = true
		hud.vxd.visible = true
		vx = {"err": true}
		return
	vx = {"p": Engine.get_singleton("VideoExport"), "n": 0}
	hud.vxl.text = "CREATING VIDEO …\nThe replay now plays once from the start.\nPlease wait."
	hud.vxs.visible = false
	hud.vxo.visible = false
	hud.vxd.visible = true
	hud.camrow.visible = false
	hud.rpsave.visible = false
	hud.vxb.visible = false
	hud.rpx.visible = false
	get_tree().create_timer(1.8, true, false, true).timeout.connect(_vx_begin)


func _vx_begin() -> void:
	if not vx.has("p"):
		return
	if not vx.p.begin(VX_W, VX_H, int(VX_FPS), 9000000):
		hud.vxl.text = "Video could not be started.\n" + str(vx.p.error())
		hud.vxo.visible = true
		return
	# Replay von vorn, ohne Anzeige, ohne Ton
	var fix = rp.get("fix", -1)
	for k in ["shots", "mines", "walls", "swalls"]:
		for n in rp.get(k, []):
			n.queue_free()
	rp = {"t": 0.0, "i": 0, "ei": -1, "ci": maxi(0, fix), "ct": 0.0, "sp": null, "sk": 1.0, "fix": fix, "fyaw": 0.6, "fpitch": 0.45, "fdist": 7.0, "follow": 0}
	hud.vxd.visible = false
	hud.layer.visible = false
	ui.fps.visible = false
	AudioServer.set_bus_mute(0, true)
	vx.on = true
	vx.last = Time.get_ticks_usec()
	RenderingServer.frame_post_draw.connect(_vx_capture)


func _vx_capture() -> void:
	if not vx.get("on", false):
		return
	var img = get_viewport().get_texture().get_image()
	if img == null:
		return
	img.convert(Image.FORMAT_RGBA8)
	img.resize(VX_W, VX_H, Image.INTERPOLATE_BILINEAR)
	vx.p.addFrame(img.get_data())
	vx.n += 1
	# Partikel und Zeitgeber laufen mit der echten Zeit: so anpassen, dass pro Bild genau 1/30 s vergeht
	var now = Time.get_ticks_usec()
	var real = maxf(0.001, (now - vx.last) / 1000000.0)
	vx.last = now
	Engine.time_scale = clampf((1.0 / VX_FPS) / real, 0.02, 4.0)


func _vx_finish() -> void:
	vx.on = false
	if RenderingServer.frame_post_draw.is_connected(_vx_capture):
		RenderingServer.frame_post_draw.disconnect(_vx_capture)
	Engine.time_scale = 1.0
	AudioServer.set_bus_mute(0, false)
	hud.layer.visible = true
	var uri = str(vx.p.finish())
	vx.uri = uri
	if uri != "":
		hud.vxl.text = "VIDEO SAVED ✓\nGallery › Movies › AntiGrav\n(%d s)" % int(round(vx.n / VX_FPS))
		hud.vxs.visible = true
	else:
		hud.vxl.text = "Saving the video failed.\n" + str(vx.p.error())
		hud.vxs.visible = false
	hud.vxo.visible = true
	hud.vxd.visible = true


func _vx_close() -> void:
	hud.vxd.visible = false
	var was_err = vx.get("err", false)
	vx = {}
	if was_err:
		return
	_replay_end()


func _rp_next() -> void:
	rp.ci = (rp.ci + 1) % (RP_CAMS.size() - 1)   # die freie Kamera gibt es nur per Knopf
	rp.ct = 0.0
	rp.sp = null


func _rp_cam(dt: float) -> bool:
	if rp.is_empty():
		return false
	var cm = RP_CAMS[rp.ci][0]
	if cm == "chase":
		return false
	var g: Dictionary = _focus()
	var f = T.frame(g.z)
	var S0: Vector3 = f.c + f.rr * g.lat + f.uu * (0.16 + g.h)
	if cm == "free":
		# frei drehbare Kamera um deinen Gleiter (zwei Finger: drehen, auseinander/zusammen: zoomen)
		var back: Vector3 = (-f.fw).rotated(Vector3.UP, rp.fyaw)
		var dir: Vector3 = (back * cos(rp.fpitch) + Vector3.UP * sin(rp.fpitch)).normalized()
		cam.global_position = S0 + dir * rp.fdist
		cam.look_at(S0 + Vector3.UP * 0.2, Vector3.UP)
		cam.fov = 55.0
		return true
	var nd: Node3D = g.node
	var SF: Vector3 = nd.global_transform.basis.z.normalized()
	var SU: Vector3 = nd.global_transform.basis.y.normalized()
	var ro: Vector3
	var ta: Vector3
	var up = Vector3.UP
	if cm == "side":
		if rp.sp == null:
			rp.sk = -rp.sk
			rp.sp = g.z + 20.0 + randf() * 8.0
		var inT = T.in_tun(T.lz(rp.sp), 2.0)
		ro = T.world(rp.sp, rp.sk * (T.TW * 0.8 if inT else T.TW + 1.5), 1.3 if inT else 0.9)
		ta = S0 + f.fw * 0.6
	elif cm == "cock":
		ro = S0 + SF * 0.3 + SU * 0.2
		ta = S0 + SF * 10.0 + SU * 0.15
		up = SU
	elif cm == "heli":
		ro = S0 - f.fw * 6.0 + Vector3.UP * 6.0 + f.rr * 2.0
		ta = S0 + f.fw * 4.0
	else:
		ro = S0 + f.fw * 6.5 + f.uu * 1.0 + f.rr * 0.9
		ta = S0 + f.uu * 0.15
	shake = maxf(0.0, shake - dt * 1.8)
	if flash_rect != null and flash_rect.color.a > 0.0:
		flash_rect.color.a = maxf(0.0, flash_rect.color.a - dt * 2.2)
	cam.global_position = ro
	cam.look_at(ta, up)
	cam.fov = 52.0 if cm != "side" else 38.0
	return true


# ---------------------------------------------------------------- Vorwärmen: jeden Effekt einmal hinter einem schwarzen Bild zeigen,
# damit das Handy die Grafik-Programme schon beim Start übersetzt und nicht mitten im Rennen (das war der große Ruckler)
var warm = false
var warm_t = 0.0
var warm_before = []
var warm_cover: CanvasLayer


# nach dem Umstellen der Grafikstufe neu vorwärmen (andere Kantenglättung = neue Grafik-Programme)
func _rewarm() -> void:
	if warm_t >= 0.0:
		return
	warm_t = 0.0
	warm_before = []
	warm_cover = null


func _warm_step(delta: float) -> void:
	if warm_cover == null:
		warm_cover = CanvasLayer.new()
		warm_cover.layer = 20
		var r = ColorRect.new()
		r.color = Color(0, 0, 0, 1)
		r.set_anchors_preset(Control.PRESET_FULL_RECT)
		warm_cover.add_child(r)
		var l = _lbl("LOADING", 34)
		l.set_anchors_preset(Control.PRESET_FULL_RECT)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.modulate = Color(1, 1, 1, 0.5)
		warm_cover.add_child(l)
		add_child(warm_cover)
		_ld_show(0.4)
		return
	warm_t += delta
	_ld_set(0.4 + 0.6 * clampf(warm_t / 0.9, 0.0, 1.0))
	if warm_before.is_empty():
		warm_before = get_children()
		warm = true
		var g: Dictionary = ships[0]
		var o: Dictionary = ships[1]
		var zf = g.z + 1.5
		_explode(zf, g.lat, true)
		_explode(zf, g.lat + 0.6, false)
		_gbomb(zf, g.lat - 0.6, -2)
		_quake_make(zf + 4.0, 1.0, null)
		var fa0 = fx_age
		fx_age = 0.6 * float(fx.gb.time)
		_gbomb(zf + 1.0, g.lat, -2)
		fx_age = fa0
		var w = _wall_node()
		_wall_pose(w, zf, 1.0, 1.0)
		var w2 = _wall_node(true)
		_wall_pose(w2, zf + 0.5, 1.0, 1.0)
		_zap_ship(g)
		g.shield = 1.0
		_shield_vis(g)
		g.orbs = 1.0
		_orbs_update(0.0, false)
		_drop_mines(g)
		_add_shot(g, false, false)
		warm = false
		return
	# ein paar Bilder lang aktualisieren, damit alles wirklich gezeichnet wird
	_fx_update(delta)
	if warm_t < 0.7:
		return
	var g2: Dictionary = ships[0]
	for n in get_children():
		if not warm_before.has(n) and n != warm_cover and not tun_l.has(n) and not nlights.has(n):
			n.queue_free()
	for e in zaps:
		e.mi.queue_free()
		e.l.queue_free()
	zaps.clear()
	fxs.clear()
	shots.clear()
	mines.clear()
	g2.shield = 0.0
	_shield_vis(g2)
	g2.orbs = 0.0
	_orbs_update(0.0, false)
	orb_n.clear()
	shake = 0.0
	big_t = 0.0
	pf.ev = {}
	live_bursts = 0
	warm_cover.queue_free()
	warm_t = -1.0
	_ld_hide()
	if state == "menu":
		_race_snap()


# ---------------------------------------------------------------- Kill-Cam: Zeitlupe, wenn du einen Gegner erledigst – erst seitlich bis zum Treffer,
# dann zwei Perspektiven auf die Explosion
var kc = {}
var kc_pending = {}


# Kill-Cam: spult ca. 2 s zurück und zeigt den Gegner in Zeitlupe bis zum Knall.
# Kamera je nach Waffe: Rakete von vorn (man sieht sie anfliegen), Mine von hinten, sonst von der Seite.
func _kc_check() -> void:
	if kc_pending.is_empty() or not kc.is_empty():
		return
	if state != "race" or ships[0].out:
		kc_pending = {}
		return
	if rec_clk >= kc_pending.t0 + 1.0:
		_kc_start()


func _kc_start() -> void:
	var t0: float = kc_pending.t0
	var F = rec
	var ts = t0 - 2.0
	var i = 0
	while i < F.size() - 2 and F[i + 1].t <= ts:
		i += 1
	if F.size() < 10:
		kc_pending = {}
		return
	var saved = []
	for o in ships:
		saved.append({"z": o.z, "lat": o.lat, "h": o.h, "psi": o.psi, "roll": o.roll, "boost": o.boost, "spd": o.spd, "shield": o.shield, "orbs": o.orbs})
	# laufende Effekte ausblenden (sie laufen unsichtbar weiter)
	var hidden = []
	for n in get_children():
		if (n is GPUParticles3D or n is MeshInstance3D or n is OmniLight3D) and not tun_l.has(n) and n.visible:
			n.visible = false
			hidden.append(n)
	kc = {"t0": t0, "end": t0 + 0.95, "victim": kc_pending.idx, "kind": kc_pending.kind, "saved": saved, "hidden": hidden,
		"before": get_children(), "fxs": fxs.duplicate(), "zaps": zaps.duplicate(), "top": hud.top.text, "side": 1.0 if randf() < 0.5 else -1.0,
		"dpos": Vector3.ZERO, "dz": 0.0, "dlat": 0.0}
	kc_pending = {}
	rp = {"t": F[i].t, "i": i, "ei": i, "ci": 0, "ct": 0.0, "sp": null, "sk": 1.0}
	state = "kill"
	hud.layer.visible = false
	kco.layer.visible = true
	kco.who.text = NAMES[kc.victim].to_upper()
	AudioServer.playback_speed_scale = 0.75


func _kc_step(dt: float) -> void:
	var rel = rp.t - kc.t0
	# Zeitlupe: anfangs etwas schneller, um den Treffer herum ganz langsam
	var rate = 0.6 if rel < -0.6 else (0.28 if rel < 0.4 else 0.5)
	# echte Zeitlupe: auch Partikel und Funken laufen langsamer
	Engine.time_scale = rate
	_replay(dt)
	if state != "kill":
		return
	var v: Dictionary = ships[kc.victim]
	if rp.t <= kc.t0:
		kc.dz = v.z
		kc.dlat = v.lat
	var tt = Time.get_ticks_msec() / 1000.0
	kco.dot.visible = fmod(tt, 1.0) < 0.6
	kco.ts.text = "%s   ×%.2f" % [_fmt(maxf(0.0, rp.t)), rate]
	hud.top.text = kc.top
	if rp.t >= kc.end:
		_kc_end()


func _kc_end() -> void:
	if kc.is_empty():
		return
	# alles zurück auf den Stand des laufenden Rennens
	for k in range(ships.size()):
		var o: Dictionary = ships[k]
		var sv: Dictionary = kc.saved[k]
		for key in sv:
			o[key] = sv[key]
		(o.node as Node3D).visible = not o.out
		_shield_vis(o)
	for k in ["shots", "mines", "walls", "swalls"]:
		for n in rp.get(k, []):
			if is_instance_valid(n):
				n.queue_free()
	rp = {}
	var keep_fx = []
	for e in fxs:
		if kc.fxs.has(e):
			keep_fx.append(e)
	fxs = keep_fx
	var keep_z = []
	for e in zaps:
		if kc.zaps.has(e):
			keep_z.append(e)
		else:
			e.mi.queue_free()
			e.l.queue_free()
	zaps = keep_z
	for n in get_children():
		if not kc.before.has(n) and not tun_l.has(n) and (n is GPUParticles3D or n is MeshInstance3D or n is OmniLight3D):
			n.queue_free()
	for n in kc.hidden:
		if is_instance_valid(n):
			n.visible = true
	if quake == null:
		_rset("qs", 0.0)
	if quake2 == null:
		_rset("qs2", 0.0)
	hud.top.text = kc.top
	var vic: int = kc.victim
	kc = {}
	state = "race"
	if int(cfg.get("comic", 1)) == 1 and vic >= 1 and vic <= 3:
		_comic_start("ko", vic)
	hud.layer.visible = true
	kco.layer.visible = false
	AudioServer.playback_speed_scale = 1.0
	Engine.time_scale = 1.0
	shake = 0.0
	big_t = 0.0


func _kc_cam() -> bool:
	var v: Dictionary = ships[kc.victim]
	var alive = rp.t <= kc.t0
	var z: float = v.z if alive else kc.dz
	var lat: float = v.lat if alive else kc.dlat
	var f = T.frame(z)
	var V: Vector3 = f.c + f.rr * lat + f.uu * (0.25 + (v.h if alive else 0.0))
	var up = Vector3.UP
	var ro: Vector3
	var ta: Vector3
	var sd: float = kc.side
	match kc.kind:
		"rocket":
			# von vorn: man sieht die Rakete von hinten auf den Gegner zufliegen
			ro = V + f.fw * 4.6 + up * 1.0 + f.rr * (1.3 * sd)
			ta = V - f.fw * 1.5
		"mine":
			# von hinten: der Gegner fliegt in die Minen
			ro = V - f.fw * 4.8 + up * 1.3 + f.rr * (0.8 * sd)
			ta = V + f.fw * 2.5
		_:
			ro = V + f.rr * (3.4 * sd) + up * 1.1 - f.fw * 1.2
			ta = V + f.fw * 0.6
	if not alive:
		# nach dem Knall langsam zurückziehen
		var k = clampf((rp.t - kc.t0) / 0.9, 0.0, 1.0)
		ro += (ro - V).normalized() * 3.0 * k + up * 0.8 * k
	cam.global_position = ro
	cam.look_at(ta, up)
	cam.fov = 48.0
	if flash_rect != null and flash_rect.color.a > 0.0:
		flash_rect.color.a = maxf(0.0, flash_rect.color.a - 0.05)
	return true


# Minen-Warnung: „düt, düt, düt“, je näher die gegnerischen Minen vor dir liegen, desto schneller und höher
var mine_bt = 0.0
var en_low = false


func _mine_warn(dt: float, racing: bool) -> void:
	var g: Dictionary = ships[0]
	var best = 999.0
	if racing and not g.out:
		for m in mines:
			if m.get("own", 0) == 0:
				continue
			var dz: float = m.z - g.z
			if dz > 1.0 and dz < 35.0 and absf(m.lat - g.lat) < 1.4 and dz < best:
				best = dz
	if hud.get("mlamp") == null:
		var ml = Control.new()
		ml.anchor_left = 0.5
		ml.anchor_right = 0.5
		ml.offset_left = -150
		ml.offset_right = 150
		ml.offset_top = 150
		ml.offset_bottom = 230
		ml.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ml.draw.connect(func():
			var tt = Time.get_ticks_msec() / 1000.0
			var pu = 0.5 + 0.5 * sin(tt * 12.0)
			var cc = Vector2(46, 40)
			var rc = Color(1.0, 0.12, 0.08)
			ml.draw_circle(cc, 30.0, Color(rc.r, rc.g, rc.b, 0.18 + 0.25 * pu))
			ml.draw_circle(cc, 20.0, Color(rc.r * (0.6 + 0.4 * pu), rc.g, rc.b, 1.0))
			ml.draw_arc(cc, 30.0, 0.0, TAU, 32, Color(1, 0.4, 0.35, 0.8), 2.5, true)
			_wicon(ml, cc, 13.0, "mine", Color(1, 1, 1, 0.9))
			ml.draw_string(ThemeDB.fallback_font, Vector2(88, 52), "MINES AHEAD", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(1.0, 0.35, 0.3, 0.6 + 0.4 * pu)))
		ml.visible = false
		(hud.fire as Control).get_parent().add_child(ml)
		hud.mlamp = ml
	hud.mw.visible = false
	var lamp: Control = hud.mlamp
	if best > 100.0:
		lamp.visible = false
		mine_bt = 0.0
		return
	if not lamp.visible:
		# Lämpchen geht an: kurzes Doppelsignal wie im Cockpit
		_snd("beep", -4.0, 1.7)
		get_tree().create_timer(0.13).timeout.connect(func(): _snd("beep", -4.0, 1.7))
	lamp.visible = true
	lamp.queue_redraw()


# Ergebnistafel nach dem Rennen
var board_t = 0.0
var board_man = -1   # -1 = wechselt von selbst; 0/1 = von Hand gewählt (Ergebnis/Schaden), bleibt dann stehen


func _board_update(dt: float) -> void:
	var show = state == "done" and hud.resb.visible
	hud.board.visible = show
	hud.rdim.visible = show
	hud.ring.visible = not show
	if show:
		hud.fire.visible = false
	if not show:
		board_t = 0.0
		board_man = -1
		return
	board_t += dt
	var dmg_mode = fmod(board_t, 9.0) > 5.0 if board_man < 0 else board_man == 1
	var list = ships.duplicate()
	if dmg_mode:
		hud.boardt.text = "DAMAGE DEALT"
		list.sort_custom(func(a, b): return a.dealt > b.dealt)
	else:
		hud.boardt.text = "RESULTS"
		list.sort_custom(func(a, b):
			var ka = 0 if a.fin > 0.0 else (1 if not a.out else 2)
			var kb = 0 if b.fin > 0.0 else (1 if not b.out else 2)
			if ka != kb:
				return ka < kb
			if ka == 0:
				return a.fin < b.fin
			if ka == 1:
				return a.z > b.z
			return a.outT > b.outT)
	for i in range(list.size()):
		var o: Dictionary = list[i]
		var cols: Array = hud.rows[i]
		cols[0].text = ["1st", "2nd", "3rd", "4th"][i]
		cols[1].text = "YOU" if o.idx == 0 else NAMES[o.idx].to_upper()
		if dmg_mode:
			cols[2].text = "%d %%" % int(round(o.dealt * 100.0))
		elif o.fin > 0.0:
			cols[2].text = _fmt(o.fin)
		elif o.out:
			cols[2].text = "ELIMINATED"
		else:
			cols[2].text = "racing …"
		var c = Color(1, 0.85, 0.4) if o.idx == 0 else (Color(1, 0.45, 0.4) if o.out and not dmg_mode else Color(1, 1, 1))
		for l in cols:
			l.modulate = c


# ---------------------------------------------------------------- Leistungsmessung: Bildzeiten im Rennen, Ruckler mit Umständen
var pf = {"n": 0, "sum": 0.0, "hist": [0, 0, 0, 0, 0], "sec": [], "acc": 0.0, "an": 0, "aw": 0.0, "sp": [], "ev": {},
	"gs": 0.0, "cs": 0.0, "ps": 0.0, "ag": 0.0, "ac": 0.0, "ap": 0.0}
var gpu_ms = 0.0   # Grafikkarte: Zeit fürs letzte Bild (ms)
var measuring = false
var cpu_ms = 0.0   # Prozessor: Spiel-Logik + Zeichenbefehle (ms)
var fps_t = 0.0


# Zeitmessung von Grafikkarte und Prozessor (zeigt, wer bremst)
func _measure(delta: float) -> void:
	# nur messen, wenn FPS-Anzeige, Leistungsbericht oder Leistungstest es brauchen
	var need = int(cfg.fps) == 1 or int(cfg.perf) == 1 or state == "bench"
	var rid = get_viewport().get_viewport_rid()
	if need != measuring:
		measuring = need
		RenderingServer.viewport_set_measure_render_time(rid, need)
	if not need:
		return
	gpu_ms = RenderingServer.viewport_get_measured_render_time_gpu(rid)
	cpu_ms = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0 + RenderingServer.viewport_get_measured_render_time_cpu(rid) + RenderingServer.get_frame_setup_time_cpu()
	fps_t -= delta
	if fps_t <= 0.0:
		fps_t = 0.5
		ui.fps.text = "%d fps · gpu %.1f · cpu %.1f ms" % [Engine.get_frames_per_second(), gpu_ms, cpu_ms]


func _pev(k: String) -> void:
	pf.ev[k] = race_t


func _perf_ctx() -> String:
	var g: Dictionary = ships[0]
	var gb = 0
	var ex = 0
	for e in fxs:
		if e.get("gb", false):
			gb += 1
		else:
			ex += 1
	var rec_ev2 = []
	for k in pf.ev:
		var a = race_t - float(pf.ev[k])
		if a < 2.5:
			rec_ev2.append("%s %.1fs" % [k, a])
	var c = "z%d fx%d hole%d part%d shot%d mine%d wall%d zap%d" % [int(T.lz(g.z)), ex, gb, live_bursts, shots.size(), mines.size(), walls.size(), zaps.size()]
	if quake != null:
		c += " quake"
	if tun_k > 0.5:
		c += " tunnel"
	if g.boost > 0.5:
		c += " boost"
	if g.shield > 0.0:
		c += " shield"
	if g.orbs > 0.0:
		c += " orbs"
	c += " dc%d" % int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	c += " tri%dk" % int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0)
	if not rec_ev2.is_empty():
		c += " | " + ", ".join(rec_ev2)
	return c


func _perf(delta: float) -> void:
	if state != "race" or int(cfg.perf) != 1:
		return
	var ms = delta / maxf(0.01, Engine.time_scale) * 1000.0
	pf.n += 1
	pf.sum += ms
	var b = 0 if ms < 18.0 else (1 if ms < 25.0 else (2 if ms < 34.0 else (3 if ms < 50.0 else 4)))
	pf.hist[b] += 1
	pf.acc += delta
	pf.an += 1
	pf.aw = maxf(pf.aw, ms)
	pf.gs += gpu_ms
	pf.cs += cpu_ms
	pf.ps += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	pf.ag += gpu_ms
	pf.ac += cpu_ms
	if pf.acc >= 1.0:
		pf.sec.append("%5.1f  %3d fps  worst %3d ms  gpu %4.1f  cpu %4.1f  %s" % [race_t, int(round(pf.an / pf.acc)), int(pf.aw), pf.ag / pf.an, pf.ac / pf.an, _perf_ctx()])
		pf.acc = 0.0
		pf.an = 0
		pf.aw = 0.0
		pf.ag = 0.0
		pf.ac = 0.0
	if ms > maxf(45.0, 2.0 * pf.sum / pf.n):
		pf.sp.append([ms, "%5.1f  %3d ms  %s" % [race_t, int(ms), _perf_ctx()]])
		if pf.sp.size() > 40:
			pf.sp.sort_custom(func(a, c): return a[0] > c[0])
			pf.sp.resize(30)


func _perf_text() -> String:
	var vp = get_viewport()
	var sz = vp.get_visible_rect().size
	var ws = DisplayServer.window_get_size()
	var t = "AntiGrav 3D performance\n"
	t += "Device: %s · %s · renderer %s\n" % [OS.get_model_name(), RenderingServer.get_video_adapter_name(), str(ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile" if OS.has_feature("mobile") else "rendering/renderer/rendering_method"))]
	t += "Screen %dx%d (ui %dx%d) · 3D scale %.2f · gfx %s · res %d %% · look %s · speed %d %%\n" % [ws.x, ws.y, sz.x, sz.y, vp.scaling_3d_scale,
		["Low", "Medium", "High"][int(cfg.gfx)], int(float(cfg.res) * 100), "Noir" if _noir() else "Color", int(float(cfg.speed) * 100)]
	if pf.n > 0:
		var h: Array = pf.hist
		t += "Frames %d · avg %.1f ms (%.0f fps)\n" % [pf.n, pf.sum / pf.n, 1000.0 / (pf.sum / pf.n)]
		t += "Frame times: <18ms %d · 18-25 %d · 25-34 %d · 34-50 %d · >50 %d\n" % [h[0], h[1], h[2], h[3], h[4]]
		t += "Average GPU %.1f ms · CPU %.1f ms (game logic %.1f ms) · refresh %d Hz · fps cap %d\n" % [pf.gs / pf.n, pf.cs / pf.n, pf.ps / pf.n,
			maxi(0, int(DisplayServer.screen_get_refresh_rate())), Engine.max_fps]
		var E: Dictionary = fx.env
		var C: Dictionary = fx.city
		t += "FX: wet %.2f · gloss %.2f · neon light %.2f · fog %.2f · lamps %.2f · holo %.2f · signs %.2f · haze %.2f\n" % [float(E.wet), float(E.gloss), float(E.nlight), float(E.fog), float(E.lamps), float(C.holo), float(C.signs), float(fx.haze.amp)]
	t += "\nWorst hitches (time, ms, situation):\n"
	var sp: Array = pf.sp.duplicate()
	sp.sort_custom(func(a, c): return a[0] > c[0])
	for i in range(mini(20, sp.size())):
		t += sp[i][1] + "\n"
	t += "\nPer second (time, fps, worst frame, situation):\n"
	for l in pf.sec:
		t += l + "\n"
	return t


# ---------------------------------------------------------------- Fahrphysik (wie HTML-Version: Nase lenken, Flugrichtung folgt mit begrenzter Haftung)
func _phys(s: Dictionary, inp: float, is_p: bool, dt: float, racing: bool) -> void:
	if state == "intro" or state == "count" or state == "menu":
		s.u = 0.0
		s.psi = 0.0
		s.vpsi = 0.0
		s.roll = 0.0
		return
	var z: float = s.z
	s.u += (inp - s.u) * (1.0 - exp(-dt / (0.03 * float(fx.ship.steer) if is_p else 0.08)))
	var turn: float = T.kap(z) * s.spd
	var SH: Dictionary = fx.ship
	var yk = YAW_P * float(SH.steerk) if is_p else YAW_AI
	if is_p:
		# bei hohem Tempo sanfter lenken, sonst schießt das Schiff zur Seite
		# geglättetes Tempo: beim Boost-Feld wird die Lenkung fließend weicher, nie schlagartig
		s.sps = lerpf(float(s.get("sps", s.spd)), s.spd, 1.0 - exp(-dt / 0.5))
		yk /= 1.0 + float(SH.get("spdst", 0.25)) * maxf(0.0, float(s.sps) / maxf(1.0, base_spd) - 0.8)
	s.psi = clampf(s.psi + (s.u * yk + turn) * dt, -0.9, 0.9)
	if is_p and not s.air:
		# Auto-center: ohne Lenken dreht sich die Nase wieder in Fahrtrichtung
		var ce = float(SH.get("center", 1.0)) * 4.0 * (1.0 - clampf(absf(s.u) * 1.6, 0.0, 1.0))
		s.psi -= s.psi * (1.0 - exp(-dt * ce))
	var grip = 0.8 if s.air else (9.5 if is_p else 7.0)
	if is_p and not s.air:
		# Grip: wie fest das Schiff in der Spur bleibt; Drift: beim Einlenken rutscht es seitlich weiter (Nase zeigt in die Kurve)
		grip *= float(SH.grip) / (1.0 + float(SH.drift) * absf(s.u) * 1.5)
	s.vpsi = clampf(s.vpsi + ((s.psi - s.vpsi) * grip + turn) * dt, -0.9, 0.9)
	var ap = is_p and (s.auto > 0.0 or state == "done" or state == "replay") and not s.out
	if ap:
		# Autopilot wie im alten Spiel: ruhig auf die Mittellinie gleiten, dann schnurgerade, nichts bremst ihn
		s.u = 0.0
		var dl = (0.0 - s.lat) * (1.0 - exp(-dt / 1.4))
		s.vpsi = atan2(dl / maxf(dt, 1e-4), maxf(1.0, s.spd))
		s.psi += (s.vpsi - s.psi) * (1.0 - exp(-dt / 0.15))
		s.slow = 1.0
		s.slowT = 0.0
	if is_p and not ap and not s.out and int(cfg.get("ctrl", 1)) >= 2 and (racing or state == "count"):
		# Gleit-Modus: das Schiff fährt die Kurven selbst und gleitet zur Spur, die der Daumen vorgibt;
		# loslassen = zurück zur Mitte. Kurven und Boost ziehen etwas nach außen, die Ränder federn ab.
		var SG: Dictionary = fx.steer
		var lim = T.TW - 0.35
		var pull = clampf(T.kap(z) * maxf(1.0, s.spd) * 6.0, -1.0, 1.0) * float(SG.gpull) * lim * 0.25   # nur Kurven, Boost zieht nicht extra
		var tgt = clampf(glide_in * float(SG.gwidth) * lim + pull, -lim, lim)
		if int(cfg.get("ctrl", 1)) == 4:
			tgt = lane_cur * LANE_W
		if int(cfg.get("ctrl", 1)) == 5:
			# Spur antippen: fester Zeitplan – ganz außen nach ganz außen dauert „ltime“ Sekunden, egal wie schnell du fährst.
			# Kurz anfahren, gleichmäßig rüber, weich einrasten; die Nase zeigt nur leicht in die Richtung.
			tgt = lane_cur * LANE_W
			var lt = maxf(0.08, float(SG.get("ltime", 0.35)))
			# schneller als Reisetempo (Boost-Feld): Wechsel entsprechend flotter, damit er auf der Strecke gleich kurz wirkt
			# (sonst braucht er bei 1,6-fachem Tempo 60 % mehr Strecke – das fühlt sich verzögert an)
			lt /= 1.0 + 0.6 * clampf(float(s.boost), 0.0, 1.5)
			var vmax = 2.0 * LANE_W / lt * 1.25
			var amax = vmax / (0.18 * lt)
			var d = tgt - s.lat
			var des = clampf(d * vmax / (LANE_W * 0.35), -vmax, vmax)
			var lv = float(s.get("lv", 0.0))
			lv += clampf(des - lv, -amax * dt, amax * dt)
			if absf(d) < 0.004 and absf(lv) < 0.05:
				lv = 0.0
			s.lv = lv
			var spd0 = maxf(0.01, s.spd)
			s.vpsi = asin(clampf(lv / spd0, -0.3, 0.3))   # Nase: höchstens ~17° in die Wechselrichtung
			s.lat += (lv - s.spd * sin(s.vpsi)) * dt      # den Rest schiebt das Schwebefeld direkt seitlich
			s.psi += (s.vpsi - s.psi) * (1.0 - exp(-dt / 0.08))
			s.u = clampf(lv / vmax * 1.6, -1.0, 1.0)
		else:
			var tau = maxf(0.05, float(SG.glide))   # beim Boost genauso flink wie sonst
			var dl = (tgt - s.lat) * (1.0 - exp(-dt / tau))
			var want = atan2(dl / maxf(dt, 1e-4), maxf(1.0, s.spd))
			s.vpsi = clampf(want, -0.6, 0.6)
			s.psi += (s.vpsi - s.psi) * (1.0 - exp(-dt / 0.12))
			s.u = clampf((tgt - s.lat) * 1.2, -1.0, 1.0)
	s.slow += (1.0 - s.slow) * (1.0 - exp(-dt / 1.4))
	s.boost *= exp(-dt / 1.4)
	if s.out:
		s.spd = 0.0
		return
	if s.slowT > 0.0:
		s.slowT -= dt
	s.spd = base_spd * s.sk * (1.0 + 0.6 * s.boost) * s.slow * (0.75 if s.slowT > 0.0 else 1.0) if racing or state == "done" else 0.0
	if T.S and is_p:
		s.spd *= stt_spd
	if is_p and not fin.is_empty() and fin.get("fly", false):
		# Siegerrunde: sanft ausrollen und schwebend stehen bleiben (für die Kamerafahrt)
		s.ro = float(s.get("ro", 1.0)) * exp(-dt * 1.4)
		s.spd *= s.ro
		s.boost = 0.0
	var fwd: float = s.spd * cos(s.vpsi)
	s.z += fwd * dt
	s.lat += s.spd * sin(s.vpsi) * dt
	# Sprung: über der Lücke fliegt er, Schwerkraft holt ihn zurück (Weite begrenzt)
	if not s.air and T.gap(s.z):
		s.air = true
		s.h = 0.45
		var tf = maxf(8.5 / maxf(1.0, fwd), 0.6)  # flacher, gut sichtbarer Sprung, kurze Flugzeit
		s.vy = (2.0 * tf * tf - s.h) / tf
	# über die Leitplanke hinaus geflogen: sofort mittig über der Strecke neu erscheinen (mit Glitch),
	# aus etwa Force-field-Höhe fallen lassen, auf dem Antigrav-Polster abfedern – kostet nur gut eine Sekunde
	if s.air and absf(s.lat) > T.TW + 0.15 and not s.out:
		s.lat = 0.0
		s.psi = 0.0
		s.vpsi = 0.0
		s.u = 0.0
		s.h = 1.5
		s.vy = 0.0
		s.drop = 1
		s.rsT = 0.45
		s.slow = minf(s.slow, 0.55)
		s.boost = 0.0
		if is_p:
			_snd("phase", 0.0, 1.3)
			_flash(Color(0.5, 0.9, 1.0), 0.18)
		_zap_ship(s)
	if s.get("rsT", 0.0) > 0.0:
		# Glitch beim Erscheinen: Schiff flackert ein paar Mal
		s.rsT -= dt
		var vis_on = s.rsT <= 0.0 or fmod(s.rsT, 0.09) > 0.035
		if (s.node as Node3D).visible != vis_on:
			(s.node as Node3D).visible = vis_on
	if s.air:
		var drp = int(s.get("drop", 0))
		s.vy -= (14.0 if drp > 0 else 4.0) * dt
		s.h += s.vy * dt
		if s.h <= 0.0 and not T.gap(s.z):
			if is_p and s.vy < -1.2:
				_snd("land")
			if drp > 0 and drp < 3 and s.vy < -0.6:
				# Antigrav-Polster federt: kleiner werdende Hüpfer
				s.h = 0.0
				s.vy = -s.vy * (0.42 if drp == 1 else 0.3)
				s.drop = drp + 1
				if is_p:
					shake = maxf(shake, 0.35 / drp)
			else:
				s.h = 0.0
				s.air = false
				s.vy = 0.0
				s.drop = 0
				if not ap:
					s.slow = minf(s.slow, 0.9)
	# Leitplanke: weich parallel ausrichten, etwas bremsen
	var ml = T.TW - 0.3
	if absf(s.lat) > ml and not s.air:
		s.lat = signf(s.lat) * ml
		s.psi -= s.psi * minf(1.0, dt * 6.0)
		s.vpsi -= s.vpsi * minf(1.0, dt * 6.0)
		if s.shield > 0.0 and racing:
			# Schild schluckt den Stoß: kein Bremsen, kein Kratzen – nur kurzes Aufleuchten
			if race_t - s.hitT > 0.45:
				s.hitT = race_t
				_shield_ping(s)
		elif race_t - s.hitT > 0.45 and racing:
			s.hitT = race_t
			s.slow = minf(s.slow, 0.65)
			if is_p:
				_snd("zap", -2.0, randf_range(0.9, 1.1))
	# Boost-Feld
	var k = int(round(s.z / 35.0))
	var fz = (s.z - _bzp(k)) / 35.0
	if fz >= 0.0 and fz < 0.08 and _pad_ok(_bzp(k)) and not s.air and absf(s.lat - _bpx(k)) < PAD_HW and k != s.padK and racing:
		s.padK = k
		s.boost = 1.0
		if is_p:
			_snd("boost", -3.0)


# Gegner fahren ruhig: eigene Spur, sanft zur Kurvenaußenseite (Boost-Felder), Regler auf Wunsch-Querbewegung statt Pendeln
func _ai_inp(o: Dictionary, t: float, dt: float) -> float:
	var zz: float = o.z
	var spd = maxf(1.0, o.spd)
	var d2 = T.d2px(zz + 14.0)
	var tg = o.lane + signf(d2) * minf(0.5, absf(d2) * 45.0)
	o.tl += (tg - o.tl) * (1.0 - exp(-dt / 1.2))
	var turn: float = T.kap(zz) * spd
	var vd = clampf((o.tl - o.lat) / 0.9, -3.0, 3.0)
	var vdes = asin(clampf(vd / spd, -0.3, 0.3))
	var pdes = vdes - turn / 7.0 + (vdes - o.vpsi) * 0.5
	return clampf((6.0 * (pdes - o.psi) - turn) / YAW_AI, -1.0, 1.0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if get_tree().paused:
			# Zurück im Pausemenü = weiterfahren – aber nicht die zweite Meldung desselben Tastendrucks,
			# die direkt nach dem Öffnen der Pause kommt (sonst geht die Pause sofort wieder zu)
			if Time.get_ticks_msec() / 1000.0 - back_t >= 0.25:
				back_t = Time.get_ticks_msec() / 1000.0
				_pause(false)
			return
		_go_back()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		# App verlassen (Anruf, Home-Taste): mitten im Rennen automatisch anhalten
		if state in ["intro", "count", "race"] and fin.is_empty() and kc.is_empty():
			_pause(true)


var back_t = -10.0
var back_q = -10.0


func _toast(t: String) -> void:
	# dunkle Sprechblase, volle Breite mit Rand, Text bricht um – ragt nie aus dem Bild und bleibt lesbar
	var pc = PanelContainer.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.03, 0.06, 0.92)
	sb.border_color = Color(1, 1, 1, 0.25)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(18)
	sb.set_content_margin_all(18)
	pc.add_theme_stylebox_override("panel", sb)
	pc.anchor_left = 0.06
	pc.anchor_right = 0.94
	pc.anchor_top = 0.34
	pc.anchor_bottom = 0.34
	pc.grow_vertical = Control.GROW_DIRECTION_BOTH
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l = _lbl(t, 30)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pc.add_child(l)
	var cl = CanvasLayer.new()
	cl.layer = 30
	cl.add_child(pc)
	add_child(cl)
	get_tree().create_timer(2.0).timeout.connect(cl.queue_free)


# Android-Zurück: Menüs schließen, aus Rennen/Labor ins Hauptmenü; im Hauptmenü erst beim zweiten Mal beenden
func _go_back() -> void:
	var now = Time.get_ticks_msec() / 1000.0
	if now - back_t < 0.25:
		return   # Taste und Systemmeldung kommen manchmal doppelt
	back_t = now
	if ui.has("namep") and is_instance_valid(ui.namep):
		ui.named.call()   # Zurück = Name übernehmen, Rekord geht nicht verloren
		return
	if true:
		if state == "menu":
			if ui.setp.visible:
				_show_settings(false)
			elif ui.has("recp") and is_instance_valid(ui.recp):
				_show_records(false)
			elif ui.has("helpp") and is_instance_valid(ui.helpp):
				_show_help(false)
			elif ui.has("rpl") and is_instance_valid(ui.rpl) and (ui.rpl as Control).visible:
				_show_replays(false)
			elif now - back_q < 2.0:
				get_tree().quit()
			else:
				back_q = now
				_toast("Press back again to quit")
		elif state == "replay":
			_replay_end()
		elif state == "kill":
			_kc_end()
		elif state == "lab":
			_lab_close()
		elif state in ["intro", "count", "race"] and fin.is_empty():
			_pause(true)
		else:
			_to_menu()


# ---------------------------------------------------------------- Leistungstest: feste Szene, jeder Effekt einmal aus
# Gleiche Stelle, gleiche Kamera – nur ein Schalter ändert sich je Abschnitt. So sieht man genau, was die Grafikkarte kostet.
var bench = {}
const BENCH = [["base", "Everything on (your settings)"], ["msaa", "Edge smoothing (MSAA) off"], ["res75", "Resolution 75 %"], ["fsr", "Resolution 75 % + FSR sharpening"],
	["shadow", "Moon shadows off"], ["glow", "Glow off"], ["post", "Screen filter off"], ["haze", "Heat shimmer off"], ["nlight", "Neon reflections off"],
	["lamps", "Track lamps off"], ["jets", "Plasma jets off"], ["city", "Holograms/signs/cars off"], ["sky", "Sky shader off"], ["wet", "Wet road off/on"], ["base2", "Everything on again"]]


func _bench_begin() -> void:
	_start()
	state = "bench"
	hud.mid.text = ""
	bench = {"i": -1, "t": 0.0, "res": [], "fx": JSON.parse_string(JSON.stringify(fx)), "nosh": false}
	_bench_next()


func _bench_undo() -> void:
	fx = JSON.parse_string(JSON.stringify(bench.fx))
	bench.nosh = false
	_apply_cfg()
	_env_apply()
	_city_apply()
	get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	wenv.glow_enabled = true
	wenv.background_mode = Environment.BG_SKY
	if post_rect != null:
		post_rect.visible = true


func _bench_next() -> void:
	_bench_undo()
	bench.i += 1
	bench.t = 0.0
	bench.g = 0.0
	bench.f = 0.0
	bench.n = 0
	if bench.i >= BENCH.size():
		_bench_end()
		return
	var k: String = BENCH[bench.i][0]
	var vp = get_viewport()
	match k:
		"msaa":
			vp.msaa_3d = Viewport.MSAA_DISABLED
		"res75":
			vp.scaling_3d_scale = vp.scaling_3d_scale * 0.75
		"fsr":
			vp.scaling_3d_scale = vp.scaling_3d_scale * 0.75
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
		"shadow":
			bench.nosh = true
		"glow":
			wenv.glow_enabled = false
		"post":
			post_rect.visible = false
		"haze":
			fx.haze.amp = 0.0
		"nlight":
			fx.env.nlight = 0.0
		"lamps":
			fx.env.lamps = 0.0
			for b in lights_nodes:
				b.visible = false
		"jets":
			fx.haze.jglow = 0.0
		"city":
			for c in ["holo", "signs", "search", "cars"]:
				fx.city[c] = 0.0
			_city_apply()
		"sky":
			wenv.background_mode = Environment.BG_COLOR
			wenv.background_color = Color(0.01, 0.01, 0.03)
		"wet":
			fx.env.wet = 0.0 if float(fx.env.wet) > 0.01 else 1.0
			_wet_apply()
	hud.mid.add_theme_font_size_override("font_size", 40)
	hud.mid.text = "PERFORMANCE TEST %d/%d\n%s" % [bench.i + 1, BENCH.size(), BENCH[bench.i][1]]


func _bench_step(dt: float) -> void:
	# feste Szene: offenes Stück mit Stadt, Hologramm und drei Gegnern vor dir
	var g: Dictionary = ships[0]
	g.z = 300.0
	g.lat = 0.3
	g.spd = base_spd
	g.boost = 0.0
	for i in range(1, ships.size()):
		var o: Dictionary = ships[i]
		o.z = g.z + 5.0 + i * 4.0
		o.lat = [-1.0, 0.9, -0.2][i - 1]
		o.spd = base_spd
		o.boost = 0.5 if i == 2 else 0.0
		(o.node as Node3D).visible = true
	_lap_pos(g.z)
	_tunnel(dt)
	_pose_all(dt)
	_camera(dt)
	_post_update(dt)
	_resb_arm(dt)
	if bench.i < 0 or bench.i >= BENCH.size():
		return
	bench.t += dt
	if bench.t > 0.8:
		bench.g += gpu_ms
		bench.f += get_process_delta_time() * 1000.0
		bench.n += 1
	if bench.t > 2.8:
		bench.res.append([BENCH[bench.i][1], bench.g / maxf(1, bench.n), bench.f / maxf(1, bench.n)])
		_bench_next()


func _bench_end() -> void:
	var t = "AntiGrav 3D performance test\n"
	t += "Device: %s · %s · Godot %s\n" % [OS.get_model_name(), RenderingServer.get_video_adapter_name(), Engine.get_version_info().string]
	t += "Settings: gfx %s · res %d %% · 3D scale %.2f · fps cap %s · refresh %d Hz\n\n" % [["Low", "Medium", "High"][int(cfg.gfx)], int(float(cfg.res) * 100),
		get_viewport().scaling_3d_scale, "60" if int(cfg.cap) == 1 else "max", maxi(0, int(DisplayServer.screen_get_refresh_rate()))]
	t += "GPU ms · frame ms · test\n"
	var b0 = bench.res[0][1] if not bench.res.is_empty() else 0.0
	for r in bench.res:
		t += "%5.1f · %5.1f · %s  (%+.1f)\n" % [r[1], r[2], r[0], r[1] - b0]
	DisplayServer.clipboard_set(t)
	bench.txt = t
	hud.mid.add_theme_font_size_override("font_size", 22)
	hud.mid.text = "Performance test done – result copied.\nPaste it in the chat.\n\n" + t
	_show_resb()
	if OS.get_cmdline_user_args().has("--bench"):
		print(t)
		await get_tree().create_timer(0.5).timeout
		get_viewport().get_texture().get_image().save_png("user://bench.png")
		get_tree().quit()


# ---------------------------------------------------------------- Bestenliste: schnellste Runde, schnellste Gesamtzeit, meister Schaden – je Tempo-Stufe
const REC_PATH = "user://records.cfg"


func _rec_key() -> String:
	return "speed%d" % int(round(float(cfg.speed) * 100.0))


const REC_N = 5   # Plätze je Liste
const REC_CATS = [["lap", "Fastest lap"], ["total", "Fastest race"], ["dmg", "Most damage"]]


# Liste lesen: [[Wert, Name], …] – alte Einzelwerte werden übernommen
func _rec_list(c: ConfigFile, k: String, cat: String) -> Array:
	var v = c.get_value(k, cat, [])
	if v is float or v is int:
		return [[float(v), "—"]] if float(v) > 0.0 else []
	return v if v is Array else []


func _rec_better(cat: String, a: float, b: float) -> bool:
	return a > b if cat == "dmg" else a < b


func _rec_fmt(cat: String, v: float) -> String:
	return ("%d %%" % int(round(v * 100.0))) if cat == "dmg" else _fmt(v)


# Rennende: was schafft es in die Bestenliste? Dann Namen eintragen lassen (wie am Spielautomaten)
func _records_end(finished: bool) -> void:
	var g: Dictionary = ships[0]
	var vals = {}
	if float(g.get("bestlap", 0.0)) > 0.0:
		vals.lap = float(g.bestlap)
	if finished:
		vals.total = race_t
	if float(g.dealt) > 0.0:
		vals.dmg = float(g.dealt)
	var c = ConfigFile.new()
	c.load(REC_PATH)
	var k = _rec_key()
	var hits = []
	for cat in vals:
		var lst = _rec_list(c, k, cat)
		var rank = lst.size()
		for i in range(lst.size()):
			if _rec_better(cat, vals[cat], float(lst[i][0])):
				rank = i
				break
		if rank < REC_N:
			hits.append([cat, vals[cat], rank])
	if hits.is_empty():
		return
	hud.res.text += "\nNEW RECORD!"
	_snd("pick", 0.0, 1.5)
	get_tree().create_timer(1.2).timeout.connect(func(): _name_entry(hits))


func _name_entry(hits: Array) -> void:
	var cl = CanvasLayer.new()
	cl.layer = 14
	add_child(cl)
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.78)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP   # Knöpfe darunter sind gesperrt
	cl.add_child(bg)
	var vb = VBoxContainer.new()
	vb.anchor_left = 0.08
	vb.anchor_right = 0.92
	vb.anchor_top = 0.08
	vb.anchor_bottom = 0.6
	vb.add_theme_constant_override("separation", 16)
	cl.add_child(vb)
	var t = _lbl("NEW RECORD", 52)
	t.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	vb.add_child(t)
	for h in hits:
		var nm = {"lap": "Fastest lap", "total": "Fastest race", "dmg": "Most damage"}[h[0]]
		var l = _lbl("%s   %s   ·   #%d" % [nm, _rec_fmt(h[0], h[1]), int(h[2]) + 1], 30)
		vb.add_child(l)
	vb.add_child(_lbl("Your name:", 30))
	var le = LineEdit.new()
	le.text = str(cfg.get("pname", ""))
	le.placeholder_text = "Name"
	le.max_length = 14
	le.alignment = HORIZONTAL_ALIGNMENT_CENTER
	le.add_theme_font_size_override("font_size", 44)
	le.custom_minimum_size = Vector2(0, 100)
	le.select_all_on_focus = true
	vb.add_child(le)
	var ok = _btn("SAVE", true)
	vb.add_child(ok)
	var done = func():
		var nm2 = le.text.strip_edges()
		if nm2 == "":
			nm2 = "Player"
		cfg.pname = nm2
		_save_cfg()
		var c = ConfigFile.new()
		c.load(REC_PATH)
		var k = _rec_key()
		for h in hits:
			var lst = _rec_list(c, k, h[0])
			lst.append([h[1], nm2])
			var cat: String = h[0]
			lst.sort_custom(func(a, b): return _rec_better(cat, float(a[0]), float(b[0])))
			if lst.size() > REC_N:
				lst.resize(REC_N)
			c.set_value(k, cat, lst)
		c.save(REC_PATH)
		DisplayServer.virtual_keyboard_hide()
		cl.queue_free()
	ui.namep = cl
	ui.named = done
	ok.pressed.connect(done)
	le.text_submitted.connect(func(_t): done.call())
	le.grab_focus.call_deferred()


func _show_records(on: bool) -> void:
	if ui.has("recp"):
		if is_instance_valid(ui.recp):
			ui.recp.queue_free()
		ui.erase("recp")
	if not on:
		return
	var cl = CanvasLayer.new()
	cl.layer = 12
	add_child(cl)
	ui.recp = cl
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.88)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	cl.add_child(bg)
	var vb = VBoxContainer.new()
	vb.anchor_left = 0.06
	vb.anchor_right = 0.94
	vb.anchor_top = 0.06
	vb.anchor_bottom = 0.94
	vb.add_theme_constant_override("separation", 12)
	cl.add_child(vb)
	vb.add_child(_lbl("RECORDS", 48))
	var sc = ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)
	var lst = VBoxContainer.new()
	lst.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lst.add_theme_constant_override("separation", 6)
	sc.add_child(lst)
	var c = ConfigFile.new()
	c.load(REC_PATH)
	var secs = Array(c.get_sections())
	secs.sort_custom(func(a, b): return int(a.substr(5)) < int(b.substr(5)))
	# aktuelle Tempo-Stufe zuerst
	if secs.has(_rec_key()):
		secs.erase(_rec_key())
		secs.push_front(_rec_key())
	if secs.is_empty():
		lst.add_child(_lbl("No records yet – go race!", 28))
	for k in secs:
		var hd = _lbl("Speed %d %%" % int(k.substr(5)), 34)
		hd.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4) if k == _rec_key() else Color(0.75, 0.85, 1.0))
		lst.add_child(hd)
		for ct in REC_CATS:
			var rows = _rec_list(c, k, ct[0])
			if rows.is_empty():
				continue
			var ch = _lbl(ct[1], 26)
			ch.modulate = Color(1, 1, 1, 0.6)
			lst.add_child(ch)
			for i in range(rows.size()):
				var row = HBoxContainer.new()
				var a = _lbl("%d.  %s" % [i + 1, str(rows[i][1])], 28)
				a.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
				a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				row.add_child(a)
				var b = _lbl(_rec_fmt(ct[0], float(rows[i][0])), 28)
				b.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
				row.add_child(b)
				lst.add_child(row)
		lst.add_child(_lbl(" ", 16))
	var bb = _btn("Back", true)
	bb.pressed.connect(func(): _show_records(false))
	vb.add_child(bb)


# Sieg: großes, leuchtendes VICTORY, springt auf und pulsiert
func _victory() -> void:
	var cl = CanvasLayer.new()
	cl.layer = 8
	cl.set_meta("rfx", true)   # beim Neustart wegräumen
	add_child(cl)
	var l = Label.new()
	l.text = "VICTORY"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 132)
	var gold = OR if _noir() else Color(1.0, 0.86, 0.35)
	l.add_theme_color_override("font_color", Color(1, 1, 1))
	l.add_theme_color_override("font_outline_color", gold)
	l.add_theme_constant_override("outline_size", 14)
	l.add_theme_color_override("font_shadow_color", Color(gold.r, gold.g, gold.b, 0.6))
	l.add_theme_constant_override("shadow_outline_size", 40)
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 0)
	l.anchor_right = 1.0
	l.anchor_top = 0.2
	l.anchor_bottom = 0.2
	l.offset_top = -90
	l.offset_bottom = 90
	cl.add_child(l)
	l.pivot_offset = Vector2(get_viewport().get_visible_rect().size.x * 0.5, 90)
	l.scale = Vector2(0.2, 0.2)
	l.modulate.a = 0.0
	var tw = l.create_tween()
	tw.tween_property(l, "scale", Vector2(1.18, 1.18), 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "modulate:a", 1.0, 0.2)
	tw.tween_property(l, "scale", Vector2(1.0, 1.0), 0.25)
	var tp = l.create_tween().set_loops()
	tp.tween_property(l, "modulate", Color(1.25, 1.2, 1.0, 1.0), 0.6).set_delay(0.6)
	tp.tween_property(l, "modulate", Color(1, 1, 1, 1), 0.6)
	_flash(Color(1.0, 0.9, 0.6), 0.5)


# Rundenkopien (hinter/unter/vor dir) zur Stelle z schieben – nur wenn sich die Runde ändert
func _lap_pos(z: float) -> void:
	var l0 = int(floor((z - 20.0) / T.LAP))
	for i in range(laps.size()):
		var p = Vector3(0, 0, (l0 - 1 + i) * T.LAP)
		if laps[i].position != p:
			laps[i].position = p


func _process(delta: float) -> void:
	var dt = minf(delta, 0.05)
	if flash_rect != null and flash_rect.visible and flash_rect.color.a <= 0.003:
		flash_rect.visible = false   # unsichtbare Vollbild-Fläche nicht jedes Bild zeichnen
	t_state += dt
	_measure(delta)
	_live_poll(dt)
	_duck(delta / maxf(0.01, Engine.time_scale))
	_perf(delta)
	var g: Dictionary = ships[0]
	if warm_t >= 0.0:
		_warm_step(delta)
	if state == "menu" and bench_req and warm_t < 0.0:
		bench_req = false
		_bench_begin()
	if state == "bench":
		_bench_step(dt)
		return
	if state == "menu" and restart and warm_t < 0.0 and rpf.is_empty():
		restart = false
		_start()
	if state == "menu" and not rpf.is_empty() and warm_t < 0.0:
		rec = rpf.rec
		ui.root.visible = false
		hud.layer.visible = true
		hud.res.text = rpf.get("res", "")
		_replay_start()
	if state == "menu":
		menu_t += dt
		_lap_pos(g.z)
		_tunnel(dt)
		_pose_all(dt)
		var f = T.frame(g.z)
		var S0: Vector3 = f.c + f.rr * g.lat + f.uu * 0.16
		var a = menu_t * 0.25
		cam.global_position = S0 + f.fw * cos(a) * 3.4 + f.rr * sin(a) * 3.4 + Vector3.UP * (0.9 + 0.25 * sin(a * 1.7))
		cam.look_at(S0 + Vector3.UP * 0.1, Vector3.UP)
		cam.fov = 52.0
		_sound_update(dt)
		_post_update(dt)
		_shot()
		return
	if state == "lab":
		_lab_step(dt)
		return
	if state == "kill":
		_kc_step(dt)
		if state == "kill":
			_lap_pos(g.z)
			_tunnel(dt)
			_pose_all(dt)
			_camera(dt)
			_post_update(dt)
			_shot()
			return
	if state == "replay":
		if vx.get("on", false):
			dt = 1.0 / VX_FPS
			_replay(dt)
		elif vx.is_empty():
			var hold = rp.get("paused", false) or rp.get("scrub", false)
			_replay(0.0 if hold else dt)
			if not rp.is_empty():
				if rp.get("dirty", false) and Time.get_ticks_msec() - rp.get("rbt", 0) > 250:
					_rp_rebuild_fx()
				_rp_freeze(hold)
		if state == "replay":
			_lap_pos(_focus().z)
			_tunnel(dt)
			_pose_all(dt)
			_camera(dt)
			_sound_update(dt)
			_post_update(dt)
			_shot()
			return
	var racing = state == "race"
	_fin_update(dt)
	if not cm.is_empty():
		_comic_update(dt)
		if state == "intro":
			t_state = 0.0   # Vorbeiflug wartet, bis der Comic durch ist
	if state == "intro" and t_state > INTRO_T:
		state = "count"
		t_state = 0.0
	elif state == "count":
		var c = 3 - int(floor(t_state))
		if c != last_c:
			_start_step(c, last_c == 99)
			last_c = c
		hud.mid.text = str(c) if c > 0 else "GO"
		if c <= 0:
			state = "race"
			t_state = 0.0
	if state == "race" and t_state > 0.7 and hud.mid.text == "GO":
		hud.mid.text = ""
	if racing or state == "done":
		race_t += dt
	# Lenkung mit Anlaufkurve
	var swm = int(cfg.get("ctrl", 1)) >= 1 and (state == "race" or state == "count")
	var b = _steer_input()
	if swm and not (Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_RIGHT)):
		b = 0
	# Eingabe-Verzögerung (FX Lab „Steering“): es zählt, was vor „delay“ Sekunden gedrückt war
	var now = Time.get_ticks_msec() / 1000.0
	var SD: Dictionary = fx.steer
	var dly = float(SD.delay)
	st_hist.append([now, b])
	while st_hist.size() > 2 and float(st_hist[1][0]) <= now - dly:
		st_hist.pop_front()
	if dly > 0.001:
		b = int(st_hist[0][1]) if float(st_hist[0][0]) <= now - dly else 0
	if b != steer_btn:
		if steer_btn != 0 and b == 0:
			rel_v = last_steer
			rel_t = 0.0
		steer_btn = b
		btn_t = 0.0
	btn_t += dt
	var steer = 0.0
	# Lenkkurven (am PC auf der Live-Seite einstellbar): Drücken = Kraft über die Haltedauer, Loslassen = Nachwirken
	if b != 0:
		steer = b * _curve_at("press", btn_t / maxf(0.05, float(SD.ptime)))
	else:
		rel_t += dt
		var rt = float(SD.rtime)
		if rt > 0.001 and rel_t < rt:
			steer = rel_v * _curve_at("release", rel_t / rt)
	if swm and b == 0:
		var sws = _sw_steer(dt)
		if sws != null:
			steer = sws
			steer_btn = int(signf(steer)) if absf(steer) > 0.01 else 0
	if int(cfg.get("ctrl", 1)) >= 3 and state != "done":
		steer = ptr_lat
		steer_btn = 0
		if int(cfg.get("ctrl", 1)) == 5:
			if not lt_hold.is_empty():
				if not touches.has(int(lt_hold.i)):
					lt_hold = {}
				else:
					lt_hold.t = float(lt_hold.t) + dt
					if float(lt_hold.t) >= maxf(0.05, float(fx.steer.get("lhold", 0.25))):
						lt_hold.t = 0.0
						_lane_step(int(lt_hold.dir))
			steer = float(lane_cur)
			lane_fl = maxf(0.0, lane_fl - dt * 3.0)
			if hud.has("lanei"):
				(hud.lanei as Control).queue_redraw()
		if int(cfg.get("ctrl", 1)) == 4:
			# Spur-Modus: der unsichtbare Zeiger wählt die nächste der drei Spuren (mit etwas Spiel gegen Hin- und Herspringen)
			var want = clampi(int(roundf(ptr_lat)), -1, 1)
			if want != lane_cur and absf(ptr_lat - lane_cur) > 0.62:
				lane_cur = want
				lane_fl = 1.0
				if float(fx.steer.vib) > 0.5:
					Input.vibrate_handheld(22)
				_lane_beep()
			steer = float(lane_cur)
			lane_fl = maxf(0.0, lane_fl - dt * 3.0)
			if hud.has("lanei"):
				(hud.lanei as Control).queue_redraw()
	last_steer = steer
	glide_in = clampf(steer, -1.0, 1.0)
	if T.S:
		_stt_update(dt)
	_steer_glow(dt, steer)
	if state == "done":
		steer = clampf(-g.lat * 0.6 - g.vpsi * 2.0, -1.0, 1.0)
	var n = maxi(1, int(ceil(dt / 0.0125)))
	var hdt = dt / n
	var tt = Time.get_ticks_msec() / 1000.0
	if g.auto > 0.0:
		steer = 0.0
		g.auto -= dt
		# Autopilot geht nur auf gerader Strecke aus: in Kurven oder im Sprung hält er noch
		g.ahold = g.auto <= 0.05 and (g.air or _curvy(g.z))
		if g.ahold:
			g.auto = 0.05
		if g.get("sauto", false):
			g.boost = maxf(g.boost, 1.3)
			for o in ships:
				if o.idx != 0 and not o.out and absf(o.z - g.z) < 1.7 and absf(o.lat - g.lat) < 0.8 and race_t - o.get("ramT", -9.0) > 0.8:
					o.ramT = race_t
					var away = signf(o.lat - g.lat) if o.lat != g.lat else 1.0
					if not _prot(o):
						o.lat = clampf(o.lat + away * 0.9, -T.TW + 0.3, T.TW - 0.3)
						o.vpsi += away * 0.3
						o.slow = minf(o.slow, 0.5)
					_dmg(o, 0.15, 0, "ram")
					_zap_ship(o)
					_snd("zap", 2.0, 0.8, (o.node as Node3D).global_position)
					shake = maxf(shake, 0.6)
		if g.auto <= 0.0:
			g.sauto = false
	if g.turbo > 0.0:
		g.turbo -= dt
		g.boost = maxf(g.boost, 1.5)
	g.shield = maxf(0.0, g.shield - dt)
	g.mshield = maxf(0.0, float(g.get("mshield", 0.0)) - dt)
	for k in range(n):
		_phys(g, steer, true, hdt, racing)
	for i in range(1, ships.size()):
		var o: Dictionary = ships[i]
		if o.out:
			continue
		var inp = _ai_inp(o, tt, dt)
		_ai_weapons(o, dt, racing)
		for k in range(n):
			_phys(o, inp, false, hdt, racing)
		# Gummiband, ganz sanft: wer hinten liegt, holt höchstens 8 % auf; wer weit vorn ist, lässt höchstens 4 % nach
		var dz: float = o.z - g.z
		var st: float = o.sk0
		if racing:
			if dz < -4.0:
				st = o.sk0 * (1.0 + minf(0.08, (-dz - 4.0) * 0.0022))
			elif dz > 18.0:
				st = o.sk0 * (1.0 - minf(0.04, (dz - 18.0) * 0.0013))
		o.sk += (st - o.sk) * (1.0 - exp(-dt / 1.8))
		# Vorbeiflug-Zischen
		var pd = o.get("pdz", dz)
		if racing and signf(pd) != signf(dz) and absf(o.lat - g.lat) < 2.4 and race_t - o.get("psT", -9.0) > 1.5:
			o.psT = race_t
			_snd("pass", -2.0, 1.0, (o.node as Node3D).global_position)
		o.pdz = dz
		# Rempeln
		if absf(dz) < 1.4 and absf(o.lat - g.lat) < 0.4 and racing and not g.air and not o.air and g.auto <= 0.0:
			var pu = signf(g.lat - o.lat) if g.lat != o.lat else 1.0
			g.lat += pu * 0.6 * dt * 6.0
			o.lat -= pu * 0.6 * dt * 6.0
		var fin = T.ZST + T.LAPS * T.LAP
		if o.z >= fin and o.fin == 0.0 and (racing or state == "done"):
			o.fin = race_t
	# Rundenzeiten (für die Bestenliste)
	if racing:
		var lk = int(floor((g.z - T.ZST) / T.LAP))
		if lk >= 1 and lk > int(g.get("lapk", 0)):
			var lt = race_t - float(g.get("lapT", 0.0))
			g.lapk = lk
			g.lapT = race_t
			if lt > 1.0 and (g.get("bestlap", 0.0) == 0.0 or lt < g.bestlap):
				g.bestlap = lt
	# Ziel
	var finish = T.ZST + T.LAPS * T.LAP
	var place = 1
	for i in range(1, ships.size()):
		if ships[i].z > g.z and not ships[i].out:
			place += 1
	_weapons(dt, racing)
	_mine_warn(dt, racing)
	if racing and g.out:
		state = "done"
		t_state = 0.0
		hud.res.text = ""   # die große rote Meldung und die Tabelle zeigen es schon
		_fin_flow(4, true)
		_records_end(false)
	elif racing and kc_pending.is_empty() and _all_out():
		state = "done"
		t_state = 0.0
		g.fin = race_t
		_snd("win")
		hud.res.text = "1st  ·  LAST ONE STANDING\n%s" % _fmt(race_t)
		_fin_flow(1)
		_records_end(false)
	elif racing and g.z >= finish and not free_ride:
		state = "done"
		t_state = 0.0
		g.fin = race_t
		_snd("win")
		hud.res.text = "%s  ·  %s" % [["1st", "2nd", "3rd", "4th"][place - 1], _fmt(race_t)]
		_fin_flow(place)
		_records_end(true)
	_board_update(dt)
	_resb_arm(dt)
	var lap = clampi(int(floor((g.z - T.ZST) / T.LAP)) + 1, 1, T.LAPS)
	if state != "done" or t_state < 0.1:
		hud.top.text = _fmt(race_t)
		var prog = clampf((g.z - T.ZST) / (T.LAPS * T.LAP), 0.0, 1.0) * T.LAPS
		for k in range(T.LAPS):
			var fl: ColorRect = hud.pgf[k][0]
			fl.size.x = hud.pgf[k][1] * clampf(prog - k, 0.0, 1.0)
		var alive = 1
		for i in range(1, ships.size()):
			if not ships[i].out:
				alive += 1
		if place != last_place and last_place > 0 and racing:
			pl_flash = 1.0
			pl_col = Color(0.35, 1.0, 0.5) if place < last_place else Color(1.0, 0.35, 0.3)
		last_place = place
		hud.pl.text = ["1st", "2nd", "3rd", "4th"][clampi(place - 1, 0, 3)]
		hud.pln.text = "/%d" % alive
	pl_flash = maxf(0.0, pl_flash - dt * 1.3)
	hud.pl.modulate = Color(1, 1, 1).lerp(pl_col, pl_flash)
	hud.plbox.scale = Vector2.ONE * (1.0 + 0.18 * pl_flash)
	hud.plbox.pivot_offset = hud.plbox.size
	_record(dt)
	_kc_check()
	# Rundenkopien mitwandern lassen
	_lap_pos(g.z)
	_tunnel(dt)
	_pose_all(dt)
	_camera(dt)
	_sound_update(dt)
	_post_update(dt)
	_shot()


# ---------------------------------------------------------------- FX Lab: Teststrecke für alle Effekte, mit Reglern
const LZ = 40.0
const VOICE_LAB_URL = "https://claude.ai/artifact/E8ePfMb2RbvnrVhn1Q1HeD"
var lab = {}


func _lab_open() -> void:
	state = "lab"
	t_state = 0.0
	ui.root.visible = false
	hud.layer.visible = false
	var g: Dictionary = ships[0]
	g.z = LZ
	g.lat = 0.0
	g.psi = 0.0
	g.vpsi = 0.0
	g.spd = 0.0
	g.boost = 0.0
	for i in range(1, ships.size()):
		ships[i].z = LZ - 120.0
		(ships[i].node as Node3D).visible = false
	_lap_pos(20.0)
	lab = {"rep": {}, "fine": 1.0, "tab": "boom", "auto": false, "at": 0.0, "yaw": 0.35, "pit": 0.22, "dist": 12.0, "tch": {}, "sv": -1.0, "view": 0}
	var cl = CanvasLayer.new()
	cl.layer = 6
	add_child(cl)
	lab.cl = cl
	var pn = _pillar_node()
	var pf = T.frame(LZ + 5.0)
	pn.transform = Transform3D(Basis(pf.rr, pf.uu, pf.fw), pf.c + pf.uu * 1.1)
	pn.visible = false
	add_child(pn)
	lab.pn = pn
	var root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(root)
	var tl = _lbl("FX LAB", 40)
	tl.set_anchors_preset(Control.PRESET_TOP_WIDE)
	tl.offset_top = 50
	tl.add_theme_color_override("font_color", Color(0.75, 0.95, 1.0))
	root.add_child(tl)
	var hint = _lbl("drag = rotate  ·  pinch = zoom\nfine tuning: hold a knob, slide finger up/down", 19)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.set_anchors_preset(Control.PRESET_TOP_WIDE)
	hint.offset_top = 104
	hint.modulate = Color(1, 1, 1, 0.8)
	hint.add_theme_constant_override("outline_size", 7)
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	tl.add_theme_constant_override("outline_size", 8)
	tl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	root.add_child(hint)
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.62)
	bg.anchor_right = 1.0
	bg.anchor_top = 0.5
	bg.anchor_bottom = 1.0
	root.add_child(bg)
	var vb = VBoxContainer.new()
	vb.anchor_left = 0.04
	vb.anchor_right = 0.96
	vb.anchor_top = 0.5
	vb.anchor_bottom = 1.0
	vb.offset_top = 16
	vb.offset_bottom = -28
	vb.add_theme_constant_override("separation", 12)
	root.add_child(vb)
	var grid = GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	vb.add_child(grid)
	lab.tabs = {}
	for t in FXT:
		var b = _btn(t[1])
		b.add_theme_font_size_override("font_size", 21)
		b.custom_minimum_size = Vector2(0, 66)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var key: String = t[0]
		b.pressed.connect(func(): _lab_tab(key))
		grid.add_child(b)
		lab.tabs[key] = b
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	vb.add_child(row)
	var bf = _btn("FIRE", true)
	bf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bf.size_flags_stretch_ratio = 2.0
	bf.custom_minimum_size = Vector2(0, 96)
	bf.pressed.connect(_lab_fire)
	row.add_child(bf)
	lab.fire = bf
	var ba = _btn("Auto")
	ba.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ba.custom_minimum_size = Vector2(0, 96)
	ba.add_theme_font_size_override("font_size", 30)
	ba.pressed.connect(func():
		lab.auto = not lab.auto
		lab.at = 0.0
		_lab_style())
	row.add_child(ba)
	lab.ab = ba
	var bsu = _btn("Super")
	bsu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bsu.custom_minimum_size = Vector2(0, 96)
	bsu.add_theme_font_size_override("font_size", 28)
	bsu.pressed.connect(func():
		lab.sup = not lab.get("sup", false)
		_lab_style())
	row.add_child(bsu)
	lab.sb = bsu
	var bv = _btn("View")
	bv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bv.custom_minimum_size = Vector2(0, 96)
	bv.add_theme_font_size_override("font_size", 30)
	bv.pressed.connect(_lab_view)
	row.add_child(bv)
	var sc = ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	sc.mouse_filter = Control.MOUSE_FILTER_IGNORE   # Wischen in der Liste übernimmt _lab_input
	vb.add_child(sc)
	# breite Scrollleiste rechts, bequem mit dem Daumen zu schieben
	var vsb: VScrollBar = sc.get_v_scroll_bar()
	vsb.custom_minimum_size = Vector2(46, 0)
	var trk = StyleBoxFlat.new()
	trk.bg_color = Color(1, 1, 1, 0.08)
	trk.set_corner_radius_all(14)
	trk.content_margin_left = 6
	trk.content_margin_right = 6
	vsb.add_theme_stylebox_override("scroll", trk)
	vsb.add_theme_stylebox_override("scroll_focus", trk)
	for sk in ["grabber", "grabber_highlight", "grabber_pressed"]:
		var gb = StyleBoxFlat.new()
		gb.bg_color = Color(0.93, 0.41, 0.18, 0.85 if sk == "grabber" else 1.0)
		gb.set_corner_radius_all(14)
		gb.content_margin_left = 16
		gb.content_margin_right = 16
		vsb.add_theme_stylebox_override(sk, gb)
	# Abstand rechts, damit kein Reglerknopf unter der Scrollleiste verschwindet
	var mc = MarginContainer.new()
	mc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mc.add_theme_constant_override("margin_right", 60)
	sc.add_child(mc)
	lab.lstc = mc
	var lst = VBoxContainer.new()
	lst.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lst.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lst.add_theme_constant_override("separation", 2)
	mc.add_child(lst)
	lab.lst = lst
	lab.sc = sc
	var row2 = HBoxContainer.new()
	row2.add_theme_constant_override("separation", 10)
	vb.add_child(row2)
	var br = _btn("Reset")
	br.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	br.custom_minimum_size = Vector2(0, 84)
	br.add_theme_font_size_override("font_size", 30)
	br.pressed.connect(_lab_reset)
	row2.add_child(br)
	var bc = _btn("Copy settings")
	bc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bc.size_flags_stretch_ratio = 1.4
	bc.custom_minimum_size = Vector2(0, 84)
	bc.add_theme_font_size_override("font_size", 22)
	bc.pressed.connect(_lab_copy)
	row2.add_child(bc)
	lab.cb = bc
	var bvl = _btn("Voice Lab")
	bvl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bvl.size_flags_stretch_ratio = 1.3
	bvl.custom_minimum_size = Vector2(0, 84)
	bvl.add_theme_font_size_override("font_size", 22)
	bvl.pressed.connect(func(): OS.shell_open(VOICE_LAB_URL))
	row2.add_child(bvl)
	var bb = _btn("Done", true)
	bb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bb.custom_minimum_size = Vector2(0, 84)
	bb.add_theme_font_size_override("font_size", 30)
	bb.pressed.connect(_lab_close)
	row2.add_child(bb)
	_lab_tab("boom")


# alle Werte als Text in die Zwischenablage – zum Einfügen im Chat, damit sie fest ins Spiel kommen
func _lab_copy() -> void:
	_fx_save()
	var ch = {}
	for gk in FXS:
		for it in FXS[gk]:
			var v = float(fx[gk][it[0]])
			if absf(v - float(it[4])) > 0.0001:
				if not ch.has(gk):
					ch[gk] = {}
				ch[gk][it[0]] = snappedf(v, 0.01)
	DisplayServer.clipboard_set("ANTIGRAV FX " + JSON.stringify(ch))
	lab.cb.text = "Copied ✓"
	get_tree().create_timer(2.0).timeout.connect(func():
		if is_instance_valid(lab.get("cb")):
			lab.cb.text = "Copy settings")


func _lab_grp(t: String) -> String:
	if t in ["shield", "orbs", "haze"]:
		return "near"
	if t in ["env", "jungle"]:
		return "wide"   # weit über die Strecke bis zum Horizont: Himmel, Berge, Nebel, Bäume
	if t == "city":
		return "city"
	if t in ["ship", "pillar"]:
		return t
	return "fx"


# Schiff zurück an die Teststelle (nach dem Fahren im Reiter „Ship“)
func _lab_park() -> void:
	var g: Dictionary = ships[0]
	g.z = LZ
	g.lat = 0.0
	g.psi = 0.0
	g.vpsi = 0.0
	g.u = 0.0
	g.spd = 0.0
	g.air = false
	g.h = 0.0
	g.vy = 0.0
	_lap_pos(20.0)


func _lab_close() -> void:
	_fx_save()
	_reload()


func _lab_style() -> void:
	for k in lab.tabs:
		var on = k == lab.tab
		var st = _style(Color(0.93, 0.41, 0.18) if on else Color(1, 1, 1, 0.08), Color(1, 0.7, 0.54) if on else Color(1, 1, 1, 0.22))
		st.content_margin_top = 8
		st.content_margin_bottom = 8
		for sk in ["normal", "pressed", "hover", "focus"]:
			lab.tabs[k].add_theme_stylebox_override(sk, st)
	var sa = _style(Color(0.2, 0.75, 0.45) if lab.auto else Color(1, 1, 1, 0.08), Color(0.6, 1, 0.75) if lab.auto else Color(1, 1, 1, 0.22))
	for sk in ["normal", "pressed", "hover", "focus"]:
		lab.ab.add_theme_stylebox_override(sk, sa)
	var son = lab.get("sup", false)
	var ss = _style(Color(0.9, 0.68, 0.12) if son else Color(1, 1, 1, 0.08), Color(1, 0.88, 0.5) if son else Color(1, 1, 1, 0.22))
	if lab.has("sb"):
		for sk in ["normal", "pressed", "hover", "focus"]:
			lab.sb.add_theme_stylebox_override(sk, ss)
	lab.fire.disabled = lab.tab in ["env", "pillar", "city"]
	lab.fire.modulate.a = 0.35 if lab.fire.disabled else 1.0
	lab.fire.text = "BOOST" if lab.tab in ["haze", "ship"] else ("PLAY" if lab.tab == "sound" else "FIRE")


func _lab_val(it: Array, v: float) -> String:
	var k: String = it[0]
	if k.begins_with("hue"):
		return "%+d°" % int(round(v * 360.0))
	if k == "life":
		return "%d s" % int(round(v))
	if k == "city":
		return "On" if v > 0.5 else "Off"
	if k == "shape":
		return LK_SHAPES[clampi(int(round(v)), 0, LK_SHAPES.size() - 1)]
	if k == "time":
		return "%.1f s" % (1.3 * v)
	if k in ["ptime", "rtime", "delay"]:
		return "%.2f s" % v
	return "%d %%" % int(round(v * 100.0)) if v >= 0.995 or v == 0.0 else "%.1f %%" % (v * 100.0)


func _lab_tab(t: String) -> void:
	if lab.has("tab") and _lab_grp(lab.tab) != _lab_grp(t):
		var V = {"near": [0.35, 0.22, 5.5], "ship": [0.55, 0.2, 6.0], "pillar": [0.45, 0.12, 6.5], "city": [0.25, 0.08, 80.0], "wide": [0.0, 0.06, 14.0]}.get(_lab_grp(t), [0.35, 0.22, 12.0])
		lab.yaw = V[0]
		lab.pit = V[1]
		lab.dist = V[2]
		if lab.tab == "ship":
			_lab_park()
		if t == "ship":
			var g: Dictionary = ships[0]
			g.lane = 0.0
			g.tl = 0.0
			g.sk = 1.0
			g.slow = 1.0
	if lab.has("pn"):
		lab.pn.visible = t == "pillar"
	lab.tab = t
	lab.sls = []
	lab.grab = {}
	lab.rep = {}
	for c in lab.lst.get_children():
		c.queue_free()
	for it in FXS[t]:
		var key: String = it[0]
		var lb = Label.new()
		lb.add_theme_font_size_override("font_size", 26)
		lb.custom_minimum_size = Vector2(0, 44)
		lb.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # lange Reglernamen brechen um statt das Labor aus dem Bild zu schieben
		lab.lst.add_child(lb)
		var hs = HSlider.new()
		hs.min_value = it[2]
		hs.max_value = it[3]
		hs.step = 1.0 if key in ["city", "life", "shape"] else 0.001
		hs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hs.value = float(fx[t][key])
		hs.custom_minimum_size = Vector2(0, 60)
		hs.add_theme_icon_override("grabber", _dot(40))
		hs.add_theme_icon_override("grabber_highlight", _dot(46))
		var tsb = StyleBoxFlat.new()
		tsb.bg_color = Color(1, 1, 1, 0.25)
		tsb.content_margin_top = 6
		tsb.content_margin_bottom = 6
		tsb.set_corner_radius_all(6)
		hs.add_theme_stylebox_override("slider", tsb)
		hs.mouse_filter = Control.MOUSE_FILTER_IGNORE   # nur der Knopf selbst lässt sich ziehen (siehe _lab_input)
		lab.sls.append(hs)
		var upd = func(v: float):
			fx[t][key] = v
			lb.text = "%s   %s" % [it[1], _lab_val(it, v)] + ("   · fine ×%d" % int(round(1.0 / lab.fine)) if lab.fine < 0.75 else "")
			lab.sv = 0.6
			if t == "env":
				if key in ["city", "dens", "bh", "bw", "bd"]:
					_city_fill()
				_env_apply()
			if t == "pillar":
				_pillar_apply()
			if t == "jungle":
				_jungle_apply()
			if t == "ship":
				_nav_apply()
			if t == "city":
				if key == "mega":
					_city_fill()
				_city_apply()
			if t == "sound":
				_start_bus_apply()
				lab.sndre = 0.45   # kurz nach dem Loslassen probehören
		hs.value_changed.connect(upd)
		lb.text = "%s   %s" % [it[1], _lab_val(it, hs.value)]
		# − Regler +  (kleine Schritte; gedrückt halten wiederholt)
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var stp = 1.0 if key in ["city", "life", "shape"] else (0.005 if key.contains("hue") else 0.05)
		for sd in [-1, 1]:
			var pb = _btn("−" if sd < 0 else "+")
			pb.custom_minimum_size = Vector2(68, 60)
			pb.add_theme_font_size_override("font_size", 34)
			var pst = _style(Color(1, 1, 1, 0.08), Color(1, 1, 1, 0.22))
			pst.content_margin_top = 0
			pst.content_margin_bottom = 0
			pst.set_corner_radius_all(14)
			for sk in ["normal", "hover", "focus"]:
				pb.add_theme_stylebox_override(sk, pst)
			var dd = sd * stp
			# erst beim Loslassen zählen (wer über den Knopf scrollt, verstellt nichts); gedrückt halten = wiederholen
			pb.button_down.connect(func(): lab.rep = {"hs": hs, "d": dd, "t": 0.45, "n": 0})
			pb.button_up.connect(func():
				if not lab.rep.is_empty() and lab.rep.n == 0:
					hs.value = hs.value + dd
				lab.rep = {})
			if sd < 0:
				row.add_child(pb)
				row.add_child(hs)
			else:
				row.add_child(pb)
		lab.lst.add_child(row)
	lab.sc.scroll_vertical = 0
	_lab_style()


func _lab_reset() -> void:
	var t: String = lab.tab
	for it in FXS[t]:
		fx[t][it[0]] = it[4]
	if t == "env" or t == "city":
		_city_fill()
		_env_apply()
	if t == "sound":
		_start_bus_apply()
	_pillar_apply()
	lab.sv = 0.1
	_lab_tab(t)


func _lab_view() -> void:
	lab.view = (lab.view + 1) % 4
	var V = [[0.35, 0.22, 12.0], [1.45, 0.12, 11.0], [0.3, 0.7, 40.0], [-2.7, 0.18, 13.0]][lab.view]
	lab.yaw = V[0]
	lab.pit = V[1]
	lab.dist = V[2]


func _lab_fire() -> void:
	var g: Dictionary = ships[0]
	g.sup = lab.get("sup", false)
	match lab.tab:
		"boom":
			_explode(LZ + 6.0, 0.0, true)
		"mine":
			_drop_mines(g, g.sup)
		"quake":
			g.wpn = "beben"
			_fire()
		"gb":
			_gbomb(LZ + 9.0, 0.0, 0)
		"rak":
			_add_shot(g, false, false, 1.0, g.sup)
		"wall":
			g.wpn = "wand"
			_fire()
		"shield":
			g.wpn = "schild"
			_fire()
		"orbs":
			g.wpn = "orbs"
			_fire()
		"haze", "ship":
			g.boost = 2.5
			_snd("boost")
		"sound":
			_start_play(false)


# Mittelpunkt des Reglerknopfs (x, Bildschirm)
func _knob_x(hs: HSlider) -> float:
	var r = hs.get_global_rect()
	var gw = 40.0
	var u = (hs.value - hs.min_value) / maxf(0.0001, hs.max_value - hs.min_value)
	return r.position.x + gw * 0.5 + u * (r.size.x - gw)


func _lab_list(ev: InputEvent) -> bool:
	var sr: Rect2 = lab.sc.get_global_rect()
	var vsb: VScrollBar = lab.sc.get_v_scroll_bar()
	if ev is InputEventScreenTouch:
		if ev.pressed:
			if not sr.has_point(ev.position) or (vsb.visible and vsb.get_global_rect().grow(6).has_point(ev.position)):
				return false
			# Knopf getroffen? Dann wird nur dieser Regler gezogen, sonst wird gescrollt
			for hs in lab.sls:
				var r: Rect2 = hs.get_global_rect().grow_individual(0, 14, 0, 14)
				var kx = _knob_x(hs)
				if r.has_point(ev.position) and absf(ev.position.x - kx) < 48.0:
					lab.grab[ev.index] = {"hs": hs, "v": hs.value, "cy": hs.get_global_rect().get_center().y}
					hs.add_theme_icon_override("grabber", _dot(52))
					return true
			lab.grab[ev.index] = {"scroll": true, "sy": float(lab.sc.scroll_vertical), "mv": 0.0}
			return true
		elif lab.grab.has(ev.index):
			var gd = lab.grab[ev.index]
			if gd.has("hs") and is_instance_valid(gd.hs):
				gd.hs.add_theme_icon_override("grabber", _dot(40))
				lab.fine = 1.0
			lab.grab.erase(ev.index)
			return true
	elif ev is InputEventScreenDrag and lab.grab.has(ev.index):
		var gd = lab.grab[ev.index]
		if gd.has("hs"):
			var hs: HSlider = gd.hs
			if is_instance_valid(hs):
				var r = hs.get_global_rect()
				var off = maxf(0.0, absf(ev.position.y - gd.cy) - 45.0)
				var sens = 1.0 / (1.0 + off / 45.0)
				gd.v = clampf(gd.v + ev.relative.x / maxf(1.0, r.size.x - 40.0) * (hs.max_value - hs.min_value) * sens, hs.min_value, hs.max_value)
				hs.value = gd.v
				lab.fine = sens
		else:
			gd.mv += absf(ev.relative.y)
			if gd.mv > 10.0:
				lab.rep = {}   # beim Scrollen über einen ±-Knopf nicht weiterzählen
			gd.sy -= ev.relative.y
			gd.sy = clampf(gd.sy, 0.0, maxf(0.0, lab.lstc.size.y - sr.size.y))
			lab.sc.scroll_vertical = int(gd.sy)
		return true
	return false


func _lab_input(ev: InputEvent) -> void:
	if _lab_list(ev):
		return
	var top = get_viewport().get_visible_rect().size.y * 0.5
	if ev is InputEventScreenTouch:
		if ev.pressed and ev.position.y < top:
			lab.tch[ev.index] = ev.position
		elif not ev.pressed:
			lab.tch.erase(ev.index)
	elif ev is InputEventScreenDrag and lab.tch.has(ev.index):
		if lab.tch.size() == 1:
			lab.yaw -= ev.relative.x * 0.008
			lab.pit = clampf(lab.pit + ev.relative.y * 0.006, -0.08, 1.45)
		elif lab.tch.size() >= 2:
			var other = -1
			for k in lab.tch:
				if k != ev.index:
					other = k
			var d0 = (lab.tch[ev.index] - lab.tch[other]).length()
			var d1 = (ev.position - lab.tch[other]).length()
			if d0 > 10.0 and d1 > 10.0:
				lab.dist = clampf(lab.dist * d0 / d1, 4.0, 90.0)
		lab.tch[ev.index] = ev.position
	elif ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			lab.dist = maxf(4.0, lab.dist * 0.9)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			lab.dist = minf(90.0, lab.dist * 1.1)


func _lab_step(dt: float) -> void:
	if lab.auto and not lab.tab in ["env", "pillar", "city"]:
		lab.at -= dt
		if lab.at <= 0.0:
			_lab_fire()
			lab.at = {"ship": 4.0, "quake": 4.0, "wall": 5.3 * float(fx.wall.dur) + 0.4, "mine": 3.2, "shield": 6.3, "orbs": 10.3, "haze": 3.0, "sound": 7.0}.get(lab.tab, 3.0)
	var g: Dictionary = ships[0]
	g.shield = maxf(0.0, g.shield - dt)
	g.boost = maxf(0.0, g.boost - dt * 0.9)
	# ±-Knopf gedrückt halten: wiederholen
	if not lab.rep.is_empty():
		lab.rep.t -= dt
		if lab.rep.t <= 0.0:
			lab.rep.t = 0.07
			lab.rep.n += 1
			if is_instance_valid(lab.rep.hs):
				lab.rep.hs.value = lab.rep.hs.value + lab.rep.d
	if lab.sv > 0.0:
		lab.sv -= dt
		if lab.sv <= 0.0:
			_fx_save()
	if lab.get("sndre", 0.0) > 0.0 and lab.rep.is_empty():
		lab.sndre -= dt
		if lab.sndre <= 0.0:
			_start_play(true)
	var grp = _lab_grp(lab.tab)
	if grp == "ship":
		var nn = maxi(1, int(ceil(dt / 0.0125)))
		var tt0 = Time.get_ticks_msec() / 1000.0
		for _k in range(nn):
			_phys(g, _ai_inp(g, tt0, dt / nn), true, dt / nn, true)
		# Tunnel überspringen: im Tunnel sähe man von außen nichts
		var zl = T.lz(g.z)
		for tu in T.TUN:
			if zl > tu[0] - 18.0 and zl < tu[1] + 3.0:
				g.z += tu[1] + 4.0 - zl
				lab.tz = g.z + 0.3
		_lap_pos(g.z)
	_weapons(dt, false)
	_tunnel(dt)
	_pose_all(dt)
	# Kamera kreist um die Teststelle bzw. fliegt im Reiter „Ship“ mit dem Gleiter mit
	var tzz = {"near": LZ + 0.3, "ship": g.z + 0.3, "pillar": LZ + 5.0, "city": LZ + 2.0, "wide": LZ + 30.0}.get(grp, LZ + 7.0)
	var tll = g.lat if grp == "ship" else 0.0
	if grp == "ship" and absf(lab.get("tz", tzz) - tzz) < 3.0:
		lab.tz = tzz
	else:
		lab.tz = lerpf(lab.get("tz", LZ + 7.0), tzz, 1.0 - exp(-dt / 0.3))
	lab.tl = lerpf(lab.get("tl", 0.0), tll, 1.0 - exp(-dt / 0.15))
	var f = T.frame(lab.tz)
	var tg: Vector3 = f.c + f.rr * lab.tl + f.uu * {"near": 0.4, "ship": 0.4, "pillar": 1.1, "city": 3.0, "wide": 3.5}.get(grp, 0.8)
	if grp == "city" and not holos.is_empty() and (holos[0].n as Node3D).visible:
		# Reiter „City“: um die Hologramm-Tänzerin kreisen
		var hn: Node3D = holos[0].n
		tg = hn.global_position + Vector3.UP * float(holos[0].get("H", HOLO_H)) * 0.62
	var cp = cos(lab.pit)
	var off: Vector3 = (-f.fw * cos(lab.yaw) + f.rr * sin(lab.yaw)) * cp + Vector3.UP * sin(lab.pit)
	var ro: Vector3 = tg + off * lab.dist
	ro.y = maxf(ro.y, tg.y - 0.5)
	shake = maxf(0.0, shake - dt * 1.8)
	if flash_rect != null and flash_rect.color.a > 0.0:
		flash_rect.color.a = maxf(0.0, flash_rect.color.a - dt * 2.2)
	if shake > 0.0:
		var tt2 = Time.get_ticks_msec() / 1000.0
		ro += Vector3(sin(tt2 * 61.0), sin(tt2 * 53.0 + 1.0) * 0.7, sin(tt2 * 47.0 + 2.0) * 0.5) * shake * 0.09
	cam.global_position = ro
	cam.look_at(tg, Vector3.UP)
	cam.fov = 62.0
	# Teststelle in die obere Bildhälfte (unten liegt das Regelfeld): Kamera etwas nach unten neigen
	# – im Reiter „City“ dagegen nach oben, zu den Hologrammen und Hochhäusern
	cam.rotate_object_local(Vector3(1, 0, 0), 0.12 if grp == "city" else -0.29)
	_sound_update(dt)
	_post_update(dt)
	_shot()


# Nur zum Testen am Rechner: godot -- --shot=Pfad,z  → setzt dich an die Stelle z und speichert ein Bild
var shot_n = 0
func _all_out() -> bool:
	if free_ride:
		return false
	for i in range(1, ships.size()):
		if not ships[i].out:
			return false
	return true


var shot_s = "?"   # Testbild-Auftrag von der Kommandozeile (einmal gelesen)


func _shot() -> void:
	if shot_s == "?":
		shot_s = ""
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--shot="):
				shot_s = a
	if shot_s == "":
		return
	for a in [shot_s]:
		if a.begins_with("--shot="):
			var p = a.substr(7).split(",")
			shot_n += 1
			if p.size() > 3 and p[2] == "lab":
				if shot_n == 60:
					_lab_open()
					_lab_tab(p[3])
					if p.size() > 4 and p[4] == "sup":
						lab.sup = true
					elif p.size() > 6:
						lab.yaw = float(p[4])
						lab.pit = float(p[5])
						lab.dist = float(p[6])
				if shot_n == 80 and p[3] != "env":
					_lab_fire()
				var at = 60 + {"boom": 25, "mine": 26, "quake": 30, "gb": 36, "rak": 34, "wall": 40, "env": 30, "pillar": 70, "ship": 90}.get(p[3], 40)
				if shot_n == at:
					get_viewport().get_texture().get_image().save_png(p[0])
					get_tree().quit()
				return
			if not rpf.is_empty():
				if shot_n == 40:
					get_viewport().get_texture().get_image().save_png(p[0])
					get_tree().quit()
				return
			if p.size() > 3 and p[3] == "rsave":
				if shot_n == 70:
					state = "done"
					_replay_start()
					_rp_cam_pick(4)
				if shot_n == 80:
					_rp_save()
					var d = DirAccess.open("user://replays")
					var fs = d.get_files()
					fs.sort()
					pending_rp = "user://replays/" + fs[fs.size() - 1]
					_reload()
					return
			if shot_n == 2 and p.size() > 2 and p[2] != "menu":
				_start()
				if p[2] != "intro":
					state = "race"
			if shot_n == 40 and p.size() > 2 and p[2] == "menu":
				print("MENUSTART race0=", not race0.is_empty(), " warm_t=", warm_t)
				_start()
				state = "race"
			if p.size() > 3 and p[3].begins_with("go") and state == "race" and t_state >= float(p[3].substr(2)):
				get_viewport().get_texture().get_image().save_png(p[0])
				print("GOSHOT z=", ships[0].z, " spd=", ships[0].spd, " cam=", cam.global_position, " fig=", starter.n.global_position if not starter.is_empty() else Vector3.ZERO)
				get_tree().quit()
			if p.size() > 3 and p[3].begins_with("go"):
				if shot_n == 3 and float(p[1]) > 0.0:
					ships[0].z = float(p[1])
				return
			if shot_n == 50 and shot_s.contains("resbtest"):
				state = "done"
				t_state = 0.0
				_show_resb()
			if shot_n == 60 and shot_s.contains("finwin"):
				state = "done"
				t_state = 0.0
				_fin_flow(1)
			if shot_n == 60 and shot_s.contains("finlose"):
				state = "done"
				t_state = 0.0
				ships[2].fin = 1.0
				_fin_flow(3)
			if shot_s.contains("swtest") and state == "race":
				var evs = {45: ["t", 0, 270.0, true], 47: ["d", 0, 300.0], 49: ["d", 0, 330.0], 52: ["d", 0, 322.0], 53: ["d", 0, 316.0], 60: ["dt"]}
				if shot_n == 60:
					for q in [[true, 100.0], [false, 100.0], [true, 102.0], [false, 102.0]]:
						var te = InputEventScreenTouch.new()
						te.index = 1
						te.pressed = q[0]
						te.position = Vector2(q[1], 900)
						_input(te)
				elif evs.has(shot_n):
					var e: Array = evs[shot_n]
					var ie
					if e[0] == "t":
						ie = InputEventScreenTouch.new()
						ie.pressed = e[3]
					else:
						ie = InputEventScreenDrag.new()
						ie.velocity = Vector2(900, 0)
					ie.index = e[1]
					ie.position = Vector2(e[2], 900)
					Input.parse_input_event(ie)
				if shot_n in [44, 46, 50, 55, 62, 66, 90, 120]:
					print("SWT n=", shot_n, " ptr=", ptr_lat, " lat=", ships[0].lat, " z=", ships[0].z, " steer=", last_steer, " m=", sw.m, " idx=", sw.idx, " wpn=", ships[0].wpn, " fire=", fire_req)
			if shot_s.contains("again"):
				# Test: Rennen mit Effekten „beenden“, dann ohne Neuladen neu starten
				if shot_n == 45:
					print("AGAIN start kids=", get_child_count(), " z=", ships[0].z)
					set_meta("k45", get_children())
				if shot_n == 66:
					var k45: Array = get_meta("k45")
					for n in get_children():
						if not k45.has(n):
							print("AGAIN new: ", n.get_class(), " ", n.name)
				if shot_n == 50:
					_explode(ships[0].z + 4.0, 0.0, true)
					_gbomb(ships[0].z + 6.0, 0.0)
					ships[2].en = 0.01
					_dmg(ships[2], 0.5, 0)
					_drop_mines(ships[0])
					_add_shot(ships[0], false, false)
				if shot_n == 58:
					print("AGAIN mid kids=", get_child_count(), " fx=", fxs.size(), " mines=", mines.size(), " out2=", ships[2].out)
					state = "done"
					_victory()
					_show_resb()
				if shot_n == 62:
					if shot_s.contains("againmenu"):
						_pause(true)
						_to_menu()
						print("AGAIN menu state=", state, " paused=", get_tree().paused)
					else:
						var ok = _soft_reset()
						print("AGAIN soft=", ok)
						_start()
				if shot_n == 64:
					print("AGAIN after kids=", get_child_count(), " fx=", fxs.size(), " mines=", mines.size(), " out2=", ships[2].out, " vis2=", (ships[2].node as Node3D).visible, " z=", ships[0].z, " en2=", ships[2].en, " state=", state, " race_t=", race_t)
			if shot_s.contains("lanetap") and state == "race":
				# Test: Spur antippen – rechts außen, dann ganz nach links; Zeit messen
				if shot_n == 40:
					cfg.ctrl = 5
				var W = get_viewport().get_visible_rect().size.x
				var tap = func(x: float):
					for pr in [true, false]:
						var te = InputEventScreenTouch.new()
						te.index = 0
						te.pressed = pr
						te.position = Vector2(x, 500)
						_input(te)
				if shot_n == 45:
					tap.call(W * 0.9)
					set_meta("lt0", race_t)
				if shot_s.contains("lanehold"):
					if shot_n == 60:
						var te = InputEventScreenTouch.new()
						te.index = 0
						te.pressed = true
						te.position = Vector2(W * 0.1, 500)
						_input(te)
						set_meta("lt0", race_t)
					if shot_n == 80:
						var te2 = InputEventScreenTouch.new()
						te2.index = 0
						te2.pressed = false
						te2.position = Vector2(W * 0.1, 500)
						_input(te2)
						print("LT released")
				elif shot_n == 75 or shot_n == 77:
					if shot_s.contains("laneboost"):
						ships[0].boost = 1.0
					tap.call(W * 0.1)
					if shot_n == 75:
						set_meta("lt0", race_t)
				if shot_n == 86:
					tap.call(W * 0.5)
					print("LT fire_req=", fire_req, " lane=", lane_cur)
				if shot_n >= 45:
					var tg = lane_cur * LANE_W
					print("LT n=", shot_n, " t=", snappedf(race_t - float(get_meta("lt0")), 0.001), " lane=", lane_cur, " lat=", snappedf(ships[0].lat, 0.001), " psi=", snappedf(ships[0].psi, 0.01), " spd=", snappedf(ships[0].spd, 0.1))
			if shot_n == 50 and shot_s.contains("backtest"):
				# Test: Android meldet Zurück doppelt (Taste + Systemmeldung) – Pause muss offen bleiben
				var ke = InputEventKey.new()
				ke.keycode = KEY_BACK
				ke.pressed = true
				_input(ke)
				_notification(NOTIFICATION_WM_GO_BACK_REQUEST)
				print("BACKTEST after double: paused=", get_tree().paused)
				var tm2 = get_tree().create_timer(0.6, true)
				tm2.timeout.connect(func():
					_notification(NOTIFICATION_WM_GO_BACK_REQUEST)
					print("BACKTEST second press: paused=", get_tree().paused)
					get_tree().quit())
			if shot_n == 50 and shot_s.contains("pausetest"):
				_pause(true)
				var tm = get_tree().create_timer(1.5, true)
				tm.timeout.connect(func():
					get_viewport().get_texture().get_image().save_png(p[0])
					print("PAUSESHOT paused=", get_tree().paused)
					get_tree().quit())
			if shot_n == 60 and shot_s.contains(",ko"):
				_comic_start("ko", 1)
			if shot_n >= 2 and p.size() > 2 and p[2].begins_with("st"):
				var v = float(p[2].substr(2))   # Start-Mädel testen: Zeit ab Countdown-Beginn
				state = "count" if v < 3.0 else "race"
				t_state = v if v < 3.0 else v - 3.0
				last_c = 3 - int(floor(v))
			if shot_n == 3 and p.size() > 1 and float(p[1]) > 0.0:
				ships[0].z = float(p[1])
				for i in range(1, 4):
					ships[i].z = float(p[1]) + 2.0 + i * 2.5
			if shot_n == 40 and p.size() > 3:
				if p[3].begins_with("boom") or p[3] == "repb":
					_explode(ships[0].z + 6.0, 0.0, true)
				elif p[3].begins_with("gb"):
					_gbomb(ships[0].z + 9.0, 0.0)
					ships[0].boost = 1.5
				elif p[3].begins_with("rs"):
					ships[0].air = true
					ships[0].h = 0.6
					ships[0].lat = T.TW + 0.4
				elif p[3].begins_with("mega"):
					ships[0].wpn = p[3].substr(5) if p[3].contains("_") else "rak"
					ships[0].sup = true
					ships[0].mega = true
					for o in ships:
						o.en = 1.0
					fire_req = true
				elif p[3].begins_with("armed"):
					ships[0].wpn = p[3].get_slice("_", 1) if p[3].contains("_") else "lenk"
				elif p[3].begins_with("kill"):
					for i in range(1, 4):
						ships[i].en = 0.05
					ships[0].wpn = "lenk"
					fire_req = true
				elif not p[3].begins_with("rep"):
					ships[0].wpn = p[3]
					fire_req = true
			if p.size() > 3 and p[3].begins_with("rep") and shot_n == 70:
				state = "done"
				_replay_start()
				if p[3] == "repf":
					_rp_follow(2)
				else:
					for k in range(int(p[3].substr(3))):
						_rp_next()
			if p.size() > 3 and p[3] == "repb" and shot_n == 74:
				var te = 0.0
				for fr in rec:
					for ev in fr.ev:
						if ev[0] == "boom":
							te = fr.t
				_rp_seek(te + 0.35)
				rp.paused = true
			if shot_n == ({"repb": 84, "repf": 85, "armed": 50, "kill1": 75, "kill4": 160, "kill2": 90, "kill3": 110, "long": 700, "i1": 22, "i2": 38, "i3": 52, "orbs": 47, "rep0": 85, "rep1": 85, "rep2": 85, "rep4": 85, "rep5": 85, "wand": 56, "boom": 42, "boom2": 70, "beben": 47, "gb1": 47, "gb2": 53, "schild": 44, "mega1": 46, "mega2": 52, "rs1": 43, "rs2": 50, "rs3": 58, "armed2": 130}.get(p[3], 90) if p.size() > 3 else 90):
				get_viewport().get_texture().get_image().save_png(p[0])
				if p.size() > 3 and p[3] == "long":
					print(_perf_text())
				if p.size() > 3 and p[3].begins_with("rs"):
					print("RS h=", ships[0].h, " lat=", ships[0].lat, " air=", ships[0].air, " drop=", ships[0].get("drop", 0), " vis=", ships[0].node.visible)
				if p.size() > 3 and p[3].begins_with("mega"):
					for o in ships:
						print("MEGA idx=", o.idx, " en=", o.en, " out=", o.out, " z=", o.z)
				get_tree().quit()


func _fmt(t: float) -> String:
	return "%d:%05.2f" % [int(t / 60.0), fmod(t, 60.0)]


# Lage der Gleiter: Bahnpunkt + seitlich + Schweben, Nase um psi gedreht, in Kurven leicht geneigt
var tun_k = 0.0
var tun_l = []


# Im Tunnel: Umgebungslicht, Himmel und Nebel weg; Lichter wandern mit den Magenta-Ringen vorbei
func _tunnel(dt: float) -> void:
	var g: Dictionary = _focus()
	var zl = T.lz(g.z)
	var k = 0.0
	for tu in T.tuns():
		k = maxf(k, clampf(minf(zl - tu[0] + 2.0, tu[1] - zl + 2.0) / 7.0, 0.0, 1.0))
	tun_k += (k - tun_k) * (1.0 - exp(-dt / 0.2))
	wenv.ambient_light_energy = lerpf(0.35 * _newr("amb", 1.0), 0.02, tun_k)
	wenv.fog_density = lerpf((0.03 if _jungle() else 0.012) * float(fx.env.fog), 0.0, tun_k)
	var fog_on = float(fx.env.fog) > 0.01
	if wenv.fog_enabled != fog_on:
		wenv.fog_enabled = fog_on
	wenv.background_energy_multiplier = lerpf(1.0, 0.05, tun_k)
	moon.light_energy = lerpf(0.45 * float(fx.env.moon) * _newr("moon", 1.0), 0.0, tun_k)
	_lamps_cull()
	_neon_lights()
	_city_live()
	_starter_live()
	# Explosions-Helligkeitsstoß abklingen lassen
	expo_v = maxf(0.0, expo_v - dt * 2.2)
	if wenv.tonemap_exposure != 1.0 + expo_v:
		wenv.tonemap_exposure = 1.0 + expo_v
	# im Tunnel sieht man den Mond nicht: Schattenberechnung sparen
	# (nur bei Änderung setzen – jedes Setzen ordnet die Schatten neu zu)
	var sh_on = int(cfg.gfx) >= 1 and tun_k < 0.6 and float(fx.env.moon) > 0.01 and not bench.get("nosh", false)
	if moon.shadow_enabled != sh_on:
		moon.shadow_enabled = sh_on
	if tun_l.is_empty():
		for i in range(4 if int(cfg.gfx) >= 2 else 2):
			var l = OmniLight3D.new()
			l.omni_range = 6.0
			l.omni_attenuation = 1.4
			l.light_energy = 0.0
			add_child(l)
			tun_l.append(l)
	var base = g.z - zl
	var j = 0
	for tu in ([] if _jungle() else T.TUN):   # Erdtunnel bleibt dunkel
		var ti0 = 4
		while j < tun_l.size():
			var zr = tu[0] + 1.0 + ti0 * 1.43
			if zr > tu[1]:
				break
			var d = zr - zl
			if d > -4.0 and d < 24.0:
				var l: OmniLight3D = tun_l[j]
				var wv = sin(PI * (d + 4.0) / 28.0)
				l.light_energy = 5.0 * wv * wv * tun_k
				l.light_color = MG if (int(ti0 / 5) % 2 == 0) else CY
				l.global_position = T.world(base + zr, 0.0, 0.4 + T.TW * 0.95)
				l.visible = true
				j += 1
			ti0 += 5
	for i in range(j, tun_l.size()):
		tun_l[i].visible = false


func _pose_all(dt: float) -> void:
	if jleaf != null and cam != null:
		jleaf.global_position = cam.global_position - cam.global_transform.basis.z * 9.0
	var tt = Time.get_ticks_msec() / 1000.0
	for i in range(ships.size()):
		var s: Dictionary = ships[i]
		var f = T.frame(s.z)
		var SX: Dictionary = fx.ship
		var bob = 0.012 * float(SX.bob) * sin(tt * 2.7 + s.ai)
		var pos: Vector3 = f.c + f.rr * s.lat + f.uu * (0.16 * float(SX.height) + s.h + bob)
		var dir: Vector3 = (f.fw * cos(s.psi) + f.rr * sin(s.psi)).normalized()
		if state != "replay" and state != "kill":
			# Feder: Neigen in Kurven und Nicken beim Beschleunigen schwingen je nach „Wobble“ nach
			var om = 9.0 * float(SX.stiff)
			var ze = 1.0 / (1.0 + float(SX.wobble))
			var acc = (s.spd - s.get("lspd", s.spd)) / maxf(dt, 1e-4)
			s.lspd = s.spd
			s.pacc = lerpf(s.get("pacc", 0.0), acc, 1.0 - exp(-dt / 0.2))
			var tr = s.u * 0.32 * float(SX.bank)
			var tp = clampf((s.pacc * 0.006 + s.boost * 0.035) * float(SX.pitch), -0.35, 0.35)
			var nsub = maxi(1, int(ceil(dt * om / 0.25)))
			var sdt = dt / nsub
			for _i in range(nsub):
				s.rv = s.get("rv", 0.0) + (om * om * (tr - s.roll) - 2.0 * ze * om * s.get("rv", 0.0)) * sdt
				s.roll += s.rv * sdt
				s.pv = s.get("pv", 0.0) + (om * om * (tp - s.get("pit", 0.0)) - 2.0 * ze * om * s.get("pv", 0.0)) * sdt
				s.pit = s.get("pit", 0.0) + s.pv * sdt
		var up: Vector3 = f.uu.rotated(dir, s.roll)
		var x = up.cross(dir).normalized()
		up = dir.cross(x).normalized()
		var nd: Node3D = s.node
		nd.global_transform = Transform3D(Basis(x, up, dir), pos)
		# Nase hoch beim Gasgeben; „Nose trim“ kippt die ganze Grundhaltung nach vorn (Nase Richtung Boden)
		var pitch_t = -float(s.get("pit", 0.0)) + float(SX.trim) * 0.25
		if absf(pitch_t) > 0.0001:
			nd.rotate_object_local(Vector3(1, 0, 0), pitch_t)
		if nd.visible and (cam == null or cam.global_position.distance_squared_to(pos) < 1600.0):
			_dangle_step(nd, dt)
			_rings_step(nd, s, 0.16 * float(SX.height) + s.h + bob)
		var HX: Dictionary = fx.haze
		# Plasmastrahl: Länge/Breite/Helligkeit nach Tempo und Boost
		var spk = clampf(s.spd / maxf(1.0, base_spd), 0.0, 1.6)
		var bo = clampf(s.boost, 0.0, 1.6) * float(HX.jboost)
		var JL = (0.3 + 0.28 * spk + 0.95 * bo) * float(HX.jlen)
		var JW = (1.0 + 0.4 * bo) * float(HX.jwid)
		var pjm: Array = nd.get_meta("pjm")
		var jc = _hs(Color(0.55, 0.38, 1.0), float(HX.jhue))
		var jc2 = _hs(Color(0.78, 0.93, 1.0), float(HX.jhue))
		if _noir():
			jc = OR
			jc2 = Color(1.0, 0.85, 0.6)
		var jk = (0.85 + 0.35 * spk + 1.2 * bo) * float(HX.jglow)
		if i == 0 and not fin.is_empty() and fin.fly and fin.phase == 0:
			jk *= 0.75   # Kamerafahrt ganz nah am Schiff: Düsen glühen, blenden aber nicht
		_sp(pjm[0], "jk", jk)
		_sp(pjm[0], "jl", JL)
		_sp(pjm[0], "jd", float(HX.jdia))
		_sp(pjm[0], "jc", _v3(jc))
		_sp(pjm[0], "jc2", _v3(jc2))
		_sp(pjm[1], "jk", minf(jk * 0.8, 2.5))
		_sp(pjm[1], "jc", _v3(jc))
		for pj in nd.get_meta("pj"):
			var cone: MeshInstance3D = pj[0]
			var jd: Array = pj[1]
			var r: float = jd[3] * JW
			# Kegelachse (y) zeigt nach vorn zur Düse, Spitze nach hinten
			cone.transform = Transform3D(Basis(Vector3(r, 0, 0), Vector3(0, 0, JL), Vector3(0, -r, 0)), Vector3(jd[0], jd[1], jd[2] - JL * 0.5))
			if cone.visible != (jk > 0.01):
				cone.visible = jk > 0.01
		var lt: OmniLight3D = nd.get_meta("light")
		# das Licht kommt vom Plasmastrahl: spiegelt sich auf der Fahrbahn
		lt.light_energy = (1.2 + 0.5 * spk + 3.0 * s.boost) * (1.0 + 1.2 * tun_k) * _newr("ship", 1.0) * minf(1.5, float(HX.jglow))
		lt.position.z = -0.85 - JL * 0.35
		# Flimmern nur, wo man es sieht: weit entfernte Gegner brauchen es nicht
		var hz_on = float(HX.amp) > 0.01 and nd.visible and (cam == null or cam.global_position.distance_squared_to(pos) < 900.0)
		var hzn: Array = nd.get_meta("hazen")
		if hz_on:
			var shc: Vector3 = nd.global_transform * Vector3(0, 0.12, 0.05)
			for hm in nd.get_meta("haze"):
				_sp(hm, "k", 0.55 + 0.35 * spk + 0.9 * float(HX.boost) * minf(1.0, s.boost))
				_sp(hm, "hs", float(HX.amp))
				_sp(hm, "hv", float(HX.speed))
				_sp(hm, "hf", float(HX.fine))
				hm.set_shader_parameter("shc", shc)
			for k in range(hzn.size()):
				var hn: MeshInstance3D = hzn[k]
				hn.scale = Vector3.ONE * (0.75 if k == 0 else 1.1) * float(HX.size)
				# hinter dem Plasmastrahl, wo die heiße Luft ausströmt
				hn.position.z = -0.76 - (0.25 + JL * 0.55 if k == 0 else 0.6 + JL) * float(HX.len)
		for hn in hzn:
			if hn.visible != hz_on:
				hn.visible = hz_on
		lt.omni_range = 4.0 + 4.0 * tun_k
		lt.light_color = jc.lerp(Color(0.3, 0.8, 1.0) if not _noir() else jc2, clampf(s.boost, 0.0, 1.0))


# Kamera: hinter dem Gleiter, folgt der Nase gedämpft, bleibt beim Boost kurz zurück
func _camera(dt: float) -> void:
	if state == "replay" and _rp_cam(dt):
		return
	if state == "kill" and _kc_cam():
		return
	if state == "done" and _fly_cam(dt):
		return
	if OS.get_environment("TOPCAM") != "":
		# nur zum Testen: Blick senkrecht von oben auf die Strecke
		var tz = float(OS.get_environment("TOPCAM"))
		var tf = T.frame(tz)
		cam.global_position = tf.c + Vector3.UP * 9.0
		cam.look_at(tf.c, tf.fw)
		cam.fov = 60.0
		return
	var g: Dictionary = _focus()
	var f = T.frame(g.z)
	var S0: Vector3 = f.c + f.rr * g.lat + f.uu * (0.16 + g.h)
	cam_psi += (g.psi - cam_psi) * (1.0 - exp(-dt / 0.25))
	var tc = minf(1.0, g.boost) * 0.55
	cam_d += (tc - cam_d) * (1.0 - exp(-dt / (0.14 if tc > cam_d else 0.8)))
	var cp = cam_psi * 0.6
	var fc: Vector3 = (f.fw * cos(cp) + f.rr * sin(cp)).normalized()
	var uc: Vector3 = (Vector3.UP * 0.25 + f.uu * 0.75).normalized()
	var ro: Vector3 = S0 - fc * (2.6 + cam_d) + uc * (0.95 - 0.15 * cam_d) - f.uu * g.h * 0.5
	var ta: Vector3 = S0 + fc * 7.0 + uc * 0.35
	# Countdown: Blick leicht nach oben, damit das riesige Start-Mädel ganz ins Bild passt
	var lift = 0.0
	if state == "count":
		lift = 1.0
	elif state == "intro":
		lift = clampf((t_state / INTRO_T - 0.6) / 0.4, 0.0, 1.0)
	elif state == "race":
		lift = clampf(1.0 - t_state / 0.9, 0.0, 1.0)
	ta += Vector3.UP * 1.3 * lift * lift * (3.0 - 2.0 * lift)
	if state == "intro":
		var u = clampf(t_state / INTRO_T, 0.0, 1.0)
		var Y = Vector3.UP
		var K = [S0 + f.fw * 6.5 + Y * 3.4 + f.rr * 1.4, S0 + f.fw * 2.6 + Y * 1.1 + f.rr * 1.5, S0 + f.fw * 0.3 + Y * 0.45 + f.rr * 1.25,
			S0 - f.fw * 1.8 + Y * 0.7 + f.rr * 0.8, ro]
		var e = u * u * (3.0 - 2.0 * u)
		var n = K.size() - 1
		var x = minf(n - 1e-4, e * n)
		var i = int(floor(x))
		var t = x - i
		var p0: Vector3 = K[maxi(0, i - 1)]
		var p1: Vector3 = K[i]
		var p2: Vector3 = K[i + 1]
		var p3: Vector3 = K[mini(n, i + 2)]
		ro = 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t)
		var w = clampf((u - 0.62) / 0.38, 0.0, 1.0)
		var ww = w * w * (3.0 - 2.0 * w)
		ta = (S0 + f.fw * 0.25).lerp(ta, ww)
		uc = Y.lerp(uc, ww).normalized()
	shake = maxf(0.0, shake - dt * 1.8)
	if flash_rect != null and flash_rect.color.a > 0.0:
		flash_rect.color.a = maxf(0.0, flash_rect.color.a - dt * 2.2)
	if shake > 0.0:
		var tt2 = Time.get_ticks_msec() / 1000.0
		ro += Vector3(sin(tt2 * 61.0), sin(tt2 * 53.0 + 1.0) * 0.7, sin(tt2 * 47.0 + 2.0) * 0.5) * shake * 0.09
	cam.global_position = ro
	cam.look_at(ta, uc)
	cam.fov = 52.0 * (1.0 + 0.12 * minf(1.5, g.boost) + 0.1 * post_spd)
	cam.rotate_object_local(Vector3(0, 0, 1), -g.u * 0.05)   # leichtes Mitneigen beim Lenken


# ---------------------------------------------------------------- Comic: Manga-Panels mit den Fahrern (Cyber Gothic)
# Fahrer: Name, Beiname, Farbe, Bildname (art/comic/<bild>_<0..2>.jpg: 0 ruhig/grinsend, 1 wütend/erschrocken, 2 Triumph)
# Index = Platz in ships[] (0 = du als Ren, 1 Vega, 2 Kato, 3 Mira)
const CHARS = [
	["REN", "RED DRAGON", Color(0.9, 0.1, 0.14), "ren"],
	["VEGA", "THE CHAMPION", Color(0.66, 0.36, 1.0), "vega"],
	["KATO", "THE WRECKER", Color(1.0, 0.48, 0.12), "kato"],
	["MIRA", "THE TRICKSTER", Color(0.15, 0.95, 0.95), "mira"]]
const CM_LINES = {
	"ren": ["Stay out of my line.", "This one's mine.", "Watch the dragon fly."],
	"vega": ["The crown stays\nwith me.", "Kneel, rookie.", "You race\nfor second."],
	"kato": ["I'll scrap you,\nkid!", "Outta my way!", "Hope you brought\nspare parts!"],
	"mira": ["Watch your step...\nhehe.", "I left you\na present.", "Catch me\nif you can~"]}
const CM_WIN = {"ren": ["Too slow.", "The dragon\nflies first."], "vega": ["Impossible!", "This isn't\nover!"],
	"kato": ["ARGH!", "Lucky shot,\nkid!"], "mira": ["Hmpf. Rigged!", "No fair!"]}
const CM_LOSE = {"ren": ["Next time...", "Tch."], "vega": ["As expected.", "Bow to the\nchampion."],
	"kato": ["HAHA! Eat\nmy dust!", "Who's the\nboss now?"], "mira": ["Byeee~", "Too easy!"]}
const CM_KO = {"vega": ["My crown...!", "You'll pay\nfor this!"], "kato": ["MY BABY!!", "Who's paying\nfor that?!"],
	"mira": ["Hmpf!", "Not cool!"]}
var cm = {}
var cm_tex = {}


func _cm_img(k: String) -> Texture2D:
	if not cm_tex.has(k):
		cm_tex[k] = load("res://art/comic/" + k + ".jpg")
	return cm_tex[k]


func _pick(a: Array):
	return a[randi() % a.size()]


# kind: start | win | lose | ko · who: Gewinner (lose) bzw. Opfer (ko)
func _comic_start(kind: String, who := 0) -> void:
	if not cm.is_empty():
		_comic_end()
	cm = {"pending": kind, "who": who}   # erst bauen, wenn das Vorwärmen der Shader fertig ist (das räumt neue Knoten weg)


func _comic_build(kind: String) -> void:
	var who: int = cm.get("who", 0)
	var layer = CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	var c = Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE if kind == "ko" else Control.MOUSE_FILTER_STOP
	layer.add_child(c)
	var pn = []
	var stamp = ["RACE!", Color(0.95, 0.08, 0.12)]
	var end = 0.0
	var hold = false
	match kind:
		"start":
			# die Rivalen protzen, Ren antwortet zum Schluss
			var k = 0
			for i in [1, 2, 3, 0]:
				var ch: Array = CHARS[i]
				pn.append({"ch": ch, "img": _cm_img(ch[3] + "_" + str(1 if i == 0 else 0)), "line": _pick(CM_LINES[ch[3]]), "t0": 0.3 + k * 0.62, "fy": 0.45, "vo": "cv_%s_start" % ch[3] if k == 0 or k == 3 else ""})
				k += 1
			end = 0.3 + 4 * 0.62 + 1.0
		"win":
			var r: Array = CHARS[0]
			pn.append({"ch": r, "img": _cm_img("ren_2"), "line": _pick(CM_WIN.ren), "t0": 0.25, "fy": 0.45, "big": true, "vo": "cv_ren_win"})
			var k2 = 0
			var vk = randi() % 3   # nur einer der Verlierer meckert hörbar, sonst wird's ein Durcheinander
			for i in [1, 2, 3]:
				var ch2: Array = CHARS[i]
				pn.append({"ch": ch2, "img": _cm_img(ch2[3] + "_1"), "line": _pick(CM_WIN[ch2[3]]), "t0": 0.8 + k2 * 0.3, "fy": 0.45, "vo": "cv_%s_mad" % ch2[3] if k2 == vk else ""})
				k2 += 1
			stamp = ["VICTORY!", Color(1.0, 0.8, 0.2)]
			hold = true
		"lose":
			var w: Array = CHARS[clampi(who, 1, 3)]
			pn.append({"ch": w, "img": _cm_img(w[3] + "_2"), "line": _pick(CM_LOSE[w[3]]), "t0": 0.25, "fy": 0.45, "big": true, "vo": "cv_%s_win" % w[3]})
			pn.append({"ch": CHARS[0], "img": _cm_img("ren_1"), "line": _pick(CM_LOSE.ren), "t0": 1.9, "fy": 0.45, "vo": "cv_ren_lose"})
			stamp = ["DEFEAT", Color(0.75, 0.75, 0.8)]
			hold = true
		"ko":
			var v: Array = CHARS[clampi(who, 1, 3)]
			pn.append({"ch": v, "img": _cm_img("ko_" + v[3]), "line": _pick(CM_KO[v[3]]), "t0": 0.0, "fy": 0.5, "noname": false, "vo": "cv_%s_ko" % v[3]})
			stamp = ["K.O.!", Color(1.0, 0.85, 0.15)]
			end = 2.8
			_snd("cm_crash", -3.0)
	var ns = pn.size()
	var st = pn[ns - 1].t0 + 0.5
	cm = {"kind": kind, "who": who, "t": 0.0, "layer": layer, "c": c, "pn": pn, "end": end if end > 0.0 else 6.0,
		"skip": -1.0, "hit": -1, "stamp": stamp, "st": st, "hold": hold}
	c.draw.connect(_comic_draw)
	c.gui_input.connect(func(ev):
		if (ev is InputEventScreenTouch or ev is InputEventMouseButton) and ev.pressed and not cm.is_empty() and cm.t > 0.6:
			cm.skip = cm.t)


func _comic_end() -> void:
	if cm.has("layer") and is_instance_valid(cm.layer):
		(cm.layer as CanvasLayer).queue_free()
	cm = {}


func _comic_update(dt: float) -> void:
	if cm.has("pending"):
		if warm_t < 0.0:
			_comic_build(cm.pending)
		return
	if not is_instance_valid(cm.c):
		cm = {}
		return
	cm.t += dt
	# Tschack: jedes Panel knallt mit einem Schlag rein
	var pn: Array = cm.pn
	# Geräusche je Panel: Wusch beim Reinfliegen, Schlag beim Aufprall, Plopp für die Blase, dazu die Stimme
	for k in range(pn.size()):
		var pd: Dictionary = pn[k]
		if cm.skip >= 0.0:
			break
		if cm.t >= pd.t0 and not pd.get("s0", false):
			pd.s0 = true
			_snd("cm_whoosh", -8.0, randf_range(0.9, 1.15))
		if cm.t >= pd.t0 + 0.22 and not pd.get("s1", false):
			pd.s1 = true
			_snd("cm_hit", -5.0, 1.0 + 0.06 * k)
			cm.shake = 1.0
		if cm.t >= pd.t0 + 0.34 and not pd.get("s2", false):
			pd.s2 = true
			_snd("cm_pop", -9.0, randf_range(0.95, 1.1))
			if str(pd.get("vo", "")) != "":
				_snd(pd.vo, 2.0)
	if cm.t >= cm.st + 0.15 and not cm.get("sth", false) and cm.skip < 0.0:
		cm.sth = true
		cm.shake = 1.4
		_snd("cm_stamp", -2.0)
	cm.shake = maxf(0.0, cm.get("shake", 0.0) - dt * 6.0)
	var fin = cm.end if cm.skip < 0.0 else cm.skip + 0.25
	if cm.t > fin:
		_comic_end()
		return
	cm.fade = clampf((fin - cm.t) / 0.25, 0.0, 1.0) if cm.t > fin - 0.25 else 1.0
	(cm.c as Control).queue_redraw()


func _ease_back(a: float) -> float:
	var c1 = 1.9
	var u = a - 1.0
	return 1.0 + (c1 + 1.0) * u * u * u + c1 * u * u


# Panel-Umrisse je Layout in Pixeln (vier Ecken, im Uhrzeigersinn ab oben links) und Einflugseite
func _cm_layout(kind: String, n: int, W: float, H: float) -> Array:
	var mg = W * 0.045
	var gut = W * 0.016
	var sl = W * 0.07
	var out = []
	match kind:
		"start":
			var top = H * 0.07
			var ph = (H * 0.86) / n
			for i in range(n):
				var y0 = top + i * ph
				var y1 = y0 + ph
				var s0 = (sl * (1.0 if i % 2 == 0 else -1.0)) if i > 0 else 0.0
				var s1 = (sl * (-1.0 if i % 2 == 0 else 1.0)) if i < n - 1 else 0.0
				out.append([[Vector2(mg, y0 + gut + s0), Vector2(W - mg, y0 + gut - s0), Vector2(W - mg, y1 - gut - s1), Vector2(mg, y1 - gut + s1)], -1.0 if i % 2 == 0 else 1.0])
		"win", "lose":
			var yb = H * 0.6
			out.append([[Vector2(mg, H * 0.1), Vector2(W - mg, H * 0.1), Vector2(W - mg, yb - sl - gut), Vector2(mg, yb + sl - gut)], -1.0])
			var m = n - 1
			var y2 = H * 0.88
			for i in range(m):
				var xa = mg + (W - 2.0 * mg) * i / m
				var xb = mg + (W - 2.0 * mg) * (i + 1) / m
				var ga = gut if i > 0 else 0.0
				var gb = gut if i < m - 1 else 0.0
				var ta = yb + sl - 2.0 * sl * (xa - mg) / (W - 2.0 * mg) + gut
				var tb = yb + sl - 2.0 * sl * (xb - mg) / (W - 2.0 * mg) + gut
				var k = W * 0.03
				out.append([[Vector2(xa + ga + (k if i > 0 else 0.0), ta), Vector2(xb - gb + (k if i < m - 1 else 0.0), tb), Vector2(xb - gb - (k if i < m - 1 else 0.0), y2), Vector2(xa + ga - (k if i > 0 else 0.0), y2)], 1.0 if i % 2 == 0 else -1.0])
		"ko":
			var pw = W - 2.0 * mg
			var y0k = H * 0.13
			var h = pw * 0.6
			out.append([[Vector2(mg, y0k), Vector2(W - mg, y0k + sl * 0.5), Vector2(W - mg, y0k + h), Vector2(mg, y0k + h - sl * 0.5)], 1.0])
	return out


func _comic_draw() -> void:
	if cm.is_empty():
		return
	var c: Control = cm.c
	var sz: Vector2 = c.size
	var W = sz.x
	var H = sz.y
	var t: float = cm.t
	var fa: float = cm.get("fade", 1.0)
	var kind: String = cm.kind
	var font = c.get_theme_default_font()
	var sh = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 10.0 * cm.get("shake", 0.0)
	# Hintergrund: schwarze Seite mit Speedlines aus der Mitte (beim K.o. nur ein Hauch, das Rennen läuft weiter)
	if kind != "ko":
		c.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.03, 0.02, 0.03, 0.93 * fa * clampf(t / 0.15, 0.0, 1.0)))
		var ctr = Vector2(W * 0.5, H * 0.47)
		var lc = Color(0.55, 0.05, 0.08) if kind != "win" else Color(0.7, 0.5, 0.08)
		for i in range(64):
			var a = i * TAU / 64.0 + sin(i * 7.3) * 0.04
			var r0 = W * (0.35 + 0.25 * fmod(i * 0.618, 1.0))
			c.draw_line(ctr + Vector2(cos(a), sin(a)) * r0, ctr + Vector2(cos(a), sin(a)) * W * 1.6, Color(lc, 0.35 * fa), 2.0 + fmod(i * 1.7, 3.0))
	var pn: Array = cm.pn
	var lay = _cm_layout(kind, pn.size(), W, H)
	for i in range(pn.size()):
		var pd: Dictionary = pn[i]
		var a = clampf((t - pd.t0) / 0.3, 0.0, 1.0)
		if a <= 0.0:
			continue
		_cm_panel(c, font, pd, lay[i][0], lay[i][1], t, a, sh, fa, W, kind)
	# Schluss: großer Stempel quer über die Seite
	var tz = t - cm.st
	if tz > 0.0:
		var e2 = _ease_back(clampf(tz / 0.22, 0.0, 1.0))
		var fs4 = int(W * (0.21 if kind == "start" else 0.17))
		var txt: String = cm.stamp[0]
		var tw2 = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs4).x
		var sp = {"start": Vector2(0.5, 0.5), "win": Vector2(0.5, 0.6), "lose": Vector2(0.5, 0.6), "ko": Vector2(0.62, 0.13 + (W - W * 0.09) * 0.6 / H)}[kind]
		c.draw_set_transform(Vector2(W, H) * sp + sh, -0.12, Vector2.ONE * lerpf(2.4, 1.0, e2))
		c.draw_string_outline(font, Vector2(-tw2 * 0.5, fs4 * 0.35), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs4, int(W * 0.035), Color(0, 0, 0, fa))
		c.draw_string(font, Vector2(-tw2 * 0.5, fs4 * 0.35), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs4, Color(cm.stamp[1], fa))
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if kind != "ko":
		var fs5 = int(W * 0.026)
		var hint = "tap to continue" if cm.hold else "tap to skip"
		var hw = font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, fs5).x
		c.draw_string(font, Vector2(W * 0.5 - hw * 0.5, H - W * 0.03), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, fs5, Color(1, 1, 1, 0.45 * fa))
	# weißer Blitz beim Übergang von der Kamerafahrt
	if kind == "win" and t < 0.2:
		c.draw_rect(Rect2(Vector2.ZERO, sz), Color(1, 1, 1, 1.0 - t / 0.2))


func _cm_panel(c: Control, font: Font, pd: Dictionary, base: Array, side: float, t: float, a: float, sh: Vector2, fa: float, W: float, kind: String) -> void:
	var ch: Array = pd.ch
	var col: Color = ch[2]
	var e = _ease_back(a)
	var off = Vector2(side * (1.0 - e) * W * 1.1, 0.0) + sh
	if kind == "ko":
		off = Vector2(0.0, -(1.0 - e) * W * 1.2) + sh
	var poly = PackedVector2Array()
	for pt in base:
		poly.append(pt + off)
	var mn = poly[0]
	var mx = poly[0]
	for pt in poly:
		mn = Vector2(minf(mn.x, pt.x), minf(mn.y, pt.y))
		mx = Vector2(maxf(mx.x, pt.x), maxf(mx.y, pt.y))
	var bw = mx.x - mn.x
	var bh = mx.y - mn.y
	# Bild: füllt das Panel, langsamer Zoom und Schwenk (Ken Burns)
	var img: Texture2D = pd.img
	var isz = img.get_size()
	var cover = maxf(bw / isz.x, bh / isz.y)
	var zt = clampf((t - pd.t0) / 3.0, 0.0, 1.0)
	var zoom = cover * (1.06 - 0.05 * zt)
	var pc = (mn + mx) * 0.5 + Vector2(side * W * 0.02 * zt, 0.0)
	var uvs = PackedVector2Array()
	for pt in poly:
		uvs.append(((pt - pc) / zoom + isz * Vector2(0.5, pd.fy)) / isz)
	var cs = PackedColorArray()
	var fl = clampf(1.0 - (t - pd.t0 - 0.3) / 0.12, 0.0, 1.0) if t > pd.t0 + 0.3 else 0.0   # Aufblitzen beim Aufprall
	for _k in range(4):
		cs.append(Color(1.0 + fl * 2.0, 1.0 + fl * 2.0, 1.0 + fl * 2.0, fa))
	c.draw_polygon(poly, cs, uvs, img)
	# Rahmen: dick schwarz, innen eine feine Linie in der Fahrerfarbe
	var cl = poly.duplicate()
	cl.append(poly[0])
	c.draw_polyline(cl, Color(0, 0, 0, fa), W * 0.014, true)
	var inner = PackedVector2Array()
	var pm = (mn + mx) * 0.5
	for pt in cl:
		inner.append(pt + (pm - pt).normalized() * W * 0.012)
	c.draw_polyline(inner, Color(col, 0.9 * fa), 2.0, true)
	var small = bw < W * 0.5
	# Name in der unteren Ecke, schräg gesetzt
	if kind != "ko":
		var fs = int(bw * (0.2 if small else 0.115))
		var nm: String = ch[0]
		var nw = font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var by = poly[3].y if side > 0.0 else poly[2].y
		var nx = poly[3].x + bw * 0.05 if side > 0.0 else poly[2].x - bw * 0.05 - nw
		var npos = Vector2(nx, by - bw * (0.07 if small else 0.06))
		c.draw_set_transform(npos, -0.06, Vector2.ONE)
		c.draw_string_outline(font, Vector2.ZERO, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(W * (0.016 if small else 0.022)), Color(0, 0, 0, fa))
		c.draw_string(font, Vector2.ZERO, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col, fa))
		if not small:
			var fs2 = int(W * 0.032)
			var sub: String = ch[1]
			c.draw_string_outline(font, Vector2(4, fs2 * 1.3), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, int(W * 0.012), Color(0, 0, 0, fa))
			c.draw_string(font, Vector2(4, fs2 * 1.3), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, Color(1, 1, 1, fa))
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Sprechblase: ploppt kurz nach dem Panel auf, Spitze zeigt zum Gesicht
	var b = clampf((t - pd.t0 - 0.32) / 0.18, 0.0, 1.0)
	if b <= 0.0:
		return
	var bs = _ease_back(b)
	var fs3 = int(W * (0.034 if small else 0.04))
	var lines: PackedStringArray = str(pd.line).split("\n")
	var tw = 0.0
	for ln in lines:
		tw = maxf(tw, font.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, fs3).x)
	var rx = tw * 0.5 + W * (0.035 if small else 0.05)
	var ry = lines.size() * fs3 * 0.62 + W * 0.03
	var topy = minf(poly[0].y, poly[1].y)
	var bc: Vector2
	if small:
		bc = Vector2(pm.x, topy + ry + W * 0.02)
	else:
		bc = Vector2(mx.x - rx - W * 0.03 if side > 0.0 else mn.x + rx + W * 0.03, topy + ry + W * 0.035)
	var face = pc + Vector2(-side * W * 0.04, -bh * 0.05) if not small else pm + Vector2(0, bh * 0.1)
	var dirf = (face - bc).normalized()
	var tip = bc + dirf * (maxf(rx, ry) * 0.9 + W * (0.04 if small else 0.07))
	var tb = Vector2(-dirf.y, dirf.x) * W * 0.025
	var ell = PackedVector2Array()
	for k2 in range(28):
		var an = k2 * TAU / 28.0
		ell.append(bc + Vector2(cos(an) * rx, sin(an) * ry) * bs)
	var tail = PackedVector2Array([bc + tb * bs + dirf * ry * 0.6 * bs, tip * bs + bc * (1.0 - bs), bc - tb * bs + dirf * ry * 0.6 * bs])
	var ol = W * 0.009
	c.draw_colored_polygon(tail, Color(0, 0, 0, fa))
	var big = PackedVector2Array()
	for pt in ell:
		big.append(bc + (pt - bc) * (1.0 + ol / maxf(rx, 1.0)))
	c.draw_colored_polygon(big, Color(0, 0, 0, fa))
	c.draw_colored_polygon(ell, Color(0.97, 0.96, 0.93, fa))
	var tin = PackedVector2Array([tail[0].lerp(bc, 0.15), tail[1].lerp(bc, 0.12), tail[2].lerp(bc, 0.15)])
	c.draw_colored_polygon(tin, Color(0.97, 0.96, 0.93, fa))
	if bs > 0.6:
		for j in range(lines.size()):
			var lw = font.get_string_size(lines[j], HORIZONTAL_ALIGNMENT_LEFT, -1, fs3).x
			var ly = bc.y - (lines.size() - 1) * fs3 * 0.55 + j * fs3 * 1.1 + fs3 * 0.35
			c.draw_string(font, Vector2(bc.x - lw * 0.5, ly), lines[j], HORIZONTAL_ALIGNMENT_LEFT, -1, fs3, Color(0.05, 0.03, 0.03, fa))


# ---------------------------------------------------------------- Zieleinlauf: Kamerafahrt ums Siegerschiff, dann Comic, dann Ergebnis
var fin = {}


func _fin_flow(place: int, out := false) -> void:
	if int(cfg.get("comic", 1)) != 1 or not rpf.is_empty():
		_show_resb()
		if place == 1 and not out:
			_victory()
		return
	var win = place == 1 and not out
	var who = 0
	if not win:
		# Sieger: wer am schnellsten im Ziel war, sonst wer vorne liegt
		var best = 1e9
		var bz = -1e9
		for i in range(1, ships.size()):
			var o: Dictionary = ships[i]
			if o.fin > 0.0 and o.fin < best:
				best = o.fin
				who = i
		if who == 0:
			for i in range(1, ships.size()):
				if not ships[i].out and ships[i].z > bz:
					bz = ships[i].z
					who = i
		who = maxi(who, 1)
	fin = {"t": 0.0, "win": win, "who": who, "fly": win and not ships[0].out, "phase": 0}
	hud.layer.visible = false


func _fin_update(dt: float) -> void:
	if fin.is_empty():
		return
	fin.t += dt
	if OS.get_environment("FINT") != "" and fin.t >= float(OS.get_environment("FINT")):
		get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOTPATH"))
		get_tree().quit()
	var fly_t = FLY_T
	if fin.fly and fin.phase == 0 and fin.t >= 6.6 and not fin.has("lbl"):
		# an den Düsen: Platz und Zeit einblenden
		var cl = CanvasLayer.new()
		cl.layer = 9
		cl.set_meta("rfx", true)
		add_child(cl)
		var l = _lbl(str(hud.res.text).replace("  ·  ", "\n"), 84)
		l.add_theme_color_override("font_color", Color(1.0, 0.86, 0.35))
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		l.add_theme_constant_override("outline_size", 14)
		l.set_anchors_preset(Control.PRESET_TOP_WIDE)
		l.offset_top = 260
		l.modulate.a = 0.0
		cl.add_child(l)
		create_tween().tween_property(l, "modulate:a", 1.0, 0.4)
		fin.lbl = cl
	if fin.phase == 0:
		var wait = fly_t if fin.fly else 1.2
		if fin.t >= wait:
			fin.phase = 1
			if fin.has("lbl") and is_instance_valid(fin.lbl):
				(fin.lbl as Node).queue_free()
			_comic_start("win" if fin.win else "lose", fin.who)
	elif fin.phase == 1 and cm.is_empty():
		fin.phase = 2
		hud.layer.visible = true
		_show_resb()
		fin = {}


# Kamerafahrt in Schiffs-Koordinaten (Nase +z): ganz nah an die Düsen, an der Seite entlang über die 37,
# um die Nase herum und dann hoch nach oben weg
const FLY = [[0.0, Vector3(-0.8, 0.9, -2.9), Vector3(0.0, 0.12, -0.3)], [1.5, Vector3(-1.9, 0.6, -0.2), Vector3(0.0, 0.12, 0.0)],
	[2.9, Vector3(-0.6, 0.45, 2.6), Vector3(0.0, 0.12, 0.2)], [4.3, Vector3(-1.6, 0.4, 0.3), Vector3(0.0, 0.12, -0.1)],
	[5.7, Vector3(-1.0, 0.35, -1.6), Vector3(0.0, 0.13, -0.5)], [7.0, Vector3(-0.3, 0.3, -2.0), Vector3(0.0, 0.14, -0.72)],
	[9.0, Vector3(-0.28, 0.3, -2.05), Vector3(0.0, 0.14, -0.72)]]
const FLY_T = 8.6   # danach kommt die Comic-Seite


func _fly_cam(dt: float) -> bool:
	if fin.is_empty() or not fin.fly or fin.phase != 0:
		return false
	var nd: Node3D = ships[0].node
	# geglättete Schiffslage: Schweben und Nachfedern reißen die Kamera nicht mit
	var cur: Transform3D = nd.global_transform
	if not fin.has("cx"):
		fin.cx = cur
	var sm: Transform3D = fin.cx
	var k = 1.0 - exp(-dt / 0.35)
	var q0 = sm.basis.get_rotation_quaternion()
	var q1 = cur.basis.get_rotation_quaternion()
	sm = Transform3D(Basis(q0.slerp(q1, k)), sm.origin.lerp(cur.origin, 1.0 - exp(-dt / 0.12)))
	fin.cx = sm
	var xf = sm
	var t: float = fin.t
	var ki = 0
	while ki < FLY.size() - 2 and t > FLY[ki + 1][0]:
		ki += 1
	var u = clampf((t - FLY[ki][0]) / (FLY[ki + 1][0] - FLY[ki][0]), 0.0, 1.0)
	u = u * u * (3.0 - 2.0 * u) * 0.35 + u * 0.65   # weich anfahren und abbremsen, ohne stehenzubleiben
	var pos = _cr(FLY, ki, u, 1)
	var tg = _cr(FLY, ki, u, 2)
	var wp: Vector3 = xf * pos
	var wt: Vector3 = xf * tg
	var up: Vector3 = xf.basis.y.normalized()
	if (wt - wp).normalized().abs().dot(up.abs()) > 0.98:
		up = xf.basis.z.normalized()
	cam.global_position = wp
	cam.look_at(wt, up)
	cam.fov = 50.0
	return true


# Catmull-Rom zwischen den Stützpunkten k und k+1 (Spalte col der Tabelle)
func _cr(P: Array, k: int, u: float, col: int) -> Vector3:
	var p0: Vector3 = P[maxi(k - 1, 0)][col]
	var p1: Vector3 = P[k][col]
	var p2: Vector3 = P[k + 1][col]
	var p3: Vector3 = P[mini(k + 2, P.size() - 1)][col]
	var u2 = u * u
	var u3 = u2 * u
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u3)


# ---------------------------------------------------------------- Ladebildschirm: Manga-Splash, Drachenschuppen-Balken, Spruch
# hängt am Fenster (nicht an der Szene), damit er das Neuladen überlebt
static var ld: CanvasLayer = null


func _ld_show(p: float) -> void:
	if ld != null and is_instance_valid(ld):
		_ld_set(p)
		return
	ld = CanvasLayer.new()
	ld.layer = 100
	var box = Control.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	ld.add_child(box)
	var bg = ColorRect.new()
	bg.color = Color(0.02, 0.015, 0.02)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_child(bg)
	var who = randi() % 4
	var ch: Array = CHARS[who]
	var tr = TextureRect.new()
	tr.texture = _cm_img("load_" + ch[3])
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_child(tr)
	var q = RichTextLabel.new()
	q.bbcode_enabled = true
	q.fit_content = true
	q.scroll_active = false
	q.mouse_filter = Control.MOUSE_FILTER_IGNORE
	q.add_theme_font_size_override("normal_font_size", 34)
	q.add_theme_constant_override("outline_size", 8)
	q.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	var line: String = _pick(CM_LINES[ch[3]]).replace("\n", " ")
	q.text = "[center][color=#%s]%s:[/color]  “%s”[/center]" % [ch[2].to_html(false), ch[0], line]
	q.anchor_left = 0.06
	q.anchor_right = 0.94
	q.anchor_top = 0.84
	q.anchor_bottom = 0.84
	q.offset_bottom = 60
	box.add_child(q)
	# Balken: dunkler Rahmen, darin rote Schuppen, die sich füllen
	var fr = ColorRect.new()
	fr.color = Color(0.0, 0.0, 0.0, 0.9)
	fr.anchor_left = 0.1
	fr.anchor_right = 0.9
	fr.anchor_top = 0.905
	fr.anchor_bottom = 0.905
	fr.offset_top = -4
	fr.offset_bottom = 26
	box.add_child(fr)
	var edge = ReferenceRect.new()
	edge.border_color = Color(0.85, 0.1, 0.14)
	edge.border_width = 2.0
	edge.editor_only = false
	edge.set_anchors_preset(Control.PRESET_FULL_RECT)
	fr.add_child(edge)
	var fill = TextureRect.new()
	fill.texture = _scale_tex()
	fill.stretch_mode = TextureRect.STRETCH_TILE
	fill.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fill.anchor_top = 0.0
	fill.anchor_bottom = 1.0
	fill.anchor_left = 0.0
	fill.anchor_right = 0.0
	fill.offset_left = 4
	fill.offset_top = 4
	fill.offset_bottom = -4
	fr.add_child(fill)
	var lb = Label.new()
	lb.text = "LOADING"
	lb.add_theme_font_size_override("font_size", 22)
	lb.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	lb.anchor_left = 0.1
	lb.anchor_right = 0.9
	lb.anchor_top = 0.935
	lb.anchor_bottom = 0.935
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(lb)
	ld.set_meta("fill", fill)
	ld.set_meta("box", box)
	get_tree().root.add_child(ld)
	_ld_set(p)


func _ld_set(p: float) -> void:
	if ld == null or not is_instance_valid(ld):
		return
	var fill: TextureRect = ld.get_meta("fill")
	var pp = maxf(float(ld.get_meta("p", 0.0)), clampf(p, 0.0, 1.0))
	ld.set_meta("p", pp)
	fill.anchor_right = pp
	fill.offset_right = -4.0 * pp


func _ld_hide() -> void:
	if ld == null or not is_instance_valid(ld):
		return
	_ld_set(1.0)
	var box: Control = ld.get_meta("box")
	var l = ld
	ld = null
	var tw = create_tween()
	tw.tween_interval(0.15)
	tw.tween_property(box, "modulate:a", 0.0, 0.35)
	tw.tween_callback(l.queue_free)


var _scale_t: ImageTexture = null
func _scale_tex() -> ImageTexture:
	if _scale_t != null:
		return _scale_t
	# Drachenschuppen: Halbkreise versetzt, heller Rand oben, dunkle Fuge
	var im = Image.create(24, 22, false, Image.FORMAT_RGBA8)
	for y in range(22):
		for x in range(24):
			var best = 99.0
			for cy in [0.0, 11.0, 22.0]:
				var ox = 12.0 if int(cy) % 22 == 11 else 0.0
				for cx in [ox - 24.0, ox, ox + 24.0]:
					var d = Vector2(x + 0.5 - cx, (y + 0.5 - cy) * 1.15).length()
					if y + 0.5 >= cy - 2.0:
						best = minf(best, d)
			var e = clampf((best - 8.5) / 2.5, 0.0, 1.0)
			var hl = clampf(1.0 - best / 12.0, 0.0, 1.0)
			var c = Color(0.62, 0.03, 0.06).lerp(Color(0.95, 0.2, 0.18), hl * 0.6).lerp(Color(0.15, 0.0, 0.02), e)
			im.set_pixel(x, y, c)
	_scale_t = ImageTexture.create_from_image(im)
	return _scale_t


# Neu laden mit Ladebildschirm: erst das Bild zeigen, dann die Szene bauen (das hängt ein paar Sekunden)
func _reload() -> void:
	_ld_show(0.12)
	await get_tree().process_frame
	await get_tree().process_frame
	_ld_set(0.3)
	await get_tree().process_frame
	get_tree().reload_current_scene()


# ---------------------------------------------------------------- Cyber-Gothic-HUD
# Tempo: Bogen aus 17 Schuppen über einem Spitzbogen; Boost lässt die Schuppen rot glühen und pulsieren.
# Energie: zehn schmale Spitzbogen-Fenster darunter, unter 25 % flackern sie und bekommen Risse.
func _gh_scale(c: Control, ctr: Vector2, a0: float, a1: float, r0: float, r1: float, col: Color, out: Color) -> void:
	var am = (a0 + a1) * 0.5
	var pts = PackedVector2Array()
	for k in range(5):
		var a = lerpf(a0, a1, k / 4.0)
		pts.append(ctr + Vector2(cos(a), sin(a)) * r0)
	pts.append(ctr + Vector2(cos(a1), sin(a1)) * (r1 - (r1 - r0) * 0.25))
	pts.append(ctr + Vector2(cos(am), sin(am)) * (r1 + (r1 - r0) * 0.18))   # Schuppenspitze
	pts.append(ctr + Vector2(cos(a0), sin(a0)) * (r1 - (r1 - r0) * 0.25))
	c.draw_colored_polygon(pts, col)
	var ol = pts.duplicate()
	ol.append(pts[0])
	c.draw_polyline(ol, out, 1.6, true)


func _gh_lancet(c: Control, x: float, y: float, w: float, h: float, col: Color, out: Color, fill := true) -> void:
	# schmales Spitzbogen-Fenster (unten gerade, oben spitz zulaufend)
	var pts = PackedVector2Array([Vector2(x, y + h), Vector2(x, y + w * 0.6)])
	for k in range(1, 7):
		var u = k / 6.0
		pts.append(Vector2(x + w * 0.5 * (1.0 - cos(u * PI * 0.5)), y + w * 0.6 * (1.0 - sin(u * PI * 0.5)) - w * 0.55 * u))
	for k in range(5, -1, -1):
		var u = k / 6.0
		pts.append(Vector2(x + w - w * 0.5 * (1.0 - cos(u * PI * 0.5)), y + w * 0.6 * (1.0 - sin(u * PI * 0.5)) - w * 0.55 * u))
	pts.append(Vector2(x + w, y + h))
	if fill:
		c.draw_colored_polygon(pts, col)
	var ol = pts.duplicate()
	ol.append(pts[0])
	c.draw_polyline(ol, out, 1.5, true)


func _gh_draw(c: Control) -> void:
	if ships.is_empty() or not hud.has("gs"):
		return
	var g: Dictionary = ships[0]
	var t = Time.get_ticks_msec() / 1000.0
	var ctr = Vector2(186, 292)
	var top = 1.6 * maxf(1.0, base_spd)
	var fr = clampf(float(hud.gs) / top, 0.0, 1.0)
	var bo = clampf(g.boost, 0.0, 1.0)
	var n = 17
	var a0 = PI * 1.02
	var a1 = PI * 1.98
	var lit = fr * n
	# Rahmen: dunkler Spitzbogen hinter dem Bogen, feine Zierlinien
	var frame = PackedVector2Array()
	for k in range(33):
		var a = lerpf(a0 - 0.1, a1 + 0.1, k / 32.0)
		frame.append(ctr + Vector2(cos(a), sin(a)) * 152.0)
	frame.append(ctr + Vector2(150, 28))
	frame.append(ctr + Vector2(-150, 28))
	c.draw_colored_polygon(frame, Color(0.02, 0.01, 0.03, 0.55))
	var fo = frame.duplicate()
	fo.append(frame[0])
	c.draw_polyline(fo, Color(0.75, 0.1, 0.16, 0.7), 2.0, true)
	c.draw_arc(ctr, 96.0, a0, a1, 40, Color(0.75, 0.1, 0.16, 0.45), 1.5, true)
	c.draw_line(ctr + Vector2(0, -150), ctr + Vector2(0, -168), Color(0.85, 0.15, 0.2, 0.8), 2.0, true)   # Turmspitze
	c.draw_circle(ctr + Vector2(0, -172), 3.5, Color(1.0, 0.25, 0.3, 0.9))
	for k in range(n):
		var sa = lerpf(a0, a1, float(k) / n) + 0.012
		var sb = lerpf(a0, a1, float(k + 1) / n) - 0.012
		var f = clampf(lit - k, 0.0, 1.0)
		var base = Color(0.16, 0.12, 0.15, 0.75)
		var hot = Color(0.95, 0.95, 1.0).lerp(Color(0.4, 0.95, 1.0), float(k) / n)
		if bo > 0.02:
			var pu = 0.6 + 0.4 * sin(t * 18.0 - k * 0.6)
			hot = Color(1.0, 0.2 + 0.25 * pu, 0.18) * (1.0 + 0.6 * pu)
		var col = base.lerp(hot, f)
		col.a = 0.75 + 0.25 * f
		_gh_scale(c, ctr, sa, sb, 104.0, 134.0 + 6.0 * f * bo, col, Color(0, 0, 0, 0.85))
	# Tempo-Zahl in der Mitte
	var font = c.get_theme_default_font()
	var v = int(round(float(hud.gs) * 12.0))
	var vs = str(v)
	var fs = 54
	var vw = font.get_string_size(vs, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var vc = Color(1.0, 0.35, 0.3) if bo > 0.02 else Color(0.92, 0.96, 1.0)
	c.draw_string_outline(font, ctr + Vector2(-vw * 0.5, -30), vs, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 8, Color(0, 0, 0, 0.9))
	c.draw_string(font, ctr + Vector2(-vw * 0.5, -30), vs, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, vc)
	var ks = "BOOST" if bo > 0.02 else "KM/H"
	var kw = font.get_string_size(ks, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	c.draw_string(font, ctr + Vector2(-kw * 0.5, -6), ks, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(vc, 0.75))
	# Energie: zehn Fenster
	var en = clampf(g.en, 0.0, 1.0)
	var low = en <= 0.25 and not g.out
	var ec = Color(0.36, 1.0, 0.6) if en > 0.5 else (Color(1.0, 0.85, 0.25) if en > 0.25 else Color(1.0, 0.25, 0.2))
	var x0 = ctr.x - 132.0
	var wsl = 24.0
	for k in range(10):
		var f2 = clampf(en * 10.0 - k, 0.0, 1.0)
		var cc = Color(0.12, 0.1, 0.12, 0.7).lerp(ec, f2)
		if low and f2 > 0.0:
			cc.a *= 0.55 + 0.45 * float(fmod(t * 7.0 + k * 0.37, 1.0) < 0.6)
		var xx = x0 + k * (wsl + 3.0)
		_gh_lancet(c, xx, ctr.y + 40.0, wsl, 44.0, cc, Color(0, 0, 0, 0.9))
		if low and k == int(en * 10.0):
			# Riss quer durchs angebrochene Fenster
			c.draw_polyline(PackedVector2Array([Vector2(xx + 3, ctr.y + 58), Vector2(xx + 11, ctr.y + 66), Vector2(xx + 8, ctr.y + 74), Vector2(xx + 20, ctr.y + 82)]), Color(0, 0, 0, 0.9), 2.0, true)
	var es = "ENERGY  %d %%" % int(round(en * 100.0))
	c.draw_string_outline(font, Vector2(x0, ctr.y + 110), es, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 6, Color(0, 0, 0, 0.8))
	c.draw_string(font, Vector2(x0, ctr.y + 110), es, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(ec, 0.85))


# Waffen-Medaillon: Dornenkranz, Doppelring mit Zierpunkten, vier Spitzbögen; Super = gold, Mega = rot
func _gh_medal(c: Control, ctr: Vector2, t: float, oc: Color) -> void:
	var g: Dictionary = ships[0]
	var col = oc
	if g.get("mega", false):
		col = Color(1.0, 0.15, 0.2)
	elif g.get("sup", false):
		col = Color(1.0, 0.8, 0.25)
	var pu = 0.5 + 0.5 * sin(t * 5.0)
	# Dornenkranz, dreht sich langsam
	var sp = PackedVector2Array()
	var nsp = 16
	for k in range(nsp * 2 + 1):
		var a = t * 0.4 + k * PI / nsp
		var r = 124.0 + 8.0 * pu if k % 2 == 0 else 106.0
		sp.append(ctr + Vector2(cos(a), sin(a)) * r)
	c.draw_polyline(sp, Color(col, 0.75), 2.5, true)
	c.draw_arc(ctr, 100.0, 0.0, TAU, 72, Color(col, 0.95), 5.0, true)
	c.draw_arc(ctr, 90.0, 0.0, TAU, 72, Color(0, 0, 0, 0.6), 2.0, true)
	c.draw_arc(ctr, 86.0, 0.0, TAU, 72, Color(col, 0.6), 2.0, true)
	for k in range(24):
		var a2 = -t * 0.6 + k * TAU / 24.0
		c.draw_circle(ctr + Vector2(cos(a2), sin(a2)) * 93.0, 2.2, Color(col, 0.9))
	# vier Spitzbögen außen (oben, unten, links, rechts)
	for k in range(4):
		var a3 = k * PI * 0.5 - PI * 0.5
		var d = Vector2(cos(a3), sin(a3))
		var q = Vector2(-d.y, d.x)
		var b = ctr + d * 104.0
		c.draw_colored_polygon(PackedVector2Array([b + q * 11.0, b + d * 30.0, b - q * 11.0]), Color(col, 0.85))
		c.draw_polyline(PackedVector2Array([b + q * 11.0, b + d * 30.0, b - q * 11.0]), Color(0, 0, 0, 0.8), 1.5, true)
	# Mega: zusätzlich glühender Außenschein
	if g.get("mega", false):
		c.draw_arc(ctr, 132.0 + 6.0 * pu, 0.0, TAU, 72, Color(1.0, 0.1, 0.15, 0.35 + 0.3 * pu), 7.0, true)


# ---------------------------------------------------------------- Lenk-Teststrecke: gerade Strecke mit Toren
# Slalom (Rhythmus), Spurwechsel (Überschießen) und schmale Ziel-Tore (gezieltes Anfahren wie bei den Säulen).
# Oben rechts ein Knopf für die Einstellleiste (geht ohne PC), unten die Lenkanzeige.
# Tor: [Position in der Runde, Mitte (seitlich), halbe Breite, Abschnitt]
var stt = {}


func _stt_gates() -> Array:
	var out = []
	var sd = 1.0
	for k in range(6):
		out.append([60.0 + k * 38.0, 1.0 * sd, 0.85, 0])
		sd = -sd
	for q in [[300, -1.4], [345, 1.4], [375, 1.4], [420, -1.4], [450, -1.4]]:
		out.append([float(q[0]), float(q[1]), 0.8, 1])
	var rng = RandomNumberGenerator.new()
	rng.seed = 37
	var prev = 0.0
	for k in range(7):
		var lat = rng.randf_range(-1.6, 1.6)
		if absf(lat - prev) < 0.7:
			lat = clampf(-prev * 0.8, -1.6, 1.6)
		prev = lat
		out.append([500.0 + k * 30.0, lat, 0.5, 2])
	return out


const STT_COL = [Color(0.25, 0.9, 1.0), Color(1.0, 0.3, 0.8), Color(1.0, 0.8, 0.25)]
const STT_NAME = ["SLALOM", "LANES", "TARGET"]


func _stt_build() -> void:
	stt = {"g": [], "res": [[0, 0], [0, 0], [0, 0]], "lz": -1.0, "open": false}
	for gd in _stt_gates():
		var m = StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = STT_COL[gd[3]]
		var nd = Node3D.new()
		for sd in [-1.0, 1.0]:
			var post = MeshInstance3D.new()
			var cy = CylinderMesh.new()
			cy.top_radius = 0.04
			cy.bottom_radius = 0.04
			cy.height = 1.1
			cy.radial_segments = 8
			cy.rings = 1
			post.mesh = cy
			post.material_override = m
			post.position = Vector3(sd * float(gd[2]), 0.55, 0)
			post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			nd.add_child(post)
		var bar = MeshInstance3D.new()
		var bx = BoxMesh.new()
		bx.size = Vector3(float(gd[2]) * 2.0 + 0.08, 0.06, 0.06)
		bar.mesh = bx
		bar.material_override = m
		bar.position = Vector3(0, 1.1, 0)
		bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		nd.add_child(bar)
		add_child(nd)
		stt.g.append({"d": gd, "n": nd, "m": m, "done": -1, "fl": 0.0, "ok": false})
	# Anzeige oben, Lenkanzeige unten, Knopf + Einstellleiste
	var cl = CanvasLayer.new()
	cl.layer = 7
	add_child(cl)
	stt.cl = cl
	var lb = _lbl("", 26)
	lb.set_anchors_preset(Control.PRESET_TOP_WIDE)
	lb.offset_top = 470
	lb.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	lb.add_theme_constant_override("outline_size", 8)
	cl.add_child(lb)
	stt.lb = lb
	var ind = Control.new()
	ind.set_anchors_preset(Control.PRESET_FULL_RECT)
	ind.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(ind)
	ind.draw.connect(func(): _stt_draw_ind(ind))
	stt.ind = ind
	var gb = _btn("⚙ STEERING")
	gb.add_theme_font_size_override("font_size", 26)
	gb.anchor_left = 1.0
	gb.anchor_right = 1.0
	gb.offset_left = -300
	gb.offset_right = -24
	gb.offset_top = 380
	gb.offset_bottom = 450
	gb.pressed.connect(func():
		stt.open = not stt.open
		(stt.pnl as Control).visible = stt.open)
	cl.add_child(gb)
	stt.gb = gb
	var pnl = PanelContainer.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.03, 0.06, 0.88)
	sb.border_color = Color(0.85, 0.15, 0.2, 0.8)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(18)
	sb.set_content_margin_all(18)
	pnl.add_theme_stylebox_override("panel", sb)
	pnl.anchor_left = 0.04
	pnl.anchor_right = 0.96
	pnl.anchor_bottom = 1.0
	pnl.offset_top = 570
	pnl.offset_bottom = -40
	pnl.visible = false
	cl.add_child(pnl)
	stt.pnl = pnl
	# alles in einer Scrollliste, damit unten nichts abgeschnitten wird
	var psc = ScrollContainer.new()
	psc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pnl.add_child(psc)
	stt.sc = psc
	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	psc.add_child(vb)
	var bcm2 = _btn("")
	bcm2.add_theme_font_size_override("font_size", 24)
	stt.mbtn = bcm2
	bcm2.add_theme_font_size_override("font_size", 30)
	bcm2.clip_text = true
	bcm2.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	bcm2.pressed.connect(func(): _set_ctrl((int(cfg.get("ctrl", 1)) + 1) % 6))
	vb.add_child(bcm2)
	# kurze Erklärung zum Modus unter dem Knopf – bricht um, wird nie breiter als die Leiste
	var mh = _lbl("", 22)
	mh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mh.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mh.modulate = Color(1, 1, 1, 0.65)
	vb.add_child(mh)
	stt.mhint = mh
	var sr = HBoxContainer.new()
	sr.add_theme_constant_override("separation", 10)
	vb.add_child(sr)
	# Tempo stufenlos: 10 … 150 % vom normalen Renntempo
	var sl = Label.new()
	sl.add_theme_font_size_override("font_size", 24)
	sl.custom_minimum_size = Vector2(190, 0)
	sr.add_child(sl)
	var hs = HSlider.new()
	hs.min_value = 0.1
	hs.max_value = 1.5
	hs.step = 0.01
	hs.value = stt_spd
	hs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hs.custom_minimum_size = Vector2(0, 64)
	hs.add_theme_icon_override("grabber", _dot(40))
	hs.add_theme_icon_override("grabber_highlight", _dot(46))
	var tsb = StyleBoxFlat.new()
	tsb.bg_color = Color(1, 1, 1, 0.25)
	tsb.content_margin_top = 6
	tsb.content_margin_bottom = 6
	tsb.set_corner_radius_all(6)
	hs.add_theme_stylebox_override("slider", tsb)
	var upd = func(v: float):
		stt_spd = v
		sl.text = "Tempo %d %%" % int(round(v * 100.0))
	hs.value_changed.connect(upd)
	upd.call(stt_spd)
	sr.add_child(hs)
	stt.sb = hs
	var rowbox = VBoxContainer.new()
	rowbox.add_theme_constant_override("separation", 12)
	vb.add_child(rowbox)
	stt.rowbox = rowbox
	_stt_rows()
	_stt_vals()
	if OS.get_environment("STTOPEN") != "":
		stt.open = true
		pnl.visible = true


func _stt_step(r: Array, sg: float) -> void:
	var g: String = r[0]
	var k: String = r[1]
	for it in FXS[g]:
		if it[0] == k:
			fx[g][k] = clampf(snappedf(float(fx[g][k]) + sg * float(r[3]), 0.01), it[2], it[3])
	_fx_changed(g, k)
	live_sv = 0.8
	_stt_vals()


func _stt_vals() -> void:
	for e in stt.get("rows", []):
		var r: Array = e[0]
		var v = float(fx[r[0]][r[1]])
		(e[1] as Label).text = ("%.2f s" % v) if r[1] in ["ptime", "glide"] else (("An" if v > 0.5 else "Aus") if r[1] == "vib" else (("Aus" if v < 0.01 else "%d %%" % int(round(v * 100.0))) if r[1] == "lbeep" else ("%.2f" % v)))


func _steer_preset(i: int) -> void:
	fx_ver += 1
	var pr: Array = STEER_PRE[clampi(i, 0, STEER_PRE.size() - 1)]
	fx.steer.ptime = pr[1]
	fx.steer.rtime = pr[2]
	fx.steer.delay = 0.0
	fx.ship.steer = pr[3]
	fx.ship.steerk = pr[4]
	fx.ship.grip = pr[5]
	curves.press = (pr[6] as Array).duplicate(true)
	curves.release = (CURVE_DEF.release as Array).duplicate(true)
	for k in curves:
		curve_lut[k] = _curve_bake(curves[k])
	_curves_save()
	live_sv = 0.5
	_stt_vals()
	_toast("Steering: " + str(pr[0]))


func _stt_hit(p: Vector2) -> bool:
	if not stt.has("gb"):
		return false
	if (stt.gb as Control).get_global_rect().has_point(p):
		return true
	return stt.open and (stt.pnl as Control).get_global_rect().has_point(p)


func _stt_update(dt: float) -> void:
	if (state != "race" and state != "done") or warm_t >= 0.0:
		return   # erst nach dem Vorwärmen bauen (das räumt neue Knoten wieder weg)
	if stt.is_empty() or not is_instance_valid(stt.get("cl")):
		_stt_build()
	var g: Dictionary = ships[0]
	var lap = floor((g.z - 20.0) / 700.0)
	var zl = g.z - 20.0 - lap * 700.0 + 20.0
	# Rundenwechsel: Ergebnis zeigen und neu zählen
	if stt.lz > 600.0 and zl < 100.0:
		var tot = 0
		var hit = 0
		for r in stt.res:
			tot += r[1]
			hit += r[0]
		_toast("Runde: %d von %d Toren  ·  %s %d/%d  %s %d/%d  %s %d/%d" % [hit, tot, STT_NAME[0], stt.res[0][0], stt.res[0][1], STT_NAME[1], stt.res[1][0], stt.res[1][1], STT_NAME[2], stt.res[2][0], stt.res[2][1]])
		stt.res = [[0, 0], [0, 0], [0, 0]]
	stt.lz = zl
	for e in stt.g:
		var gd: Array = e.d
		var z = lap * 700.0 + float(gd[0])
		if z < g.z - 40.0:
			z += 700.0
		var f = T.frame(z)
		(e.n as Node3D).global_transform = Transform3D(Basis(f.rr, f.uu, f.fw), f.c + f.rr * float(gd[1]))
		# durchflogen? (jede Runde einmal werten)
		var lid = int(floor((z - 20.0) / 700.0))
		if g.z >= z and e.done != lid and g.z - z < 6.0:
			e.done = lid
			var ok = absf(g.lat - float(gd[1])) <= float(gd[2])
			e.ok = ok
			e.fl = 0.6
			stt.res[gd[3]][1] += 1
			if ok:
				stt.res[gd[3]][0] += 1
				_snd("pick", -10.0, 1.4)
			else:
				_snd("beep", -8.0, 0.6)
		if e.fl > 0.0:
			e.fl -= dt
			(e.m as StandardMaterial3D).albedo_color = (Color(0.3, 1.0, 0.4) if e.ok else Color(1.0, 0.15, 0.1)) if e.fl > 0.0 else STT_COL[gd[3]]
	var sec = 0 if zl < 280.0 else (1 if zl < 480.0 else 2)
	(stt.lb as Label).text = "%s   ·   %d / %d" % [STT_NAME[sec], stt.res[sec][0], stt.res[sec][1]]
	(stt.lb as Label).add_theme_color_override("font_color", STT_COL[sec])
	(stt.ind as Control).queue_redraw()


# Lenkanzeige oben unter dem Abschnitt: Balken füllt sich von der Mitte nach links/rechts.
# Orange Linie = dein Finger (Lenkbefehl), grüne Füllung = was das Schiff gerade tut
func _stt_draw_ind(c: Control) -> void:
	if ships.is_empty():
		return
	var g: Dictionary = ships[0]
	var vp = c.size
	var cy = 528.0
	var hw = vp.x * 0.36
	var cx = vp.x * 0.5
	c.draw_rect(Rect2(cx - hw, cy - 10, hw * 2.0, 20), Color(0, 0, 0, 0.45))
	c.draw_rect(Rect2(cx - hw, cy - 10, hw * 2.0, 20), Color(1, 1, 1, 0.3), false, 2.0)
	var cmd = clampf(last_steer, -1.0, 1.0)
	var act = clampf(float(g.u), -1.0, 1.0)
	if absf(act) > 0.005:
		c.draw_rect(Rect2(cx + minf(0.0, act * hw), cy - 8, absf(act) * hw, 16), Color(0.36, 1.0, 0.6, 0.9))
	if absf(cmd) > 0.005:
		c.draw_rect(Rect2(cx + minf(0.0, cmd * hw), cy + 12, absf(cmd) * hw, 5), Color(1.0, 0.5, 0.2, 0.95))
	c.draw_line(Vector2(cx, cy - 16), Vector2(cx, cy + 20), Color(1, 1, 1, 0.7), 2.0)
	var font = c.get_theme_default_font()
	var s = "%d %%" % int(round(absf(act) * 100.0))
	var w = font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	var tx = cx + hw + 12.0
	c.draw_string_outline(font, Vector2(tx, cy + 8), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 6, Color(0, 0, 0, 0.8))
	c.draw_string(font, Vector2(tx, cy + 8), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, 0.85))


# ---------------------------------------------------------------- Gothic-Altar-HUD
# Der Rahmen ist ein Bild (art/hud/frame.png, 941×1672): oberer Teil oben angeheftet, unterer Teil unten.
# Alle Koordinaten unten sind Bildpunkte im Rahmenbild; gezeichnet wird mit dem Maßstab Bildschirmbreite/941.
const GA_W = 941.0
const GA_H = 1672.0
var ga_tex: Texture2D = null
var ga_font: FontVariation = null
var ga_rl = {}        # Roulette: {"t", "seq", "fin"}
var ga_last = ""


func _ga_frame(g: Dictionary, dt: float) -> void:
	# alte Anzeigen weg, die der Rahmen ersetzt
	hud.plbox.visible = false
	hud.ring.visible = false
	if state in ["race", "count", "intro"]:
		hud.top.modulate.a = 0.0
	else:
		hud.top.modulate.a = 1.0
	# FIRE-Trefferfläche: das ganze Waffenrad samt FIRE-Knopf
	var k = get_viewport().get_visible_rect().size.x / GA_W
	var f: Label = hud.fire
	f.modulate.a = 0.0
	if int(cfg.get("ctrl", 1)) >= 1:
		# Wisch-Lenkung: nur der kleine FIRE-Kreis feuert, der Rest ist Lenkfläche
		f.offset_left = -62.0 * k
		f.offset_right = 62.0 * k
		f.offset_top = -(GA_H - 1478.0) * k
		f.offset_bottom = -(GA_H - 1590.0) * k
	else:
		f.offset_left = -150.0 * k
		f.offset_right = 150.0 * k
		f.offset_top = -(GA_H - 1250.0) * k
		f.offset_bottom = -(GA_H - 1585.0) * k
	# Roulette starten, wenn eine neue Waffe eingesammelt wurde
	var w: String = g.wpn
	if w != ga_last:
		if w != "" and state == "race":
			var seq = []
			for i in range(13):
				seq.append(WP[randi() % WP.size()][0])
			seq.append(w)
			ga_rl = {"t": 0.0, "seq": seq, "i": -1}
		ga_last = w
	if not ga_rl.is_empty():
		ga_rl.t += dt
		var n: int = ga_rl.seq.size()
		var u = clampf(ga_rl.t / 1.15, 0.0, 1.0)
		var idx = mini(n - 1, int(floor((1.0 - pow(1.0 - u, 2.6)) * (n - 1) + 0.0001)))
		if idx != ga_rl.i:
			ga_rl.i = idx
			_snd("beep", -16.0, 2.2 if idx < n - 1 else 1.4)
		if ga_rl.t > 1.6:
			ga_rl = {}
	hud.gs = lerpf(float(hud.gs), g.spd, 1.0 - exp(-dt / 0.15))
	(hud.ga as Control).queue_redraw()


func _ga_txt(c: Control, p: Vector2, s: String, sz: int, col: Color, al := 0, ol := 0) -> void:
	# al: 0 links, 1 Mitte, 2 rechts (an p ausgerichtet)
	if ga_font == null:
		ga_font = FontVariation.new()
		ga_font.base_font = c.get_theme_default_font()
		ga_font.variation_embolden = 0.9
		ga_font.variation_transform = Transform2D(Vector2(1, 0), Vector2(-0.22, 1), Vector2.ZERO)
	var w = ga_font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	var q = p - Vector2(w * (0.5 if al == 1 else (1.0 if al == 2 else 0.0)), 0.0)
	if ol > 0:
		c.draw_string_outline(ga_font, q, s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, ol, Color(0, 0, 0, 0.9))
	c.draw_string(ga_font, q, s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)


func _ga_wsel(i: int) -> String:
	return WP[posmod(i, WP.size())][0]


func _ga_widx(w: String) -> int:
	for i in range(WP.size()):
		if WP[i][0] == w:
			return i
	return 0


func _ga_draw(c: Control) -> void:
	if ships.is_empty():
		return
	if ga_tex == null:
		ga_tex = load("res://art/hud/frame.png")
	var g: Dictionary = ships[0]
	var vp = c.size
	var k = vp.x / GA_W
	var t = Time.get_ticks_msec() / 1000.0
	var OR2 = Color(1.0, 0.55, 0.15)
	var TXT = Color(1.0, 0.82, 0.62)
	# ---- oben
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2(k, k))
	c.draw_texture_rect_region(ga_tex, Rect2(0, 0, GA_W, 420), Rect2(0, 0, GA_W, 420))
	_ga_txt(c, Vector2(72, 150), "POS", 22, OR2)
	if free_ride:
		_ga_txt(c, Vector2(72, 200), "FREE", 46, TXT, 0, 6)
	else:
		var pl = str(hud.pl.text).substr(0, 1)
		_ga_txt(c, Vector2(150, 202), pl if pl != "" else "-", 62, Color(1, 1, 1), 2, 6)
		_ga_txt(c, Vector2(156, 202), str(hud.pln.text), 34, TXT, 0, 5)
	var lap = clampi(int(floor((g.z - T.ZST) / T.LAP)) + 1, 1, 99)
	_ga_txt(c, Vector2(668, 150), "LAP", 22, OR2)
	_ga_txt(c, Vector2(872, 160), ("%d" % lap) if free_ride else ("%d/%d" % [mini(lap, T.LAPS), T.LAPS]), 44, Color(1, 1, 1), 2, 6)
	_ga_txt(c, Vector2(646, 226), "TIME", 20, OR2)
	_ga_txt(c, Vector2(868, 234), _fmt(race_t), 32, TXT, 2, 5)
	# ---- unten
	var oy = vp.y - GA_H * k
	c.draw_set_transform(Vector2(0, oy), 0.0, Vector2(k, k))
	c.draw_texture_rect_region(ga_tex, Rect2(0, 1100, GA_W, GA_H - 1100), Rect2(0, 1100, GA_W, GA_H - 1100))
	# Tempo
	var bo = clampf(g.boost, 0.0, 1.0)
	var sc = Color(1.0, 0.3, 0.2) if bo > 0.02 else Color(1, 1, 1)
	_ga_txt(c, Vector2(62, 1497), "BOOST" if bo > 0.02 else "SPEED", 20, Color(1.0, 0.3, 0.2) if bo > 0.02 else OR2)
	_ga_txt(c, Vector2(232, 1540), str(int(round(float(hud.gs) * 12.0))), 52, sc, 2, 6)
	_ga_txt(c, Vector2(240, 1538), "KM/H", 16, TXT)
	# Energie: zehn schräge Segmente
	var en = clampf(g.en, 0.0, 1.0)
	var low = en <= 0.25 and not g.out
	var ec = OR2 if en > 0.5 else (Color(1.0, 0.85, 0.25) if en > 0.25 else Color(1.0, 0.2, 0.15))
	_ga_txt(c, Vector2(646, 1497), "ENERGY", 20, ec)
	_ga_txt(c, Vector2(880, 1497), "%d %%" % int(round(en * 100.0)), 20, TXT, 2)
	for i in range(10):
		var x0 = 648.0 + i * 24.0
		var fl = clampf(en * 10.0 - i, 0.0, 1.0)
		var col = Color(0.18, 0.1, 0.06, 0.9).lerp(ec, fl)
		if low and fl > 0.0 and fmod(t * 7.0 + i * 0.37, 1.0) > 0.6:
			col.a *= 0.4
		c.draw_colored_polygon(PackedVector2Array([Vector2(x0 + 9, 1506), Vector2(x0 + 29, 1506), Vector2(x0 + 20, 1534), Vector2(x0, 1534)]), col)
	# Waffenrad: Mitte = deine Waffe, links/rechts die Nachbarn; beim Einsammeln rattert es durch (Roulette)
	var w: String = g.wpn
	var cw = w
	var spin = not ga_rl.is_empty() and int(ga_rl.i) < int(ga_rl.seq.size()) - 1
	if not ga_rl.is_empty():
		cw = ga_rl.seq[maxi(0, int(ga_rl.i))]
	var ci = _ga_widx(cw)
	var mega = g.get("mega", false)
	var sup = g.get("sup", false)
	var gc = Color(1.0, 0.15, 0.2) if mega else (Color(1.0, 0.8, 0.25) if sup else WC.get(cw, OR2))
	if cw != "":
		var lw = _ga_wsel(ci - 1)
		var rw = _ga_wsel(ci + 1)
		_wicon(c, Vector2(366, 1352), 26.0, lw, Color(1, 1, 1, 0.3 if not spin else 0.55))
		_wicon(c, Vector2(574, 1352), 26.0, rw, Color(1, 1, 1, 0.3 if not spin else 0.55))
		var bounce = 0.0
		if not ga_rl.is_empty():
			var since = float(ga_rl.t) - 1.15
			if since > 0.0:
				bounce = sin(since * 22.0) * exp(-since * 7.0) * 6.0
		var pu = 0.5 + 0.5 * sin(t * 5.0)
		if not spin:
			# Glühen hinter dem mittleren Feld
			var tr = PackedVector2Array([Vector2(394, 1298), Vector2(548, 1298), Vector2(502, 1430), Vector2(440, 1430), Vector2(394, 1298)])
			c.draw_polyline(tr, Color(gc, 0.35 + 0.4 * pu), 9.0, true)
			c.draw_polyline(tr, Color(gc, 0.9), 3.0, true)
		_wicon(c, Vector2(471, 1340 + bounce), 40.0, cw, Color(1, 1, 1, 0.95) if not spin else Color(1, 1, 1, 0.75))
		var nm = str(WN.get(cw, "")).replace("FORCE FIELD", "FIELD")
		_ga_txt(c, Vector2(471, 1405 + bounce), nm, 22 if nm.length() < 7 else 18, Color(gc, 1.0) if not spin else TXT, 1, 5)
		if (sup or mega) and not spin:
			_ga_txt(c, Vector2(471, 1290), "MEGA" if mega else "SUPER", 18, gc, 1, 5)
	elif g.auto > 0.0:
		_wicon(c, Vector2(471, 1340), 40.0, "auto", Color(0.5, 0.95, 1.0, 0.9))
		_ga_txt(c, Vector2(471, 1405), "AUTO %.1f" % g.auto, 20, Color(0.5, 0.95, 1.0), 1, 5)
	else:
		_ga_txt(c, Vector2(471, 1372), "—", 30, Color(1, 1, 1, 0.25), 1)
	# Autopilot-Restzeit als Bogen ums Rad
	if g.auto > 0.0 and state == "race":
		c.draw_arc(Vector2(467, 1400), 152.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(g.auto / 5.0, 0.0, 1.0), 64, Color(0.4, 0.95, 1.0, 0.9), 6.0, true)
	# FIRE-Knopf: Schwert und Schrift, glüht, wenn eine Waffe bereit ist
	var armed = w != "" and not spin
	var fp = Vector2(470, 1532)
	if armed:
		var pf = 0.5 + 0.5 * sin(t * 6.0)
		c.draw_circle(fp, 44.0, Color(gc, 0.16 + 0.14 * pf))
		c.draw_arc(fp, 47.0, 0.0, TAU, 40, Color(gc, 0.6 + 0.4 * pf), 4.0, true)
	var sw = Color(1, 1, 1, 0.95) if armed else Color(1, 1, 1, 0.3)
	c.draw_line(fp + Vector2(0, -32), fp + Vector2(0, 2), sw, 4.0, true)
	c.draw_line(fp + Vector2(-11, -20), fp + Vector2(11, -20), sw, 4.0, true)
	c.draw_colored_polygon(PackedVector2Array([fp + Vector2(-4, -32), fp + Vector2(0, -40), fp + Vector2(4, -32)]), sw)
	_ga_txt(c, fp + Vector2(0, 30), "FIRE", 20, sw, 1, 4)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ---------------------------------------------------------------- Wisch-Lenkung (unsichtbarer Joystick) und Doppeltipp zum Feuern
# Der erste Daumen auf dem Bildschirm lenkt: wo er aufsetzt, ist die Mitte; nach links/rechts schieben lenkt
# (Stärke über die Kurve „Wischweg“, schnelles Wischen gibt Extra über „Wischtempo“). Schiebt man weiter als
# den vollen Ausschlag, wandert die Mitte mit, damit der Rückweg sofort wirkt. Kurz abheben hält die Lenkung fest.
# Zwei schnelle Tipper (ohne Wischen) – mit welchem Finger auch immer – feuern die Waffe.
var lane_cur = 0      # Spur-Modus: aktuelle Spur −2 … 2
var lane_fl = 0.0     # Aufleuchten beim Einrasten
var ptr_lat = 0.0    # Touchpad-Modus: Spur −1 … 1, bleibt stehen, wenn man loslässt
var glide_in = 0.0   # Gleit-Modus: gewünschte Spur −1 … 1 (aus Wisch-Lenkung)
var sw = {"idx": -1, "ax": 0.0, "x": 0.0, "v": 0.0, "hold": 0.0, "keep": 0.0, "last": 0.0, "m": 0.0, "vm": 0.0}
var tinfo = {}
var tap_last = {"t": -9.0, "p": Vector2.ZERO}


func _sw_w() -> float:
	return maxf(1.0, get_viewport().get_visible_rect().size.x)


func _sw_down(i: int, p: Vector2) -> void:
	tinfo[i] = {"t": Time.get_ticks_msec() / 1000.0, "p": p, "mv": false}
	if int(cfg.get("ctrl", 1)) < 1:
		return
	if int(cfg.get("ctrl", 1)) == 5:
		# Spur antippen: linkes Drittel = eine Spur nach links, rechtes = eine nach rechts, Mitte = Feuer.
		# Das Schiff bleibt auf seiner Spur, bis wieder getippt wird.
		var W = _sw_w()
		if p.x >= W / 3.0 and p.x <= W * 2.0 / 3.0:
			if state == "race":
				fire_req = true
			return
		var dir = -1 if p.x < W / 3.0 else 1
		_lane_step(dir)
		lt_hold = {"i": i, "dir": dir, "t": 0.0}   # drauf bleiben = nach der Haltezeit noch eine Spur weiter
		return
	if sw.idx < 0:
		sw.idx = i
		sw.x = p.x
		sw.v = 0.0
		# kurz abgehoben und wieder aufgesetzt: dort weiterlenken, wo man war
		sw.ax = p.x - (sw.keep if sw.hold > 0.0 else 0.0)
		sw.hold = 0.0
		sw.ext = p.x
		sw.dir = 0


func _sw_drag(i: int, p: Vector2, vel: Vector2) -> void:
	if tinfo.has(i) and p.distance_to(tinfo[i].p) > _sw_w() * 0.03:
		tinfo[i].mv = true
	if i != sw.idx or int(cfg.get("ctrl", 1)) == 5:
		return
	if int(cfg.get("ctrl", 1)) >= 3:
		# wie ein Mauszeiger: nur die Bewegung zählt, Beschleunigung nur im Moment (keine Nachwirkung)
		var W = _sw_w()
		var vn = clampf(absf(vel.x) / (W * 2.0), 0.0, 1.0)
		var gain = float(fx.steer.psens) * (1.0 + float(fx.steer.paccel) * vn * vn)
		if int(cfg.get("ctrl", 1)) == 4:
			gain *= 2.0   # Spuren: ein kurzer Wisch (ca. 1/6 Bildschirmbreite) reicht für eine Spur
		ptr_lat = clampf(ptr_lat + (p.x - sw.x) / W * gain, -1.0, 1.0)
		sw.x = p.x
		return
	sw.x = p.x
	# Richtungswechsel erkennen: weiteste Stelle in Wischrichtung merken; zurück um mehr als den Puffer = Umkehr
	var buf = float(fx.steer.revbuf) * _sw_w()
	var dr = int(sw.get("dir", 0))
	var ext = float(sw.get("ext", p.x))
	if dr == 0:
		if absf(p.x - ext) > buf:
			sw.dir = int(signf(p.x - ext))
			sw.ext = p.x
	elif signf(p.x - ext) == dr:
		sw.ext = p.x
	elif absf(p.x - ext) > buf:
		sw.dir = -dr
		sw.ext = p.x
		sw.v = 0.0
		vel = Vector2.ZERO
		if float(fx.steer.revmode) > 0.5 and int(cfg.get("ctrl", 1)) == 1:
			# Mitte unter den Daumen (plus den Puffer, den er schon zurückgelegt hat): sanftes Gegenlenken ab sofort
			sw.ax = p.x + dr * buf
	sw.v = lerpf(float(sw.v), vel.x, 0.5)
	var rng = float(fx.steer.swrange) * _sw_w()
	var d = sw.x - sw.ax
	if absf(d) > rng:
		sw.ax = sw.x - signf(d) * rng


func _sw_up(i: int, p: Vector2) -> void:
	if int(lt_hold.get("i", -1)) == i:
		lt_hold = {}
	var now = Time.get_ticks_msec() / 1000.0
	if tinfo.has(i):
		var ti: Dictionary = tinfo[i]
		if not ti.mv and now - float(ti.t) < 0.25 and state == "race" and int(cfg.get("ctrl", 1)) != 5:
			if now - float(tap_last.t) < float(fx.steer.dtap) and p.distance_to(tap_last.p) < _sw_w() * 0.18:
				fire_req = true
				tap_last.t = -9.0
			else:
				tap_last.t = now
				tap_last.p = p
		tinfo.erase(i)
	if i == sw.idx:
		sw.idx = -1
		sw.keep = sw.x - sw.ax
		sw.hold = float(fx.steer.hold)
		sw.v = 0.0
		# liegt noch ein anderer Finger auf, übernimmt er das Lenken (ab seiner Position, ohne Sprung)
		for k in touches:
			if k != i:
				sw.idx = k
				sw.x = float(touches[k])
				sw.ax = sw.x - sw.keep
				sw.hold = 0.0
				break


# liefert die Lenkung (−1 … 1) oder null, wenn gerade nichts zu tun ist (dann greift die Loslass-Kurve)
func _sw_steer(dt: float):
	var SD: Dictionary = fx.steer
	if sw.idx >= 0:
		var rng = float(SD.swrange) * _sw_w()
		var d = (sw.x - sw.ax) / maxf(1.0, rng)
		var m = clampf(absf(d), 0.0, 1.0)
		var base = _curve_at("swipe", m)
		# Wischtempo: nur in Richtung des Ausschlags, klingt schnell ab
		var vn = clampf(absf(float(sw.v)) / (_sw_w() * 2.5), 0.0, 1.0)
		var extra = 0.0
		var thr = float(SD.velmin)
		if signf(float(sw.v)) == signf(d) and m > 0.02 and vn > thr:
			extra = _curve_at("swvel", (vn - thr) / maxf(0.05, 1.0 - thr)) * float(SD.velk)
		sw.v = float(sw.v) * exp(-dt / 0.08)
		sw.m = m
		sw.vm = vn
		var st = signf(d) * clampf(base + extra, 0.0, 1.0)
		sw.last = st
		rel_t = 9.0
		return st
	sw.m = 0.0
	if sw.hold > 0.0:
		sw.hold -= dt
		if sw.hold <= 0.0:
			rel_v = float(sw.last)
			rel_t = 0.0
		return float(sw.last)
	return null


# ---------------------------------------------------------------- Fingerscrollen in Listen mit Knöpfen und Reglern
# Senkrecht wischen = scrollen (auch wenn der Finger auf einem Knopf oder Regler startet; der Knopf löst dann nicht aus).
# Regler bewegen sich nur bei einem klar waagrechten Zug. Kurzes Tippen = Knopf wie gewohnt.
var scr = {}


func _scr_prep(sc: ScrollContainer) -> void:
	# Regler nehmen den Finger nicht mehr selbst – wir bewegen sie, wenn der Zug waagrecht ist
	for n in sc.find_children("*", "Slider", true, false):
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE


func _scr_input(ev: InputEvent, sc: ScrollContainer) -> bool:
	if ev is InputEventScreenTouch:
		if ev.pressed:
			if not scr.is_empty() and scr.idx != ev.index:
				return false
			if not sc.get_global_rect().has_point(ev.position):
				return false
			var sl = null
			for n in sc.find_children("*", "Slider", true, false):
				if (n as Control).is_visible_in_tree() and (n as Control).get_global_rect().grow_individual(0, 18, 0, 18).has_point(ev.position):
					sl = n
			scr = {"idx": ev.index, "p": ev.position, "sv": sc.scroll_vertical, "mode": "", "sl": sl, "vel": 0.0, "lt": Time.get_ticks_msec()}
			return false
		if scr.is_empty() or scr.idx != ev.index:
			return false
		var mode: String = scr.mode
		var v = float(scr.vel)
		scr = {}
		if mode == "scroll":
			_scr_fling(sc, v)
			return true
		return mode == "slide"
	if ev is InputEventScreenDrag and not scr.is_empty() and scr.idx == ev.index:
		var d: Vector2 = ev.position - scr.p
		if scr.mode == "":
			if absf(d.y) > 16.0 and absf(d.y) > absf(d.x):
				scr.mode = "scroll"
				_scr_cancel_press()
			elif absf(d.x) > 14.0 and absf(d.x) > absf(d.y) and scr.sl != null:
				scr.mode = "slide"
				_scr_cancel_press()
		if scr.mode == "scroll":
			sc.scroll_vertical = int(float(scr.sv) - d.y)
			var now = Time.get_ticks_msec()
			var dtm = maxf(1.0, float(now - int(scr.lt)))
			scr.vel = lerpf(float(scr.vel), -ev.relative.y / dtm * 1000.0, 0.4)
			scr.lt = now
			return true
		if scr.mode == "slide":
			var sl: Range = scr.sl
			var r = (sl as Control).get_global_rect()
			var f = clampf((ev.position.x - r.position.x) / maxf(1.0, r.size.x), 0.0, 1.0)
			sl.value = lerpf(sl.min_value, sl.max_value, f)
			return true
	return false


# angefangenen Knopfdruck abbrechen, sobald klar ist, dass gescrollt wird
func _scr_cancel_press() -> void:
	var hc = get_viewport().gui_get_hovered_control()
	while hc != null and not (hc is BaseButton):
		hc = hc.get_parent() as Control
	if hc is BaseButton and not (hc as BaseButton).disabled:
		var b: BaseButton = hc
		b.disabled = true
		b.set_deferred("disabled", false)
	get_viewport().gui_release_focus()


# Schwung: nach dem Loslassen läuft die Liste kurz weiter
func _scr_fling(sc: ScrollContainer, v: float) -> void:
	if absf(v) < 200.0:
		return
	var tw = create_tween()
	var target = sc.scroll_vertical + int(v * 0.25)
	tw.tween_property(sc, "scroll_vertical", target, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)



func _set_ctrl(m: int) -> void:
	cfg.ctrl = m
	_save_cfg()
	fx_ver += 1
	ptr_lat = float(lane_cur) if m >= 4 else 0.0
	if not stt.is_empty() and stt.has("rowbox") and is_instance_valid(stt.rowbox):
		_stt_rows()



# Einstellleiste: nur die Regler, die der gewählte Lenkmodus braucht
const STT_ROWS = {
	0: [["ship", "steer", "Trägheit  (weniger = reagiert schneller)", 0.1], ["ship", "steerk", "Lenkkraft  (mehr = engere Kurven)", 0.05],
		["steer", "ptime", "Anlaufzeit  (kürzer = sofort volle Kraft)", 0.05], ["ship", "center", "Auto-Gerade  (mehr = Nase schneller gerade)", 0.25], ["ship", "spdst", "Tempo-Dämpfung  (mehr = ruhiger bei Speed)", 0.1]],
	1: [["ship", "steer", "Trägheit  (weniger = reagiert schneller)", 0.1], ["ship", "steerk", "Lenkkraft  (mehr = engere Kurven)", 0.05],
		["steer", "swrange", "Wischweg bis voll  (mehr = feiner)", 0.02], ["ship", "center", "Auto-Gerade  (mehr = Nase schneller gerade)", 0.25], ["ship", "spdst", "Tempo-Dämpfung  (mehr = ruhiger bei Speed)", 0.1]],
	2: [["steer", "swrange", "Wischweg bis zum Rand  (mehr = feiner)", 0.02], ["steer", "glide", "Folgezeit  (weniger = flinker)", 0.05], ["steer", "gwidth", "Reichweite zum Rand", 0.05]],
	3: [["steer", "psens", "Empfindlichkeit  (mehr = weniger Daumenweg)", 0.25], ["steer", "paccel", "Beschleunigung  (mehr = schnelle Züge weiter)", 0.25], ["steer", "glide", "Folgezeit  (weniger = flinker)", 0.05]],
	4: [["steer", "psens", "Empfindlichkeit  (mehr = kürzerer Wisch pro Spur)", 0.25], ["steer", "paccel", "Beschleunigung  (schneller Ruck = ganz rüber)", 0.25],
		["steer", "glide", "Einrasten  (weniger = springt flinker in die Spur)", 0.05], ["steer", "vib", "Vibration  (0 aus, 1 an)", 1.0],
		["steer", "lbeep", "Piep beim Spurwechsel  (0 = aus)", 0.25]],
	5: [["steer", "ltime", "Spurwechsel ganz außen → ganz außen  (Sekunden)", 0.05], ["steer", "lhold", "Gedrückt halten → nächste Spur nach  (Sekunden)", 0.05], ["steer", "vib", "Vibration  (0 aus / 1 an)", 1.0], ["steer", "lbeep", "Piep beim Spurwechsel  (0 = aus)", 0.25]]}

const STT_MN = ["Tippen", "Wischen", "Gleiten", "Touchpad", "Spuren", "Spur antippen"]
const STT_MH = ["Linke oder rechte Bildschirmhälfte halten", "Wischen lenkt, Doppeltipp feuert", "Wischen schiebt rüber, loslassen = zurück zur Mitte", "Daumen bewegen wie einen Mauszeiger", "Wischen wählt links, Mitte oder rechts",
	"Links / rechts tippen = eine Spur weiter · Mitte tippen = Feuer"]


func _stt_rows() -> void:
	var m = clampi(int(cfg.get("ctrl", 1)), 0, 5)
	(stt.mbtn as Button).text = "Lenken: " + STT_MN[m]
	if stt.has("mhint"):
		(stt.mhint as Label).text = STT_MH[m]
	var vb: VBoxContainer = stt.rowbox
	for c in vb.get_children():
		c.queue_free()
	stt.rows = []
	if m <= 1:
		var pr = HBoxContainer.new()
		pr.add_theme_constant_override("separation", 10)
		vb.add_child(pr)
		for k in range(STEER_PRE.size()):
			var b = _btn(str(STEER_PRE[k][0]))
			b.add_theme_font_size_override("font_size", 26)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var kk = k
			b.pressed.connect(func(): _steer_preset(kk))
			pr.add_child(b)
	for r in STT_ROWS[m]:
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		vb.add_child(row)
		var tl = Label.new()
		tl.text = r[2]
		tl.add_theme_font_size_override("font_size", 22)
		tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(tl)
		var bm = _btn("−")
		bm.custom_minimum_size = Vector2(96, 80)
		row.add_child(bm)
		var vl = Label.new()
		vl.custom_minimum_size = Vector2(110, 0)
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vl.add_theme_font_size_override("font_size", 28)
		row.add_child(vl)
		var bpl = _btn("+")
		bpl.custom_minimum_size = Vector2(96, 80)
		row.add_child(bpl)
		var rr = r
		bm.pressed.connect(func(): _stt_step(rr, -1.0))
		bpl.pressed.connect(func(): _stt_step(rr, 1.0))
		stt.rows.append([r, vl])
	_stt_vals()



func _lane_draw(c: Control) -> void:
	if int(cfg.get("ctrl", 1)) < 4 or not (state == "race" or state == "count"):
		return
	var vp = c.size
	var k = vp.x / 941.0
	var cy = vp.y - (1672.0 - 1118.0) * k - 22.0
	var gap = 58.0
	c.draw_rect(Rect2(vp.x * 0.5 - gap * 1.6, cy - 20, gap * 3.2, 40), Color(0, 0, 0, 0.45))
	for i in range(-1, 2):
		var p = Vector2(vp.x * 0.5 + i * gap, cy)
		var on = i == lane_cur
		var r = 12.0 + (6.0 * lane_fl if on else 0.0)
		var col = Color(1.0, 0.6, 0.2, 0.95) if on else Color(1, 1, 1, 0.28)
		var pts = PackedVector2Array([p + Vector2(0, -r), p + Vector2(r * 0.75, 0), p + Vector2(0, r), p + Vector2(-r * 0.75, 0)])
		if on and lane_fl > 0.0:
			c.draw_circle(p, r * 2.2, Color(1.0, 0.55, 0.15, 0.35 * lane_fl))
		c.draw_colored_polygon(pts, col)
		pts.append(pts[0])
		c.draw_polyline(pts, Color(0, 0, 0, 0.7), 1.5, true)


# ---------------------------------------------------------------- Neustart ohne Neuladen und Pause
# „Race again“ und „Menu“ bauen die Strecke nicht neu auf: Schiffe und Rennzustand gehen auf den Stand
# direkt nach dem Vorwärmen zurück, Effekte des letzten Rennens werden weggeräumt – das geht sofort.
const RACE_VARS = ["shots", "mines", "fxs", "walls", "quake", "quake2", "bwaves", "fire_req", "t_state", "race_t", "steer_btn", "btn_t",
	"rel_t", "rel_v", "last_steer", "st_hist", "touches", "cam_psi", "cam_d", "post_spd", "scr_v", "gl_v", "expo_v", "kmax", "sg_a",
	"resb_t", "resb_armed", "msg_t", "last_place", "pl_flash", "big_t", "shake", "live_bursts", "fx_age", "mine_grp", "megaw",
	"lk_tg", "lk_k", "lk_bt", "lk_t", "zaps", "rec", "rec_ev", "rec_clk", "rec_acc", "rec_pl", "rp", "kc", "kc_pending", "mine_bt",
	"en_low", "board_t", "board_man", "fin", "ga_rl", "ga_last", "lane_cur", "lane_fl", "ptr_lat", "glide_in", "sw", "tinfo",
	"tap_last", "last_c", "tun_k", "cm", "lt_hold"]
var race0 = {}
var ships0 = []
var race_kids = []
var paused_ui: CanvasLayer = null


func _race_snap() -> void:
	race0 = {}
	for k in RACE_VARS:
		var v = get(k)
		race0[k] = v.duplicate(true) if (v is Array or v is Dictionary) else v
	ships0 = []
	for o in ships:
		ships0.append((o as Dictionary).duplicate(true))


func _free_fx_entry(e) -> void:
	if e is Node:
		if is_instance_valid(e):
			(e as Node).queue_free()
	elif e is Dictionary:
		for v in (e as Dictionary).values():
			if v is Node and is_instance_valid(v) and not (v as Node).has_meta("keep"):
				var isship = false
				for o in ships:
					if o.node == v:
						isship = true
				if not isship:
					(v as Node).queue_free()


# Rennen zurücksetzen (Strecke bleibt stehen). false = geht nicht, dann klassisch neu laden.
func _soft_reset() -> bool:
	if race0.is_empty() or ships0.size() != ships.size() or not rpf.is_empty() or T.S or free_ride or not vx.is_empty():
		return false
	get_tree().paused = false
	if paused_ui != null and is_instance_valid(paused_ui):
		paused_ui.queue_free()
	paused_ui = null
	Engine.time_scale = 1.0
	AudioServer.playback_speed_scale = 1.0
	# Effekte des letzten Rennens wegräumen
	for k in ["shots", "mines", "fxs", "walls", "bwaves", "megaw", "zaps"]:
		for e in get(k):
			_free_fx_entry(e)
	for k in ["quake", "quake2"]:
		if get(k) != null:
			_free_fx_entry(get(k))
	for k in ["shots", "mines", "walls", "swalls"]:
		for n in rp.get(k, []):
			if is_instance_valid(n):
				n.queue_free()
	if fin.has("lbl") and is_instance_valid(fin.lbl):
		(fin.lbl as Node).queue_free()
	for n in get_children():
		if n.has_meta("rfx"):
			n.queue_free()
		elif (n is GPUParticles3D or n is MeshInstance3D or n is OmniLight3D) and not race_kids.has(n) and not tun_l.has(n) and not nlights.has(n) and n != lk_n and not n.has_meta("keep"):
			n.queue_free()
		elif n is GPUParticles3D:
			n.speed_scale = 1.0
		elif (n is AudioStreamPlayer or n is AudioStreamPlayer3D) and not loops.values().has(n):
			n.queue_free()   # noch klingende Einzel-Geräusche
	if not cm.is_empty():
		for v in cm.values():
			if v is CanvasLayer and is_instance_valid(v):
				v.queue_free()
	# Rennzustand zurück
	for k in RACE_VARS:
		var v = race0[k]
		set(k, v.duplicate(true) if (v is Array or v is Dictionary) else v)
	fx_gen += 1
	for i in range(ships.size()):
		var o: Dictionary = ships[i]
		var o0: Dictionary = ships0[i]
		for k in o.keys():
			if not o0.has(k) and not (o[k] is Object):
				o.erase(k)
		for k in o0.keys():
			var v = o0[k]
			if v is Object:
				continue
			o[k] = v.duplicate(true) if (v is Array or v is Dictionary) else v
		var nd: Node3D = o.node
		nd.visible = true
		if nd.has_meta("eng"):
			var ep: AudioStreamPlayer3D = nd.get_meta("eng")
			if not ep.playing:
				ep.play()
		_shield_vis(o)
	_orbs_update(0.0, false)
	_rset("qs", 0.0)
	_rset("qs2", 0.0)
	if lk_n != null:
		lk_n.visible = false
	if lk_txt != null:
		lk_txt.visible = false
	# Anzeige zurück
	hud.resb.visible = false
	hud.board.visible = false
	hud.rdim.visible = false
	hud.res.text = ""
	hud.res.visible = true
	if hud.has("rpx"):
		hud.rpx.visible = false
	if flash_rect != null:
		flash_rect.color = Color(0, 0, 0, 0)
	state = "menu"
	_lap_pos(ships[0].z)
	return true


func _race_again() -> void:
	if _soft_reset():
		_start()
	else:
		if T.S:
			pending_test = true
		elif free_ride:
			pending_free = true
		else:
			restart = true
		_reload()


func _to_menu() -> void:
	if _soft_reset():
		menu_t = 0.0
		hud.layer.visible = false
		ui.root.visible = true
		if ui.has("setp"):
			(ui.setp as Control).visible = false
	else:
		_reload()


# Pause: alles friert ein, darüber ein kleines Menü (läuft weiter, obwohl das Spiel steht)
func _pause(on: bool) -> void:
	if not on:
		get_tree().paused = false
		if paused_ui != null and is_instance_valid(paused_ui):
			paused_ui.queue_free()
		paused_ui = null
		touches.clear()
		return
	if get_tree().paused:
		return
	touches.clear()
	get_tree().paused = true
	var cl = CanvasLayer.new()
	cl.layer = 30
	cl.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(cl)
	paused_ui = cl
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	cl.add_child(dim)
	var bx = VBoxContainer.new()
	bx.anchor_left = 0.5
	bx.anchor_right = 0.5
	bx.anchor_top = 0.5
	bx.anchor_bottom = 0.5
	bx.offset_left = -240
	bx.offset_right = 240
	bx.offset_top = -420
	bx.offset_bottom = 420
	bx.add_theme_constant_override("separation", 20)
	bx.alignment = BoxContainer.ALIGNMENT_CENTER
	cl.add_child(bx)
	var tl = _lbl("PAUSED", 64)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bx.add_child(tl)
	var b1 = _btn("RESUME", true)
	b1.pressed.connect(func(): _pause(false))
	bx.add_child(b1)
	var bc = _btn("")
	bc.add_theme_font_size_override("font_size", 30)
	var cset = func(): bc.text = "Steering: " + CTRL_N[clampi(int(cfg.get("ctrl", 1)), 0, 5)]
	cset.call()
	bc.pressed.connect(func():
		_set_ctrl((int(cfg.get("ctrl", 1)) + 1) % 6)
		cset.call())
	bx.add_child(bc)
	var vl = _lbl("", 30)
	vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bx.add_child(vl)
	var hs = HSlider.new()
	hs.min_value = 0.0
	hs.max_value = 1.0
	hs.step = 0.05
	hs.value = float(cfg.vol)
	hs.custom_minimum_size = Vector2(0, 64)
	hs.add_theme_icon_override("grabber", _dot(40))
	hs.add_theme_icon_override("grabber_highlight", _dot(46))
	var tsb = StyleBoxFlat.new()
	tsb.bg_color = Color(1, 1, 1, 0.25)
	tsb.content_margin_top = 6
	tsb.content_margin_bottom = 6
	tsb.set_corner_radius_all(6)
	hs.add_theme_stylebox_override("slider", tsb)
	var vset = func(v: float):
		vl.text = "Volume  %d %%" % int(round(v * 100.0))
	vset.call(hs.value)
	hs.value_changed.connect(func(v):
		cfg.vol = v
		vset.call(v)
		AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.001, float(cfg.vol))))
		_save_cfg())
	bx.add_child(hs)
	var b2 = _btn("RESTART")
	b2.pressed.connect(func(): _race_again())
	bx.add_child(b2)
	var b3 = _btn("MENU")
	b3.pressed.connect(func(): _to_menu())
	bx.add_child(b3)


# Sicherheitsnetz für Menüs: Knöpfe, die eine Zeile füllen, kürzen zu langen Text mit „…“,
# statt das ganze Menü über den Bildschirmrand zu schieben.
func _fit(root: Node) -> void:
	for c in root.find_children("*", "Button", true, false):
		var b: Button = c
		var fills = (b.size_flags_horizontal & Control.SIZE_EXPAND) != 0 or b.get_parent() is VBoxContainer
		if fills and not (b is CheckBox):
			b.clip_text = true
			b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS


# Lenk-Erklärung passend zum gewählten Modus (Anleitung und Hinweis im Rennen)
func _steer_help() -> String:
	return ["Hold the left or right half of the screen.", "Swipe left or right to steer. Double-tap to fire.",
		"Swipe to slide over – let go to return to the middle.", "Move your thumb like a mouse to steer.",
		"Swipe to pick the left, middle or right lane.", "Tap left or right to move one lane. Tap the middle to fire."][clampi(int(cfg.get("ctrl", 1)), 0, 5)]


# Spur antippen: eine Spur weiter (mit Piep und kurzem Vibrieren)
var lt_hold = {}
func _lane_step(dir: int) -> void:
	var want = clampi(lane_cur + dir, -1, 1)
	if want != lane_cur and (state == "race" or state == "count"):
		lane_cur = want
		ptr_lat = float(want)
		lane_fl = 1.0
		if float(fx.steer.vib) > 0.5:
			Input.vibrate_handheld(22)
		_lane_beep()


# Piep beim Spurwechsel – Lautstärke (oder aus) über „Lanes: change beep volume“
func _lane_beep() -> void:
	var v = float(fx.steer.get("lbeep", 1.0))
	if v > 0.01:
		_snd("beep", -18.0 + linear_to_db(v), 2.6 + 0.15 * lane_cur)
