# AntiGrav 3D – erste Godot-Version: Neon Night, ein Gleitermodell, drei Gegner, echte Beleuchtung,
# Bildschirm-Spiegelungen, Schatten, Glühen. Alles wird beim Start im Code aufgebaut.
extends Node3D

# gespeichertes Replay, das nach dem Neuladen der Szene abgespielt werden soll (bleibt über reload_current_scene erhalten)
static var pending_rp = ""
static var pending_free = false
static var pending_test = false
static var stt_spd = 1.0   # Tempo auf der Teststrecke (Anteil vom normalen Tempo)   # Neustart direkt in die Lenk-Teststrecke   # nach dem FX Lab gleich wieder ins Free ride (Live-Regler vom PC)
static var restart = false
# Fehlerprotokoll (bleibt über Neustarts der Szene erhalten): Spur der letzten Ereignisse, Fehlermeldungen, letzter Haltepunkt
static var dg_trail: Array = []
static var dg_init = false
static var dg_logger = null
static var dg_cpf: FileAccess = null
static var dg_report = ""        # Bericht vom letzten Absturz (leer = keiner)
static var dg_shown = false
static var dg_reloading = false
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
const START = 0.55
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
var cfg = {"pads": 0, "ship": 0, "speed": 1.0, "gfx": 2, "glow": 0.5, "neon": 0.8, "vol": 0.9, "ai": 1.05, "look": 0, "res": 0.85, "fps": 0, "cap": 0, "perf": 0, "pname": "", "tips": 1, "tseen": "", "live": 0, "comic": 1, "hud": 2, "ctrl": 1, "music": 0.6, "voice": 1.0, "vib": 1, "kcam": 0, "mcam": 1, "view": 0, "vmode": 0, "trk": 1}
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
const WP = [["rak", 0.17], ["lenk", 0.17], ["mine", 0.12], ["schild", 0.09], ["turbo", 0.11], ["beben", 0.08], ["auto", 0.05], ["wand", 0.07], ["blk", 0.06], ["orbs", 0.08]]
const WP_AI = [["lenk", 0.33], ["rak", 0.23], ["mine", 0.19], ["schild", 0.1], ["turbo", 0.1], ["blk", 0.05]]
# eigene Farbe je Waffe, damit man sie im Augenwinkel unterscheiden kann
const WC = {"rak": Color(1.0, 0.55, 0.12), "lenk": Color(1.0, 0.18, 0.22), "mine": Color(1.0, 0.86, 0.1), "orbs": Color(0.3, 0.6, 1.0),
	"wand": Color(0.1, 0.95, 0.85), "beben": Color(0.72, 0.32, 1.0), "schild": Color(0.35, 1.0, 0.45), "turbo": Color(1.0, 0.3, 0.75), "auto": Color(0.92, 0.92, 0.95), "blk": Color(0.72, 1.0, 0.12)}
# kurze Erklärung je Waffe (Hinweise beim ersten Mal und „How to play“)
const WD = {"rak": "Flies straight ahead – aim by steering.", "lenk": "Locks onto the rival ahead and hits for sure.",
	"mine": "Drops mines behind you.", "schild": "Protects you from two hits.", "turbo": "A big burst of speed.",
	"beben": "A shock wave rolls ahead and throws rivals off course.", "auto": "Autopilot for 5 seconds – steers for you.",
	"wand": "An energy wall ahead – rivals flying through it get zapped, and it stops rockets coming from behind.", "orbs": "Glowing orbs circle you and hit anyone close.",
	"blk": "Lights out! For 5 seconds rivals only see the neon lines – they wobble, brake and bump into walls."}
const WN = {"rak": "ROCKET", "lenk": "HOMING", "mine": "MINES", "schild": "SHIELD", "turbo": "TURBO", "beben": "QUAKE", "auto": "AUTO", "wand": "FORCE FIELD", "orbs": "ORBS", "blk": "BLACKOUT"}
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
var last_steer = 0.0
var touches = {}
var hud = {}
var cam_psi = 0.0
var cam_d = 0.0


var rpf = {}   # geladenes Replay aus einer Datei


func _ready() -> void:
	_dg_start()
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
	if OS.get_cmdline_user_args().has("--noir"):
		cfg.look = 1
	if OS.get_cmdline_user_args().has("--jungle"):
		cfg.look = 2
	if OS.get_environment("TRK") != "":
		cfg.trk = int(OS.get_environment("TRK"))   # nur zum Testen: 0 Classic, 1 Extreme
	T.J = _jungle()   # eigene Streckenführung im Dschungel
	T.X = int(cfg.get("trk", 1)) == 1 and not _jungle()   # Extreme: Korkenzieher-Röhre und See
	T.S = pending_test or (OS.get_cmdline_user_args().has("--steertest") and OS.get_environment("AG_RELOADED") == "")
	if T.S:
		pending_test = false
		T.J = false
		free_ride = true
		_start.call_deferred()
	if OS.get_cmdline_user_args().has("--bench"):
		bench_req = true
	if OS.get_cmdline_user_args().has("--free") and OS.get_environment("AG_RELOADED") == "":
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
	cam = Camera3D.new()
	cam.doppler_tracking = Camera3D.DOPPLER_TRACKING_IDLE_STEP
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
	if AudioServer.get_bus_index("Stadium") == -1:
		AudioServer.add_bus()
		var si = AudioServer.bus_count - 1
		AudioServer.set_bus_name(si, "Stadium")
		AudioServer.set_bus_send(si, "Master")
		var hp = AudioEffectHighPassFilter.new()
		hp.cutoff_hz = 320.0
		AudioServer.add_bus_effect(si, hp)
		var lp = AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 5200.0
		AudioServer.add_bus_effect(si, lp)
		var ds = AudioEffectDistortion.new()
		ds.mode = AudioEffectDistortion.MODE_OVERDRIVE
		ds.drive = 0.18
		ds.post_gain = -3.0
		AudioServer.add_bus_effect(si, ds)
		var rv = AudioEffectReverb.new()
		rv.room_size = 0.85
		rv.damping = 0.35
		rv.wet = 0.38
		rv.dry = 0.9
		rv.predelay_msec = 90.0
		AudioServer.add_bus_effect(si, rv)
	for nm in ["Game", "Voice", "Music", "Cabin"]:
		if AudioServer.get_bus_index(nm) == -1:
			AudioServer.add_bus()
			var i = AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, nm)
			AudioServer.set_bus_send(i, "Master")
	# Bordcomputer: Waffen-Ansagen klingen synthetisch und schmalbandig, leicht metallisch – läuft danach durch den Stimmen-Kanal
	if AudioServer.get_bus_index("Board") == -1:
		AudioServer.add_bus()
		var bi = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bi, "Board")
		AudioServer.set_bus_send(bi, "Voice")
		var bhp = AudioEffectHighPassFilter.new()
		bhp.cutoff_hz = 320.0
		AudioServer.add_bus_effect(bi, bhp)
		var blp = AudioEffectLowPassFilter.new()
		blp.cutoff_hz = 5500.0
		AudioServer.add_bus_effect(bi, blp)
		var bch = AudioEffectChorus.new()   # zwei eng verschobene Kopien: der typische Computer-Klang
		bch.voice_count = 2
		bch.dry = 0.75
		bch.wet = 0.55
		bch.set_voice_delay_ms(0, 7.0)
		bch.set_voice_rate_hz(0, 0.0)
		bch.set_voice_depth_ms(0, 0.0)
		bch.set_voice_delay_ms(1, 13.0)
		bch.set_voice_rate_hz(1, 0.0)
		bch.set_voice_depth_ms(1, 0.0)
		AudioServer.add_bus_effect(bi, bch)
		var bds = AudioEffectDistortion.new()
		bds.mode = AudioEffectDistortion.MODE_OVERDRIVE
		bds.drive = 0.18
		bds.post_gain = 2.0
		AudioServer.add_bus_effect(bi, bds)
	var gi = AudioServer.get_bus_index("Game")
	if AudioServer.get_bus_effect_count(gi) == 0:
		var clp = AudioEffectLowPassFilter.new()   # 0: Cockpit-Dämpfung (aus = 20 kHz)
		clp.cutoff_hz = 20000.0
		clp.resonance = 0.6
		AudioServer.add_bus_effect(gi, clp)
		var ceq = AudioEffectEQ6.new()               # 1: Cockpit-Bass
		AudioServer.add_bus_effect(gi, ceq)
		AudioServer.set_bus_effect_enabled(gi, 0, false)
		AudioServer.set_bus_effect_enabled(gi, 1, false)
	var vi = AudioServer.get_bus_index("Voice")
	_bus_levels()
	# Begrenzer, damit die lautere Stimme nicht übersteuert
	if AudioServer.get_bus_effect_count(vi) == 0:
		# erst sanft verdichten, dann begrenzen – der harte Begrenzer allein hat bei lauten Ansagen gekratzt
		var cp = AudioEffectCompressor.new()
		cp.threshold = -14.0
		cp.ratio = 4.0
		cp.attack_us = 3000.0
		cp.release_ms = 150.0
		AudioServer.add_bus_effect(vi, cp)
		var lim = AudioEffectHardLimiter.new()
		lim.ceiling_db = -0.5
		AudioServer.add_bus_effect(vi, lim)
	if AudioServer.get_bus_effect_count(vi) == 2:
		# Bordfunk im Cockpit (sonst aus): schmalbandig, leicht angezerrt, dadurch klar und knackig über dem dumpfen Rest
		var rhp = AudioEffectHighPassFilter.new()
		rhp.cutoff_hz = 380.0
		AudioServer.add_bus_effect(vi, rhp)
		var rlp = AudioEffectLowPassFilter.new()
		rlp.cutoff_hz = 4200.0
		AudioServer.add_bus_effect(vi, rlp)
		var rds = AudioEffectDistortion.new()
		rds.mode = AudioEffectDistortion.MODE_OVERDRIVE
		rds.drive = 0.22
		rds.post_gain = 3.0
		AudioServer.add_bus_effect(vi, rds)
		for k in range(2, 5):
			AudioServer.set_bus_effect_enabled(vi, k, false)


# ---------------------------------------------------------------- Startsound-Labor: eigener Kanal „Start“ mit Tonhöhe, Klang, Echo, Hall, Biss
# Countdown-Piepser und Startgrollen laufen über diesen Kanal; die Regler im Reiter „Sound“ wirken sofort.
# Dazu auf Wunsch eigene Synth-Piepser (Tonhöhe, Klangfarbe, GO-Anstieg), im Spiel erzeugt.
var start_prev = []   # gerade laufende Vorhör-Klänge


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
	# Piepser bei 3, 2, 1 und das Startsignal bei GO – dazu zählt die Ansagerin mit
	if float(S.beeps) > 0.01:
		_start_snd(snd.get("go" if c <= 0 else "cbeep"), linear_to_db(float(S.beeps)) - 2.0)
	_snd("vo_go" if c <= 0 else "vo_%d" % clampi(c, 1, 3), -5.0)   # Countdown leiser (war zu laut und hat gekratzt)
	if c <= 0:
		_snd("ignite", -1.0)   # bei GO zünden die Triebwerke
	if first:
		if float(S.rumble) > 0.01:
			_start_snd(snd.get("start"), linear_to_db(float(S.rumble)))


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
		var bsteps = [[0.0, 1], [1.0, 0]] if short else [[0.0, 3], [1.0, 2], [2.0, 1], [3.0, 0]]
		for stp in bsteps:
			var cc: int = stp[1]
			if stp[0] <= 0.0:
				start_prev.append(_start_snd(snd.get("go" if cc <= 0 else "cbeep"), linear_to_db(float(S.beeps)) - 2.0))
			else:
				get_tree().create_timer(stp[0]).timeout.connect(func():
					if state == "lab":
						start_prev.append(_start_snd(snd.get("go" if cc <= 0 else "cbeep"), linear_to_db(float(S.beeps)) - 2.0)))
	if float(S.rumble) > 0.01:
		start_prev.append(_start_snd(snd.get("start"), linear_to_db(float(S.rumble)), t0 * 0.5))


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
	var mi = AudioServer.get_bus_index("Music")
	if mi >= 0:
		AudioServer.set_bus_volume_db(mi, duck_db * 0.3 + linear_to_db(maxf(0.001, float(cfg.get("music", 0.6)))) + 2.0)   # lauter, bei Ansagen nur leicht gedämpft


func _sounds() -> void:
	_buses()
	for n in ["boom.ogg", "engine.wav", "idle.wav", "pick.ogg", "rak.ogg", "shield.ogg", "start.ogg", "win.ogg", "wallon.ogg",
			"boost.wav", "zap.wav", "beep.wav", "go.wav", "pass.wav", "land.wav", "field.wav", "gbomb.wav", "phase.wav",
			"vo_rak.wav", "vo_lenk.wav", "vo_mine.wav", "vo_orbs.wav", "vo_wand.wav", "vo_beben.wav", "vo_schild.wav", "vo_auto.wav", "vo_turbo.wav", "vo_elim.wav", "vo_enlow.wav", "vo_super.wav", "vo_mega.wav", "vo_blk.wav", "minedrop.wav",
			"vo_3.wav", "vo_2.wav", "vo_1.wav", "vo_go.wav", "vo_final.wav", "vo_lrec.wav", "vo_p1.wav", "vo_p2.wav", "vo_p3.wav", "vo_p4.wav",
			"cbeep.wav", "load_weapon.wav", "holozap.wav", "confetti.wav", "crowd_roar.wav", "an_p1.wav", "an_p2.wav", "an_p3.wav", "an_p4.wav", "an_final.wav", "an_wow.wav", "crowd.ogg", "neon_buzz.wav", "crash_bump.wav", "crash_scrape.wav", "ko_boom.wav", "debris.wav", "dmg_spark.ogg", "dmg_fire.ogg", "quake.wav", "shieldbreak.wav", "lap.wav", "click.wav", "lock.wav", "incoming.wav", "radio.wav", "ck_herz90.ogg", "ck_herz140.ogg", "ck_mines.ogg", "ck_missile.ogg", "water.wav", "splash.wav", "blackout.wav", "minewarn.wav", "hover.wav", "ignite.wav",
			"amb_city.ogg", "amb_jungle.ogg", "music_race.ogg", "music_menu.ogg",
			"cm_whoosh.wav", "cm_hit.wav", "cm_pop.wav", "cm_stamp.wav", "cm_crash.wav"]:
		snd[n.get_basename()] = load("res://sfx/" + n)
	# Fahrer-Stimmen (japanisch) für die Comic-Seiten
	for c in ["ren", "vega", "kato", "mira"]:
		for k in ["start", "win", "mad", "lose", "ko"]:
			var pth = "res://sfx/cv_%s_%s.wav" % [c, k]
			if ResourceLoader.exists(pth):
				snd["cv_%s_%s" % [c, k]] = load(pth)
	snd["amb"] = snd["amb_jungle"] if _jungle() else snd["amb_city"]   # Hintergrund passend zur Strecke
	for k in ["engine", "idle", "field", "hover", "amb", "dmg_spark", "dmg_fire"]:
		var p = AudioStreamPlayer.new()
		p.stream = _looped(snd[k])
		p.volume_db = -80.0
		p.bus = "Game"
		add_child(p)
		p.play()
		loops[k] = p
	# See: Wasserrauschen unter dem Gleiter (läuft still mit)
	var wp2 = AudioStreamPlayer.new()
	wp2.stream = _looped(snd["water"])
	wp2.volume_db = -80.0
	wp2.bus = "Game"
	add_child(wp2)
	wp2.play()
	loops["water"] = wp2
	# Cockpit: Herzschlag und Warntöne – eigener Kanal ohne Dämpfung, laufen still mit und werden nur hochgezogen
	for k in ["ck_herz90", "ck_herz140", "ck_mines", "ck_missile"]:
		var p2 = AudioStreamPlayer.new()
		p2.stream = _looped(snd[k])
		p2.volume_db = -80.0
		p2.bus = "Cabin"
		add_child(p2)
		p2.play()
		loops[k] = p2
	# Musik: eigener Kanal (Regler „Music“ in den Einstellungen), wechselt weich zwischen Menü und Rennen
	music_p = AudioStreamPlayer.new()
	music_p.bus = "Music"
	music_p.volume_db = -80.0
	add_child(music_p)
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


# Ansagen des Bordcomputers (Waffen und Warnungen) – die Sprecher-Ansagen (Runde, Platz, Start) bleiben natürlich
const BOARD_VO = ["vo_rak", "vo_lenk", "vo_mine", "vo_orbs", "vo_wand", "vo_beben", "vo_schild", "vo_auto", "vo_turbo", "vo_blk", "vo_super", "vo_mega", "vo_enlow", "incoming"]


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
	if k.begins_with("vo_") or k == "incoming":
		_rev(["vo", k, db])   # Ansagen auch in der Wiederholung
		p.bus = "Board" if k in BOARD_VO else "Voice"
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
	# Cockpit: alles klingt wie durch die Hülle – dumpfer, mehr Bass, der eigene Antrieb brummt tiefer
	var ckt = 1.0 if _ck_on() else 0.0
	ck_snd += (ckt - ck_snd) * (1.0 - exp(-dt / 0.15))
	_ck_bus(ck_snd)
	var pk = 1.0 - 0.14 * ck_snd
	loops.engine.pitch_scale = clampf((0.7 + 0.6 * sp + 0.35 * g.boost) * pk, 0.3, 3.0)
	loops.engine.volume_db = linear_to_db(0.02 + (0.5 + 0.35 * sp + 0.35 * g.boost if on else 0.12)) + 1.5 * ck_snd
	loops.idle.pitch_scale = clampf((0.75 + 0.45 * sp + 0.25 * g.boost) * (1.0 - 0.25 * ck_snd), 0.3, 3.0)
	loops.idle.volume_db = linear_to_db((0.32 if state != "menu" else 0.2) * (1.0 + 0.9 * ck_snd))
	if loops.has("water"):
		var onw = state in ["race", "done"] and T.in_water(T.lz(float(g.z))) and not g.air and not g.out
		wat_snd = move_toward(wat_snd, (0.35 + 0.4 * clampf(float(g.spd) / maxf(1.0, base_spd), 0.0, 1.5)) if onw else 0.0, dt * 2.5)
		loops.water.volume_db = linear_to_db(maxf(0.0001, wat_snd))
		loops.water.pitch_scale = 0.85 + 0.3 * clampf(float(g.spd) / maxf(1.0, base_spd), 0.0, 1.5)
	# Cockpit-Warntöne und Herzschlag (nur im Rennen, nur im Cockpit)
	if loops.has("ck_herz90"):
		var live = ckt > 0.5 and state in ["race", "count"] and not g.out
		var hk = clampf((0.22 - float(g.en)) / 0.2, 0.0, 1.0) if live else 0.0   # ab 22 % Energie leise, bei 2 % voll
		ck_hb += (hk - ck_hb) * (1.0 - exp(-dt / (0.4 if hk > ck_hb else 1.2)))
		var fast = clampf((ck_hb - 0.45) / 0.35, 0.0, 1.0)
		loops.ck_herz90.volume_db = linear_to_db(maxf(0.0001, ck_hb * (1.0 - fast) * 0.9))
		loops.ck_herz140.volume_db = linear_to_db(maxf(0.0001, ck_hb * fast * 1.0))
		var wm = 1.0 if live and bool(ckh.get("mis", false)) else 0.0
		var wn = 1.0 if live and bool(ckh.get("mine", false)) and wm < 0.5 else 0.0
		loops.ck_missile.volume_db = linear_to_db(maxf(0.0001, wm * 0.55))
		loops.ck_mines.volume_db = linear_to_db(maxf(0.0001, wn * 0.45))
	var scr = on and absf(g.lat) >= T.TW - 0.31 and not g.air and g.spd > 1.0 and g.shield <= 0.0
	var tv = 0.25 if scr else 0.0   # Leitplanke: nur dezent
	scr_v += (tv - scr_v) * (1.0 - exp(-dt / (0.02 if scr else 0.08)))
	loops.field.volume_db = linear_to_db(maxf(0.0005, scr_v))
	# Schwebe-Summen unter dem Schiff (im Stand gut hörbar) und Hintergrund der Strecke
	var hov = 0.0 if g.out or state == "lab" else (0.16 if state == "menu" else 0.22 + 0.12 * (1.0 - clampf(sp, 0.0, 1.0)))
	loops.hover.volume_db = linear_to_db(maxf(0.0005, hov))
	loops.hover.pitch_scale = clampf(1.0 + 0.08 * sp + 0.05 * g.boost, 0.5, 2.0)
	loops.amb.volume_db = linear_to_db(0.5 if state == "menu" else 0.35)
	# Schaden hörbar: ab halber Energie knistern Funken, kurz vor dem K.o. prasselt Feuer
	var dmg_on = (state == "race" or state == "done") and not g.out and not free_ride
	var en = clampf(g.en, 0.0, 1.0)
	loops.dmg_spark.volume_db = linear_to_db(maxf(0.0005, (clampf((0.55 - en) / 0.4, 0.0, 1.0) * 0.6) if dmg_on else 0.0))
	loops.dmg_fire.volume_db = linear_to_db(maxf(0.0005, (clampf((0.2 - en) / 0.12, 0.0, 1.0) * 0.8) if dmg_on else 0.0))
	_music_update(dt)
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
uniform int vm=0;   // Cockpit-Sicht: 0 normal, 1 Infrarot, 2 Gitter
uniform float bo=0.;   // Blackout: alles schwarz, nur Neon leuchtet weiter
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
	// Geschwindigkeit: Bewegungsunschärfe entlang der Fluchtlinien – Bildmitte (Schiff, Strecke voraus) bleibt scharf,
	// zum Rand hin wird immer stärker verwischt. e = 0 in der Mitte … 1 am Bildrand (Hoch- und Querformat gleich).
	vec2 cd=uv-vec2(.5,.47);float e=smoothstep(.4,.98,length(cd*vec2(2.,1.6)));
	float mb=spd*e*.11;
	float ca=.006*gl+.01*abs(gs);
	vec3 col=vec3(0.);
	vec3 c0=texture(scr,uv).rgb;
	// nur wo wirklich verwischt wird, mehrfach lesen (spart auf dem Handy viel)
	if(mb<.003&&ca<.0004){col=c0;}
	else if(ca<.0004){
		// 7 Proben Richtung Fluchtpunkt, pro Pixel leicht versetzt (keine Stufen); außen rötlich, innen bläulich gewichtet → Farbsaum ohne Mehrkosten
		float j=hg(floor(SCREEN_UV/SCREEN_PIXEL_SIZE))*.7;vec3 ws=vec3(0.);
		for(int i=0;i<7;i++){float k=(float(i)+j)/7.;vec3 w=vec3(.55+k*.9,1.,1.45-k*.9);
			col+=texture(scr,vec2(.5,.47)+cd*(1.-mb*k)).rgb*w;ws+=w;}
		col/=ws;}
	else{ca+=.004*spd*e;for(int i=0;i<6;i++){float f=1.-float(i)*.2*mb;vec2 q=vec2(.5,.47)+cd*f;
		col+=vec3(texture(scr,q-cd*ca).r,texture(scr,q).g,texture(scr,q+cd*ca).b);}
	col/=6.;}
	// schwarzer Kern und leuchtender Ring der Bombe
	if(bomb){
		float gp=max(gs,0.);
		col*=1.-smoothstep(.06*gp+.01,.0,r)*gp*gd;
		col+=grc*exp(-pow(abs((r-.075*gp)*55./grw),2.))*gp*1.6*grb;
		if(gr>=0.)col+=vec3(.6,.45,1.)*exp(-pow(abs((r-gr)*30.),2.))*gk*.8;
	}
	// Speed-Linien: feine helle Striche schießen am Bildrand nach außen – bei normalem Tempo wenige und zart, bei Boost viele und kräftig
	if(spd*e>.004){
		float an=atan(cd.y,cd.x*asp);float lane=floor(an*90.);float hl=h21(vec2(lane,3.));
		float fa=fract(an*90.);float thin=smoothstep(0.,.3,fa)*smoothstep(1.,.7,fa);
		float ph=fract(length(cd*vec2(asp,1.))*1.7-TIME*(2.2+hl*2.6)*(.6+spd)+hl*7.);
		float lw=.2+.45*spd;   // Strichlänge wächst mit dem Tempo
		col+=vec3(.72,.88,1.)*step(1.-.035-.13*spd,hl)*thin*smoothstep(.0,.06,ph)*smoothstep(lw,lw*.25,ph)*e*e*(.25+.75*spd);
	}
	// knackig: Kanten schärfen, feines Filmkorn
	vec2 px=SCREEN_PIXEL_SIZE;
	vec3 bl=(texture(scr,uv+px*vec2(1.,.5)).rgb+texture(scr,uv-px*vec2(1.,.5)).rgb)*.5;
	col+=(c0-bl)*shp*(1.-min(1.,mb*30.));   // im Verwischten nicht nachschärfen
	col=max(col,vec3(0.));
	col+=(hg(floor(SCREEN_UV/px)+floor(fract(TIME*7.3)*91.)*17.)-.5)*grn*(.5+.5*(1.-clamp(dot(col,vec3(.33)),0.,1.)));
	// Cockpit-Sichten
	if(vm==1){
		// Infrarot: Helligkeit wird zu Wärme – kalt = dunkelblau, warm = rot, heiß (Antriebe, Explosionen) = gelb bis weiß
		float L=clamp(dot(col,vec3(.3,.55,.15))*1.2,0.,1.);
		L=pow(L,.75);
		vec3 th=vec3(.02,.02,.14)+vec3(.25,0.,.5)*smoothstep(.05,.35,L);
		th=mix(th,vec3(.95,.12,.18),smoothstep(.3,.6,L));
		th=mix(th,vec3(1.,.75,.1),smoothstep(.6,.85,L));
		th=mix(th,vec3(1.,1.,.9),smoothstep(.88,1.,L));
		th*=.92+.08*sin(SCREEN_UV.y/px.y*1.6+TIME*30.);   // feine Abtastzeilen
		col=th+(hg(floor(SCREEN_UV/px*.5)+floor(TIME*24.))-.5)*.05;
	}else if(vm==2){
		// Gitter: nur Kanten bleiben, als grüne Leuchtlinien; was hell glüht (Schiffe, Antriebe, Geschosse), wird rot
		vec2 d=px*1.5;
		float a1=dot(texture(scr,uv+vec2(d.x,0.)).rgb,vec3(.33));float a2=dot(texture(scr,uv-vec2(d.x,0.)).rgb,vec3(.33));
		float a3=dot(texture(scr,uv+vec2(0.,d.y)).rgb,vec3(.33));float a4=dot(texture(scr,uv-vec2(0.,d.y)).rgb,vec3(.33));
		float ed=clamp((abs(a1-a2)+abs(a3-a4))*3.2,0.,1.);
		float L=dot(c0,vec3(.3,.55,.15));
		vec3 gcol=vec3(.15,1.,.55)*ed*1.3+vec3(1.,.12,.2)*smoothstep(.72,.95,L)*.9;
		// leichtes Raster über allem, wie ein Messgitter
		vec2 gq=fract(SCREEN_UV/px/48.);
		gcol+=vec3(0.,.12,.07)*(step(gq.x,.03)+step(gq.y,.03));
		col=gcol;
	}
	// Blackout: nur kräftig farbig leuchtende Stellen (Neon) und sehr Helles (Antriebe) überleben
	if(bo>0.){
		float mx=max(col.r,max(col.g,col.b)),mn=min(col.r,min(col.g,col.b));
		float sat=(mx-mn)/max(mx,.001);
		float neon=max(smoothstep(.6,.9,mx)*smoothstep(.5,.75,sat),smoothstep(.86,1.,mx));
		vec3 dk=col*clamp(neon,0.,1.)*1.2+col*.012;
		col=mix(col,dk,bo);
	}
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
	var g: Dictionary = _focus()
	var q = int(cfg.gfx)
	var sp = 0.0
	# Tempo-Effekte nur, wenn die Kamera mit dem Gleiter nach vorn fliegt: im Rennen und im Replay bei „Chase“ und „Cockpit“.
	# Bei Kamerafahrt/Siegerfeier, Kill-Cam und den anderen Replay-Perspektiven wären Linien zur Bildmitte falsch.
	var fwd_cam = state == "race" or (state == "replay" and not rp.is_empty() and RP_CAMS[rp.ci][0] in ["chase", "cock"])
	if fwd_cam:
		# normale Fahrt: dezentes Grundmaß (0,32); Boost, Speedpads und Turbo legen deutlich bis 1 drauf; wer ausgebremst wird, verliert es
		var sv: float = g.spd / BASE_DEF
		sp = clampf(clampf((sv - 0.35) / 0.65, 0.0, 1.0) * 0.32 + maxf(0.0, sv - 1.0) * 0.5 + float(g.boost) * 0.3 + (0.25 if float(g.get("turbo", 0.0)) > 0.0 else 0.0), 0.0, 1.0)
	if OS.get_environment("SPDK") != "":
		sp *= float(OS.get_environment("SPDK"))   # nur zum Testen: Tempo-Effekte stärker/schwächer/aus
	if OS.get_environment("VMODE") != "":
		cfg.vmode = int(OS.get_environment("VMODE"))   # nur zum Testen
	_sp(post, "vm", int(cfg.get("vmode", 0)) if _ck_on() else 0)
	# Blackout: flackert beim Ausgehen kurz, bleibt dunkel, kommt am Ende flackernd zurück (wie Neonröhren)
	if OS.get_environment("BLKT") != "" and state == "race" and blk_t <= 0.0 and race_t > float(OS.get_environment("BLKT")) and race_t < float(OS.get_environment("BLKT")) + 0.1:
		blk_t = 5.0
		blk_d = 5.0
	var bt = 0.0
	if blk_t > 0.0 and state in ["race", "count"]:
		if not get_tree().paused:
			blk_t = maxf(0.0, blk_t - dt)
		var el = blk_d - blk_t
		bt = clampf(el / 0.35, 0.0, 1.0) * clampf(blk_t / 0.7, 0.0, 1.0)
		if el < 0.35 or blk_t < 0.7:
			bt *= 0.55 + (0.45 if fposmod(sin(el * 47.0) * 43758.5, 1.0) > 0.35 else 0.0)
		if blk_t <= 0.0:
			_snd("neon_buzz", -6.0, 1.2)
	elif state not in ["race", "count"]:
		blk_t = 0.0
	blk_v = bt
	if city_root != null and is_instance_valid(city_root):
		city_root.visible = blk_v < 0.7
	if sky_m != null:
		sky_m.set_shader_parameter("bk", blk_v)
	_sp(post, "bo", blk_v)
	if ck.has("body") and is_instance_valid(ck.body):
		var dm = 1.0 - 0.85 * blk_v   # Cockpit wird dunkel, nur seine Leuchten bleiben
		(ck.body as CanvasItem).self_modulate = Color(dm, dm, dm)
		if ck.has("hands") and is_instance_valid(ck.hands):
			(ck.hands as CanvasItem).self_modulate = Color(dm, dm, dm)
	if fwd_cam:
		post_spd += (sp - post_spd) * (1.0 - exp(-dt / 0.25))
	else:
		post_spd = 0.0   # sofort aus, sonst sähe man beim Schnitt auf eine andere Perspektive noch kurz die Linien
	if OS.get_environment("SPDDBG") != "" and Engine.get_process_frames() % 20 == 0:
		print("POSTSPD state=", state, " cam=", (RP_CAMS[rp.ci][0] if not rp.is_empty() else "-"), " post=", snappedf(post_spd, 0.01), " fov=", snappedf(cam.fov, 0.1))
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
	"ship": [["height", "Hover height", 0.2, 8.0, 1.0], ["bob", "Hover bob", 0.0, 10.0, 1.0], ["pitch", "Nose pitch", 0.0, 8.0, 1.0],
		["wobble", "Spring wobble", 0.0, 8.0, 0.0], ["stiff", "Spring stiffness", 0.2, 5.0, 1.0],
		["trim", "Nose trim (down +)", -1.0, 1.0, 0.0], ["rdots", "Rear rival dots range (0 = off)", 0.0, 40.0, 15.0],
		["weight", "Tassel weight", 0.1, 3.0, 1.0], ["swing", "Tassel swing", 0.1, 3.0, 1.0], ["wind", "Tassel wind (driving)", 0.0, 3.0, 1.0],
		["breeze", "Breeze (also standing)", 0.0, 3.0, 1.0]],
	# Lenkung – nur diese vier Werte (eingestellt wird auf der Teststrecke am Handy)
	"steer": [["ramp", "Reaction: time to full steering", 0.1, 1.5, 0.56], ["power", "Steering strength", 0.4, 2.0, 1.0],
		["assist", "Steering assist to pads", 0.0, 1.0, 0.3], ["bank", "Lean in curves", 0.0, 3.0, 1.0],
		["recover", "Straighten up speed", 0.5, 4.0, 2.0], ["leanin", "Lean-in speed (look)", 0.3, 3.0, 1.0],
		["wob", "Lean wobble (look)", 0.0, 2.0, 0.0], ["nosev", "Nose turn (look)", 0.0, 1.5, 1.0]],
	"env": [["city", "Buildings", 0.0, 1.0, 1.0], ["dens", "Building count", 0.0, 5.0, 1.0], ["bh", "Height", 0.3, 6.0, 1.0], ["bw", "Width", 0.2, 6.0, 1.0],
		["bd", "Distance", 0.2, 6.0, 1.0], ["win", "Lit windows", 0.0, 2.5, 1.0], ["hue_w", "Window color", -0.5, 0.5, 0.0], ["edge", "Neon edges", 0.0, 10.0, 1.0],
		["hue_s", "Sky color", -0.5, 0.5, 0.0], ["skyb", "Sky brightness", 0.0, 6.0, 1.0], ["stars", "Stars", 0.0, 10.0, 1.0], ["haze", "Skyline haze", 0.0, 3.0, 0.6], ["skyl", "Skyline", 0.0, 5.0, 1.0],
		["fog", "Fog density", 0.0, 12.0, 1.0], ["hue_f", "Fog color", -0.5, 0.5, 0.0], ["moon", "Moon", 0.0, 6.0, 1.0], ["beams", "Light pillars", 0.0, 10.0, 1.0],
		["lamps", "Track lights", 0.0, 10.0, 1.0], ["nlight", "Neon reflections", 0.0, 6.0, 1.0],
		["gloss", "Road gloss", 0.0, 4.0, 2.0], ["wet", "Wet road", 0.0, 4.0, 1.0]],
	"city": [["holo", "Holograms", 0.0, 4.0, 1.0], ["hsize", "Hologram size", 0.3, 3.0, 1.0], ["hflick", "Hologram glitch", 0.0, 12.0, 1.0], ["hhue", "Hologram color", -0.5, 0.5, 0.0],
		["signs", "Neon signs", 0.0, 4.0, 1.0], ["search", "Searchlights", 0.0, 4.0, 1.0], ["cars", "Flying cars", 0.0, 4.0, 1.0],
		["mega", "Mega towers", 0.0, 3.0, 1.0]],
	"sound": [["vol", "Volume", 0.0, 3.0, 1.0], ["pitch", "Pitch", 0.5, 2.0, 1.0], ["bass", "Bass", 0.0, 2.0, 1.0], ["treble", "Treble", 0.0, 2.0, 1.0],
		["grit", "Grit", 0.0, 2.0, 0.0], ["echo", "Echo", 0.0, 2.0, 0.0], ["etime", "Echo time", 0.2, 3.0, 1.0], ["reverb", "Reverb", 0.0, 2.0, 0.0], ["room", "Room size", 0.0, 1.0, 0.6],
		["rumble", "Engine rumble", 0.0, 3.0, 1.0], ["beeps", "Countdown beeps", 0.0, 3.0, 1.0]],
}
const FXT = [["boom", "Boom"], ["mine", "Mine"], ["quake", "Quake"], ["gb", "Hole"], ["rak", "Rocket"], ["lock", "Lock"], ["wall", "Field"], ["shield", "Shield"], ["orbs", "Orbs"], ["haze", "Jet"], ["pillar", "Pillar"], ["ship", "Ship"], ["env", "World"], ["city", "City"], ["jungle", "Jungle"], ["sound", "Sound"]]
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
	# keine MSAA-Kantenglättung: laut Leistungstest auf dem Handy kostete 2× rund 4 ms, 4× rund 11 ms pro Bild (John: lieber ohne)
	get_viewport().msaa_3d = Viewport.MSAA_DISABLED
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
	_bus_levels()


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
		sky_m.set_shader_parameter("hz", float(E.get("haze", 0.6)))
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
uniform float sb=1.;uniform float st=1.;uniform float sl=1.;uniform float mn=1.;uniform float hu=0.;uniform float hz=1.;
uniform float bk=0.;   // Blackout: Himmel und Skyline aus
float h21(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
vec3 hr(vec3 c,float a){vec3 k=vec3(.57735);float ca=cos(a);return c*ca+cross(k,c)*sin(a)+k*dot(k,c)*(1.-ca);}
float vn(vec2 p){vec2 i=floor(p);vec2 f=fract(p);f=f*f*(3.-2.*f);return mix(mix(h21(i),h21(i+vec2(1.,0.)),f.x),mix(h21(i+vec2(0.,1.)),h21(i+vec2(1.)),f.x),f.y);}
void sky(){
	vec3 d=EYEDIR;float h=d.y;float an=atan(d.x,d.z);
	vec3 c=hr(mix(vec3(.04,.02,.07),vec3(.002,.003,.012),smoothstep(0.,.5,h)),hu*6.2832)*sb;
	// feine, scharfe Sterne: wenige, unterschiedlich hell, leicht funkelnd (keine Flecken)
	vec2 sp=vec2(an*420.,h*760.);vec2 ci=floor(sp);float sr=h21(ci);
	float pt=smoothstep(.22,.02,length(fract(sp)-.5-(vec2(h21(ci+1.7),h21(ci+5.3))-.5)*.5));
	float tw=.75+.25*sin(TIME*(1.5+sr*4.)+sr*40.);
	// ungleichmäßig: Sternhaufen und leere Flecken statt gleichmäßigem Teppich, insgesamt weniger
	float cl=smoothstep(.38,.85,vn(vec2(an*2.2,h*4.))*.65+vn(vec2(an*7.,h*11.))*.35);
	float thr=.9978-.011*cl;
	c+=vec3(.82,.86,1.)*step(thr,sr)*(.15+.85*pow(h21(ci+9.1),3.))*1.25*tw*pt*smoothstep(.05,.3,h)*st;
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
	c+=hr(vec3(.5,.12,.45)*exp(-abs(h)*22.)*.22,hu*6.2832)*sb*hz;   // Dunst über der Skyline (Regler)
	if(h<-.04)c=mix(c,vec3(.006,.005,.012),smoothstep(-.04,-.15,h));
	COLOR=c*(1.-bk);
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


# Wand-Textur aus den Bildvorlagen: Farbe + Rauheit, Struktur und eigene Leuchtteile (Lampen); v wird bei Bedarf umgedreht
func _tex_wall(nm: String, su: float, sv: float, flip: float) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	var tc: Texture2D = load("res://tex/%s_cr.png" % nm)
	m.albedo_texture = tc
	m.albedo_color = Color(0.85, 0.85, 0.88) if not _noir() else Color(0.7, 0.7, 0.7)
	m.metallic = 0.55
	m.roughness_texture = tc
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_ALPHA
	m.roughness = 1.0
	m.normal_enabled = true
	m.normal_texture = load("res://tex/%s_n.png" % nm)
	m.normal_scale = 0.9
	m.emission_enabled = true
	m.emission_texture = load("res://tex/%s_e.jpg" % nm)
	m.emission = Color(1, 1, 1) if not _noir() else Color(0.75, 0.75, 0.75)
	m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY   # sonst addiert Godot Farbe + Bild und alles leuchtet weiß
	m.emission_energy_multiplier = 2.4
	m.uv1_scale = Vector3(su, -sv if flip > 0.5 else sv, 1.0)
	m.uv1_offset = Vector3(0.0, 1.0 if flip > 0.5 else 0.0, 0.0)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return m


# Werbetafel mit einem der vier Motive (Atlas 2x2), zur Strecke gewandt, ungespiegelt
func _board(z: float, sd: float, k: int) -> void:
	st_z = z
	var f = T.frame(z)
	var c: Vector3 = f.c + f.rr * (sd * (T.TW + 0.405)) + f.uu * 0.86
	var rt: Vector3 = -f.fw * sd * 0.72   # von der Strecke aus gesehen „rechts“
	var up: Vector3 = f.uu * 0.72
	var o = Vector2(float(k % 2), float(k / 2)) * 0.5
	keep_wind = true
	_quad(_st("boards"), c - rt + up, c + rt + up, c + rt - up, c - rt - up, -f.rr * sd, o, o + Vector2(0.5, 0.0), o + Vector2(0.5, 0.5), o + Vector2(0.0, 0.5))
	keep_wind = false


func _neon(c: Color, e: float = 5.0) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = Color(0, 0, 0)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	neon_mats.append([m, e])
	return m


static var shader_cache = {}   # bleibt beim Neustart erhalten: keine Neu-Kompilierung, kein Ruckeln


# Fahrbahn-Wert setzen – Bebenwelle auch für die Nass-Spiegelung (zweiter Durchgang), damit beide gleich gewölbt sind
func _rset(p: StringName, v) -> void:
	mats.road.set_shader_parameter(p, v)
	if mats.has("pipe") and String(p).begins_with("q"):
		(mats.pipe as ShaderMaterial).set_shader_parameter(p, v)   # Bebenwelle auch in der Röhre
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
	var f = T.sframe(z, lat)
	var c: Vector3 = f.c + f.uu * h
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


# kurze Marke (ein einzelnes Viereck) zwischen z0 und z1 – für Pfosten und Striche, die zu Hunderten an der Strecke stehen
func _mark(key: String, z0: float, z1: float, la: float, lb: float, ha: float, hb: float) -> void:
	if T.gap(z0) or T.gap(z1):
		return
	st_z = z0
	var f0 = T.frame(z0)
	_quad(_st(key), T.world(z0, la, ha), T.world(z0, lb, hb), T.world(z1, lb, hb), T.world(z1, la, ha), f0.uu)


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
		var fa = T.sframe(z, la)   # in der Röhre liegt alles auf der gewölbten Fläche
		var fb = T.sframe(z, lb)
		var p: Array = [fa.c + fa.uu * ha, fb.c + fb.uu * hb]
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
			if key == "wall" or key == "wallcap":
				# Leitplanke: Texturkoordinaten längs (z) und quer (Höhe/Breite des Bandes);
				# von innen gesehen soll die Schrift nicht spiegeln: rechts läuft u gegen die Fahrtrichtung
				var L = absf(lb - la) + absf(hb - ha)
				var sg = -1.0 if la + lb > 0.0 else 1.0
				_quad(_st(key), prev[0], prev[1], p[1], p[0], n, Vector2((z - 0.5) * sg, 0.0), Vector2((z - 0.5) * sg, L), Vector2(z * sg, L), Vector2(z * sg, 0.0))
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
		if prev.size() > 0 and not T.gap(z - 0.25) and not T.in_water(z - 0.25) and not T.in_pipe(z - 0.25):
			for i in range(8):
				var u0 = float(i) / 8.0
				var u1 = float(i + 1) / 8.0
				_quad(road, prev[i], row[i], row[i + 1], prev[i + 1], f.uu, Vector2(u0, (z - 0.5) * 0.08), Vector2(u0, z * 0.08), Vector2(u1, z * 0.08), Vector2(u1, (z - 0.5) * 0.08))
		prev = row
		z += 0.5
	# Leitplanken: Metallwand innen, Deckel, Neonband (links Cyan, rechts Magenta)
	for sd in ([] if _jungle() else [-1.0, 1.0]):   # Dschungel: keine Leitplanken, der Erdwall begrenzt die Piste
		for dz in T.dry(20.0, 720.0):   # über dem See keine Bande
			_strip("wall", dz[0], dz[1], sd * TW, sd * TW, -0.06, 0.46)
			_strip("wallcap", dz[0], dz[1], sd * TW, sd * (TW + 0.12), 0.46, 0.46)
			_strip("neonL" if sd < 0 else "neonR", dz[0], dz[1], sd * (TW - 0.012), sd * (TW - 0.012), 0.30, 0.36)
			# Leuchtkante auf der Fahrbahn
			_strip("neonL" if sd < 0 else "neonR", dz[0], dz[1], sd * (TW - 0.16), sd * (TW - 0.11), 0.006, 0.006)
	# Mittellinie, gestrichelt (im Dschungel nicht)
	var zz = 20.0 if not _jungle() else 9999.0
	while zz < 720.0:
		if not T.in_water(zz, 1.5) and not T.in_pipe(zz, 1.5):
			_strip("line", zz, zz + 1.5, -0.012, 0.012, 0.005, 0.005)
		zz += 3.33
	# Tempo-Marken: dicht am Schiff huscht ständig etwas vorbei – Leuchtpfosten an der Bande (alle 2), Randstriche auf der
	# Fahrbahn (alle 2, versetzt), Spurstriche und kleine Lampen auf der Bande (alle 6). Im Dschungel gibt es keine Bande.
	if not _jungle():
		var zp = 21.0
		var pk = 0
		while zp < 719.0:
			for sd in ([] if T.in_water(zp, 2.0) or T.in_pipe(zp, 2.0) else [-1.0, 1.0]):
				var pm = "postL" if sd < 0 else "postR"
				_mark(pm, zp, zp + 0.09, sd * (TW - 0.014), sd * (TW - 0.014), 0.05, 0.25)
				_mark("line", zp + 1.0, zp + 1.6, sd * (TW - 0.5), sd * (TW - 0.38), 0.005, 0.005)
				if pk % 3 == 1:
					_box(pm, zp + 1.0, sd * (TW + 0.06), 0.495, 0.03, 0.035, 0.1)
				if pk % 2 == 0:
					_mark("line", zp + 0.3, zp + 1.3, sd * TW * 0.5 - 0.012, sd * TW * 0.5 + 0.012, 0.005, 0.005)
			zp += 2.0
			pk += 1
	# Röhre (nur Extreme): die Fahrbahn wölbt sich zur geschlossenen Röhre. Innen dunkles Glas mit Leuchtbahnen längs,
	# Ringen quer und Pfeilen auf dem Boden; an den Enden offen (Halbröhre), dort eine Neonkante als Grenze.
	if T.X and not T.S:
		var pz0 = float(T.PIPE[0])
		var pz1 = float(T.PIPE[1])
		var NP = 48
		var zt = pz0
		while zt < pz1 - 0.001:
			st_z = zt
			var tst = _st("pipe")
			var la = T.lim(zt)
			var lb = T.lim(zt + 0.5)
			for k in range(NP):
				var u0 = -1.0 + 2.0 * k / NP
				var u1 = -1.0 + 2.0 * (k + 1) / NP
				var a0 = T.sframe(zt, u0 * la)
				var a1 = T.sframe(zt, u1 * la)
				var b0 = T.sframe(zt + 0.5, u0 * lb)
				var b1 = T.sframe(zt + 0.5, u1 * lb)
				_quad(tst, a0.c, b0.c, b1.c, a1.c, a0.uu,
					Vector2(u0 * la, zt), Vector2(u0 * lb, zt + 0.5), Vector2(u1 * lb, zt + 0.5), Vector2(u1 * la, zt))
			zt += 0.5
		mats["pipe"] = _shader_mat("""
shader_type spatial;
render_mode unshaded,cull_disabled,blend_mix,depth_draw_always,shadows_disabled;
uniform float pr=%f;
uniform float z0=%f;
uniform float z1=%f;
// Bebenwelle (wie auf der Fahrbahn): läuft als glühender Ring durch die Röhre und hebt die Wand rundum an
uniform float qz=-1000.;uniform float qs=0.;uniform float qz2=-1000.;uniform float qs2=0.;uniform vec3 qc=vec3(1.,.42,.08);uniform float qg=1.;
varying float qh;
float qw(float d,float s){return s*(1.6*exp(-pow(abs(d/2.6),2.))-.5*exp(-pow(abs((d+6.)/2.6),2.))+.22*exp(-pow(abs((d+12.)/2.4),2.)));}
float quake(float z){return qw(z-qz,qs)+qw(qz2-z,qs2);}
void vertex(){float wz=(MODEL_MATRIX*vec4(VERTEX,1.)).z;qh=quake(wz);VERTEX+=NORMAL*qh;}
void fragment(){
	float x=UV.x,z=UV.y;
	float ang=x/pr;                 // Winkel um die Röhre, 0 = Boden
	float bot=smoothstep(1.4,.6,abs(ang));
	// Leuchtbahnen längs, alle 30 Grad; abwechselnd Cyan und Magenta
	float q=ang/(PI/6.);
	float ln=1.-smoothstep(0.,.05,abs(fract(q)-.5));
	vec3 lc=mod(floor(q),2.)<.5?vec3(.2,.9,1.):vec3(1.,.25,.85);
	// Ringe quer, Lichtpulse nach vorn, Pfeile auf dem Boden
	float rib=1.-smoothstep(0.,.04,abs(fract(z/4.)-.5));
	float pulse=smoothstep(.85,1.,fract(z/16.-TIME*1.4));
	float qq=fract(z/5.-TIME*.7);
	float chev=(1.-smoothstep(0.,.07,abs(qq-(.5-abs(ang)*.8))))*step(abs(ang),.5);
	vec3 base=mix(vec3(.02,.03,.07),vec3(.04,.05,.09),bot);
	vec3 c=base;
	c+=lc*ln*(.6+1.3*pulse);
	c+=vec3(.5,.7,1.)*rib*.25;
	c+=vec3(.3,.9,1.)*chev*1.2;
	float cr=max(qh,0.)/max(max(qs,qs2),.01);
	c+=qc*pow(cr,1.5)*1.8*step(.01,qs+qs2)*qg;
	ALBEDO=c;
	ALPHA=min(1.,mix(.88,.55,1.-bot)+cr*.5*step(.01,qs+qs2));     // oben durchscheinend: man sieht die Stadt durch die Decke
}""" % [T.PR, pz0, pz1])
		# Ränder der Halbröhre an den Enden (wo noch keine geschlossene Röhre ist)
		for side in [-1.0, 1.0]:
			for rng in [[pz0, pz0 + T.PT], [pz1 - T.PT, pz1]]:
				var ze = float(rng[0])
				while ze < float(rng[1]) - 0.001:
					st_z = ze
					var est = _st("neonL" if side < 0 else "neonR")
					var ea = T.sframe(ze, side * (T.lim(ze) - 0.02))
					var eb = T.sframe(ze + 0.5, side * (T.lim(ze + 0.5) - 0.02))
					_quad(est, ea.c - ea.rr * 0.06, eb.c - eb.rr * 0.06, eb.c + eb.rr * 0.06 + eb.uu * 0.25, ea.c + ea.rr * 0.06 + ea.uu * 0.25, ea.rr * -side,
						Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0))
					ze += 0.5
	# See (nur Extreme): die Fahrbahn endet, man gleitet über spiegelndes Wasser; Bojenketten statt Bande
	if T.X and not T.S:
		var w0 = float(T.WAT[0])
		var w1 = float(T.WAT[1])
		var zw = w0 - 16.0
		var XS = [-60.0, -30.0, -16.0, -8.0, -4.0, -2.4, 0.0, 2.4, 4.0, 8.0, 16.0, 30.0, 60.0]
		while zw < w1 + 16.0 - 0.001:
			st_z = zw
			var wst = _st("water")
			var fa = T.frame(zw)
			var fb = T.frame(zw + 1.0)
			for k in range(XS.size() - 1):
				var xa = XS[k]
				var xb = XS[k + 1]
				_quad(wst, fa.c + fa.rr * xa - fa.uu * 0.05, fb.c + fb.rr * xa - fb.uu * 0.05, fb.c + fb.rr * xb - fb.uu * 0.05, fa.c + fa.rr * xb - fa.uu * 0.05, fa.uu,
					Vector2(xa, zw), Vector2(xa, zw + 1.0), Vector2(xb, zw + 1.0), Vector2(xb, zw))
			zw += 1.0
		mats["water"] = _shader_mat("""
shader_type spatial;
render_mode unshaded,cull_disabled,blend_mix,depth_draw_opaque,shadows_disabled;
uniform float z0=%f;
uniform float z1=%f;
uniform sampler2D scr : hint_screen_texture, filter_linear;
uniform vec4 shp[4];          // Gleiter: Weltposition xyz, w = Stärke (0 = nicht auf dem Wasser)
uniform vec4 shz[4];          // Gleiter für die Schneise: Seitenlage, Strecken-z, Stärke, Tempo
varying vec3 wp;
float hs(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5);}
float vn(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(hs(i),hs(i+vec2(1,0)),f.x),mix(hs(i+vec2(0,1)),hs(i+1.),f.x),f.y);}
// Steigung einer Sinuswelle a*sin(k*(p·d) - s*t)
vec2 wv(vec2 p,vec2 d,float k,float a,float s,float t,float lod){return d*(a*k*cos(dot(p,d)*k-t*s))*clamp(1.3-k*lod*1.6,0.,1.);}
void vertex(){wp=(MODEL_MATRIX*vec4(VERTEX,1.)).xyz;}
void fragment(){
	float t=TIME;
	vec2 p=wp.xz;
	float lod=length(fwidth(p));   // wie viel Wasser ein Pixel abdeckt: feine Wellen in der Ferne weglassen, sonst flimmert es
	// Dünung + Kräuselwellen aus verschiedenen Richtungen
	// stiller Stadtsee: kaum Dünung, nur feines Windkräuseln (fast ein Spiegel)
	vec2 g=wv(p,vec2(.287,.958),.6,.018,1.1,t,lod);
	g+=wv(p,vec2(-.6,.8),1.5,.008,1.7,t,lod);
	g+=wv(p,vec2(.914,.406),3.4,.004,2.6,t,lod);
	vec2 q=p*2.4+vec2(t*.3,t*.2);
	float n0=vn(q);
	g+=vec2(vn(q+vec2(.08,0.))-n0,vn(q+vec2(0.,.08))-n0)*.03*clamp(1.-lod*6.,0.,1.);
	// Schneise: wo ein Gleiter durch ist, ist das Wasser aufgewühlt (wird hinter ihm breiter und beruhigt sich)
	float churn=0.;
	for(int i=0;i<4;i++){
		float dz=shz[i].y-UV.y;
		if(shz[i].z>0. && dz>-1. && dz<40.){
			float w=.35+max(dz,0.)*.07;
			float ac=(UV.x-shz[i].x)/w;
			float m=exp(-ac*ac*1.6)*exp(-max(dz,0.)/(7.+shz[i].w*6.))*smoothstep(-1.,.3,dz)*shz[i].z;
			vec2 qq=p*3.2+vec2(t*2.1,-t*1.7);
			g+=(vec2(vn(qq),vn(qq.yx*1.13+4.))-.5)*m*1.4;
			churn=max(churn,m);
		}
	}
	// Wellenringe rund um die Gleiter, nach hinten gezogen (Luftkissen drückt aufs Wasser)
	for(int i=0;i<4;i++){
		vec2 d=p-shp[i].xz;
		float r=length(d*vec2(1.,.55))+.001;
		g+=(d/r)*sin(r*5.-t*11.)*shp[i].w*exp(-r*1.3)*.1*clamp(1.-lod*4.,0.,1.);
	}
	vec3 nw=normalize((INV_VIEW_MATRIX*vec4(NORMAL,0.)).xyz);
	nw*=sign(nw.y+.0001);
	vec3 n=normalize(nw+vec3(-g.x,0.,-g.y));
	vec3 cam=INV_VIEW_MATRIX[3].xyz;
	vec3 v=normalize(cam-wp);
	float fr=.03+.97*pow(1.-max(dot(n,v),0.),5.);
	vec3 r=reflect(-v,n);
	r.y=abs(r.y);
	// Spiegelung: reflektierten Strahl ein Stück weit verfolgen und das Bild von dort nehmen (Stadt, Neon, Gleiter)
	vec3 Q=wp+r*16.;
	vec4 cq=PROJECTION_MATRIX*(VIEW_MATRIX*vec4(Q,1.));
	vec4 cp=PROJECTION_MATRIX*(VIEW_MATRIX*vec4(wp,1.));
	vec2 uq=cq.xy/cq.w*.5+.5;
	vec2 up=cp.xy/cp.w*.5+.5;
	if(abs(up.y-SCREEN_UV.y)>abs(1.-up.y-SCREEN_UV.y)){uq.y=1.-uq.y;}
	vec3 sky=mix(vec3(.16,.06,.26),vec3(.02,.02,.07),clamp(r.y*2.2,0.,1.));
	vec3 refl=sky;
	if(cq.w>0.){
		float eb=smoothstep(0.,.06,min(min(uq.x,1.-uq.x),min(uq.y,1.-uq.y)));
		vec3 sc=texture(scr,clamp(uq,.001,.999)).rgb;
		refl=mix(sky,sc*1.15+sky*.25,eb);
	}
	// Wasserkörper: tief dunkel, an Wellenkämmen etwas türkis durchscheinend
	float crest=clamp(length(g)*1.6,0.,1.);
	vec3 deep=mix(vec3(.0,.02,.045),vec3(.0,.09,.12),crest*.6);
	vec3 c=mix(deep,refl,clamp(fr*1.25,0.,1.));
	float fo=smoothstep(.45,.75,vn(p*5.5+vec2(t*1.5,0.)))*churn;   // aufgewühlter Schaum in der Schneise
	c=mix(c,vec3(.55,.7,.8)*(.5+.5*fr),clamp(fo*.55,0.,1.));
	// Glitzern: winzige Funken, wo die Kräuselwellen das Licht kippen
	float sp=pow(vn(p*14.+vec2(t*1.3,-t))*vn(p*9.-t*.7),6.)*fr*5.*clamp(1.-lod*5.,0.,1.);
	c+=vec3(.7,.85,1.)*sp;
	// Bojenlicht spiegelt sich links Cyan, rechts Magenta
	float x=UV.x;
	float edge=exp(-pow((abs(x)-2.55)*2.2,2.))*(.6+.4*sin(UV.y*3.+t*2.));
	c+=mix(vec3(.2,.85,1.),vec3(1.,.25,.8),step(0.,x))*edge*.35;
	float fade=smoothstep(z0,z0+8.,UV.y)*smoothstep(z1,z1-8.,UV.y)*smoothstep(60.,40.,abs(x));
	ALBEDO=c;
	ALPHA=fade;
}""" % [w0 - 16.0, w1 + 16.0])
		# Kraftfeldwände über dem See: unsichtbar, bis Wasser dagegenklatscht (Shader „wwall“)
		var zq = w0 - 2.0
		while zq < w1 + 6.0 - 0.001:
			st_z = zq
			var qst = _st("wwall")
			var qa = T.frame(zq)
			var qb = T.frame(zq + 1.0)
			for sd in [-1.0, 1.0]:
				var la = sd * WWALL
				var vo = 0.0 if sd < 0 else 2.0
				_quad(qst, qa.c + qa.rr * la - qa.uu * 0.05, qb.c + qb.rr * la - qb.uu * 0.05, qb.c + qb.rr * la + qb.uu * 2.6, qa.c + qa.rr * la + qa.uu * 2.6, -qa.rr * sd,
					Vector2(zq, vo), Vector2(zq + 1.0, vo), Vector2(zq + 1.0, vo + 1.0), Vector2(zq, vo + 1.0))
			zq += 1.0
		mats["wwall"] = _shader_mat("""
shader_type spatial;
render_mode unshaded,cull_disabled,blend_mix,depth_draw_never,shadows_disabled;
uniform sampler2D scr : hint_screen_texture, filter_linear;
uniform vec4 src[8];   // Spritzquelle: Strecken-z des Gleiters, Stärke, Tempo, Seite (-1/1)
float hs(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5);}
float vn(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(hs(i),hs(i+vec2(1,0)),f.x),mix(hs(i+vec2(0,1)),hs(i+1.),f.x),f.y);}
void fragment(){
	float side=UV.y>1.5?1.:-1.;
	float v=UV.y-(side>0.?2.:0.);      // 0 = Wasserlinie, 1 = 2,6 m hoch
	float z=UV.x;
	float cover=0.,crest=0.,riv=0.;
	for(int i=0;i<8;i++){
		if(src[i].y<=0. || src[i].w!=side) continue;
		float dz=src[i].x-z;
		float age=dz/max(src[i].z,5.)-.06;   // Wasser braucht kurz, bis es an der Wand ist
		if(age<0. || age>2.2) continue;
		float top=mix(.08,.78*src[i].y+.12,smoothstep(0.,.16,age))-age*.26;   // schießt hoch, sackt dann ab
		float body=smoothstep(top+.02,top-.1,v)*smoothstep(0.,.05,age);
		float fade=pow(1.-age/2.2,1.6)*src[i].y;
		// Rinnsale: senkrechte Bahnen, die nach unten laufen und mit der Zeit dünner werden
		float r=vn(vec2(z*5.5+float(i)*3.1,v*1.4+age*1.8))*.7+vn(vec2(z*13.,v*3.+age*3.))*.3;
		float thr=.15+age*.32;
		float film=mix(smoothstep(thr,thr+.18,r),1.,clamp(1.-age*3.,0.,1.));
		float ci=body*fade*film;
		if(ci>cover){cover=ci;riv=r;}
		crest=max(crest,exp(-pow((v-top)/.035,2.))*clamp(1.-age*1.8,0.,1.)*src[i].y*smoothstep(0.,.05,age));
	}
	if(cover+crest<.005) discard;
	// Wasserfilm bricht das Licht dahinter (Stadt, Neon) wie eine nasse Scheibe
	vec2 off=vec2(vn(vec2(z*4.,v*6.))-.5,riv-.5)*.045*cover;
	vec3 bg=texture(scr,SCREEN_UV+off).rgb;
	// das getroffene Kraftfeld leuchtet in Waben auf
	vec2 hx=vec2(z*2.4,v*5.2);
	hx.x+=step(1.,mod(floor(hx.y),2.))*.5;
	vec2 fh=abs(fract(hx)-.5);
	float grid=1.-smoothstep(.0,.06,.5-max(fh.x,fh.y));
	vec3 fc=side<0.?vec3(.2,.85,1.):vec3(1.,.3,.85);
	vec3 c=bg*1.1+vec3(.55,.8,1.)*(.12+.25*riv)*cover+fc*grid*cover*.55+vec3(.85,.95,1.)*crest*.8;
	ALBEDO=c;
	ALPHA=clamp(cover*.85+crest*.6+grid*cover*.3,0.,1.);
}""")
		# Bojen: kleine Leuchtkörper alle 2 Einheiten auf Höhe der Bande, links Cyan, rechts Magenta
		var zb = w0 + 1.0
		while zb < w1 - 0.5:
			for sd in [-1.0, 1.0]:
				_box("postL" if sd < 0 else "postR", zb, sd * TW, 0.02, 0.07, 0.07, 0.07)
			zb += 2.0
		# Kante, wo die Fahrbahn ins Wasser übergeht
		for ze in [w0, w1]:
			_mark("neonR", ze - 0.18, ze + 0.0, -TW, TW, 0.01, 0.01)
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
		elif zc > 20.0 and not T.in_tun(zc, 2.0) and not T.in_water(zc, 1.0) and not T.in_pipe(zc, 2.0):
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
		if zc > 715.0 or T.in_tun(zc, 2.0) or _jungle() or zc < 56.0 or zc > 684.0 or T.in_pipe(zc, 2.0):
			continue
		var sd = 1.0 if k % 2 == 0 else -1.0
		if _noir():
			_box("metal", zc, sd * (TW + 0.42), 0.42, 0.03, 0.3, 1.6)
			_box("board" + str(k % 3), zc, sd * (TW + 0.385), 0.42, 0.006, 0.26, 1.5)
		else:
			_box("metal", zc, sd * (TW + 0.44), 0.86, 0.03, 0.76, 0.78)
			_board(zc, sd, k % 4)
	if not _jungle():
		_tribunes()
		_blimp_make()
	_props_make()
	for k in range(2, 51):
		var zc = k * 14.0 + 7.0
		if zc > 715.0 or T.in_tun(zc, 1.0) or T.gap(zc) or _jungle() or T.in_water(zc, 1.0) or T.in_pipe(zc, 6.0):
			continue
		_box("metal", zc, 0.0, -3.3, 0.16, 3.1, 0.16)
	# Neonringe in Gruppen (im Dschungel stattdessen Baumwurzeln über der Strecke)
	if _jungle():
		_jungle_track()
	for zr in ([] if _jungle() else T.RINGS):
		if T.in_pipe(float(zr), 3.0):
			continue   # in der Röhre keine Ringe
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
					var ua = z2 - 1.0
					var ub = z2
					if not _jungle():
						# v: 0 an der Decke, 1 unten an der Fahrbahn; u von innen gesehen ungespiegelt
						var sg = 1.0 if i < na / 2 else -1.0
						ua *= sg
						ub *= sg
						v0 = absf(-am + 2.0 * am * i / na) / am
						v1 = absf(-am + 2.0 * am * (i + 1) / na) / am
					_quad(_st("tube"), pr[i][0], ring[i][0], ring[i + 1][0], pr[i + 1][0], ring[i][1], Vector2(ua, v0), Vector2(ub, v0), Vector2(ub, v1), Vector2(ua, v1))
			pr = ring
			z2 += 1.0
		var zt: float = tu[0] + 1.0 if not _jungle() else 9999.0   # Erdtunnel: keine Leuchtringe
		var ti = 0
		while zt < tu[1]:
			_ring("ringC" if ti % 5 != 4 else "ringM", zt, R - 0.03, 0.4, 0.025, am * 0.98, 30)
			zt += 2.86   # weniger Ringe, damit man die Tunnelwände sieht
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
uniform float tk=1.;uniform float ts=2.4;uniform float jg=0.;uniform float nr=0.;uniform float ds=0.;
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
	vec2 tuv=nr>.5?vec2(z/4.8,(x+2.4)/4.8):vec2(x,z)/ts;
	vec4 tc=texture(tcr,tuv);
	base*=mix(vec3(1.),clamp(tc.rgb/.05,0.,3.5),.85*tk*(1.-edge));
	if(nr>.5){base=mix(vec3(.11),tc.rgb*1.15,tk);base=mix(base,vec3(dot(base,vec3(.3,.59,.11))),ds);seam=0.;edge=0.;}   // nasser Asphalt mit gelben Randstrichen
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
	mats.road.set_shader_parameter("tcr", load("res://tex/road2_cr.png" if not _jungle() else "res://tex/mud_cr.png"))
	mats.road.set_shader_parameter("tn", load("res://tex/road2_n.png" if not _jungle() else "res://tex/mud_n.png"))
	if not _jungle():
		mats.road.set_shader_parameter("nr", 1.0)
		mats.road.set_shader_parameter("ds", 0.85 if _noir() else 0.0)
	if _jungle():
		mats.road.set_shader_parameter("jg", 1.0)
		mats.road.set_shader_parameter("ts", 3.0)
	# Leitplanken: zerkratzter Stahl „Metal 038“, Tunnel: „Metal Plates 006“ (beide ambientCG, CC0)
	mats["wall"] = _tex_wall("barrier", 1.0 / (4.0 * 0.43), 1.0 / 0.52, 1.0) if not _jungle() else _tex_metal("bark", Color(0.42, 0.38, 0.32), 0.8, 0.85, 0.0)
	mats["wallcap"] = _tex_metal("rail", Color(0.36, 0.37, 0.4), 0.7, 0.22, 0.85, 0.07)
	mats["metal"] = _metal(Color(0.09, 0.095, 0.11), 0.3)
	mats["tube"] = _tex_wall("tunnel", 1.0 / (5.0 * 3.6), 1.0, 0.0) if not _jungle() else _tex_metal("mud", Color(0.38, 0.31, 0.22), 0.35, 0.95, 0.0)
	if _jungle():
		mats["root"] = _tex_metal("bark", Color(0.45, 0.4, 0.33), 0.7, 0.85, 0.0, 0.03, Color(0.3, 0.9, 0.6))
		mats["jfloor"] = _tex_metal("mud", Color(0.62, 0.52, 0.38), 0.33, 0.9, 0.0, 0.07, Color(0.55, 0.42, 0.28))
	mats["neonL"] = _neon(CY, 5.0)
	mats["neonR"] = _neon(MG, 5.0)
	mats["ringC"] = _neon(CY, 7.0 if not _jungle() else 1.2)
	mats["ringM"] = _neon(MG, 7.0 if not _jungle() else 1.2)
	mats["line"] = _neon(Color(0.8, 0.85, 1.0), 0.6)
	mats["postL"] = _neon(CY, 2.2)
	mats["postR"] = _neon(MG, 2.2)
	mats["tlight"] = _neon(Color(0.9, 0.95, 1.0), 4.0)
	mats["board0"] = _neon(Color(0.8, 0.8, 0.85) if _noir() else Color(0.1, 0.4, 1.0), 2.2)
	mats["board1"] = _neon(OR if _noir() else Color(1.0, 0.2, 0.5), 2.2)
	mats["board2"] = _neon(Color(0.35, 0.35, 0.37) if _noir() else Color(1.0, 0.7, 0.1), 2.2)
	mats["boards"] = _shader_mat("""
shader_type spatial;
render_mode unshaded,cull_disabled,shadows_disabled;
uniform sampler2D tx:source_color,filter_linear_mipmap;uniform float k=1.3;
void fragment(){ALBEDO=texture(tx,UV).rgb*k;}""")
	mats.boards.set_shader_parameter("tx", load("res://tex/boards.jpg"))
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
uniform sampler2D tx:source_color,filter_linear_mipmap,repeat_enable;uniform float ds=0.;
void fragment(){vec3 c=texture(tx,vec2(UV.y*2.,UV.x)).rgb;ALBEDO=mix(c,vec3(dot(c,vec3(.3,.59,.11))),ds)*.9;}""")
	mats.start.set_shader_parameter("tx", load("res://tex/start.jpg"))
	mats.start.set_shader_parameter("ds", 0.85 if _noir() else 0.0)
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
		if key == "wall" or key == "wallcap" or key == "tube" or key == "root" or key == "jfloor":
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
			var f = T.sframe(wp[0], wp[1])
			var wsc = 1.0 + 0.8 * T.pipe_k(wp[0])   # in der Röhre breiter, passend zur größeren Trefferbreite
			bm.transform = Transform3D(Basis(f.rr * wsc, f.uu, f.fw * wsc), f.c + f.uu * 1.1)
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
uniform sampler2D fa:source_color,filter_linear_mipmap;
vec3 hr(vec3 c,float a){vec3 k=vec3(.57735);float ca=cos(a);return c*ca+cross(k,c)*sin(a)+k*dot(k,c)*(1.-ca);}
varying vec3 wp;varying vec3 wn;varying vec4 cd;
void vertex(){wp=(MODEL_MATRIX*vec4(VERTEX,1.)).xyz;wn=normalize((MODEL_MATRIX*vec4(NORMAL,0.)).xyz);cd=INSTANCE_CUSTOM;}
float h21(vec2 p){return fract(sin(dot(p,vec2(12.9898,78.233)))*43758.5453);}
void fragment(){
	float side=1.-step(.9,abs(wn.y));float u=abs(wn.x)>.5?wp.z:wp.x;
	float vi=floor(h21(vec2(cd.a*.731,cd.a*.177))*7.);vec2 ao=vec2(mod(vi,4.)*.25,floor(vi/4.)*.5);
	vec2 t=vec2(u,-wp.y)/14.;vec2 sc=vec2(.25,.5);vec3 tx=textureGrad(fa,ao+fract(t)*sc,dFdx(t)*sc,dFdy(t)*sc).rgb;
	tx=tx;
	ALBEDO=mix(vec3(.015,.017,.025),tx*.12,side);METALLIC=.6;ROUGHNESS=.25;
	EMISSION=hr(tx*tx*1.9,wh*6.2832)*side*wl+cd.rgb*smoothstep(cd.a-.8,cd.a-.3,wp.y)*step(wp.y,cd.a)*side*5.*eg;
}""", [["tx=tx;", "tx=vec3(dot(tx,vec3(.3,.59,.11)))*vec3(1.,.93,.85);"]]))
	city_mat.set_shader_parameter("fa", load("res://tex/facade.jpg"))
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
# Hologramm-Plätze: z, Seite, Art, Abstand der Figur-Achse zur Streckenmitte (klein = die Strecke läuft durch ihre Beine)
const HOLO_SPOTS = [[80.0, 1.0, "dancer", 30.0], [370.0, -1.0, "dancer", 3.0], [455.0, 1.0, "dancer", 30.0], [680.0, -1.0, "dancer", 3.0],
	[128.0, -1.0, "koi"], [392.0, 1.0, "koi"], [615.0, -1.0, "koi"]]
# Hologramm-Figuren: [Datei, Höhe im Modell, dreht sich (stehende Figur)]
# fig_woman3: Blade-Runner-Frau (Tripo, Mixamo-Skelett) – tanzt mit dem Samba des Tänzers (zur Laufzeit übertragen)
# Der Tänzer selbst wird nicht mehr gezeigt, er liefert nur noch den Samba („src“)
const HOLO_FIGS = [["res://holo/dancer.glb", 1.66, false, "", "src"], ["res://holo/fig_woman3.glb", 0.0, false, "samba"]]
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
	float g=fl*.1+gx*4.;                                 // Stärke: Regler + Wechsel-Störung (sonst nur selten ein Glitch)
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
	float rim=fr*fr*1.25+.02;
	// feine Bildzeilen im Bildschirmraster (keine breiten Zebrastreifen auf der Figur)
	float scan=.86+.14*sin(FRAGCOORD.y*1.9-TIME*9.);
	float sweep=exp(-pow(abs(fract(my*.7-TIME*.16)-.5)*12.,2.));
	float fk=1.-min(fl,1.)*.6*step(.93,h11(floor(TIME*15.)+sd*5.));
	// Zeilen fallen aus (mehr bei starker Störung)
	float drop=step(fract(wp.y*.35+h11(floor(TIME*12.))*3.),.35*gx);   // Zeilen fallen nur beim Glitch aus
	vec3 c=mix(c2,c1,my);
	// in gestörten Streifen laufen die Farben auseinander
	c=mix(c,vec3(c.b,c.r*.6+.4,c.g)*1.4,gb);
	float fd=exp(-length(VERTEX)*.0012);
	// durchsichtig: Fläche kaum gefüllt, nur Kanten hell – die Stadt bleibt dahinter sichtbar
	ALBEDO=c*((.07+rim*1.05)*scan+sweep*.3*(.2+rim))*fk*hk*fd*(1.-drop*.9)*(1.+gx*1.2+gb*.8)*.8;
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
			if fd.size() > 4 and fd[4] == "src":
				fg.src = true
			if fd.size() > 3 and fd[3] == "samba" and not h.figs.is_empty() and h.figs[0].has("ap"):
				fg = _holo_samba(n, h.figs[0], fg)
				n = fg.n
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
		h.show = []
		for k in range(h.figs.size()):
			if not h.figs[k].get("src", false):
				h.show.append(k)
		h.fi = h.show[0] if not h.show.is_empty() else 0
		h.swt = 0.0
		h.gx = 0.0
		h.zap = 0.0
		h.inside = false
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


# Fremde Figur mit gleichem (Mixamo-)Skelett: Tanz vom Tänzer übernehmen. Gerechnet wird in Weltrichtung –
# jede Knochendrehung relativ zur Grundhaltung wird übertragen, damit unterschiedliche Knochenachsen nicht stören.
func _holo_samba(n: Node3D, src: Dictionary, fg: Dictionary) -> Dictionary:
	var sap: AnimationPlayer = src.ap
	var sroot: Node3D = src.n
	var ss: Skeleton3D = sroot.find_children("*", "Skeleton3D", true, false)[0]
	var dsl = n.find_children("*", "Skeleton3D", true, false)
	if dsl.is_empty():
		return fg
	var ds: Skeleton3D = dsl[0]
	var a: Animation = sap.get_animation("SambaDance")
	var sx: Transform3D = _rel_xf(sroot, ss)
	var dx: Transform3D = _rel_xf(n, ds)
	var qs: Quaternion = sx.basis.get_rotation_quaternion()
	var qd: Quaternion = dx.basis.get_rotation_quaternion()
	var nb = ds.get_bone_count()
	var smap = {}
	for b in range(ss.get_bone_count()):
		smap[ss.get_bone_name(b)] = b
	var srest = []
	for b in range(ss.get_bone_count()):
		srest.append(qs * ss.get_bone_global_rest(b).basis.get_rotation_quaternion())
	var drest = []
	for b in range(nb):
		drest.append(qd * ds.get_bone_global_rest(b).basis.get_rotation_quaternion())
	# Grundhaltung angleichen: der Tänzer steht im T, die neue Figur im A (Arme unten) – je Knochen die Richtung
	# zum Kind-Knochen der neuen Figur auf die des Tänzers drehen, sonst hängen die Arme beim Tanz 50° zu tief
	var fix = []
	for b in range(nb):
		var r = Quaternion.IDENTITY
		var sb = smap.get(ds.get_bone_name(b), -1)
		var ch = ds.get_bone_children(b)
		var c = -1
		for k in ch:
			if ds.get_bone_name(k).contains("Spine") or ds.get_bone_name(k).contains("Neck"):
				c = k
		if c < 0 and not ch.is_empty():
			c = ch[0]
		if sb >= 0 and c >= 0 and smap.has(ds.get_bone_name(c)):
			var sc = smap[ds.get_bone_name(c)]
			var vd: Vector3 = (dx * ds.get_bone_global_rest(c).origin - dx * ds.get_bone_global_rest(b).origin).normalized()
			var vs: Vector3 = (sx * ss.get_bone_global_rest(sc).origin - sx * ss.get_bone_global_rest(sb).origin).normalized()
			if vd.length() > 0.5 and vs.length() > 0.5 and vd.dot(vs) < 0.9999:
				r = Quaternion(vd, vs)
		elif ds.get_bone_parent(b) >= 0:
			r = fix[ds.get_bone_parent(b)]
		fix.append(r)
	for b in range(nb):
		drest[b] = fix[b] * drest[b]
	var sp = str(_rel_path(sroot, ss)) + ":"
	var rtr = []
	for b in range(ss.get_bone_count()):
		rtr.append(a.find_track(NodePath(sp + ss.get_bone_name(b)), Animation.TYPE_ROTATION_3D))
	var hs = smap.get("mixamorig_Hips", -1)
	var hd = ds.find_bone("mixamorig_Hips")
	var ptr = a.find_track(NodePath(sp + "mixamorig_Hips"), Animation.TYPE_POSITION_3D) if hs >= 0 else -1
	var na = Animation.new()
	na.length = a.length
	na.loop_mode = Animation.LOOP_LINEAR
	var dp = str(_rel_path(n, ds)) + ":"
	var otr = []
	for b in range(nb):
		var ti = na.add_track(Animation.TYPE_ROTATION_3D)
		na.track_set_path(ti, NodePath(dp + ds.get_bone_name(b)))
		otr.append(ti)
	var htr = -1
	var hr0 = 1.0
	if ptr >= 0 and hd >= 0:
		htr = na.add_track(Animation.TYPE_POSITION_3D)
		na.track_set_path(htr, NodePath(dp + "mixamorig_Hips"))
		hr0 = (dx * ds.get_bone_global_rest(hd).origin).y / maxf(0.001, (sx * ss.get_bone_global_rest(hs).origin).y)
	# Hüft-Bewegung relativ zur mittleren Lage im Tanz (die Ruhelage des Tänzers passt nicht dazu – sonst schwebt sie)
	var pmean = Vector3.ZERO
	if htr >= 0:
		var nsm = 0
		var ts = 0.0
		while ts <= a.length:
			pmean += sx * a.position_track_interpolate(ptr, ts)
			nsm += 1
			ts += 0.1
		pmean /= maxf(1.0, float(nsm))
	var t = 0.0
	while t <= a.length + 0.001:
		var sg = []
		sg.resize(ss.get_bone_count())
		for b in range(ss.get_bone_count()):
			var lq: Quaternion = a.rotation_track_interpolate(rtr[b], t) if rtr[b] >= 0 else ss.get_bone_rest(b).basis.get_rotation_quaternion()
			var pb = ss.get_bone_parent(b)
			sg[b] = (sg[pb] * lq) if pb >= 0 else lq
		var dg = []
		dg.resize(nb)
		for b in range(nb):
			var g: Quaternion
			var sb = smap.get(ds.get_bone_name(b), -1)
			if sb >= 0:
				var dlt: Quaternion = (qs * sg[sb]) * srest[sb].inverse()
				g = qd.inverse() * (dlt * drest[b])
			else:
				g = ds.get_bone_global_rest(b).basis.get_rotation_quaternion()
			dg[b] = g
			var pb = ds.get_bone_parent(b)
			var lq2: Quaternion = (dg[pb].inverse() * g) if pb >= 0 else g
			na.rotation_track_insert_key(otr[b], t, lq2.normalized())
		if htr >= 0:
			var sw: Vector3 = sx * a.position_track_interpolate(ptr, t) - pmean
			var dw: Vector3 = dx * ds.get_bone_rest(hd).origin + sw * hr0
			na.position_track_insert_key(htr, t, dx.affine_inverse() * dw)
		t += 1.0 / 24.0
	var lib = AnimationLibrary.new()
	lib.add_animation("SambaDance", na)
	var ap = AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	n.add_child(ap)
	ap.add_animation_library("", lib)
	# Füße auf 0, Mitte über dem Platz; in einen Halter packen (die Figur selbst wird pro Bild skaliert)
	var bb = AABB()
	var first = true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var bx: AABB = _rel_xf(n, mi) * (mi as MeshInstance3D).get_aabb()
		bb = bx if first else bb.merge(bx)
		first = false
	var hold = Node3D.new()
	n.position = -Vector3(bb.get_center().x, bb.position.y, bb.get_center().z)
	# Skelett-Ruhelage und Mesh-Lage stimmen bei dem Tripo-Modell nicht überein: an den Knöcheln ausrichten
	var lf = ds.find_bone("mixamorig_LeftFoot")
	var hb = ds.find_bone("mixamorig_Hips")
	if lf >= 0 and hb >= 0:
		var fy = (dx * ds.get_bone_global_rest(lf).origin).y
		var hpz: Vector3 = dx * ds.get_bone_global_rest(hb).origin
		n.position = -Vector3(hpz.x, fy - 0.045 * bb.size.y, hpz.z)
	hold.add_child(n)
	fg.n = hold
	fg.h = bb.size.y
	# Körperteile als Kapseln (Knochen von–bis, Dicke in Figurhöhen) – für die Durchfahrt
	fg.sk = ds
	fg.caps = []
	for cp in [["LeftUpLeg", "LeftLeg", 0.055], ["LeftLeg", "LeftFoot", 0.04], ["RightUpLeg", "RightLeg", 0.055], ["RightLeg", "RightFoot", 0.04],
			["Hips", "Neck", 0.09], ["LeftArm", "LeftForeArm", 0.035], ["LeftForeArm", "LeftHand", 0.03], ["RightArm", "RightForeArm", 0.035], ["RightForeArm", "RightHand", 0.03]]:
		var a0 = ds.find_bone("mixamorig_" + cp[0])
		var a1 = ds.find_bone("mixamorig_" + cp[1])
		if a0 >= 0 and a1 >= 0:
			fg.caps.append([a0, a1, cp[2]])
	return fg


# Steckt der Punkt (Schiff) gerade in der Hologramm-Figur? Prüft Kapseln entlang der Knochen.
func _holo_hit(h: Dictionary, q: Vector3) -> bool:
	var fg: Dictionary = h.figs[int(h.fi)]
	if not fg.has("caps") or not (fg.n as Node3D).visible:
		return false
	var sk: Skeleton3D = fg.sk
	var xf: Transform3D = sk.global_transform
	var R = float(h.H)
	for cp in fg.caps:
		var a: Vector3 = xf * sk.get_bone_global_pose(cp[0]).origin
		var b: Vector3 = xf * sk.get_bone_global_pose(cp[1]).origin
		var ab = b - a
		var tt = clampf((q - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
		if q.distance_to(a + ab * tt) < float(cp[2]) * R:
			return true
	return false


func _rel_path(top: Node, n: Node) -> String:
	var parts = []
	var c: Node = n
	while c != null and c != top:
		parts.push_front(str(c.name))
		c = c.get_parent()
	return "/".join(parts)


func _holos_make() -> void:
	for kind in ["dancer"]:   # nur eine Figur – höchstens einmal im Bild
		var h = _holo_node(kind)
		_sp(h.mat, "sd", float(holos.size()) * 1.37)
		if kind == "dancer":
			h.swt = 4.0 * holos.size()
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--holofig="):
					h.fi = h.show[int(a.substr(10)) % h.show.size()]
				if a.begins_with("--holoswt="):
					h.swt = float(a.substr(10))
		holos.append(h)


# Start-Mädel: großes Hologramm über der Strecke vor dem Feld – Arme hoch bei 3‑2‑1, bei GO runter, dann zack weg mit Glitch
var starter = {}
const ST_A0 = 0.0     # Ausschnitt aus „Start Plank“ (Sekunden): vom Stand …
const ST_A1 = 1.35    # … bis tief vorgebeugt, Hände nach vorn unten (Zahlen nachgemessen: Kopf ~5 Einheiten zu den Schiffen hin)
const ST_H = 15.5   # Größe in m (so groß, dass sie im Hochformat ganz ins Bild passt)


func _starter_make() -> void:
	# Start-Mädel = die Hologramm-Frau (Tripo, Mixamo-Skelett), ohne Flagge; Arme werden direkt gestellt
	var root = Node3D.new()
	var n: Node3D = load("res://holo/fig_woman3.glb").instantiate()
	var mat = _shader_mat(HOLO_CODE)
	_sp(mat, "gs", 0.25)
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = mat
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(mi as MeshInstance3D).extra_cull_margin = 0.6
	var sk: Skeleton3D = n.find_children("*", "Skeleton3D", true, false)[0]
	var dx: Transform3D = _rel_xf(n, sk)
	# Füße auf 0 (an den Knöcheln ausgerichtet), Mitte über dem Platz
	var bb = AABB()
	var first = true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var bx: AABB = _rel_xf(n, mi) * (mi as MeshInstance3D).get_aabb()
		bb = bx if first else bb.merge(bx)
		first = false
	var lf = sk.find_bone("mixamorig_LeftFoot")
	var hb = sk.find_bone("mixamorig_Hips")
	var hd = sk.find_bone("mixamorig_HeadTop_End")
	if hd < 0:
		hd = sk.find_bone("mixamorig_Head")
	var fy = (dx * sk.get_bone_global_rest(lf).origin).y if lf >= 0 else bb.position.y
	var hp: Vector3 = dx * sk.get_bone_global_rest(hb).origin if hb >= 0 else bb.get_center()
	var foot = fy - 0.045 * bb.size.y
	n.position = -Vector3(hp.x, foot, hp.z)
	var top = (dx * sk.get_bone_global_rest(hd).origin).y + (0.06 * bb.size.y if hd >= 0 and sk.get_bone_name(hd).ends_with("Head") else 0.0) if hd >= 0 else bb.end.y
	root.add_child(n)
	root.visible = false
	add_child(root)
	var mb: Basis = dx.basis.orthonormalized().inverse()
	var d = {"n": root, "sk": sk, "arms": [], "mat": mat, "mh": maxf(0.1, top - foot), "mb": mb, "tr": []}
	# Bewegung für GO: sie geht in die Knie und greift nach vorn (Ausschnitt aus Mixamo „Start Plank“)
	if ResourceLoader.exists("res://holo/st_plank.res"):
		var pa: Animation = load("res://holo/st_plank.res")
		d.anim = pa
		for i in pa.get_track_count():
			var pth = str(pa.track_get_path(i))
			var bi = sk.find_bone(pth.substr(pth.rfind(":") + 1))
			if bi >= 0:
				d.tr.append([i, bi, pa.track_get_type(i)])
	for b in [["mixamorig_LeftArm", 1.0], ["mixamorig_RightArm", -1.0]]:
		var ia = sk.find_bone(b[0])
		var ifa = sk.find_bone(b[0].replace("Arm", "ForeArm"))
		var ih = sk.find_bone(b[0].replace("Arm", "Hand"))
		if ia < 0 or ifa < 0 or ih < 0:
			continue
		var rd: Vector3 = (sk.get_bone_global_rest(ifa).origin - sk.get_bone_global_rest(ia).origin).normalized()
		d.arms.append({"ia": ia, "ifa": ifa, "ih": ih, "s": b[1], "rd": rd, "hg": sk.get_bone_global_rest(ih).basis,
			"pg": sk.get_bone_global_rest(sk.get_bone_parent(ia)).basis, "bg": sk.get_bone_global_rest(ia).basis, "fg": sk.get_bone_global_rest(ifa).basis})
	starter = d


# Start-Mädel: Arme einzeln stellen (Grad über waagrecht, Grad nach vorn) – Richtung im Modellraum (oben +y, vorn +z, links +x)
func _st_arms(d: Dictionary, upL: float, upR: float, fwdL := 0.0, fwdR := 0.0) -> void:
	var sk: Skeleton3D = d.sk
	for a in d.arms:
		var sg = float(a.s)
		var up = deg_to_rad(upL if sg > 0.0 else upR)
		var fw = deg_to_rad(fwdL if sg > 0.0 else fwdR)
		var dm = Vector3(sg * cos(up) * cos(fw), sin(up), cos(up) * sin(fw)).normalized()
		var dsk: Vector3 = ((d.mb as Basis) * dm).normalized()
		var q = Quaternion(a.rd as Vector3, dsk)
		var ag: Basis = Basis(q) * (a.bg as Basis)
		sk.set_bone_pose_rotation(a.ia, ((a.pg as Basis).inverse() * ag).get_rotation_quaternion())
		var fgp: Basis = Basis(q) * (a.fg as Basis)
		sk.set_bone_pose_rotation(a.ifa, (ag.inverse() * fgp).get_rotation_quaternion())
		var rh: Basis = Basis(q) * (a.hg as Basis)
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
		ang = -64.0 + sin(t_state * 2.0) * 3.0
		al = -64.0 + sin(t_state * 2.0 + 0.4) * 3.0
	elif state == "count":
		var c = 3 - int(floor(t_state))
		var u = t_state - floor(t_state)
		var e = 1.0 - pow(1.0 - clampf(u / 0.22, 0.0, 1.0), 3.0)
		var tg = [-62.0, 62.0, 42.0, 20.0][clampi(c, 0, 3)]       # 3: schräg hoch · 2: höher · 1: Flagge hoch
		var pv = [-62.0, 62.0, 42.0, 20.0][clampi(c + 1, 0, 3)] if c < 3 else -62.0
		ang = lerpf(pv, tg, e)
		al = ang                                  # beide Arme gleich hoch (keine Flagge mehr)
		if c == 1:
			ang += sin(u * 40.0) * 2.0 * u        # zittert vor Spannung
			al += sin(u * 40.0 + 1.0) * 2.0 * u
		sw = 0.6 + 1.2 * (1.0 - e)
	elif state == "race" and t_state < 1.4:
		# GO: Flagge runterreißen, das Tuch schlägt nach
		var a = clampf(t_state / 0.14, 0.0, 1.0)
		ang = lerpf(62.0, -50.0, a * a)
		al = ang
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
	var sc = ST_H / float(starter.mh)
	var base: Vector3 = f.c + Vector3.UP * -0.2
	# bei GO: sie beugt sich riesig über die Startenden und greift mit beiden Händen nach den Schiffen –
	# und zerfällt im selben Moment (nur ein Hologramm)
	var lean = 0.0
	var reach = 10.0
	var grow = 1.0
	var hkk = 1.0
	var anim_t = -1.0
	if state == "race" and t_state < 1.4 and starter.has("anim"):
		# echte Bewegung: in die Knie gehen, vorbeugen, nach den Schiffen greifen – dann zerfällt sie
		var u = clampf(t_state / 0.6, 0.0, 1.0)
		u = 1.0 - pow(1.0 - u, 2.0)
		var a0 = float(OS.get_environment("STA0")) if OS.get_environment("STA0") != "" else ST_A0
		var a1 = float(OS.get_environment("STA1")) if OS.get_environment("STA1") != "" else ST_A1
		anim_t = lerpf(a0, a1, u)
		grow = 1.0 + 0.15 * u
		hkk = 1.0 - 0.55 * u   # kommt sie nah, wird sie durchsichtiger (sonst strahlt das Bild weiß aus)
	var bb: Basis = Basis.looking_at(fw, Vector3.UP)   # Modell-Vorderseite (+Z) zeigt so den Startenden entgegen
	bb = Basis(bb.x, lean) * bb   # nach vorn kippen: Kopf und Hände zu den Schiffen hin (in 167 war das Vorzeichen falsch – sie kippte nach hinten)
	n.global_transform = Transform3D(bb.scaled(Vector3.ONE * sc * grow), base)
	var sks: Skeleton3D = starter.sk
	if anim_t >= 0.0:
		var pa: Animation = starter.anim
		for tr in starter.tr:
			if tr[2] == Animation.TYPE_ROTATION_3D:
				sks.set_bone_pose_rotation(tr[1], pa.rotation_track_interpolate(tr[0], anim_t))
			elif tr[2] == Animation.TYPE_POSITION_3D:
				sks.set_bone_pose_position(tr[1], pa.position_track_interpolate(tr[0], anim_t))
	else:
		sks.reset_bone_poses()
		_st_arms(starter, float(ps[2]), float(ps[1]), reach, reach)
	if OS.get_environment("STDBG") != "" and state == "race" and Engine.get_process_frames() % 4 == 0:
		var skh: Skeleton3D = starter.sk
		var hdb = skh.find_bone("mixamorig_Head")
		var tob = skh.find_bone("mixamorig_LeftToeBase")
		var hw: Vector3 = skh.global_transform * skh.get_bone_global_pose(hdb).origin
		var tw: Vector3 = skh.global_transform * skh.get_bone_global_pose(tob).origin if tob >= 0 else base
		print("STLEAN t=", snappedf(t_state, 0.01), " head_toward_ships=", snappedf((hw - base).dot(-fw), 0.1), " head_h=", snappedf(hw.y - base.y, 0.1), " toes_toward_ships=", snappedf((tw - base).dot(-fw), 0.2))
	if OS.get_environment("STDBG") != "" and Engine.get_process_frames() % 6 == 0:
		var skd: Skeleton3D = starter.sk
		var hy = []
		for a in starter.arms:
			hy.append(snappedf((skd.global_transform * skd.get_bone_global_pose(a.ih)).origin.y - base.y, 0.01))
		print("STDBG ", state, " t=", snappedf(t_state, 0.01), " L/R hand y=", hy, " ang=", ps[1], " al=", ps[2])
	var mat: ShaderMaterial = starter.mat
	_sp(mat, "by", base.y)
	_sp(mat, "hh", ST_H)
	_sp(mat, "hk", hkk)
	_sp(mat, "fl", 0.3)
	_sp(mat, "c1", _v3(OR if _noir() else Color(1.0, 0.3, 0.75)))
	_sp(mat, "c2", _v3(Color(0.9, 0.9, 0.95) if _noir() else Color(0.25, 0.85, 1.0)))
	# bei GO: Arme runter, dann zack weg mit kräftiger Bildstörung
	_sp(mat, "gx", clampf((t_state - 0.5) / 0.55, 0.0, 1.0) if state == "race" else 0.0)


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
				cands[sp[2]].append([d, zz, sp[1], sp[3] if sp.size() > 3 else 30.0])
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
			var H = HOLO_H * hs * (1.15 if h.get("near", false) else 1.0)
			if h.spot != c[1] or h.get("H", 0.0) != H:
				h.spot = c[1]
				h.H = H
				h.near = float(c[3]) < 15.0
				var p: Vector3 = f.c + f.rr * (c[2] * (float(c[3]) if h.near else (T.TW + 22.0 + 8.0 * hs))) + Vector3.UP * (-14.0)
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
				if h.show.size() > 1:
					h.fi = h.show[(h.show.find(int(h.fi)) + 1 + randi() % (h.show.size() - 1)) % h.show.size()]
			# Durchfahrt: Schiff steckt in einem Bein/Arm/Körper der Riesin → knistern und flackern
			h.zap = maxf(0.0, float(h.zap) - dt2)
			var ins = h.get("near", false) and not ships.is_empty() and _holo_hit(h, (ships[0].node as Node3D).global_position)
			if ins and not h.inside and state == "race":
				_snd("holozap", -2.0, randf_range(0.9, 1.1))
				h.zap = 0.35
			h.inside = ins
			if h.zap > 0.0:
				gx = maxf(gx, 0.55 * h.zap / 0.35 + 0.25 * randf())
			if h.swt < 0.0:
				gx = maxf(gx, clampf(-h.swt / 0.4 + 0.5, 0.0, 1.0))
			if h.swt >= 0.0 and h.swt < 0.45:
				gx = maxf(gx, 1.0 - h.swt / 0.45)
			if OS.get_environment("HOLODBG") != "":
				gx = 0.0
				_sp(mat, "fl", 0.0)
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


# ---------------------------------------------------------------- Zusammenstöße zwischen Schiffen
# Seite an Seite: auseinanderschieben und schrammen; Auffahren: der Hintere prallt ab, der Vordere bekommt einen Schubs.
var col_pairs = {}
const COL_L = 1.35   # Schiffslänge für den Stoß
const COL_W = 0.6    # Schiffsbreite


func _collide(dt: float) -> void:
	if not (state == "race" or state == "done") or party_on:
		return
	for i in range(ships.size()):
		var a: Dictionary = ships[i]
		for j in range(i + 1, ships.size()):
			var b: Dictionary = ships[j]
			var key = i * 8 + j
			var dz: float = b.z - a.z
			var dl: float = b.lat - a.lat
			if a.out or b.out or a.air or b.air or absf(dz) >= COL_L or absf(dl) >= COL_W or absf(float(a.h) - float(b.h)) > 0.5:
				col_pairs.erase(key)
				continue
			var first = not col_pairs.has(key)
			var last_snd: float = col_pairs.get(key, -9.0)
			var ox = COL_W - absf(dl)
			var oz = COL_L - absf(dz)
			var sl = signf(dl) if absf(dl) > 0.001 else (1.0 if (i + j) % 2 == 0 else -1.0)
			var kind = ""
			var rel = 0.0
			if ox / COL_W < oz / COL_L:
				# Seite an Seite
				var push = ox * 0.5 + 0.01
				a.lat = clampf(a.lat - sl * push, -T.TW + 0.25, T.TW - 0.25)
				b.lat = clampf(b.lat + sl * push, -T.TW + 0.25, T.TW - 0.25)
				a.vpsi -= sl * 0.06
				b.vpsi += sl * 0.06
				a.spd *= exp(-0.35 * dt)
				b.spd *= exp(-0.35 * dt)
				kind = "scrape"
				rel = absf(a.spd * sin(a.vpsi) - b.spd * sin(b.vpsi))
			else:
				# Auffahren
				var a_back = dz > 0.0
				var back: Dictionary = a if a_back else b
				var front: Dictionary = b if a_back else a
				rel = back.spd - front.spd
				back.z = front.z - COL_L + 0.01
				if rel > 0.0:
					back.spd = front.spd - rel * 0.25
					front.spd += rel * 0.3
				back.lat = clampf(back.lat - sl * 0.05 * (1.0 if a_back else -1.0), -T.TW + 0.25, T.TW - 0.25)
				kind = "bump"
			var now = race_t
			if first or (kind == "scrape" and now - last_snd > 1.1):
				col_pairs[key] = now
				var mid: Vector3 = ((a.node as Node3D).global_position + (b.node as Node3D).global_position) * 0.5 + Vector3(0, 0.15, 0)
				var me = a.idx == 0 or b.idx == 0
				var hard = kind == "bump" and rel > base_spd * 0.06
				_snd("crash_bump" if kind == "bump" else "crash_scrape", (0.0 if hard else -5.0) if kind == "bump" else -13.0, randf_range(0.9, 1.1), null if me else mid)
				if me:
					_vib(80 if hard else (45 if kind == "bump" else 30), 0.85 if hard else (0.55 if kind == "bump" else 0.3))
				_fx_res()
				_burst(mid, fxr.spark, 26 if hard else 14, 0.6, 3.0, 9.0, 70.0, Vector3(0, -9, 0), 0.6, 0.5, 1.0,
					_ramp([[0.0, Color(9, 6, 2.5, 1)], [0.6, Color(4, 1.2, 0.2, 1)], [1.0, Color(1, 0.2, 0.05, 0)]]), null, true, false, 0.15)
				if me:
					shake = maxf(shake, 0.5 if hard else 0.25)
				# kleiner Energieverlust beim harten Aufprall (Schild schluckt das Rempeln)
				if hard and state == "race":
					var dmg = clampf(rel / maxf(1.0, base_spd) * 0.25, 0.01, 0.05)
					_dmg(a, dmg, b.idx, "ram")
					_dmg(b, dmg, a.idx, "ram")
			elif not first and kind == "bump":
				col_pairs[key] = last_snd


# ---------------------------------------------------------------- Schaden sichtbar: Funken, Qualm, Flammen
# Jedes Schiff trägt drei Partikel-Quellen (ziehen in der Welt eine Spur hinter sich her); an/aus nach Energie.
func _dmg_emitter(mesh: Mesh, amount: int, life: float, vmin: float, vmax: float, spread: float, grav: Vector3, smin: float, smax: float, ramp: GradientTexture1D, scurve: CurveTexture, align: bool, ext: Vector3, expl: float) -> GPUParticles3D:
	var p = GPUParticles3D.new()
	var m = ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = ext
	m.direction = Vector3(0, 1, 0)
	m.spread = spread
	m.initial_velocity_min = vmin
	m.initial_velocity_max = vmax
	m.gravity = grav
	m.damping_min = 0.5
	m.damping_max = 1.5
	m.scale_min = smin
	m.scale_max = smax
	if scurve != null:
		m.scale_curve = scurve
	m.color_ramp = ramp
	m.particle_flag_align_y = align
	p.process_material = m
	p.draw_pass_1 = mesh
	p.amount = amount
	p.lifetime = life
	p.explosiveness = expl
	p.randomness = 0.6
	p.local_coords = false
	p.emitting = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-20, -20, -20), Vector3(40, 40, 40))
	return p


func _dmg_fx_build(root: Node3D) -> void:
	_fx_res()
	var bb: AABB = root.get_meta("bb")
	var ext = Vector3(bb.size.x * 0.3, 0.05, bb.size.z * 0.3)
	var sp = _dmg_emitter(fxr.spark, 18, 0.45, 1.5, 5.0, 70.0, Vector3(0, -9, 0), 0.15, 0.35,
		_ramp([[0.0, Color(3.5, 2.8, 1.6, 1)], [0.5, Color(2.2, 0.8, 0.15, 1)], [1.0, Color(0.8, 0.15, 0.04, 0)]]), null, true, ext, 0.85)
	sp.position = Vector3(0, bb.size.y * 0.7, 0)
	var sm = _dmg_emitter(fxr.smoke, 26, 1.6, 0.3, 1.0, 25.0, Vector3(0, 0.6, 0), 0.35, 0.8,
		_ramp([[0.0, Color(0.16, 0.15, 0.15, 0)], [0.1, Color(0.13, 0.12, 0.12, 0.75)], [1.0, Color(0.06, 0.06, 0.07, 0)]], false),
		_curve([[0.0, 0.4], [1.0, 1.8]]), false, Vector3(bb.size.x * 0.2, 0.04, 0.12), 0.0)
	sm.position = Vector3(0, bb.size.y * 0.75, -bb.size.z * 0.3)
	var fi = _dmg_emitter(fxr.fire, 16, 0.4, 0.3, 1.0, 25.0, Vector3(0, 1.5, 0), 0.12, 0.26,
		_ramp([[0.0, Color(2.6, 1.9, 0.8, 1)], [0.3, Color(2.0, 0.7, 0.12, 0.85)], [1.0, Color(0.4, 0.08, 0.02, 0)]]),
		_curve([[0.0, 0.6], [0.3, 1.0], [1.0, 0.3]]), false, Vector3(bb.size.x * 0.18, 0.03, 0.08), 0.0)
	fi.position = Vector3(0, bb.size.y * 0.6, -bb.size.z * 0.38)
	for e in [sp, sm, fi]:
		root.add_child(e)
	root.set_meta("dmgfx", [sp, sm, fi])


# je Bild: Stufen nach Energie – unter 55 % Funken, unter 35 % Qualm, unter 18 % kleine Flammen
func _dmg_fx_step(o: Dictionary, nd: Node3D) -> void:
	if not nd.has_meta("dmgfx"):
		return
	var ef: Array = nd.get_meta("dmgfx")
	var live = (state == "race" or state == "done") and not o.out and not free_ride and nd.visible
	var en = clampf(o.en, 0.0, 1.0)
	var lv = [0.55, 0.35, 0.18]
	for k in range(3):
		var e: GPUParticles3D = ef[k]
		var on = live and en < lv[k]
		if e.emitting != on:
			e.emitting = on
		if on:
			e.amount_ratio = clampf(0.3 + (lv[k] - en) / lv[k] * 1.2, 0.3, 1.0)


# ---------------------------------------------------------------- K.o.: Schiff zerbricht in zufällige Brocken
# Die Bruchstücke liegen vorberechnet je Schiff (ships/frag/*.glb, 20 Stücke); bei jedem K.o. werden sie zufällig
# zu 5–9 Brocken zusammengefasst, fliegen vom Knall weg, schlagen auf, schlittern Funken sprühend über die Fahrbahn.
const FRAG_F = ["qirex", "assegai", "apex", "rhsx", "r37"]
var frag_cache = {}
var debris = []


func _shatter(o: Dictionary, sd := -1) -> void:
	_bc("shatter ship %d" % int(o.idx))
	var nd: Node3D = o.node
	if not nd.has_meta("mxf"):
		return
	# gleicher Zufall in Kill-Cam und Wiederholung: Startwert wird mit aufgezeichnet
	if sd < 0:
		sd = randi() % 1000000
		_rev(["shat", o.idx, sd])
	var rn = RandomNumberGenerator.new()
	rn.seed = sd
	var sm = int(o.get("sm", 0))
	if not frag_cache.has(sm):
		var pth = "res://ships/frag/%s.glb" % FRAG_F[clampi(sm, 0, FRAG_F.size() - 1)]
		frag_cache[sm] = load(pth) if ResourceLoader.exists(pth) else null
	var sc: PackedScene = frag_cache[sm]
	if sc == null:
		return
	var holder = Node3D.new()
	add_child(holder)
	holder.global_transform = nd.global_transform
	var piv = Node3D.new()
	if nd.get_meta("flip", false):
		piv.rotation.y = PI
	holder.add_child(piv)
	var inst: Node3D = sc.instantiate()
	piv.add_child(inst)
	inst.transform = nd.get_meta("mxf")
	var pcs = inst.find_children("*", "MeshInstance3D", true, false)
	if pcs.is_empty():
		holder.queue_free()
		return
	var cen = []
	for mi in pcs:
		cen.append((mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb().get_center())
	var order = range(pcs.size())
	for k in range(order.size() - 1, 0, -1):
		var r = rn.randi_range(0, k)
		var tmp = order[k]
		order[k] = order[r]
		order[r] = tmp
	var nch = mini(rn.randi_range(7, 12), pcs.size())
	var heads = order.slice(0, nch)
	var groups = []
	for h in heads:
		groups.append([])
	for k in range(pcs.size()):
		var best = 0
		var bd = 1e9
		for gi in range(nch):
			# Brocken 0 ist das Wrack: zieht mehr Stücke an sich (großes Hauptstück vom Rumpf)
			var d = (cen[k] as Vector3).distance_to(cen[heads[gi]]) * rn.randf_range(0.8, 1.25) * (0.45 if gi == 0 else 1.0)
			if d < bd:
				bd = d
				best = gi
		groups[best].append(k)
	var f = T.frame(o.z)
	var B0 = Basis(-f.rr, f.uu, f.fw)
	var bp: Vector3 = nd.global_position
	# angesengtes Metall: Textur bleibt, wird dunkler und glüht an
	var gm: StandardMaterial3D = null
	var src_m = (pcs[0] as MeshInstance3D).mesh.surface_get_material(0)
	if src_m is StandardMaterial3D:
		gm = (src_m as StandardMaterial3D).duplicate()
	else:
		gm = StandardMaterial3D.new()
	gm.albedo_color = Color(0.72, 0.68, 0.66)
	gm.cull_mode = BaseMaterial3D.CULL_DISABLED
	gm.emission_enabled = true
	gm.emission = Color(1.0, 0.38, 0.1)
	gm.emission_energy_multiplier = 0.7
	for gi in range(nch):
		if groups[gi].is_empty():
			continue
		var c = Vector3.ZERO
		for k in groups[gi]:
			c += cen[k]
		c /= float(groups[gi].size())
		var ch = Node3D.new()
		ch.set_meta("rfx", true)
		ch.set_meta("deb", true)
		var wreck = gi == 0
		add_child(ch)
		ch.global_position = c
		var rad = 0.0
		for k in groups[gi]:
			var mi: MeshInstance3D = pcs[k]
			mi.reparent(ch, true)
			mi.material_override = gm
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			rad = maxf(rad, (cen[k] as Vector3).distance_to(c))
		var rel: Vector3 = c - f.c
		var lat = rel.dot(f.rr)
		var hh = rel.dot(f.uu)
		# Richtung vom Knall weg (normiert), etwas zufällig gestreut
		var out: Vector3 = (c - bp) + Vector3(rn.randf_range(-0.3, 0.3), 0.0, rn.randf_range(-0.3, 0.3))
		var ol = out.dot(f.rr)
		var of_ = out.dot(f.fw)
		var on = maxf(0.05, Vector2(ol, of_).length())
		ol /= on
		of_ /= on
		debris.append({"n": ch, "z": o.z + rel.dot(f.fw) - (bp - f.c).dot(f.fw), "lat": lat, "h": hh,
			"vz": o.spd * rn.randf_range(0.4, 0.95) + of_ * rn.randf_range(5.0, 14.0), "vl": o.spd * sin(o.vpsi) * 0.5 + ol * rn.randf_range(6.0, 13.0),
			"vh": rn.randf_range(4.0, 10.0), "rb": B0.transposed(), "av": Vector3(rn.randf_range(-1, 1), rn.randf_range(-1, 1), rn.randf_range(-1, 1)).normalized() * rn.randf_range(4.0, 13.0),
			"r": clampf(rad * 0.6 + 0.08, 0.08, 0.5), "t": 0.0, "m": gm, "sp": 0.0, "hit": false, "kt": 0.0, "wreck": wreck})
		if wreck:
			# Wrack: schlittert Richtung Fahrbahnrand, bleibt liegen und qualmt weiter
			var dd: Dictionary = debris[debris.size() - 1]
			dd.vl = signf(lat if absf(lat) > 0.05 else 1.0) * rn.randf_range(3.0, 6.0)
			dd.vh = rn.randf_range(2.0, 4.0)
			dd.vz = o.spd * rn.randf_range(0.35, 0.6)
			var smk = _dmg_emitter(fxr.smoke, 22, 2.2, 0.3, 0.9, 20.0, Vector3(0, 0.7, 0), 0.4, 0.9,
				_ramp([[0.0, Color(0.16, 0.15, 0.15, 0)], [0.1, Color(0.12, 0.11, 0.11, 0.7)], [1.0, Color(0.06, 0.06, 0.07, 0)]], false),
				_curve([[0.0, 0.4], [1.0, 2.0]]), false, Vector3(0.12, 0.04, 0.12), 0.0)
			smk.emitting = true
			ch.add_child(smk)
	holder.queue_free()
	_crash_site(o, bp, f, rn)
	# Funkenregen und glühende Splitter aus der Mitte
	_burst(bp + f.uu * 0.3, fxr.spark, 60, 1.2, 4.0, 14.0, 180.0, Vector3(0, -10, 0), 0.5, 0.6, 1.2,
		_ramp([[0.0, Color(9, 6, 2.5, 1)], [0.6, Color(4, 1.2, 0.2, 1)], [1.0, Color(1, 0.2, 0.05, 0)]]), null, true, false, 0.3)


# ---------------------------------------------------------------- Absturzstelle
# Bleibt bis zum Rennende: verkohlter Brandfleck auf der Fahrbahn (an der Bande auch dort), dünner Rauch,
# dazu viele kleine Blechsplitter – ein Teil davon glüht noch und flackert. Man sieht in der nächsten Runde, wo es jemanden erwischt hat.
const SCORCH_CODE = """
shader_type spatial;
render_mode unshaded,blend_mix,depth_draw_never,cull_disabled,shadows_disabled;
uniform float seed=0.;
uniform float heat=1.;
float h(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7))+seed)*43758.5453);}
float n(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(h(i),h(i+vec2(1,0)),f.x),mix(h(i+vec2(0,1)),h(i+vec2(1,1)),f.x),f.y);}
void fragment(){
	vec2 q=(UV-.5)*2.;
	float nn=n(UV*6.)*.6+n(UV*15.)*.4;
	float d=length(q)+(nn-.5)*.55;
	float a=smoothstep(1.,.3,d);
	// Asche-Rand (graubraun) um einen schwarz verkohlten Kern, darin glühende Risse, die langsam abkühlen
	float core=smoothstep(.75,.2,d);
	vec3 col=mix(vec3(.11,.095,.085),vec3(.01,.008,.007),core);
	float cr=smoothstep(.06,.0,abs(n(UV*7.+seed*.1)-.5))*smoothstep(.85,.15,d);
	float sp=smoothstep(.8,.95,n(UV*24.+seed))*core;
	float fl=.6+.4*sin(TIME*2.3+nn*17.);
	col+=vec3(2.8,.85,.18)*(cr*.9+sp)*heat*fl;
	ALBEDO=col;
	ALPHA=a*(.85+.15*nn);
}
"""
const EMBER_CODE = """
shader_type spatial;
render_mode cull_disabled,shadows_disabled;
uniform float ph=0.;
void fragment(){
	float fl=.55+.45*sin(TIME*(4.+ph)+ph*7.)*sin(TIME*1.7+ph);
	ALBEDO=vec3(.06,.04,.03);
	ROUGHNESS=.9;
	EMISSION=vec3(1.,.36,.08)*(.6+1.6*fl);
}
"""
var crash_m = {}
var scorch = []   # Brandflecken: kühlen langsam ab (glühen danach noch schwach)


func _crash_site(o: Dictionary, bp: Vector3, f: Dictionary, rn: RandomNumberGenerator) -> void:
	if crash_m.is_empty():
		crash_m.char = StandardMaterial3D.new()
		(crash_m.char as StandardMaterial3D).albedo_color = Color(0.07, 0.065, 0.06)
		(crash_m.char as StandardMaterial3D).roughness = 0.85
		(crash_m.char as StandardMaterial3D).metallic = 0.4
		crash_m.ember = _shader_mat(EMBER_CODE)
		var b1 = BoxMesh.new()
		b1.size = Vector3(0.16, 0.02, 0.1)
		var b2 = PrismMesh.new()
		b2.size = Vector3(0.12, 0.08, 0.05)
		var b3 = BoxMesh.new()
		b3.size = Vector3(0.07, 0.05, 0.22)
		crash_m.shapes = [b1, b2, b3]
	var lat0: float = clampf(o.lat, -T.TW + 0.3, T.TW - 0.3)
	if OS.get_environment("CSDBG") != "":
		print("CRASHSITE z=", o.z, " lz=", T.lz(o.z), " lat=", o.lat)
	# Brandfleck auf der Fahrbahn, länglich in Fahrtrichtung
	var sm = _shader_mat(SCORCH_CODE)
	sm.set_shader_parameter("seed", rn.randf() * 100.0)
	scorch.append({"m": sm, "t": 0.0, "n": null})
	var pm = PlaneMesh.new()
	pm.size = Vector2(1.5, 2.6)
	var sc = MeshInstance3D.new()
	sc.mesh = pm
	sc.material_override = sm
	sc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sc.set_meta("rfx", true)
	sc.set_meta("deb", true)
	add_child(sc)
	var fz = T.frame(o.z + 0.6)
	sc.global_transform = Transform3D(Basis(fz.rr, fz.uu, -fz.fw).rotated(fz.uu, rn.randf_range(-0.25, 0.25)), fz.c + fz.rr * lat0 + fz.uu * 0.012)
	# nah an der Bande: Ruß auch an der Wand
	if absf(o.lat) > T.TW - 0.75:
		var sw = sm.duplicate()
		var wm = MeshInstance3D.new()
		var qm = QuadMesh.new()
		qm.size = Vector2(2.2, 1.0)
		wm.mesh = qm
		wm.material_override = sw
		wm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wm.set_meta("rfx", true)
		wm.set_meta("deb", true)
		add_child(wm)
		var sd = signf(o.lat)
		wm.global_transform = Transform3D(Basis(fz.fw * sd, fz.uu, -fz.rr * sd), fz.c + fz.rr * (sd * (T.TW + 0.02)) + fz.uu * 0.35)
	# dünner Rauch, der noch lange aus dem Brandfleck steigt
	var smk = _dmg_emitter(fxr.smoke, 8, 3.2, 0.2, 0.5, 15.0, Vector3(0, 0.5, 0), 0.35, 0.8,
		_ramp([[0.0, Color(0.14, 0.13, 0.13, 0)], [0.15, Color(0.1, 0.1, 0.1, 0.45)], [1.0, Color(0.05, 0.05, 0.06, 0)]], false),
		_curve([[0.0, 0.4], [1.0, 2.2]]), false, Vector3(0.35, 0.02, 0.5), 0.0)
	smk.emitting = true
	smk.set_meta("rfx", true)
	smk.set_meta("deb", true)
	add_child(smk)
	smk.global_position = fz.c + fz.rr * lat0 + fz.uu * 0.05
	# Splitter: fliegen mit auseinander und bleiben liegen, jeder fünfte glüht
	var shapes: Array = crash_m.shapes
	for k in range(18):
		var mi = MeshInstance3D.new()
		mi.mesh = shapes[k % shapes.size()]
		var glow = k % 4 == 0
		if glow:
			var em: ShaderMaterial = (crash_m.ember as ShaderMaterial).duplicate()
			em.set_shader_parameter("ph", rn.randf() * 6.0)
			mi.material_override = em
		else:
			mi.material_override = crash_m.char
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var ch = Node3D.new()
		ch.set_meta("rfx", true)
		ch.set_meta("deb", true)
		add_child(ch)
		ch.add_child(mi)
		var s3 = rn.randf_range(0.6, 1.5)
		mi.scale = Vector3.ONE * s3
		var a = rn.randf() * TAU
		debris.append({"n": ch, "z": o.z, "lat": o.lat, "h": rn.randf_range(0.2, 0.5),
			"vz": o.spd * rn.randf_range(0.3, 0.9) + cos(a) * rn.randf_range(2.0, 9.0), "vl": sin(a) * rn.randf_range(2.0, 8.0),
			"vh": rn.randf_range(3.0, 9.0), "rb": Basis(), "av": Vector3(rn.randf_range(-1, 1), rn.randf_range(-1, 1), rn.randf_range(-1, 1)).normalized() * rn.randf_range(6.0, 16.0),
			"r": 0.06 * s3, "t": 0.0, "m": null, "sp": 0.0, "hit": false, "kt": 0.0, "wreck": false, "small": true})


# ---------------------------------------------------------------- See: Gischt hinter jedem Gleiter, ein Wal, Tropfen auf der Scheibe
var wsp = []          # Gischt je Schiff
var whale = {}        # laufender Wal-Sprung
var whale_lap = -1
var wet = 0.0         # wie nass die Scheibe ist
var blind = 0.0       # Gischtwand auf der Scheibe (durch fremde Fahne gefahren)
var blk_t = 0.0       # Blackout gegen dich: Restzeit
var blk_d = 1.0       # … Gesamtdauer
var blk_v = 0.0       # wie dunkel es gerade ist (0 … 1)


# Gischt je Gleiter: ein Halter (folgt Schiff + Fahrbahnlage) mit fünf Emittern, Partikel bleiben in der Welt liegen
#   tail  = hohe Fontäne direkt hinter dem Antrieb (Hahnenschwanz wie beim Jetboot)
#   sl/sr = feine Tropfenschleier, die seitlich als Bugwelle wegfächern
#   mist  = großer, zarter Sprühnebel, der hinter dem Schiff stehen bleibt und sich ausbreitet
#   dazu je Schiff ein Schaum-Kielwasser (Band aus Dreiecken auf dem Wasser, V-förmig, wird breiter und zerfällt)
var streak_mat: ShaderMaterial
var puff_tex: ImageTexture


# Tropfen als Striche: der Partikel zeigt in Flugrichtung (align_y), das Rechteck dreht sich zur Kamera und wird lang gezogen
func _streak_mat() -> ShaderMaterial:
	if streak_mat == null:
		streak_mat = _shader_mat("""
shader_type spatial;
render_mode unshaded,blend_mix,depth_draw_never,cull_disabled,shadows_disabled;
void vertex(){
	vec3 ax=MODEL_MATRIX[1].xyz;
	float sc=length(ax);
	ax/=max(sc,1e-4);
	vec3 c=MODEL_MATRIX[3].xyz;
	vec3 cam=INV_VIEW_MATRIX[3].xyz;
	vec3 sd=normalize(cross(ax,cam-c));
	vec3 w=c+sd*VERTEX.x*sc+ax*VERTEX.y*sc*5.;
	POSITION=PROJECTION_MATRIX*(VIEW_MATRIX*vec4(w,1.));
	COLOR.a*=smoothstep(.5,2.5,distance(cam,c));
}
void fragment(){
	vec2 u=UV*2.-1.;
	float a=(1.-u.x*u.x)*smoothstep(1.,.2,abs(u.y))*(.6+.4*(1.-u.y));
	ALBEDO=COLOR.rgb*(1.+.6*(1.-abs(u.x)));
	ALPHA=COLOR.a*a;
}""")
	return streak_mat


# Sprühwolke: ausgefranster, wolkiger Fetzen (Rauschen × runde Maske)
func _puff_tex() -> ImageTexture:
	if puff_tex == null:
		var nz = FastNoiseLite.new()
		nz.seed = 11
		nz.frequency = 0.09
		nz.fractal_octaves = 4
		var n = 64
		var img = Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y in range(n):
			for x in range(n):
				var d = Vector2((x + 0.5) / n - 0.5, (y + 0.5) / n - 0.5).length() * 2.0
				var v = nz.get_noise_2d(x, y) * 0.5 + 0.5
				var m = clampf(1.0 - d, 0.0, 1.0)
				var al = clampf((v * 1.4 - 0.35) * m * 1.8 + m * m * 0.25, 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, al))
		puff_tex = ImageTexture.create_from_image(img)
	return puff_tex


func _spray_part(amount: int, life: float, size: float, tex: Texture2D, flat: bool, streak: bool = false) -> CPUParticles3D:
	var p = CPUParticles3D.new()
	var qm = QuadMesh.new()
	qm.size = Vector2(size, size)
	if flat:
		qm.orientation = PlaneMesh.FACE_Y
	var mm = StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if not flat:
		mm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mm.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA   # direkt vor der Kamera ausblenden, sonst beschlägt das Bild
		mm.distance_fade_min_distance = 0.6
		mm.distance_fade_max_distance = 3.2
	mm.vertex_color_use_as_albedo = true
	mm.albedo_texture = tex
	mm.cull_mode = BaseMaterial3D.CULL_DISABLED
	qm.material = mm
	if streak:
		qm.material = _streak_mat()
		p.particle_flag_align_y = true
	p.mesh = qm
	p.amount = amount
	p.lifetime = life
	p.emitting = false
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.set_meta("keep", true)
	return p


func _sgrad(offs: Array, cols: Array) -> Gradient:
	var gr = Gradient.new()
	gr.offsets = PackedFloat32Array(offs)
	gr.colors = PackedColorArray(cols)
	return gr


func _scurve(pts: Array) -> Curve:
	var c = Curve.new()
	for q in pts:
		c.add_point(Vector2(q[0], q[1]))
	return c


var foam_tex: ImageTexture


# Schaumfleck: unregelmäßiger, löchriger Kranz aus Bläschen (einmal per Hand gerechnet)
func _foam_tex() -> ImageTexture:
	if foam_tex == null:
		var n = 64
		var img = Image.create(n, n, false, Image.FORMAT_RGBA8)
		var rn = RandomNumberGenerator.new()
		rn.seed = 7
		var bub = []
		for k in range(70):
			var a = rn.randf() * TAU
			var r = rn.randf_range(0.15, 0.95)
			bub.append([0.5 + cos(a) * r * 0.45, 0.5 + sin(a) * r * 0.45, rn.randf_range(0.02, 0.07)])
		for y in range(n):
			for x in range(n):
				var u = (x + 0.5) / n
				var v = (y + 0.5) / n
				var d = Vector2(u - 0.5, v - 0.5).length() * 2.0
				var al = 0.0
				for q in bub:
					var dd = Vector2(u - q[0], v - q[1]).length()
					var rr = float(q[2])
					al = maxf(al, clampf(1.0 - absf(dd - rr) / (rr * 0.55), 0.0, 1.0) * 0.9)   # Bläschenrand
					if dd < rr:
						al = maxf(al, 0.25)
				var ring = exp(-pow((d - 0.62) * 4.0, 2.0))
				al = clampf(al * (0.35 + ring) * smoothstep(1.0, 0.75, d), 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, al))
		foam_tex = ImageTexture.create_from_image(img)
	return foam_tex


var wake = []        # je Schiff: {"mi": MeshInstance3D, "im": ImmediateMesh, "pts": [[pos, rr, uu, t], ...]}
var wake_t = 0.0
var wake_gen = -1
const WAKE_LIFE = 3.0
const WWALL = 2.55   # seitlicher Abstand der Kraftfeldwand über dem See
const WAKE_STEP = 1.2
var wake_mat: ShaderMaterial


func _wake_node() -> Dictionary:
	if wake_mat == null:
		wake_mat = _shader_mat("""
shader_type spatial;
render_mode unshaded,cull_disabled,blend_mix,depth_draw_never,shadows_disabled;
varying vec3 wp;
float h(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5);}
float n(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(h(i),h(i+vec2(1,0)),f.x),mix(h(i+vec2(0,1)),h(i+1.),f.x),f.y);}
void vertex(){wp=VERTEX;}
void fragment(){
	float a=COLOR.a;            // 1 = frisch, 0 = verweht
	float x=UV.x;               // -1..1 quer übers Band
	vec2 q=wp.xz*4.2;
	q+=vec2(n(q*.45+3.1),n(q*.45-7.3))*1.8;                 // verwirbeln, damit nichts kastig wirkt
	mat2 R=mat2(vec2(.8,.6),vec2(-.6,.8));
	float f=n(q)*.5+n(R*q*2.13+vec2(TIME*.35,0.))*.3+n(R*R*q*4.71)*.2;
	float lines=.5+.5*sin(x*7.+f*5.);                      // Schaumschlieren längs der Fahrtrichtung
	float edge=1.-smoothstep(.4,1.,abs(x));
	float thr=mix(.74,.36,a*a);                             // frischer Schaum ist dicht, alter reißt in Fetzen auf
	float fo=smoothstep(thr,thr+.18,f*(.6+.4*edge)*(.8+.3*lines));
	ALBEDO=vec3(.82,.94,1.)*(.75+.35*f)*COLOR.rgb;
	ALPHA=clamp(fo*edge*a*.8+edge*a*a*.1,0.,1.);
}""")
		wake_mat.render_priority = 2
	var im = ImmediateMesh.new()
	var mi = MeshInstance3D.new()
	mi.mesh = im
	mi.material_override = wake_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("keep", true)
	add_child(mi)
	return {"mi": mi, "im": im, "pts": []}


# Kielwasser: Mittelstreifen (aufgewühltes Wasser direkt hinter dem Antrieb) + zwei Arme, die als V auseinanderlaufen
func _wake_draw(w: Dictionary) -> void:
	var im: ImmediateMesh = w.im
	im.clear_surfaces()
	var pts: Array = w.pts
	if pts.size() < 2:
		return
	for arm in [0.0, -1.0, 1.0]:
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for q in pts:
			var age = clampf((wake_t - float(q[3])) / WAKE_LIFE, 0.0, 1.0)
			var a = 1.0 - age
			var off = arm * (0.38 + age * 1.6)
			var hw = (0.42 + age * 0.9) if arm == 0.0 else (0.18 + age * 0.45)
			var c: Vector3 = q[0] + q[1] * off + q[2] * (0.012 + age * 0.004)
			var br = 1.0 if arm == 0.0 else 0.9
			im.surface_set_color(Color(br, br, br, a))
			im.surface_set_uv(Vector2(-1.0, 0.0))
			im.surface_add_vertex(c - q[1] * hw)
			im.surface_set_color(Color(br, br, br, a))
			im.surface_set_uv(Vector2(1.0, 0.0))
			im.surface_add_vertex(c + q[1] * hw)
		im.surface_end()


func _wake_tick(dt: float, i: int, o: Dictionary, on: bool) -> void:
	while wake.size() <= i:
		wake.append(_wake_node())
	var w: Dictionary = wake[i]
	if not is_instance_valid(w.mi):
		w = _wake_node()
		wake[i] = w
	var pts: Array = w.pts
	if on:
		var f = T.frame(float(o.z))
		var pos: Vector3 = f.c + f.rr * float(o.lat) - f.uu * 0.05 - f.fw * 0.35
		if pts.is_empty() or (pts[pts.size() - 1][0] as Vector3).distance_to(pos) > WAKE_STEP:
			pts.append([pos, f.rr, f.uu, wake_t])
		elif pts.size() >= 2:
			pts[pts.size() - 1] = [pos, f.rr, f.uu, wake_t]   # Kopf des Bandes klebt am Schiff
	while not pts.is_empty() and wake_t - float(pts[0][3]) > WAKE_LIFE:
		pts.pop_front()
	(w.mi as MeshInstance3D).visible = pts.size() >= 2
	if pts.size() >= 2 or (w.im as ImmediateMesh).get_surface_count() > 0:
		_wake_draw(w)


var sheet_mesh: ArrayMesh
var sheet_mat: ShaderMaterial


# Seitlicher Wasserschleier (wie die „Flügel“ beim Jetboot): gebogene Fläche vom Rumpf nach außen-oben-hinten,
# nah am Schiff geschlossen, außen reißt sie in Fetzen auf; dahinter wird das Licht gebrochen
func _sheet_mesh() -> ArrayMesh:
	if sheet_mesh == null:
		var st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var NU = 14
		var NV = 8
		var pts = []
		for iv in range(NV + 1):
			var row = []
			for iu in range(NU + 1):
				var u = float(iu) / NU
				var v = float(iv) / NV
				var x = 0.22 + u * 1.9
				var y = 0.02 + 1.05 * sin(u * PI * 0.8) * (0.55 + 0.45 * (1.0 - v)) + u * u * 0.1
				var z = -0.55 + v * 2.4 + u * 1.1
				row.append([Vector3(x, y, z), Vector2(u, v)])
			pts.append(row)
		for iv in range(NV):
			for iu in range(NU):
				var q = [pts[iv][iu], pts[iv][iu + 1], pts[iv + 1][iu + 1], pts[iv + 1][iu]]
				for k in [0, 1, 2, 0, 2, 3]:
					st.set_uv(q[k][1])
					st.add_vertex(q[k][0])
		sheet_mesh = st.commit()
		sheet_mat = _shader_mat("""
shader_type spatial;
render_mode unshaded,blend_mix,depth_draw_never,cull_disabled,shadows_disabled;
uniform sampler2D scr : hint_screen_texture, filter_linear;
float hs(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5);}
float vn(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(hs(i),hs(i+vec2(1,0)),f.x),mix(hs(i+vec2(0,1)),hs(i+1.),f.x),f.y);}
void fragment(){
	float u=UV.x,v=UV.y,t=TIME;
	vec2 q=vec2(u*4.5-t*8.,v*2.6+u*1.5);
	float n=vn(q)*.55+vn(q*2.3+vec2(-t*11.,1.7))*.3+vn(q*5.1+vec2(-t*15.,0.))*.15;
	float thr=mix(.12,.78,u)+v*.22;                 // am Rumpf geschlossen, außen in Fetzen
	float a=smoothstep(thr,thr+.12,n);
	a*=smoothstep(0.,.06,u)*smoothstep(1.,.7,u)*smoothstep(0.,.08,v)*smoothstep(1.,.45,v);
	a*=smoothstep(.6,2.4,length(VERTEX));             // nicht direkt vor der Kamera
	float ln=.5+.5*sin(v*38.+n*7.-u*6.);               // Schlieren im Wasserfilm
	vec2 off=(vec2(n,vn(q.yx))-.5)*.05*a;
	vec3 bg=texture(scr,SCREEN_UV+off).rgb;
	ALBEDO=bg*1.05+vec3(.62,.86,1.)*(.18+.3*ln*smoothstep(thr+.05,thr+.3,n));
	ALPHA=clamp(a*.8,0.,1.);
}""")
		sheet_mat.render_priority = 1
	return sheet_mesh


func _spray_node() -> Node3D:
	var h = Node3D.new()
	h.set_meta("keep", true)
	add_child(h)
	var dot = _soft_dot()
	var puff = _puff_tex()
	# Fontäne: Tropfenstriche ...
	var tl = _spray_part(130, 0.8, 0.035, dot, false, true)
	tl.direction = Vector3(0, 0.85, 0.55)
	tl.spread = 11.0
	tl.gravity = Vector3(0, -11.0, 0)
	tl.initial_velocity_min = 3.5
	tl.initial_velocity_max = 7.0
	tl.damping_min = 0.3
	tl.damping_max = 0.9
	tl.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	tl.emission_box_extents = Vector3(0.08, 0.02, 0.05)
	tl.scale_amount_min = 0.6
	tl.scale_amount_max = 1.4
	tl.color_ramp = _sgrad([0.0, 0.06, 0.6, 1.0], [Color(1, 1, 1, 0.0), Color(0.95, 0.99, 1.0, 0.9), Color(0.8, 0.92, 1.0, 0.6), Color(0.6, 0.8, 1.0, 0.0)])
	tl.color_initial_ramp = _sgrad([0.0, 0.5, 1.0], [Color(0.75, 0.95, 1.0), Color(1, 1, 1), Color(1.0, 0.8, 0.95)])   # Neonlicht färbt einzelne Tropfen
	h.add_child(tl)
	# ... und wolkige Wasserfetzen als Körper der Fontäne
	var bd = _spray_part(46, 0.75, 0.5, puff, false)
	bd.direction = Vector3(0, 0.8, 0.6)
	bd.spread = 12.0
	bd.gravity = Vector3(0, -7.0, 0)
	bd.initial_velocity_min = 2.5
	bd.initial_velocity_max = 5.5
	bd.damping_min = 0.8
	bd.damping_max = 1.6
	bd.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	bd.emission_box_extents = Vector3(0.1, 0.03, 0.08)
	bd.angle_min = 0.0
	bd.angle_max = 360.0
	bd.angular_velocity_min = -90.0
	bd.angular_velocity_max = 90.0
	bd.scale_amount_min = 0.6
	bd.scale_amount_max = 1.2
	bd.scale_amount_curve = _scurve([[0.0, 0.3], [0.4, 1.0], [1.0, 1.9]])
	bd.color_ramp = _sgrad([0.0, 0.1, 0.5, 1.0], [Color(0.9, 0.97, 1.0, 0.0), Color(0.9, 0.97, 1.0, 0.45), Color(0.75, 0.88, 1.0, 0.22), Color(0.6, 0.75, 1.0, 0.0)])
	h.add_child(bd)
	# Tropfenschleier links/rechts
	var sides = []
	for sd in [-1.0, 1.0]:
		var s2 = _spray_part(50, 0.6, 0.025, dot, false, true)
		s2.position = Vector3(sd * 0.3, 0.0, -0.15)
		s2.direction = Vector3(sd * 0.9, 0.75, 0.45)
		s2.spread = 14.0
		s2.flatness = 0.6
		s2.gravity = Vector3(0, -12.0, 0)
		s2.initial_velocity_min = 2.0
		s2.initial_velocity_max = 4.5
		s2.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		s2.emission_box_extents = Vector3(0.04, 0.01, 0.35)
		s2.scale_amount_min = 0.6
		s2.scale_amount_max = 1.4
		s2.color_ramp = _sgrad([0.0, 0.1, 0.7, 1.0], [Color(1, 1, 1, 0.0), Color(0.92, 0.98, 1.0, 0.9), Color(0.75, 0.9, 1.0, 0.6), Color(0.6, 0.8, 1.0, 0.0)])
		s2.color_initial_ramp = _sgrad([0.0, 0.5, 1.0], [Color(0.75, 0.95, 1.0), Color(1, 1, 1), Color(1.0, 0.8, 0.95)])
		h.add_child(s2)
		sides.append(s2)
	# Sprühnebel
	var ms = _spray_part(36, 1.6, 0.9, puff, false)
	ms.position = Vector3(0, 0.15, 0.4)
	ms.direction = Vector3(0, 1, 0.2)
	ms.spread = 50.0
	ms.gravity = Vector3(0, 0.25, 0)
	ms.initial_velocity_min = 0.4
	ms.initial_velocity_max = 1.4
	ms.damping_min = 1.0
	ms.damping_max = 2.0
	ms.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	ms.emission_box_extents = Vector3(0.3, 0.1, 0.2)
	ms.angle_min = 0.0
	ms.angle_max = 360.0
	ms.angular_velocity_min = -25.0
	ms.angular_velocity_max = 25.0
	ms.scale_amount_min = 0.7
	ms.scale_amount_max = 1.3
	ms.scale_amount_curve = _scurve([[0.0, 0.4], [1.0, 2.2]])
	ms.color_ramp = _sgrad([0.0, 0.15, 1.0], [Color(0.8, 0.9, 1.0, 0.0), Color(0.75, 0.88, 1.0, 0.16), Color(0.55, 0.7, 1.0, 0.0)])
	h.add_child(ms)
	# Gischtfahne: dichte, weiße Wolkenbank, die lange hinter dem Gleiter über dem Wasser stehen bleibt und verweht
	var pl = _spray_part(80, 3.0, 1.5, puff, false)
	pl.position = Vector3(0, 0.25, 0.9)
	pl.direction = Vector3(0, 0.6, 1.0)
	pl.spread = 35.0
	pl.gravity = Vector3(0, 0.15, 0)
	pl.initial_velocity_min = 0.8
	pl.initial_velocity_max = 2.6
	pl.damping_min = 0.6
	pl.damping_max = 1.2
	pl.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	pl.emission_box_extents = Vector3(0.45, 0.2, 0.3)
	pl.angle_min = 0.0
	pl.angle_max = 360.0
	pl.angular_velocity_min = -20.0
	pl.angular_velocity_max = 20.0
	pl.scale_amount_min = 0.8
	pl.scale_amount_max = 1.3
	pl.scale_amount_curve = _scurve([[0.0, 0.35], [0.25, 1.1], [1.0, 2.6]])
	pl.color_ramp = _sgrad([0.0, 0.05, 0.35, 1.0], [Color(0.95, 0.98, 1.0, 0.0), Color(0.95, 0.98, 1.0, 0.62), Color(0.85, 0.92, 1.0, 0.4), Color(0.7, 0.8, 0.95, 0.0)])
	h.add_child(pl)
	h.set_meta("parts", [tl, sides[0], sides[1], ms, bd, pl])
	var shs = []
	for sd in [-1.0, 1.0]:
		var mi = MeshInstance3D.new()
		mi.mesh = _sheet_mesh()
		mi.material_override = sheet_mat
		mi.scale = Vector3(sd, 1, 1)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		h.add_child(mi)
		shs.append(mi)
	h.set_meta("sheets", shs)
	return h


var soft_dot_tex: GradientTexture2D


func _soft_dot() -> GradientTexture2D:
	if soft_dot_tex == null:
		soft_dot_tex = GradientTexture2D.new()
		soft_dot_tex.fill = GradientTexture2D.FILL_RADIAL
		soft_dot_tex.fill_from = Vector2(0.5, 0.5)
		soft_dot_tex.fill_to = Vector2(1.0, 0.5)
		soft_dot_tex.width = 32
		soft_dot_tex.height = 32
		var g2 = Gradient.new()
		g2.offsets = PackedFloat32Array([0.0, 1.0])
		g2.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
		soft_dot_tex.gradient = g2
	return soft_dot_tex


func _water_update(dt: float) -> void:
	if not T.X or ships.is_empty():
		return
	while wsp.size() < ships.size():
		wsp.append(_spray_node())
	var racing_w = state in ["race", "done", "replay", "count"]
	wake_t += dt
	if wake_gen != race_gen:   # neues Rennen: altes Kielwasser weg
		wake_gen = race_gen
		for w in wake:
			w.pts.clear()
	if mats.has("water"):
		var sh = []
		for i in range(4):
			var v4 = Vector4(0, -999, 0, 0)
			if i < ships.size():
				var o2: Dictionary = ships[i]
				if racing_w and not o2.out and T.in_water(T.lz(float(o2.z))):
					var f2 = T.frame(float(o2.z))
					var c2: Vector3 = f2.c + f2.rr * float(o2.lat)
					v4 = Vector4(c2.x, c2.y, c2.z, clampf(float(o2.spd) / 30.0, 0.3, 1.0) * (0.4 if bool(o2.get("air", false)) else 1.0))
			sh.append(v4)
		(mats["water"] as ShaderMaterial).set_shader_parameter("shp", sh)
		# Schneise und Spritzwasser an den Wänden: gelten auch noch ein Stück nach dem See, damit die Spur ausläuft
		var sz = []
		var sw = []
		for i in range(4):
			var a4 = Vector4(0, 0, 0, 0)
			if i < ships.size():
				var o3: Dictionary = ships[i]
				var zl = T.lz(float(o3.z))
				if racing_w and not o3.out and zl > float(T.WAT[0]) and zl < float(T.WAT[1]) + 40.0:
					var on3 = T.in_water(zl) and not bool(o3.get("air", false))
					var stg = clampf(float(o3.spd) / 14.0, 0.3, 1.3) * (1.0 if on3 else 0.75)
					a4 = Vector4(float(o3.lat), zl, stg, clampf(float(o3.spd) / 16.0, 0.0, 1.5))
					for sd in [-1.0, 1.0]:
						var dist = WWALL - sd * float(o3.lat)
						sw.append(Vector4(zl, clampf(1.55 - dist * 0.28, 0.3, 1.0) * stg, maxf(float(o3.spd), 5.0), sd))
			sz.append(a4)
		while sw.size() < 8:
			sw.append(Vector4(0, 0, 10, 0))
		(mats["water"] as ShaderMaterial).set_shader_parameter("shz", sz)
		if mats.has("wwall"):
			(mats["wwall"] as ShaderMaterial).set_shader_parameter("src", sw)
			if OS.get_environment("WWDBG") != "" and Engine.get_process_frames() % 20 == 0:
				print("WWDBG ", sw)
	for i in range(ships.size()):
		var o: Dictionary = ships[i]
		if not is_instance_valid(wsp[i]):   # erst prüfen, dann zuweisen (gelöschtes Objekt in typisierter Variable = Absturz auf dem Handy)
			wsp[i] = _spray_node()
		var hn: Node3D = wsp[i]
		var on = racing_w and not o.out and not bool(o.get("air", false)) and float(o.spd) > 2.0 and T.in_water(T.lz(float(o.z)))
		_wake_tick(dt, i, o, on)
		var pa: Array = hn.get_meta("parts")
		for q in pa:
			if is_instance_valid(q):
				q.emitting = on
		for q in hn.get_meta("sheets", []):
			if is_instance_valid(q):
				q.visible = on
		if on:
			var f = T.frame(float(o.z))
			var sv = clampf(float(o.spd) / 40.0, 0.3, 1.6)   # Tempo-Anteil: schneller = höhere Fontäne, breiterer Fächer
			hn.global_transform = Transform3D(Basis(f.rr, f.uu, -f.fw), f.c + f.rr * float(o.lat) - f.fw * 0.5 - f.uu * 0.04)
			var tl: CPUParticles3D = pa[0]
			tl.initial_velocity_min = 2.5 + 3.0 * sv
			tl.initial_velocity_max = 4.5 + 5.0 * sv
			for k in [1, 2]:
				var s2: CPUParticles3D = pa[k]
				s2.initial_velocity_max = 2.5 + 3.5 * sv
		# Wal: einmal pro Runde springt er neben der Strecke aus dem Wasser (wenn der Spieler auf den See fährt)
	var g: Dictionary = ships[0]
	var lzg = T.lz(float(g.z))
	var lapn = int(floor((float(g.z) - 20.0) / T.LAP))
	if state == "race" and not g.out and lapn != whale_lap and lzg > float(T.WAT[0]) + 2.0 and lzg < float(T.WAT[0]) + 12.0 and whale.is_empty():
		whale_lap = lapn
		_whale_start(float(g.z) + 68.0, 13.0 if lapn % 2 == 0 else -13.0)
	if OS.get_environment("WHALE") != "" and whale.is_empty() and Engine.get_process_frames() > int(OS.get_environment("WHALEF")) and whale_lap < 0:
		whale_lap = 0
		_whale_start(float(OS.get_environment("WHALE").split(",")[0]), float(OS.get_environment("WHALE").split(",")[1]))
		print("WHALE start frame ", Engine.get_process_frames())
	if not whale.is_empty():
		_whale_tick(dt)
	# nasse Scheibe: auf dem See (im Cockpit stärker), trocknet danach in gut zwei Sekunden
	var wtar = 0.0
	if state in ["race", "count"] and not g.out and T.in_water(lzg) and not g.air:
		wtar = 1.0 if _ck_on() else 0.45
	if not whale.is_empty() and float(whale.t) > 2.4 and float(whale.t) < 3.2 and absf(float(whale.z) - float(g.z)) < 26.0:
		wtar = maxf(wtar, 1.0 if _ck_on() else 0.7)   # der Wal klatscht zurück: Wasser bis auf die Scheibe
	# durch fremde Gischtfahne: Scheibe kurz zu, dann reißt der Fahrtwind das Wasser zu den Seiten weg
	var btar = 0.0
	if state == "race" and not g.out and not g.air and lzg > float(T.WAT[0]) - 2.0 and lzg < float(T.WAT[1]) + 6.0:
		var fg = T.frame(float(g.z))
		var gp: Vector3 = fg.c + fg.rr * float(g.lat)
		for i in range(1, mini(wake.size(), ships.size())):
			for q in wake[i].pts:
				var ag = wake_t - float(q[3])
				if ag > 0.15 and ag < 2.4 and (q[0] as Vector3).distance_to(gp) < 1.5:
					btar = maxf(btar, 1.0 - ag / 3.0)
	if OS.get_environment("BLIND") != "":
		btar = float(OS.get_environment("BLIND"))
	blind = move_toward(blind, btar, dt * (6.0 if btar > blind else 0.75))
	if btar > 0.3:
		wtar = maxf(wtar, 1.0)
	wet = move_toward(wet, wtar, dt * (2.0 if wtar > wet else 0.45))
	if OS.get_environment("WET") != "":
		wet = float(OS.get_environment("WET"))
	if hud.has("drops") and is_instance_valid(hud.drops):
		hud.drops.visible = wet > 0.01 or blind > 0.01
		if hud.drops.visible:
			_sp(hud.drops.material, "wet", wet)
			_sp(hud.drops.material, "fog", blind)


# Wal: dunkler Körper mit Neon-Saum, aus Ringen gebaut; Schwanzflosse und Brustflossen als flache Flächen
func _whale_mesh() -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var L = 15.0
	var NA = 18
	var NL = 26
	var rings = []
	for i in range(NL + 1):
		var t = float(i) / NL
		var zz = -L * 0.5 + L * t
		var r = 0.14 + 1.95 * pow(sin(PI * clampf(pow(t, 1.35), 0.0, 0.985)), 0.5)   # dünner Schwanzstiel, mächtiger Kopf
		var ring = []
		for k in range(NA):
			var a = TAU * k / NA
			var y = sin(a) * r * 0.85
			if y < 0.0:
				y *= 0.85   # Bauch etwas flacher
			ring.append(Vector3(cos(a) * r, y, zz))
		rings.append(ring)
	for i in range(NL):
		for k in range(NA):
			var k2 = (k + 1) % NA
			var a = rings[i][k]
			var b = rings[i + 1][k]
			var c = rings[i + 1][k2]
			var d = rings[i][k2]
			for v in [a, b, c, a, c, d]:
				var nn = Vector3(v.x, v.y * 1.3, 0.0).normalized()
				var belly = clampf(-v.y * 1.2, 0.0, 1.0)
				var groove = 0.85 + 0.15 * sin(v.x * 9.0) if v.y < -0.3 and v.z > 0.0 else 1.0
				st.set_color(Color(0.07, 0.09, 0.13).lerp(Color(0.42, 0.45, 0.5), belly) * groove)
				st.set_normal(nn)
				st.add_vertex(v)
	# Schwanzflosse (waagrecht, nach hinten gepfeilt) und Brustflossen
	var fins = [
		[Vector3(0, 0, -7.0), Vector3(4.3, 0.2, -9.2), Vector3(0.9, 0.05, -8.6)],
		[Vector3(0, 0, -7.0), Vector3(-4.3, 0.2, -9.2), Vector3(-0.9, 0.05, -8.6)],
		[Vector3(0, 0, -7.0), Vector3(0.9, 0.05, -8.6), Vector3(0, 0, -8.1)],
		[Vector3(0, 0, -7.0), Vector3(0, 0, -8.1), Vector3(-0.9, 0.05, -8.6)],
		[Vector3(1.3, -0.6, 2.8), Vector3(4.2, -1.3, 0.4), Vector3(1.5, -0.7, 1.6)],
		[Vector3(-1.3, -0.6, 2.8), Vector3(-4.2, -1.3, 0.4), Vector3(-1.5, -0.7, 1.6)],
	]
	for tri in fins:
		for v in tri:
			st.set_color(Color(0.08, 0.1, 0.14))
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
		for j in [0, 2, 1]:
			st.set_color(Color(0.3, 0.33, 0.38))
			st.set_normal(Vector3.DOWN)
			st.add_vertex(tri[j])
	return st.commit()


func _whale_start(z: float, lat: float) -> void:
	var mi = MeshInstance3D.new()
	mi.mesh = _whale_mesh()
	mi.material_override = _shader_mat("""
shader_type spatial;
render_mode cull_disabled;
varying vec3 lp;
void vertex(){lp=VERTEX;}
float hs(vec3 p){return fract(sin(dot(p,vec3(12.9,78.2,37.7)))*43758.5);}
void fragment(){
	ALBEDO=COLOR.rgb;
	ROUGHNESS=.25;
	SPECULAR=.8;
	float fr=pow(1.-clamp(dot(NORMAL,VIEW),0.,1.),2.5);
	// leuchtet wie ein Tiefseewesen: Saum, Linie an der Flanke, Punkte auf dem Rücken
	float flank=exp(-pow((lp.y+.15)*5.,2.))*(.6+.4*sin(lp.z*2.-TIME*6.));
	vec3 cell=floor(lp*2.2);
	float dots=step(.86,hs(cell))*smoothstep(.45,.1,length(fract(lp*2.2)-.5))*step(.2,lp.y);
	EMISSION=vec3(.2,.8,1.)*(fr*1.1+flank*.9)+vec3(1.,.3,.85)*dots*1.6+COLOR.rgb*.15;
}""")
	mi.set_meta("keep", true)
	mi.set_meta("rfx", true)
	add_child(mi)
	whale = {"n": mi, "z": z, "lat": lat, "t": 0.0, "sp": 0}


func _whale_splash(pos: Vector3, big: float) -> void:
	var p = CPUParticles3D.new()
	var qm = QuadMesh.new()
	qm.size = Vector2(0.5, 0.5)
	var mm = StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mm.vertex_color_use_as_albedo = true
	mm.albedo_texture = _soft_dot()
	qm.material = mm
	qm.material = _streak_mat()   # Tropfenstriche statt Kügelchen
	qm.size = Vector2(0.07, 0.07)
	p.particle_flag_align_y = true
	p.mesh = qm
	p.amount = int(150 * big)
	p.lifetime = 1.8
	p.one_shot = true
	p.explosiveness = 0.85
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 38.0
	p.gravity = Vector3(0, -11.0, 0)
	p.initial_velocity_min = 5.0 * big
	p.initial_velocity_max = 13.0 * big
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 2.2
	p.scale_amount_min = 0.8
	p.scale_amount_max = 2.6
	var gr = Gradient.new()
	gr.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	gr.colors = PackedColorArray([Color(0.9, 0.97, 1.0, 0.0), Color(0.85, 0.95, 1.0, 0.85), Color(0.6, 0.8, 1.0, 0.0)])
	p.color_ramp = gr
	p.set_meta("deb", true)
	p.set_meta("rfx", true)
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(2.5).timeout.connect(func(): _qf(p))
	# Wasserwolke dazu, damit es kein Punkteregen ist
	var pf = _spray_part(int(36 * big), 1.7, 1.3, _puff_tex(), false)
	pf.one_shot = true
	pf.explosiveness = 0.8
	pf.direction = Vector3.UP
	pf.spread = 30.0
	pf.gravity = Vector3(0, -6.0, 0)
	pf.initial_velocity_min = 2.0 * big
	pf.initial_velocity_max = 8.0 * big
	pf.damping_min = 0.8
	pf.damping_max = 1.6
	pf.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	pf.emission_sphere_radius = 1.8
	pf.angle_min = 0.0
	pf.angle_max = 360.0
	pf.scale_amount_curve = _scurve([[0.0, 0.5], [1.0, 2.0]])
	pf.color_ramp = _sgrad([0.0, 0.12, 1.0], [Color(0.9, 0.97, 1.0, 0.0), Color(0.85, 0.95, 1.0, 0.5), Color(0.6, 0.8, 1.0, 0.0)])
	pf.set_meta("deb", true)
	pf.set_meta("rfx", true)
	add_child(pf)
	pf.global_position = pos
	pf.emitting = true
	get_tree().create_timer(2.5).timeout.connect(func(): _qf(pf))
	_snd("splash", -2.0 + 4.0 * big, randf_range(0.9, 1.05), pos)


func _whale_tick(dt: float) -> void:
	if not is_instance_valid(whale.n):
		whale = {}
		return
	var TT = 3.4
	whale.t = float(whale.t) + dt
	var t = float(whale.t)
	if t > TT + 0.3 or state == "menu":
		_qf(whale.n)
		whale = {}
		return
	var f = T.frame(float(whale.z))
	var q = clampf(t / TT, 0.0, 1.0)
	# er springt quer über die Strecke vor dir: von der Seite zu sehen, in voller Länge
	var sd = signf(float(whale.lat))
	var across: Vector3 = -f.rr * sd
	var base: Vector3 = f.c + f.rr * float(whale.lat)
	var hgt = -6.0 + 18.0 * sin(PI * q)
	var adv = -4.0 + 2.0 * absf(float(whale.lat)) * q + 8.0 * q
	var pos: Vector3 = base + across * adv + Vector3.UP * hgt
	var vel: Vector3 = across * ((2.0 * absf(float(whale.lat)) + 8.0) / TT) + Vector3.UP * (18.0 * PI / TT * cos(PI * q))
	var fwd = vel.normalized()
	var xr = Vector3.UP.cross(fwd).normalized()
	var b = Basis(xr, fwd.cross(xr).normalized(), fwd)
	b = b * Basis(Vector3(0, 0, 1), 0.5 * sin(PI * q))   # dreht sich in der Luft etwas auf die Seite
	(whale.n as Node3D).global_transform = Transform3D(b, pos)
	if int(whale.sp) == 0 and t > 0.35:
		whale.sp = 1
		_whale_splash(base + across * -3.5, 0.8)
	if int(whale.sp) == 1 and t > TT - 0.45:
		whale.sp = 2
		_whale_splash(base + across * (2.0 * absf(float(whale.lat)) + 4.0), 1.25)
		shake = maxf(shake, 0.25)


func _debris_update(dt: float) -> void:
	_water_update(dt)
	_radio_tick(dt)
	for sc in scorch:
		sc.t += dt
		(sc.m as ShaderMaterial).set_shader_parameter("heat", maxf(0.3, 1.0 - float(sc.t) / 25.0))
	if debris.is_empty():
		return
	for i in range(debris.size() - 1, -1, -1):
		var d: Dictionary = debris[i]
		if not is_instance_valid(d.n):
			debris.remove_at(i)
			continue
		var nd: Node3D = d.n
		d.t += dt
		d.vh -= 18.0 * dt
		d.z += d.vz * dt
		d.lat += d.vl * dt
		d.h += d.vh * dt
		var gr: float = d.r * 0.55
		var ground = false
		if d.h < gr:
			d.h = gr
			ground = true
			if d.vh < -2.5:
				# Aufschlag: springt etwas zurück, Funken
				d.vh = -d.vh * 0.32
				d.av = (d.av as Vector3) * 0.6 + Vector3(randf_range(-3, 3), randf_range(-3, 3), randf_range(-3, 3))
				if not d.hit:
					d.hit = true
				_debris_sparks(d, 10)
			else:
				d.vh = 0.0
		if ground:
			# schlittern: Reibung längs und quer, Drehung lässt nach (dreht vor allem noch flach weiter)
			d.vz *= exp(-1.1 * dt)
			d.vl *= exp(-2.2 * dt)
			var av: Vector3 = d.av
			d.av = Vector3(av.x * exp(-5.0 * dt), av.y * exp(-1.2 * dt), av.z * exp(-5.0 * dt))
			d.sp += dt
			if d.vz > 5.0 and d.sp > 0.12:
				d.sp = 0.0
				_debris_sparks(d, 5)
		# Leitplanken: zurückprallen
		var lim = T.TW - 0.15
		if absf(d.lat) > lim:
			d.lat = signf(d.lat) * lim
			d.vl = -d.vl * 0.4
			_debris_sparks(d, 8)
		var av2: Vector3 = d.av
		if av2.length() > 0.01:
			d.rb = Basis(av2.normalized(), av2.length() * dt) * (d.rb as Basis)
		var f = T.frame(d.z)
		var B = Basis(-f.rr, f.uu, f.fw)
		var sc = 1.0   # Trümmer bleiben bis zum Rennende liegen
		nd.global_transform = Transform3D((B * (d.rb as Basis)).orthonormalized().scaled(Vector3.ONE * maxf(sc, 0.001)), f.c + f.rr * d.lat + f.uu * d.h)
		if d.m != null:
			(d.m as StandardMaterial3D).emission_energy_multiplier = maxf(0.12 if d.get("wreck", false) else 0.0, 0.7 - d.t * 0.28)
		if (state == "race" or state == "done") and not d.get("small", false):
			_debris_hits(d, dt)


# Schiffe fahren gegen Trümmer: Brocken wird weggekickt, Schiff etwas gebremst, 1–2 % Energie; Quake wirbelt sie hoch
func _debris_hits(d: Dictionary, dt: float) -> void:
	d.kt = maxf(0.0, float(d.kt) - dt)
	for q in [quake, quake2]:
		if q != null and absf(wrapf(d.z - float(q.z), -T.LAP * 0.5, T.LAP * 0.5)) < 2.2 and d.h < 0.6:
			d.vh = randf_range(5.0, 8.0)
			d.vz += randf_range(4.0, 9.0) * float(q.get("dir", 1.0))
			d.av = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
	if d.kt > 0.0:
		return
	for o in ships:
		if o.out or o.air:
			continue
		var dz = wrapf(d.z - o.z, -T.LAP * 0.5, T.LAP * 0.5)
		var r: float = d.r
		if absf(dz) < r + 0.65 and absf(d.lat - o.lat) < r + 0.32 and d.h < 0.7:
			d.kt = 0.4
			var away = signf(d.lat - o.lat) if absf(d.lat - o.lat) > 0.02 else (1.0 if randf() < 0.5 else -1.0)
			var big = d.get("wreck", false)
			d.vz = o.spd * (0.6 if big else 1.05) + randf_range(1.0, 4.0)
			d.vl = away * randf_range(2.0, 5.0) * (0.5 if big else 1.0)
			d.vh = randf_range(1.5, 3.5) * (0.4 if big else 1.0)
			d.av = Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9)) * (0.4 if big else 1.0)
			o.spd *= 0.86 if big else 0.95
			if not _prot(o):
				_dmg(o, 0.02 if big else 0.01, -1, "ram")
			_debris_sparks(d, 10)
			var pos: Vector3 = (d.n as Node3D).global_position
			_snd("crash_bump", -9.0 if o.idx == 0 else -6.0, randf_range(1.0, 1.25), null if o.idx == 0 else pos)
			if o.idx == 0:
				_vib(90 if big else 50, 0.8 if big else 0.55)
			if o.idx == 0:
				shake = maxf(shake, 0.3 if big else 0.15)
			return


func _debris_sparks(d: Dictionary, n: int) -> void:
	if d.get("small", false):
		n = 2 if randf() < 0.4 else 0   # kleine Splitter: nur ab und zu ein Fünkchen
		if n == 0:
			return
	if not is_instance_valid(d.n) or cam == null or (d.n as Node3D).global_position.distance_squared_to(cam.global_position) > 2500.0:
		return
	_burst((d.n as Node3D).global_position, fxr.spark, n, 0.45, 1.5, 5.0, 60.0, Vector3(0, -9, 0), 0.5, 0.4, 0.9,
		_ramp([[0.0, Color(9, 7, 4, 1)], [0.6, Color(4, 1.2, 0.2, 1)], [1.0, Color(1, 0.2, 0.05, 0)]]), null, true, false, 0.1)


# ---------------------------------------------------------------- Gegner dicht hinter dir: Punkte unten am Rand
# Seitliche Lage = wo der Gegner auf der Fahrbahn ist (relativ zu dir); je näher, desto kräftiger.
func _rear_draw(c: Control) -> void:
	if ships.is_empty() or not (state == "race" or state == "count"):
		return
	var rng = float(fx.ship.get("rdots", 15.0))
	if rng < 1.0:
		return
	var g: Dictionary = ships[0]
	if g.out:
		return
	var vp = c.size
	var k = vp.x / GA_W
	var hs = int(cfg.get("hud", 2))
	var y = vp.y - (GA_H - 1150.0) * k if hs == 2 else vp.y * 0.72
	var near = 2.0
	for i in range(1, ships.size()):
		var o: Dictionary = ships[i]
		if o.out:
			continue
		var dz: float = g.z - o.z
		if dz < 0.3 or dz > rng:
			continue
		var a = clampf(1.0 - (dz - near) / maxf(0.5, rng - near), 0.15, 1.0)
		var x = vp.x * 0.5 + clampf((o.lat - g.lat) / (2.0 * T.TW), -1.0, 1.0) * vp.x * 0.42
		var col: Color = CHARS[i][2] if i < CHARS.size() else Color(1, 1, 1)
		var r = (11.0 + 9.0 * a) * k * 1.6
		c.draw_circle(Vector2(x, y), r * 1.9, Color(col.r, col.g, col.b, 0.18 * a))
		c.draw_circle(Vector2(x, y), r, Color(col.r, col.g, col.b, 0.85 * a))
		c.draw_arc(Vector2(x, y), r, 0.0, TAU, 24, Color(1, 1, 1, 0.7 * a), 2.0 * k * 1.6, true)


# ---------------------------------------------------------------- Tribünen am Ziel (beide Seiten), Zuschauer, Jubel, Stadionsprecher
const TRIB_Z = [[22.0, 54.0], [686.0, 718.0]]   # Abschnitte vor und hinter der Ziellinie
const TRIB_L0 = 1.25    # Abstand hinter der Leitplanke
const TRIB_ROWS = 12
const TRIB_SD = 0.22    # Stufentiefe (≈ 90 cm)
const TRIB_RISE = 0.11  # Stufenhöhe (≈ 45 cm)
const TRIB_BASE = 0.32  # Sockel (≈ 1,3 m)
var stadium_p: AudioStreamPlayer3D = null
var deco: Node3D = null   # Zuschauer, Neon, Jubel, Sprecher: wird mit der aktuellen Runde mitverschoben
var crowd_p: AudioStreamPlayer3D = null
var neon_signs = []
var neon_font: Font = null


func _tribunes() -> void:
	if not mats.has("tconc"):
		var m = StandardMaterial3D.new()
		m.albedo_color = Color(0.42, 0.43, 0.48)
		m.roughness = 0.75
		m.metallic = 0.1
		m.emission_enabled = true
		m.emission = Color(0.12, 0.14, 0.2) if not _noir() else Color(0.14, 0.14, 0.15)   # nachts angestrahlt (bläulich)
		mats["tconc"] = m
		var m2 = StandardMaterial3D.new()
		m2.albedo_color = Color(0.1, 0.1, 0.12)
		m2.roughness = 0.6
		m2.metallic = 0.4
		m2.emission_enabled = true
		m2.emission = Color(0.03, 0.035, 0.05)
		mats["tseat"] = m2
		mats["tneo"] = _neon(OR if _noir() else Color(1.0, 0.5, 0.1), 2.6)
		mats["tnec"] = _neon(Color(0.9, 0.9, 0.95) if _noir() else Color(0.2, 0.85, 1.0), 2.2)
	if deco == null:
		deco = Node3D.new()
		add_child(deco)
	_chg_build()
	var L0 = T.TW + TRIB_L0
	var depth = TRIB_ROWS * TRIB_SD
	var top = TRIB_BASE + TRIB_ROWS * TRIB_RISE
	var roof_h = top + 0.95
	for seg in TRIB_Z:
		for sd in [1.0, -1.0]:
			var z = seg[0]
			while z < seg[1] - 0.01:
				var hz = minf(1.0, (seg[1] - z) * 0.5)
				var zc = z + hz
				# Sockel mit orangem Leuchtband vorn
				_box("tconc", zc, sd * (L0 - 0.05), TRIB_BASE * 0.5, 0.06, TRIB_BASE * 0.5, hz)
				_box("tneo", zc, sd * (L0 - 0.115), TRIB_BASE - 0.08, 0.008, 0.018, hz)
				# Stufen (massiv) und dunkle Sitzbänke
				for r in range(TRIB_ROWS):
					var hh = TRIB_BASE + (r + 1) * TRIB_RISE
					_box("tconc", zc, sd * (L0 + (r + 0.5) * TRIB_SD), hh * 0.5, TRIB_SD * 0.5, hh * 0.5, hz)
					_box("tseat", zc, sd * (L0 + (r + 0.62) * TRIB_SD), hh + 0.03, 0.04, 0.03, hz * 0.96)
				# Rückwand bis unters Dach
				_box("tconc", zc, sd * (L0 + depth + 0.06), roof_h * 0.5, 0.06, roof_h * 0.5, hz)
				# Geländer vorn mit Leuchtkante
				_box("tseat", zc, sd * (L0 + 0.02), TRIB_BASE + 0.22, 0.012, 0.012, hz)
				# Dach: leicht schräg zur Strecke, cyan Lichtleisten darunter, orange Kante vorn
				_box("tseat", zc, sd * (L0 + depth * 0.5 - 0.15), roof_h, depth * 0.5 + 0.35, 0.05, hz)
				_box("tnec", zc, sd * (L0 + depth * 0.35), roof_h - 0.06, 0.03, 0.01, hz * 0.8)
				_box("tnec", zc, sd * (L0 + depth * 0.75), roof_h - 0.06, 0.03, 0.01, hz * 0.8)
				_box("tneo", zc, sd * (L0 - 0.48), roof_h, 0.012, 0.05, hz)
				z += 2.0 * hz
			# Stützen hinten
			var zp = seg[0] + 1.0
			while zp < seg[1]:
				_box("tseat", zp, sd * (L0 + depth + 0.2), roof_h * 0.5, 0.06, roof_h * 0.5, 0.06)
				zp += 6.0
			_crowd(seg[0], seg[1], sd, L0)
			# Neon-Schriftzug auf dem Dach, zur Strecke gewandt
			var fzm = T.frame((seg[0] + seg[1]) * 0.5)
			var zax: Vector3 = (-fzm.rr * sd).normalized()
			var up: Vector3 = fzm.uu
			var sc = OR if _noir() else (Color(1.0, 0.25, 0.7) if sd > 0.0 else Color(0.25, 0.9, 1.0))
			_neon_sign(fzm.c + fzm.rr * (sd * (L0 + depth * 0.5)) + up * (roof_h + 0.62), Basis(up.cross(zax).normalized(), up, zax), "ANTIGRAV", sc, 0.9)
	# zwei große Schriftzüge an Häusern neben der Strecke, schräg zum Verkehr
	for sp in [[150.0, 1.0, "ANTIGRAV"], [430.0, -1.0, "ANTIGRAV"], [610.0, 1.0, "ANTIGRAV"], [290.0, 1.0, "PIXEL-INSTITUT"]]:
		if T.in_tun(sp[0], 8.0):
			continue
		var f = T.frame(sp[0])
		var sd2: float = sp[1]
		var zax2: Vector3 = (-f.fw * 0.75 - f.rr * sd2 * 0.65).normalized()
		zax2 = (zax2 - f.uu * zax2.dot(f.uu)).normalized()
		var c2 = OR if _noir() else [Color(1.0, 0.2, 0.55), Color(0.3, 0.95, 1.0), Color(0.75, 0.35, 1.0)][neon_signs.size() % 3]
		_neon_sign(f.c + f.rr * (sd2 * (T.TW + 7.5)) + f.uu * 7.0, Basis(f.uu.cross(zax2).normalized(), f.uu, zax2), sp[2], c2, 2.4 if sp[2] == "ANTIGRAV" else 1.8)
	# Jubel als Schleife an der Ziellinie, Sprecher-Lautsprecher daneben (beide mit Dopplereffekt)
	var f0 = T.frame(20.0)
	crowd_p = AudioStreamPlayer3D.new()
	crowd_p.bus = "Game"
	crowd_p.unit_size = 9.0
	crowd_p.max_distance = 140.0
	crowd_p.volume_db = 2.0
	deco.add_child(crowd_p)
	crowd_p.global_position = f0.c + f0.uu * 2.0
	stadium_p = AudioStreamPlayer3D.new()
	stadium_p.bus = "Stadium"
	stadium_p.unit_size = 22.0
	stadium_p.max_distance = 400.0
	stadium_p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_IDLE_STEP
	deco.add_child(stadium_p)
	stadium_p.global_position = f0.c + f0.uu * 3.5 + f0.rr * (T.TW + 2.0)


# Stadionsprecher über die Lautsprecher an der Ziellinie
func _stadium(k: String, db: float) -> void:
	if stadium_p == null or not snd.has(k):
		return
	stadium_p.stream = snd[k]
	stadium_p.volume_db = db + 4.0
	stadium_p.play()


# Zuschauer: flache Figuren aus dem Bild-Atlas (4×4), drehen sich zur Kamera, hüpfen leicht
const CROWD_CODE = """
shader_type spatial;
render_mode unshaded,cull_disabled,depth_prepass_alpha,shadows_disabled;
uniform sampler2D tx:source_color,filter_linear_mipmap;
uniform float k=.85;
varying vec2 cuv;varying float ph;varying vec3 tint;
void vertex(){
	float idx=floor(INSTANCE_CUSTOM.x*16.+.5);ph=INSTANCE_CUSTOM.y;
	cuv=(UV+vec2(mod(idx,4.),floor(idx/4.)))*.25;
	// Kleidung in verschiedenen Farben (Fan-Trikots), leicht über das Bild gelegt
	int ti=int(floor(INSTANCE_CUSTOM.z*7.));
	tint=ti==0?vec3(1.):ti==1?vec3(1.,.35,.3):ti==2?vec3(.35,.85,1.):ti==3?vec3(1.,.4,.9):ti==4?vec3(1.,.9,.35):ti==5?vec3(.45,1.,.55):vec3(.8,.6,1.);
	float s=length(MODEL_MATRIX[0].xyz);
	vec3 x=normalize(vec3(INV_VIEW_MATRIX[0].x,0.,INV_VIEW_MATRIX[0].z));
	vec3 z=normalize(vec3(INV_VIEW_MATRIX[2].x,0.,INV_VIEW_MATRIX[2].z));
	// Oberkörper wiegt hin und her (Füße bleiben stehen), manche feuern stärker an
	float am=.012+.03*step(.55,ph);
	VERTEX.x+=sin(TIME*(1.4+ph*2.5)+ph*31.)*am*(VERTEX.y/.45);
	VERTEX.y+=abs(sin(TIME*(4.+ph*3.)+ph*6.28))*.005*step(.88,ph);
	MODELVIEW_MATRIX=VIEW_MATRIX*mat4(vec4(x*s,0.),vec4(0.,s,0.,0.),vec4(z*s,0.),MODEL_MATRIX[3]);
}
void fragment(){
	vec4 c=texture(tx,cuv);
	if(c.a<.45){discard;}
	ALBEDO=c.rgb*k*mix(vec3(1.),tint*1.25,.5);
}"""
# Leuchtstäbe über den Köpfen mancher Zuschauer: wedeln hin und her
const STICK_CODE = """
shader_type spatial;
render_mode unshaded,cull_disabled,shadows_disabled;
varying float ph;varying vec3 col;
void vertex(){
	ph=INSTANCE_CUSTOM.y;col=INSTANCE_CUSTOM.rgb;
	float s=length(MODEL_MATRIX[0].xyz);
	vec3 x=normalize(vec3(INV_VIEW_MATRIX[0].x,0.,INV_VIEW_MATRIX[0].z));
	vec3 z=normalize(vec3(INV_VIEW_MATRIX[2].x,0.,INV_VIEW_MATRIX[2].z));
	VERTEX.x+=sin(TIME*(2.5+INSTANCE_CUSTOM.a*3.)+INSTANCE_CUSTOM.a*40.)*.05*(VERTEX.y/.09);
	MODELVIEW_MATRIX=VIEW_MATRIX*mat4(vec4(x*s,0.),vec4(0.,s,0.,0.),vec4(z*s,0.),MODEL_MATRIX[3]);
}
void fragment(){ALBEDO=col*3.2;}"""
var stick_mat: ShaderMaterial = null
var crowd_mat: ShaderMaterial = null


func _crowd(z0: float, z1: float, sd: float, L0: float) -> void:
	if crowd_mat == null:
		crowd_mat = _shader_mat(CROWD_CODE)
		crowd_mat.set_shader_parameter("tx", load("res://art/crowd.png"))
		crowd_mat.set_shader_parameter("k", 0.8 if _noir() else 1.15)
	var q = QuadMesh.new()
	q.size = Vector2(0.3, 0.45)   # Mensch ≈ 1,8 m
	q.center_offset = Vector3(0, 0.225, 0)
	var rng = RandomNumberGenerator.new()
	rng.seed = int(z0 * 7.0 + sd * 3.0)
	var pts = []
	for r in range(TRIB_ROWS):
		var z = z0 + 0.3
		while z < z1 - 0.3:
			z += rng.randf_range(0.22, 0.75)   # gut gefüllt, ein paar Lücken
			# nicht über das Tribünenende hinaus (sonst stehen am Rand Leute in der Luft)
			if z > z1 - 0.2:
				break
			if rng.randf() < 0.08:
				continue
			# mitten auf der Stufe, Füße leicht eingesenkt – so schwebt keiner über der Kante
			pts.append([z, sd * (L0 + (r + 0.45) * TRIB_SD + rng.randf_range(-0.03, 0.03)), TRIB_BASE + (r + 1) * TRIB_RISE - 0.012])
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = q
	mm.instance_count = pts.size()
	for i in range(pts.size()):
		var pz = pts[i]
		var f = T.frame(pz[0])
		var sc = rng.randf_range(0.9, 1.1)
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * sc), f.c + f.rr * pz[1] + f.uu * pz[2]))
		mm.set_instance_custom_data(i, Color((rng.randi() % 16) / 16.0 + 0.01, rng.randf(), rng.randf() * 0.999, 0))
	var mi = MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = crowd_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	deco.add_child(mi)
	# Leuchtstäbe: etwa jeder Vierte hält einen hoch
	if stick_mat == null:
		stick_mat = _shader_mat(STICK_CODE)
	var sq = QuadMesh.new()
	sq.size = Vector2(0.018, 0.09)
	sq.center_offset = Vector3(0, 0.045, 0)
	var sel = []
	for i in range(pts.size()):
		if rng.randf() < 0.25:
			sel.append(pts[i])
	var sm = MultiMesh.new()
	sm.transform_format = MultiMesh.TRANSFORM_3D
	sm.use_custom_data = true
	sm.mesh = sq
	sm.instance_count = sel.size()
	var scols = [Color(0.2, 0.9, 1.0), Color(1.0, 0.25, 0.7), Color(1.0, 0.6, 0.15), Color(0.5, 1.0, 0.4), Color(1, 1, 1)]
	for i in range(sel.size()):
		var pz = sel[i]
		var f = T.frame(pz[0])
		var side = rng.randf_range(-0.07, 0.07)
		sm.set_instance_transform(i, Transform3D(Basis(), f.c + f.rr * pz[1] + f.fw * side + f.uu * (pz[2] + 0.38)))
		var cc: Color = scols[rng.randi() % scols.size()]
		sm.set_instance_custom_data(i, Color(cc.r, cc.g, cc.b, rng.randf()))
	var smi = MultiMeshInstance3D.new()
	smi.multimesh = sm
	smi.material_override = stick_mat
	smi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	deco.add_child(smi)


# Neon-Schriftzug aus einzelnen Buchstaben (Röhren-Look: dünne Schrift, heller Kern, farbiger Schein);
# ein Buchstabe ist „kaputt“: flackert, setzt aus, brummt
func _neon_sign(pos: Vector3, b: Basis, txt: String, col: Color, hgt: float) -> void:
	if neon_font == null:
		neon_font = load("res://art/Inter-Light.otf")
	var root = Node3D.new()
	deco.add_child(root)
	root.transform = Transform3D(b, pos)
	var fs = 128
	var px = hgt / float(fs) * 1.25
	var widths = []
	var tot = 0.0
	for ch in txt:
		var w = neon_font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x * px + hgt * 0.06
		widths.append(w)
		tot += w
	var x = -tot * 0.5
	var letters = []
	for i in range(txt.length()):
		var l = Label3D.new()
		l.text = txt[i]
		l.font = neon_font
		l.font_size = fs
		l.pixel_size = px
		l.outline_size = 22
		l.modulate = Color(col.r * 0.5 + 0.5, col.g * 0.5 + 0.5, col.b * 0.5 + 0.5) * 2.2
		l.outline_modulate = Color(col.r, col.g, col.b, 0.55)
		l.shaded = false
		l.double_sided = false
		l.no_depth_test = false
		l.position = Vector3(x + widths[i] * 0.5, 0, 0)
		root.add_child(l)
		letters.append(l)
		x += widths[i]
	var bad = randi() % txt.length()
	var hum = AudioStreamPlayer3D.new()
	hum.bus = "Game"
	hum.unit_size = 2.0 + hgt
	hum.max_distance = 25.0 + hgt * 8.0
	hum.volume_db = -9.0
	letters[bad].add_child(hum)
	neon_signs.append({"l": letters, "bad": bad, "t": randf() * 10.0, "on": true, "nx": randf_range(0.5, 3.0), "col": col, "hum": hum})


func _neon_live(dt: float) -> void:
	if neon_signs.is_empty() or not snd.has("neon_buzz"):
		return
	var live = state in ["race", "count", "intro", "done", "menu", "replay"]
	# Jubel an der Ziellinie (Ton wird erst nach dem Streckenbau geladen)
	if crowd_p != null:
		if crowd_p.stream == null:
			crowd_p.stream = _looped(snd["crowd"])
		if live and not crowd_p.playing:
			crowd_p.play()
		elif not live and crowd_p.playing:
			crowd_p.stop()
	for sg in neon_signs:
		var hum: AudioStreamPlayer3D = sg.hum
		if hum.stream == null:
			hum.stream = _looped(snd["neon_buzz"])
		if live and not hum.playing:
			hum.play()
		elif not live and hum.playing:
			hum.stop()
		sg.nx -= dt
		if sg.nx <= 0.0:
			# Aussetzer: meist kurz flackern, manchmal länger aus
			sg.on = not sg.on
			if sg.on:
				sg.nx = randf_range(0.4, 4.0) if randf() < 0.75 else randf_range(0.04, 0.15)
			else:
				sg.nx = randf_range(0.03, 0.12) if randf() < 0.8 else randf_range(0.4, 1.6)
		var l: Label3D = sg.l[sg.bad]
		var col: Color = sg.col
		var k = 1.0 if sg.on else 0.12
		l.modulate = Color(col.r * 0.5 + 0.5, col.g * 0.5 + 0.5, col.b * 0.5 + 0.5) * 2.2 * k
		l.outline_modulate = Color(col.r, col.g, col.b, 0.55 * k)
		hum.volume_db = -9.0 if sg.on else -27.0


# ---------------------------------------------------------------- Werbe-Zeppelin über der Stadt (Blade-Runner-Stil)
# zieht langsam eine weite Ellipse über der Stadt; Leuchtschrift an beiden Seiten, Blinklichter, zwei Suchscheinwerfer nach unten
const BLIMP_L = 30.0   # Länge in Einheiten (≈ 120 m)
var blimp = {}
var blimp_off = 0.0
const BEAM_CODE = """
shader_type spatial;
render_mode unshaded,blend_add,cull_disabled,depth_draw_never,shadows_disabled,fog_disabled;
uniform vec3 c=vec3(.6,.75,1.);uniform float k=.25;
uniform sampler2D dtex:hint_depth_texture,filter_nearest;
varying float t;
void vertex(){t=clamp((35.-VERTEX.y)/70.,0.,1.);}   // 0 am Zeppelin, 1 am unteren Ende des Kegels
void fragment(){
	// Länge: hell am Scheinwerfer, läuft weich und lang aus – am Ende ist nichts mehr zu sehen
	float len=pow(1.-t,1.5)*smoothstep(1.,.45,t);
	// Ränder: von der Seite gesehen weich statt harter Kante
	float side=pow(abs(dot(normalize(NORMAL),normalize(VIEW))),1.4);
	// wo der Kegel Häuser oder die Fahrbahn schneidet: sanft ausblenden statt harter Schnittlinie
	float d=texture(dtex,SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 nd=vec3(SCREEN_UV,d)*2.-1.;
#else
	vec3 nd=vec3(SCREEN_UV*2.-1.,d);
#endif
	vec4 vp=INV_PROJECTION_MATRIX*vec4(nd,1.);
	float scene=-vp.z/vp.w;
	float soft=clamp((scene+VERTEX.z)/8.,0.,1.);
	ALBEDO=c*k*len*(.2+.8*side)*soft;
}
"""


func _blimp_make() -> void:
	if not ResourceLoader.exists("res://city/blimp.glb"):
		return
	var root = Node3D.new()
	add_child(root)
	var m: Node3D = load("res://city/blimp.glb").instantiate()
	root.add_child(m)
	m.scale = Vector3.ONE * BLIMP_L
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var src = (mi as MeshInstance3D).mesh.surface_get_material(0)
		if src is StandardMaterial3D:
			var mm = (src as StandardMaterial3D).duplicate()
			mm.emission_enabled = true
			mm.emission_texture = mm.albedo_texture
			mm.emission = Color(0.75, 0.7, 0.75)   # von der Stadt angestrahlt, damit er sich vom dunklen Himmel abhebt
			mm.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
			mm.emission_energy_multiplier = 1.6
			(mi as MeshInstance3D).material_override = mm
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Leuchtschrift auf beiden Flanken
	var font: Font = load("res://art/Inter-Light.otf")
	var signs = []
	for sd in [1.0, -1.0]:
		var l = Label3D.new()
		l.text = "ANTIGRAV" if sd > 0.0 else "PIXEL-INSTITUT"
		l.font = font
		l.font_size = 128
		l.pixel_size = 0.05 if sd > 0.0 else 0.036
		l.outline_size = 18
		l.shaded = false
		l.double_sided = false
		var col = OR if _noir() else (Color(1.0, 0.25, 0.65) if sd > 0.0 else Color(0.3, 0.95, 1.0))
		l.modulate = Color(col.r * 0.5 + 0.5, col.g * 0.5 + 0.5, col.b * 0.5 + 0.5) * 2.0
		l.outline_modulate = Color(col.r, col.g, col.b, 0.5)
		l.position = Vector3(sd * 0.15 * BLIMP_L, 0.24 * BLIMP_L, 0.0)
		l.rotation = Vector3(0, sd * PI * 0.5, 0)
		root.add_child(l)
		signs.append([l, col])
	# Blinklichter (rot oben/Heck, weiß unter der Gondel)
	var blinks = []
	for bp in [[Vector3(0, 0.43, -0.42), Color(1, 0.1, 0.1)], [Vector3(0, 0.02, 0.05), Color(1, 1, 1)], [Vector3(0.14, 0.24, 0.45), Color(1, 0.1, 0.1)], [Vector3(-0.14, 0.24, 0.45), Color(0.1, 1, 0.3)]]:
		var b = MeshInstance3D.new()
		b.mesh = _lowsphere(0.007 * BLIMP_L, 8, 4)
		b.material_override = _glow_mat(bp[1], 8.0)
		b.position = (bp[0] as Vector3) * BLIMP_L
		root.add_child(b)
		blinks.append(b)
	# Suchscheinwerfer: zwei helle Lichtkegel nach unten, schwenken langsam
	var beams = []
	for k in range(2):
		var piv = Node3D.new()
		piv.position = Vector3(0, 0.01, 0.12 - k * 0.24) * BLIMP_L
		root.add_child(piv)
		var cone = MeshInstance3D.new()
		var cy = CylinderMesh.new()
		cy.top_radius = 0.25
		cy.bottom_radius = 7.0
		cy.height = 70.0
		cy.radial_segments = 16
		cy.rings = 1
		cy.cap_top = false
		cy.cap_bottom = false
		cone.mesh = cy
		var bm = _shader_mat(BEAM_CODE)
		bm.set_shader_parameter("c", _v3(Color(0.9, 0.8, 0.6) if _noir() else Color(0.6, 0.8, 1.0)))
		cone.material_override = bm
		cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cone.position = Vector3(0, -35.0, 0)
		piv.add_child(cone)
		beams.append(piv)
	# Bahn: Ellipse um die Mitte der Strecke
	var lo = Vector3(1e9, 1e9, 1e9)
	var hi = -lo
	for i in range(0, 700, 20):
		var c: Vector3 = T.frame(20.0 + i).c
		lo = Vector3(minf(lo.x, c.x), minf(lo.y, c.y), minf(lo.z, c.z))
		hi = Vector3(maxf(hi.x, c.x), maxf(hi.y, c.y), maxf(hi.z, c.z))
	blimp = {"bz": T.ZST + 230.0, "n": root, "c": (lo + hi) * 0.5, "rx": maxf(115.0, (hi.x - lo.x) * 0.7), "rz": maxf(115.0, (hi.z - lo.z) * 0.55),
		"y": hi.y + 36.0, "a": randf() * TAU, "signs": signs, "blinks": blinks, "beams": beams, "t": 0.0}


func _blimp_live(dt: float) -> void:
	if blimp.is_empty():
		return
	blimp.t += dt
	blimp.a += dt * 0.012
	var a: float = blimp.a
	var rx: float = blimp.rx
	var rz: float = blimp.rz
	var c: Vector3 = blimp.c
	# zieht tief und langsam die Strecke entlang, mal links, mal rechts daneben, ab und zu genau über der Fahrbahn
	blimp.bz = wrapf(float(blimp.bz) + dt * 3.0, 20.0, 20.0 + T.LAP)
	var bz: float = blimp.bz
	var fb = T.frame(bz)
	var latb = sin(blimp.t * 0.045 + 0.8) * 8.0
	var p: Vector3 = fb.c + fb.rr * latb + Vector3.UP * (13.0 + sin(blimp.t * 0.13) * 1.5) + Vector3(0, 0, blimp_off)
	var tg: Vector3 = (fb.fw * Vector3(1, 0, 1)).normalized()
	if tg.length() < 0.5:
		tg = Vector3.FORWARD
	var n: Node3D = blimp.n
	n.global_transform = Transform3D(Basis.looking_at(-tg, Vector3.UP).rotated(tg, sin(blimp.t * 0.21) * 0.03), p)
	var t: float = blimp.t
	var bl: Array = blimp.blinks
	for i in range(bl.size()):
		(bl[i] as Node3D).visible = fmod(t + i * 0.37, 1.6) < 0.12
	for sg in blimp.signs:
		var l: Label3D = sg[0]
		var col: Color = sg[1]
		var fk = 1.0 if fmod(t * 0.7 + float(l.text.length()), 9.0) > 0.25 else 0.3   # ab und zu kurz flackern
		l.modulate = Color(col.r * 0.5 + 0.5, col.g * 0.5 + 0.5, col.b * 0.5 + 0.5) * 2.0 * fk
	var bm: Array = blimp.beams
	for i in range(bm.size()):
		(bm[i] as Node3D).rotation = Vector3(sin(t * 0.31 + i * 2.0) * 0.45, 0.0, cos(t * 0.23 + i * 1.3) * 0.4)


# ---------------------------------------------------------------- Siegerfeier am Ziel
# Dein Schiff steht an der Ziellinie, daneben zwei Rivalen-Schiffe quer, Ren mit Helm, Mechanikerinnen, Fans;
# Konfettikanonen, Jubel, Kamera kreist langsam um Ren. Die Figuren sind Tripo-Modelle mit Mixamo-Bewegungen.
const PARTY_T = 10.0
const PARTY_Z = 34.0   # Lage hinter der Ziellinie (in der Runde)
var party = {}
var party_on = false
var party_cache = {}


const BLOB_CODE = """
shader_type spatial;
render_mode unshaded,blend_mix,depth_draw_never,cull_disabled,shadows_disabled;
uniform float a=.5;
void fragment(){float d=length(UV-.5)*2.;ALBEDO=vec3(0.);ALPHA=a*pow(clamp(1.-d,0.,1.),1.6);}
"""
var blob_mat: ShaderMaterial = null
# Schlagschatten in Figurform: die Figur wird (mitsamt Animation) flach auf die Fahrbahn projiziert und halbdunkel gezeichnet.
# Die Fahrbahn ist so dunkel und spiegelnd, dass echte Lichtschatten darauf kaum zu sehen waren.
const PSHADOW_CODE = """
shader_type spatial;
render_mode unshaded,blend_mix,depth_draw_always,cull_disabled,shadows_disabled,world_vertex_coords,fog_disabled;
uniform vec3 n=vec3(0.,1.,0.);uniform float d=0.;uniform vec3 L=vec3(.3,-1.,.2);uniform float a=.5;
varying float h;
void vertex(){
	float k=(dot(n,VERTEX)-d);
	h=k;
	VERTEX-=L*(k/dot(n,L));
	VERTEX+=n*.008;
}
void fragment(){ALBEDO=vec3(0.);ALPHA=a*clamp(1.-h*.35,.25,1.);}
"""


func _party_planar(m: MeshInstance3D) -> void:
	if not party.has("ld") or int(cfg.gfx) < 1:
		return
	var f = T.frame(float(party.z))
	var sm: MeshInstance3D = m.duplicate()
	var mat = _shader_mat(PSHADOW_CODE)
	mat.set_shader_parameter("n", f.uu)
	mat.set_shader_parameter("d", f.uu.dot(f.c))
	mat.set_shader_parameter("L", party.ld)
	mat.set_shader_parameter("a", 0.5)
	sm.material_override = mat
	sm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sm.sorting_offset = -1.0
	for c in sm.get_children():
		c.queue_free()
	m.add_sibling(sm)


# weicher dunkler Kontaktschatten unter einer Figur (flach auf der Fahrbahn)
func _party_blob(pos: Vector3, r: float) -> void:
	if blob_mat == null:
		blob_mat = _shader_mat(BLOB_CODE)
	var f = T.frame(float(party.z))
	var bm = MeshInstance3D.new()
	var pm = PlaneMesh.new()
	pm.size = Vector2(r * 2.0, r * 2.0)
	bm.mesh = pm
	bm.material_override = blob_mat
	bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	party.n.add_child(bm)
	bm.global_transform = Transform3D(Basis(f.rr, f.uu, -f.fw), pos + f.uu * 0.01)


func _party_fig(nm: String, anim: String, pos: Vector3, look: Vector3, tint: Color, sc: float, t0: float) -> Node3D:
	if not party_cache.has(nm):
		party_cache[nm] = load("res://win/%s.glb" % nm)
	var n: Node3D = (party_cache[nm] as PackedScene).instantiate()
	var root = Node3D.new()
	root.add_child(n)
	party.n.add_child(root)
	# Füße auf den Boden (Knöchel), Größe ≈ 1,8 m (= 0,45 Einheiten bei 6-m-Schiff)
	var sk: Skeleton3D = n.find_children("*", "Skeleton3D", true, false)[0]
	var dx: Transform3D = _rel_xf(n, sk)
	var lf = sk.find_bone("mixamorig_LeftFoot")
	var hd = sk.find_bone("mixamorig_Head")
	var hp = sk.find_bone("mixamorig_Hips")
	var fy = (dx * sk.get_bone_global_rest(lf).origin).y
	var hy = (dx * sk.get_bone_global_rest(hd).origin).y
	var hpp: Vector3 = dx * sk.get_bone_global_rest(hp).origin
	var hgt = maxf(0.05, (hy - fy) * 1.12)
	n.position = -Vector3(hpp.x, fy - 0.05 * hgt, hpp.z)
	if nm.begins_with("host"):
		# hohe Absätze: Fußspitze steht auf dem Boden (die Hülle des Modells ist zu groß und hob sie in die Luft)
		var tb = sk.find_bone("mixamorig_LeftToe_End")
		if tb < 0:
			tb = sk.find_bone("mixamorig_LeftToeBase")
		if tb >= 0:
			var ty = (dx * sk.get_bone_global_rest(tb).origin).y
			n.position.y = -(ty - 0.012 * hgt)
	var k = 0.45 * sc / hgt
	var dir: Vector3 = (look - pos) * Vector3(1, 0, 1)
	root.global_transform = Transform3D(Basis.looking_at(-dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD, Vector3.UP).scaled(Vector3.ONE * k), pos)
	_party_blob(pos, 0.34 * sc)
	# Schatten: echter Schatten vom Feier-Strahler (Form der Figur) + weicher Kontaktschatten unter den Füßen
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_party_planar(m)
		if OS.get_environment("FIGNOCULL") != "":
			var s0 = m.mesh.surface_get_material(0)
			if s0 is StandardMaterial3D:
				var m0 = (s0 as StandardMaterial3D).duplicate()
				m0.cull_mode = BaseMaterial3D.CULL_DISABLED
				m.material_override = m0
				continue
		if tint != Color(1, 1, 1):
			var src = m.mesh.surface_get_material(0)
			if src is StandardMaterial3D:
				var mm = (src as StandardMaterial3D).duplicate()
				mm.albedo_color = tint
				m.material_override = mm
	var pth = "res://win/%s_%s.res" % [nm, anim]
	if ResourceLoader.exists(pth):
		var ap = AnimationPlayer.new()
		n.add_child(ap)
		var lib = AnimationLibrary.new()
		lib.add_animation("a", load(pth))
		ap.add_animation_library("", lib)
		ap.play("a")
		ap.seek(t0, true)
		ap.speed_scale = randf_range(0.9, 1.1)
	return root


func _party_start() -> void:
	_bc("party start")
	_dg_flush()
	_party_end()
	party_on = true
	var g: Dictionary = ships[0]
	var lap = int(floor((g.z - 20.0) / T.LAP))
	var zl = T.ZST + PARTY_Z
	var zs = lap * T.LAP + zl
	if zs < g.z - 30.0:
		zs += T.LAP
	# Strecke und Deko an die Feier-Runde hängen, dein Schiff steht dort
	if deco != null:
		deco.position = Vector3(0, 0, zs - zl)
	_lap_pos(zs)
	g.z = zs
	g.lat = 0.0
	g.psi = 0.0
	g.vpsi = 0.0
	g.roll = 0.0
	g.h = 0.0
	g.boost = 0.0
	g.spd = 0.0
	var root = Node3D.new()
	add_child(root)
	party = {"n": root, "z": zs, "conf": [], "ct": 0.0, "a0": randf() * TAU}
	var f = T.frame(zs)
	var B = Basis(-f.rr, f.uu, f.fw)
	# Licht für die Schlagschatten: schräg von oben, von der Kameraseite und leicht von vorn – Schatten fallen nach hinten rechts
	party.ld = -(f.uu * 6.5 - f.rr * 2.6 + f.fw * 1.4).normalized()
	var at = func(dz: float, lat: float) -> Vector3:
		var ff = T.frame(zs + dz)
		return ff.c + ff.rr * lat
	# zwei Rivalen-Schiffe quer abgestellt
	var parked = [[2.3, 1.45, 1.15], [-2.1, 1.55, -1.95]]
	for k in range(parked.size()):
		var pk: Array = parked[k]
		var idx = (int(g.get("sm", 0)) + 1 + k) % SHIPS.size()
		var sn = _ship_node(idx)
		party.get_or_add("parked", []).append(sn)
		sn.reparent(root, false)   # _ship_node hängt es schon an die Szene – zur Feier umhängen, damit es mit ihr verschwindet
		var pp: Vector3 = at.call(pk[0], pk[1])
		sn.global_transform = Transform3D(B.rotated(f.uu, float(pk[2])), pp + f.uu * 0.04)
		# abgestellt: nur der Rumpf – Düsen, Strahlen, Ringe und Lichter aus
		for ci in range(1, sn.get_child_count()):
			var cn = sn.get_child(ci)
			if cn is Node3D:
				(cn as Node3D).visible = false
	# Ren mit Helm neben seinem Schiff, schaut zur Kamera-Seite
	var rp: Vector3 = at.call(0.25, -0.6)
	party.ren = _party_fig("ren", "victory_idle", rp, rp - f.rr * 2.0 + f.fw * 0.4, Color(1, 1, 1), 1.0, 0.0)
	# Ren jubelt einmal (Sprung), dann winkt er
	var rap: Array = (party.ren as Node3D).find_children("*", "AnimationPlayer", true, false)
	var ren_next = "res://win/ren_dance.res"
	if not rap.is_empty() and ResourceLoader.exists(ren_next):
		var ap: AnimationPlayer = rap[0]
		var lib: AnimationLibrary = ap.get_animation_library("")
		var a1: Animation = (lib.get_animation("a") as Animation).duplicate()
		a1.loop_mode = Animation.LOOP_NONE
		lib.remove_animation("a")
		lib.add_animation("a", a1)
		var a2: Animation = (load(ren_next) as Animation).duplicate()
		a2.loop_mode = Animation.LOOP_LINEAR
		lib.add_animation("w", a2)
		ap.speed_scale = 1.0
		ap.playback_default_blend_time = 0.35
		ap.play("a")
		ap.queue("w")
	# (kein Helm mehr in der Hand – er trägt jetzt den Siegerkranz)
	party.c = rp
	# zwei Hostessen links und rechts von Ren, Siegerkranz um seinen Hals, Champagner neben dem Schiff
	for hs in [["host1", 0.33], ["host2", -0.31]]:
		if ResourceLoader.exists("res://win/%s.glb" % hs[0]):
			var hp: Vector3 = at.call(0.25 + float(hs[1]), -0.52)
			var hn = _party_fig(hs[0], "idle", hp, hp - f.rr * 2.0 + f.fw * (0.3 - float(hs[1])), Color(1, 1, 1), 0.96, randf() * 2.0)
			party.get_or_add("hosts", []).append(hn)
	if ResourceLoader.exists("res://win/wreath.glb"):
		var wr: Node3D = load("res://win/wreath.glb").instantiate()
		root.add_child(wr)
		for mi in wr.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		party.wreath = wr
	if ResourceLoader.exists("res://win/bottle.glb"):
		var bt: Node3D = load("res://win/bottle.glb").instantiate()
		root.add_child(bt)
		var bp: Vector3 = at.call(-0.45, -0.42)
		bt.global_transform = Transform3D(B.rotated(f.uu, 0.6).scaled(Vector3.ONE * (0.11 / 98.0)), bp)
		var bl = OmniLight3D.new()
		bl.light_color = Color(1.0, 0.75, 0.4)
		bl.light_energy = 0.8
		bl.omni_range = 0.6
		root.add_child(bl)
		bl.global_position = bp + f.uu * 0.12 - f.rr * 0.15
	# leuchtende Pylonen und ein paar Fässer am Rand der Feier
	if prop_res.has("c") and prop_res.has("b"):
		for pp in [["c", 2.9, -1.3, 0.0], ["c", 2.6, -1.9, 0.0], ["c", -2.7, -1.5, 0.0], ["c", -3.1, -0.9, 1.4], ["b", 3.3, 1.9, 0.0], ["b", -3.2, 2.2, 0.0], ["b", -3.5, 1.6, 1.57], ["c", 1.2, -2.0, 0.0]]:
			var pn: Node3D = (prop_res[pp[0]] as PackedScene).instantiate()
			root.add_child(pn)
			var hgt = 0.6 if pp[0] == "b" else 0.45
			var wid = 0.4 / (0.65 if pp[0] == "b" else 0.69)
			var tb: Basis = B.rotated(f.uu, randf() * TAU)
			var lift = 0.0
			if float(pp[3]) > 0.0:
				tb = tb.rotated(tb.z.normalized(), float(pp[3]))   # umgekippt
				lift = 0.2
			pn.global_transform = Transform3D(tb * Basis().scaled(Vector3(wid, hgt, wid)), at.call(float(pp[1]), float(pp[2])) + f.uu * lift)
			if pp[0] == "c":
				var gl = OmniLight3D.new()
				gl.light_color = Color(1.0, 0.5, 0.1)
				gl.light_energy = 1.4
				gl.omni_range = 1.4
				root.add_child(gl)
				gl.global_position = pn.global_position + f.uu * 0.3
	# Überspringen
	var sl = CanvasLayer.new()
	sl.layer = 8
	root.add_child(sl)
	var sb = _skip_btn()
	sb.pressed.connect(func(): fin.skip = true)
	sl.add_child(sb)
	# Mechanikerinnen am Schiff, Fans im Halbkreis
	# Kamera steht links (−lat) und schaut nach rechts: Ren vorn, dahinter Schiff, Team und Fans
	# Team und Fans dicht um Ren und das Schiff (rechts davon, zwischen den abgestellten Rivalen) – niemand allein am Streckenrand
	var people = [
		["mech", "waving", 1.05, 0.65, Color(1, 1, 1)], ["mech", "clapping", -1.0, 0.7, Color(0.85, 0.9, 1.0)], ["mech", "cheering", -0.9, -0.85, Color(1.0, 0.92, 0.85)],
		["fan1", "cheering", 0.15, 0.95, Color(1, 1, 1)], ["fan2", "rallying", 0.8, 1.25, Color(1, 1, 1)], ["fan1", "standing_cheering", -0.55, 1.25, Color(0.85, 0.8, 1.0)],
		["fan2", "cheering", 1.5, 1.0, Color(1.0, 0.85, 0.85)], ["fan1", "clapping", -1.5, 1.05, Color(0.8, 1.0, 0.9)], ["fan2", "waving", 0.35, 1.55, Color(0.9, 0.9, 1.0)],
		["fan1", "rallying", -1.1, 1.5, Color(1.0, 1.0, 0.8)], ["fan2", "standing_cheering", 1.25, 1.55, Color(0.85, 1.0, 1.0)], ["fan2", "clapping", -0.2, 1.6, Color(1, 1, 1)]]
	for pe in people:
		var pp2: Vector3 = at.call(float(pe[2]) + randf_range(-0.08, 0.08), float(pe[3]) + randf_range(-0.06, 0.06))
		_party_fig(pe[0], pe[1], pp2, rp, pe[4], randf_range(0.93, 1.05), randf() * 3.0)
	# Licht auf die Szene (es ist Nacht)
	# (nicht direkt über den abgestellten Schiffen, sonst strahlen deren Rümpfe weiß aus)
	for lp in [[0.0, -1.6, Color(1.0, 0.85, 0.7), 1.7], [0.9, 1.9, Color(1.0, 0.6, 0.8), 2.6], [-0.9, 1.9, Color(0.5, 0.8, 1.0), 2.6]]:
		var l = OmniLight3D.new()
		l.light_color = lp[2]
		l.light_energy = lp[3]
		l.omni_range = 5.5
		root.add_child(l)
		l.global_position = at.call(float(lp[0]), float(lp[1])) + f.uu * 1.4
	# Düsenstrahlen deines Schiffs aus (blenden sonst die Kamera)
	var gn: Node3D = g.node
	for pj in gn.get_meta("pj", []):
		(pj[0] as Node3D).visible = false
	# alle Renn-Schiffe der Gegner ausblenden (sie fahren sonst durch die Feier)
	for i in range(1, ships.size()):
		(ships[i].node as Node3D).visible = false
	party.cannons = [at.call(-1.9, 2.1), at.call(2.4, 2.1), at.call(0.3, 2.3)]
	# Nass-Spiegelung kopiert das Bild in festen Bildschirmschritten nach unten – bei Nahaufnahmen sieht man unter
	# Rens Schuhen dann 2–3 Kopien. Während der Feier deshalb fast aus.
	if road_wet != null:
		_sp(road_wet, "wk", float(fx.env.wet) * 0.15)
	_snd("crowd_roar", 0.0)
	_stadium("an_wow", 0.0)
	hud.layer.visible = false


func _party_end() -> void:
	if party.is_empty():
		party_on = false
		return
	if is_instance_valid(party.n):
		_qf(party.n)
	for c in party.conf:
		if is_instance_valid(c):
			_qf(c)
	party = {}
	party_on = false
	_wet_apply()
	if not ships.is_empty():
		for pj in (ships[0].node as Node3D).get_meta("pj", []):
			(pj[0] as Node3D).visible = true


# Konfetti: bunte Papierschnipsel, wirbeln und fallen langsam
var conf_mesh: QuadMesh = null


func _confetti(pos: Vector3) -> void:
	if conf_mesh == null:
		conf_mesh = QuadMesh.new()
		conf_mesh.size = Vector2(0.014, 0.009)
		var m = StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		conf_mesh.material = m
	var p = GPUParticles3D.new()
	var pm = ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 18.0
	pm.initial_velocity_min = 4.0
	pm.initial_velocity_max = 7.0
	pm.gravity = Vector3(0, -3.2, 0)
	pm.damping_min = 1.0
	pm.damping_max = 1.6
	pm.angular_velocity_min = -540.0
	pm.angular_velocity_max = 540.0
	pm.particle_flag_rotate_y = true
	pm.particle_flag_disable_z = false
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 1.5
	var gr = Gradient.new()
	gr.offsets = PackedFloat32Array([0.0, 0.2, 0.4, 0.6, 0.8, 1.0])
	gr.colors = PackedColorArray([Color(1, 0.2, 0.3), Color(1, 0.85, 0.2), Color(0.2, 0.9, 1.0), Color(1, 0.3, 0.85), Color(0.4, 1, 0.5), Color(1, 1, 1)])
	var gt = GradientTexture1D.new()
	gt.gradient = gr
	pm.color_initial_ramp = gt
	p.process_material = pm
	p.draw_pass_1 = conf_mesh
	p.amount = 260
	p.lifetime = 4.0
	p.one_shot = true
	p.explosiveness = 0.92
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-12, -12, -12), Vector3(24, 24, 24))
	add_child(p)
	p.global_position = pos
	p.emitting = true
	party.conf.append(p)
	get_tree().create_timer(5.6).timeout.connect(p.queue_free)
	_snd("confetti", -2.0, randf_range(0.92, 1.08), pos)


func _party_live(dt: float) -> bool:
	if party.is_empty():
		return false
	var t: float = fin.get("pt", 0.0)
	# Hostessen nach dem ersten Bild mit Bewegung auf den Boden stellen (tiefster Fußknochen + Sohle)
	if t > 0.25 and not party.has("grounded"):
		party.grounded = true
		var fz0 = T.frame(float(party.z))
		for hn in party.get("hosts", []):
			if not is_instance_valid(hn):
				continue
			var skl: Array = (hn as Node3D).find_children("*", "Skeleton3D", true, false)
			if skl.is_empty():
				continue
			var skf: Skeleton3D = skl[0]
			var lo = 1e9
			for bn in ["mixamorig_LeftToe_End", "mixamorig_LeftToeBase", "mixamorig_LeftFoot", "mixamorig_RightToe_End", "mixamorig_RightToeBase", "mixamorig_RightFoot"]:
				var bi = skf.find_bone(bn)
				if bi >= 0:
					lo = minf(lo, (skf.global_transform * skf.get_bone_global_pose(bi).origin).y)
			if lo < 1e8:
				(hn as Node3D).global_position -= Vector3.UP * (lo - fz0.c.y - 0.004)
	if party.has("wreath") and is_instance_valid(party.wreath) and is_instance_valid(party.ren):
		var rn: Node3D = party.ren
		var sks: Array = rn.find_children("*", "Skeleton3D", true, false)
		if not sks.is_empty():
			var sk: Skeleton3D = sks[0]
			var nb = sk.find_bone("mixamorig_Neck")
			var cb = sk.find_bone("mixamorig_Spine2")
			if nb >= 0 and cb >= 0:
				# einmal in der Grundhaltung ausrichten (vor der Brust, Öffnung um den Hals), danach fest an der Brust
				# mitführen – so bleibt er auch beim Vorbeugen am Oberkörper und rutscht nicht übers Gesicht
				if not party.has("wofs"):
					var gr: Transform3D = sk.global_transform * sk.get_bone_global_rest(cb)
					var np0: Vector3 = sk.global_transform * sk.get_bone_global_rest(nb).origin
					var rb0: Basis = rn.global_transform.basis.orthonormalized()
					var up0: Vector3 = (np0 - gr.origin).normalized()
					var fw0: Vector3 = (rb0.z - up0 * rb0.z.dot(up0)).normalized()
					var wb0 = Basis(up0.cross(fw0).normalized(), up0, fw0)
					# Kranz-Modell: geschlossener Ring (97 breit, 71 tief), hinten hoch (y 66, z −35), vorn tief auf der Brust.
					# Breite nach dem Schulterabstand (die Jacke hat dicke Schulterpolster, darum etwas breiter); hinten liegt er im Nacken
					# außen am Kragen, vorn auf der Brust – vorher war er so klein, dass er im Oberkörper steckte.
					var la = sk.find_bone("mixamorig_LeftArm")
					var ra = sk.find_bone("mixamorig_RightArm")
					var dsh = (sk.global_transform * sk.get_bone_global_rest(la).origin).distance_to(sk.global_transform * sk.get_bone_global_rest(ra).origin)
					var wsc = dsh * float(OS.get_environment("WRS") if OS.get_environment("WRS") != "" else "1.3") / 97.0
					# zusätzlich nach vorn kippen: vorn hängt er tiefer auf der Brust, hinten liegt er im Nacken
					var wtl = deg_to_rad(float(OS.get_environment("WRT") if OS.get_environment("WRT") != "" else "-8"))
					var wbs: Basis = (Basis(wb0.x, wtl) * wb0).scaled(Vector3.ONE * wsc)
					var back: Vector3 = np0 - up0 * dsh * float(OS.get_environment("WRD") if OS.get_environment("WRD") != "" else "0.0") - fw0 * dsh * float(OS.get_environment("WRB") if OS.get_environment("WRB") != "" else "0.3")
					var want = Transform3D(wbs, back - wbs * Vector3(0, 66, -35))
					party.wofs = gr.affine_inverse() * want
					if OS.get_environment("WRDBG") != "":
						for lp in [Vector3(0, 66, -35), Vector3(0, 0, 35), Vector3(48, 33, 0), Vector3(0, 33, 0)]:
							var wp: Vector3 = want * lp
							print("WRDBG ", lp, " up=", snappedf((wp - np0).dot(up0) / dsh, 0.01), " fw=", snappedf((wp - np0).dot(fw0) / dsh, 0.01), " side=", snappedf((wp - np0).dot(wb0.x) / dsh, 0.01))
						var tf: Vector3 = sk.global_transform * sk.get_bone_global_rest(sk.find_bone("mixamorig_LeftToe_End")).origin - sk.global_transform * sk.get_bone_global_rest(sk.find_bone("mixamorig_LeftFoot")).origin
						print("WRDBG toe·fw0=", snappedf(tf.normalized().dot(fw0), 0.01))
						print("WRDBG head up=", snappedf((sk.global_transform * sk.get_bone_global_rest(sk.find_bone("mixamorig_Head")).origin - np0).dot(up0) / dsh, 0.01), " spine2 up=", snappedf((gr.origin - np0).dot(up0) / dsh, 0.01), " ren fwd vs rr ", rb0.z)
				var gp: Transform3D = sk.global_transform * sk.get_bone_global_pose(cb)
				(party.wreath as Node3D).global_transform = gp * (party.wofs as Transform3D)
				if OS.get_environment("WRDBG") != "" and not party.has("wrp"):
					party.wrp = 1
					for mi in (party.wreath as Node).find_children("*", "MeshInstance3D", true, false):
						var ab: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
						var npn: Vector3 = sk.global_transform * sk.get_bone_global_pose(nb).origin
						print("WRDBG live aabb center-neck=", ab.get_center() - npn, " size=", ab.size, " vis=", (mi as MeshInstance3D).is_visible_in_tree(), " ren pos-neck=", rn.global_position - npn)
	# Konfettikanonen: zuerst alle drei, dann immer wieder einzeln
	party.ct = float(party.ct) - dt
	if party.ct <= 0.0:
		var cs: Array = party.cannons
		if t < 0.3:
			for c in cs:
				_confetti(c)
		else:
			_confetti(cs[randi() % cs.size()])
		party.ct = randf_range(1.4, 2.4)
	# Kamera in drei Einstellungen: Nahaufnahme von Ren beim Jubelsprung, schnelle Fahrt an den Fans vorbei,
	# dann langsamer Kreis um Ren mit Leuten und Schiffen im Bild
	var c: Vector3 = party.c
	var f = T.frame(float(party.z))
	var zs = float(party.z)
	if t < 2.1:
		var u = t / 2.1
		var d = lerpf(0.95, 0.62, u * (2.0 - u))
		cam.global_position = c - f.rr * d + f.fw * (0.2 - 0.1 * u) + f.uu * (0.36 - 0.04 * u)
		cam.look_at(c + f.uu * (0.34 - 0.02 * u) + f.fw * 0.03, Vector3.UP)
		cam.fov = 42.0
	elif t < 4.7:
		var u = (t - 2.1) / 2.6
		var e = u * u * (3.0 - 2.0 * u) * 0.6 + u * 0.4
		var dz = lerpf(-1.7, 1.5, e)
		var ff = T.frame(zs + dz)
		cam.global_position = ff.c + ff.rr * 0.35 + ff.uu * (0.5 + 0.05 * sin(u * PI))
		cam.look_at(cam.global_position + ff.fw * 1.0 + ff.rr * 0.75 - ff.uu * 0.2, Vector3.UP)
		cam.fov = 52.0
	else:
		var t2 = t - 4.7
		var a: float = -0.75 + t2 * 0.14
		var R = 2.3 - 0.5 * clampf(t2 / (PARTY_T - 4.7), 0.0, 1.0)
		cam.global_position = c + (-f.rr * cos(a) + f.fw * sin(a)) * R + f.uu * (0.8 + 0.12 * sin(t2 * 0.4))
		cam.look_at(c + f.rr * 0.7 + f.uu * 0.25, Vector3.UP)
		cam.fov = 55.0
	if OS.get_environment("PARTYTOP") != "":
		cam.global_position = c + f.uu * 7.0 + f.rr * 0.5
		cam.look_at(c + f.rr * 0.5, f.fw)
		cam.fov = 60.0
		if not party.has("tdbg"):
			party.tdbg = 1
			var fz0 = T.frame(float(party.z))
			for lt in [-2.4, -1.2, 0.0, 1.2, 2.4]:
				print("PTOP edge lat_abs=", lt, " px=", cam.unproject_position(fz0.c + fz0.rr * lt), " vp=", get_viewport().get_visible_rect().size)
			for ch in (party.n as Node3D).get_children():
				if ch is Node3D and ch.get_child_count() > 0:
					var gp: Vector3 = (ch as Node3D).global_position
					print("PTOP ", ch.get_child(0).name, " px=", cam.unproject_position(gp), " lat=", snappedf((gp - c).dot(f.rr), 0.01), " dz=", snappedf((gp - c).dot(f.fw), 0.01))
	if OS.get_environment("RENFACE") != "" and party.has("ren") and is_instance_valid(party.ren):
		# nur zum Testen: Nahaufnahme von Rens Gesicht (Kopf-Knochen), Abstand aus RENFACE
		var rsk: Skeleton3D = (party.ren as Node).find_children("*", "Skeleton3D", true, false)[0]
		var hb = rsk.find_bone("Head")
		if hb < 0:
			for bi in rsk.get_bone_count():
				if rsk.get_bone_name(bi).to_lower().contains("head"):
					hb = bi
					break
		if not has_meta("rfp"):
			set_meta("rfp", 1)
			print("RENFACE bone=", hb, " ", rsk.get_bone_name(maxi(hb, 0)), " names=", Array(range(mini(rsk.get_bone_count(), 70))).map(func(i): return rsk.get_bone_name(i)))
		var hp: Vector3 = rsk.global_transform * rsk.get_bone_global_pose(hb).origin
		var hg: Transform3D = rsk.global_transform * rsk.get_bone_global_pose(hb)
		var rfa = OS.get_environment("RENFACE").split(",")
		var ang = deg_to_rad(float(rfa[1])) if rfa.size() > 1 else 0.0
		var fdir: Vector3 = (-f.rr * cos(ang) + f.fw * sin(ang)).normalized()
		cam.global_position = hp + fdir * float(rfa[0]) + f.uu * 0.02
		cam.look_at(hp + f.uu * 0.07 - f.uu * float(rfa[2] if rfa.size() > 2 else "0"), Vector3.UP)
		cam.fov = 35.0
		return true
	if OS.get_environment("PARTYCAM") != "":
		cam.global_position = c - f.rr * 1.1 + f.fw * 0.05 + f.uu * 0.25
		cam.look_at(c + f.uu * 0.3, Vector3.UP)
		cam.fov = 40.0
	return true


# ---------------------------------------------------------------- Hindernisse: Fässer und Leitkegel auf der Strecke
# Liegen in Gruppen auf der Fahrbahn; wer sie anfährt, kickt sie weg (2 % Energie, 2 % Tempo). Die Strecke ist von einem
# unsichtbaren Schutzschild (Röhre) umgeben: Teile prallen davon ab – an der Stelle blitzt der Schild kurz auf.
const PROP_SPOTS = [[130.0, 0.9, "b"], [132.0, 1.4, "b"], [131.0, 0.3, "c"], [275.0, -1.2, "c"], [277.0, -0.7, "c"], [279.0, -1.5, "b"],
	[360.0, 1.3, "b"], [361.5, 1.7, "b"], [362.0, 0.9, "c"], [420.0, -0.4, "c"], [421.0, 0.1, "c"], [422.0, 0.6, "c"],
	[485.0, 1.6, "b"], [486.0, 1.1, "c"], [620.0, -1.4, "b"], [621.5, -1.0, "b"], [622.0, -1.8, "c"], [668.0, 0.6, "c"], [669.5, 1.1, "b"],
	[95.0, -1.0, "c"], [96.5, -0.5, "c"], [98.0, 0.0, "c"], [150.0, 1.5, "b"], [151.5, 0.9, "b"], [255.0, -1.6, "b"], [256.0, -1.0, "c"],
	[290.0, 0.2, "b"], [312.0, -0.6, "c"], [313.5, 0.0, "c"], [315.0, 0.6, "c"], [338.0, 1.7, "b"], [398.0, -1.4, "b"], [399.5, -0.8, "c"],
	[452.0, 0.4, "c"], [453.0, 0.9, "b"], [470.0, -1.2, "c"], [471.5, -0.6, "b"], [500.0, 1.3, "b"], [600.0, -0.2, "c"], [601.0, 0.4, "c"], [646.0, -1.5, "b"]]
const SHIELD_H = 2.6   # Höhe der Schutzröhre über der Fahrbahn
var props = []
var props0 = []
var prop_res = {}
var shield_hits = []


func _props_make() -> void:
	props.clear()
	props0.clear()
	if _jungle() or T.S:
		return
	for k in ["b", "c"]:
		var pth = "res://city/%s.glb" % ("barrel" if k == "b" else "cone")
		if not ResourceLoader.exists(pth):
			return
		prop_res[k] = load(pth)
	for sp in PROP_SPOTS:
		if T.in_tun(sp[0], 3.0):
			continue
		var k: String = sp[2]
		var n: Node3D = (prop_res[k] as PackedScene).instantiate()
		# Fass: Ø ≈ halbe Schiffsbreite (0,4), entsprechend hoch (0,6); Kegel: gleiche Grundfläche, 75 % der Fasshöhe
		var hgt = 0.6 if k == "b" else 0.45
		var wid = 0.4 / (0.65 if k == "b" else 0.69)   # Modelle: Fass Ø 0,65, Kegel Ø 0,69, beide 1,0 hoch
		n.scale = Vector3(wid, hgt, wid)
		var root = Node3D.new()
		root.add_child(n)
		add_child(root)
		root.set_meta("keep", true)   # NICHT „rfx“: das räumt der Neustart weg (gelöschte Knoten → Absturz)
		if k == "c":
			# Leuchtstreifen am Kegel: oranges Glimmen
			var gl = OmniLight3D.new()
			gl.light_color = Color(1.0, 0.5, 0.1)
			gl.light_energy = 1.2
			gl.omni_range = 1.2
			gl.position = Vector3(0, hgt * 0.7, 0)
			root.add_child(gl)
			for mi in n.find_children("*", "MeshInstance3D", true, false):
				var src = (mi as MeshInstance3D).mesh.surface_get_material(0)
				if src is StandardMaterial3D:
					var mm = (src as StandardMaterial3D).duplicate()
					mm.emission_enabled = true
					mm.emission_texture = mm.albedo_texture
					mm.emission = Color(1.0, 0.55, 0.15)
					mm.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
					mm.emission_energy_multiplier = 0.9
					(mi as MeshInstance3D).material_override = mm
		var d = {"n": root, "k": k, "z": float(sp[0]), "lat": float(sp[1]), "h": 0.0, "vz": 0.0, "vl": 0.0, "vh": 0.0,
			"rb": Basis(Vector3.UP, randf() * TAU), "av": Vector3.ZERO, "r": 0.2, "hg": hgt, "kt": 0.0, "rest": true}
		props.append(d)
		props0.append(d.duplicate())


func _props_reset() -> void:
	for i in range(props.size()):
		var n = props[i].n
		props[i] = props0[i].duplicate()
		props[i].n = n


func _props_update(dt: float) -> void:
	if props.is_empty() or ships.is_empty():
		return
	var gz: float = ships[0].z
	var lap0 = floor((gz - 20.0) / T.LAP) * T.LAP
	for d in props:
		if not is_instance_valid(d.n):
			continue
		var nd: Node3D = d.n
		if not d.rest:
			d.vh -= 14.0 * dt
			d.z = wrapf(float(d.z) + d.vz * dt, 20.0, 20.0 + T.LAP)
			d.lat += d.vl * dt
			d.h += d.vh * dt
			var r: float = d.r
			if d.h <= 0.0:
				d.h = 0.0
				if d.vh < -1.5:
					d.vh = -d.vh * 0.35
					d.av = (d.av as Vector3) * 0.6
				else:
					d.vh = 0.0
				d.vz *= exp(-1.1 * dt)
				d.vl *= exp(-2.2 * dt)
				var av: Vector3 = d.av
				d.av = Vector3(av.x * exp(-4.0 * dt), av.y * exp(-2.0 * dt), av.z * exp(-4.0 * dt))
				# auf dem Boden: kommt stehend oder liegend zur Ruhe (nicht schräg in der Luft hängend)
				if (d.av as Vector3).length() < 2.5:
					var rb: Basis = d.rb
					var upv: Vector3 = rb.y.normalized()
					var tgt: Vector3 = Vector3(0, signf(upv.y), 0) if absf(upv.y) > 0.6 else Vector3(upv.x, 0.0, upv.z).normalized()
					if tgt.length() > 0.5 and upv.dot(tgt) < 0.9999:
						var ax: Vector3 = upv.cross(tgt)
						if ax.length() > 1e-4:
							d.rb = (Basis(ax.normalized(), upv.angle_to(tgt) * minf(1.0, dt * 6.0)) * rb).orthonormalized()
				if absf(d.vz) < 0.15 and absf(d.vl) < 0.15 and absf(d.vh) < 0.1 and (d.av as Vector3).length() < 0.4:
					d.rest = true
			# Schutzschild: seitlich und oben – abprallen, Schild blitzt auf
			var lim = T.TW + 0.35 - r
			if absf(d.lat) > lim:
				d.lat = signf(d.lat) * lim
				if absf(d.vl) > 0.8:
					_shield_flash(d, Vector3(signf(d.lat), 0.0, 0.0))
				d.vl = -d.vl * 0.55
			if d.h > SHIELD_H - r:
				d.h = SHIELD_H - r
				if d.vh > 0.8:
					_shield_flash(d, Vector3(0.0, 1.0, 0.0))
				d.vh = -d.vh * 0.5
			var av2: Vector3 = d.av
			if av2.length() > 0.01:
				d.rb = (Basis(av2.normalized(), av2.length() * dt) * (d.rb as Basis)).orthonormalized()
		# an der Runde des Spielers zeigen
		var zw = float(d.z) + lap0
		if zw < gz - T.LAP * 0.5:
			zw += T.LAP
		elif zw > gz + T.LAP * 0.5:
			zw -= T.LAP
		var f = T.frame(zw)
		var B = Basis(-f.rr, f.uu, f.fw)
		# umgekippt: um den halben Durchmesser anheben, sonst steckt es halb im Boden
		var tilt_up: float = absf((d.rb as Basis).y.normalized().y)
		var lift: float = float(d.r) * sqrt(maxf(0.0, 1.0 - tilt_up * tilt_up))
		nd.global_transform = Transform3D(B * (d.rb as Basis), f.c + f.rr * d.lat + f.uu * (d.h + 0.005 + lift))
		# Zusammenstoß mit Schiffen
		d.kt = maxf(0.0, float(d.kt) - dt)
		if d.kt > 0.0 or not (state == "race" or state == "done") or party_on:
			continue
		for o in ships:
			if o.out or o.air:
				continue
			var dz = wrapf(float(d.z) - wrapf(o.z, 20.0, 20.0 + T.LAP), -T.LAP * 0.5, T.LAP * 0.5)
			if absf(dz) < 0.75 + d.r and absf(d.lat - o.lat) < 0.3 + d.r and d.h < 0.5:
				d.kt = 0.35
				d.rest = false
				var sp = maxf(o.spd, 1.0)
				var away = signf(d.lat - o.lat) if absf(d.lat - o.lat) > 0.02 else (1.0 if randf() < 0.5 else -1.0)
				# wird zur Seite geschoben, kippt um und schlittert – bleibt im Bild statt davonzufliegen
				var light = 1.0 if d.k == "c" else 0.8
				# fast mit deinem Tempo mitgeschoben (sonst ist es sofort hinter der Kamera), dann bremst es langsam ab
				d.vz = sp * randf_range(0.82, 0.98)
				d.vl = away * randf_range(2.0, 3.6) * light + o.spd * sin(o.vpsi) * 0.6
				d.vh = randf_range(0.6, 1.4) * light
				d.av = Vector3(randf_range(-0.4, 0.4), randf_range(-1.0, 1.0), -away * randf_range(0.8, 1.2)).normalized() * randf_range(4.0, 8.0)
				o.spd *= 0.98
				if not _prot(o):
					_dmg(o, 0.02, -1, "ram")
				var pos: Vector3 = nd.global_position
				_snd("crash_bump", -10.0 if o.idx == 0 else -8.0, randf_range(1.2, 1.5) if d.k == "c" else randf_range(0.85, 1.05), null if o.idx == 0 else pos)
				if o.idx == 0:
					_vib(55 if d.k == "c" else 85, 0.55 if d.k == "c" else 0.8)
				if o.idx == 0:
					shake = maxf(shake, 0.25)
				break
	_shield_hits_update(dt)
	if OS.get_environment("PROPDBG") != "" and Engine.get_process_frames() % 10 == 0:
		var mv = []
		for d in props:
			if not d.rest or float(d.h) > 0.0:
				mv.append("%s z%.1f l%.2f h%.2f" % [d.k, d.z, d.lat, d.h])
		print("PROPS en=", snappedf(ships[0].en, 0.01), " ", mv, " hits=", shield_hits.size())


# Schutzschild leuchtet an der Aufprallstelle kurz auf (Sechseck-Raster, cyan), mit Schild-Klang
const SHIELD_CODE = """
shader_type spatial;
render_mode unshaded,blend_add,cull_disabled,depth_draw_never,shadows_disabled,fog_disabled;
uniform float a=1.;uniform vec3 c=vec3(.3,.9,1.);
vec2 hx(vec2 p){vec2 r=vec2(1.,1.732);vec2 h=r*.5;vec2 a1=mod(p,r)-h;vec2 b=mod(p-h,r)-h;return dot(a1,a1)<dot(b,b)?a1:b;}
void fragment(){
	vec2 q=UV-.5;float d=length(q)*2.;
	vec2 g=hx(q*9.);float e=smoothstep(.42,.5,max(abs(g.x)*1.5+abs(g.y)*.866,abs(g.y)*1.732));
	float ring=smoothstep(.15,0.,abs(d-(1.-a)*.9));
	ALBEDO=c*(e*.9+ring*1.6+.25)*smoothstep(1.,.2,d)*a;
}"""
var prop_shield_mat: ShaderMaterial = null


func _shield_flash(d: Dictionary, nrm: Vector3) -> void:
	if not is_instance_valid(d.n):
		return
	var gz: float = ships[0].z
	var lap0 = floor((gz - 20.0) / T.LAP) * T.LAP
	var zw = float(d.z) + lap0
	if zw < gz - T.LAP * 0.5:
		zw += T.LAP
	elif zw > gz + T.LAP * 0.5:
		zw -= T.LAP
	_shield_flash_at((d.n as Node3D).global_position, zw, nrm, float(d.r), 1.2, -8.0, randf_range(1.3, 1.6))


# Schild-Aufleuchten an einer Stelle: nrm.x = seitlich (Vorzeichen = Seite), nrm.y = oben
func _shield_flash_at(p: Vector3, zw: float, nrm: Vector3, off: float, size: float, vol: float, pitch: float, sn: String = "shield") -> void:
	if shield_hits.size() > 6 or not p.is_finite():
		return
	if prop_shield_mat == null:
		prop_shield_mat = _shader_mat(SHIELD_CODE)
	var f = T.frame(zw)
	var n: Vector3 = f.rr * nrm.x + f.uu * nrm.y
	if n.length_squared() < 0.01:
		return
	n = n.normalized()
	var up: Vector3 = f.fw if absf(nrm.y) > 0.5 else f.uu
	if absf(n.dot(up.normalized())) > 0.95:
		return
	var q = MeshInstance3D.new()
	var qm = QuadMesh.new()
	qm.size = Vector2(size, size)
	q.mesh = qm
	var m: ShaderMaterial = prop_shield_mat.duplicate()
	q.material_override = m
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	q.set_meta("rfx", true)
	add_child(q)
	var at: Vector3 = p + n * off
	q.global_transform = Transform3D(Basis.looking_at(n, up), at)
	shield_hits.append({"n": q, "m": m, "t": 0.0})
	_snd(sn, vol, pitch, null if sn == "phase" else at)


# Schiff prallt an der Schutzröhre ab
func _ship_shield_hit(s: Dictionary, nrm: Vector3) -> void:
	if race_t - float(s.get("shT", -9.0)) < 0.25:
		return
	s.shT = race_t
	s.slow = minf(s.slow, 0.8)
	s.boost *= 0.5
	if not _prot(s) and (state == "race"):
		_dmg(s, 0.03, -1, "ram")
	var is_p = s.idx == 0
	_shield_flash_at((s.node as Node3D).global_position, s.z, nrm, 0.45, 2.2, -1.0, randf_range(1.0, 1.15), "phase" if is_p else "shield")
	if is_p:
		shake = maxf(shake, 0.3)
		_flash(Color(0.4, 0.85, 1.0), 0.12)
		_vib(100, 0.85)


func _shield_hits_update(dt: float) -> void:
	for i in range(shield_hits.size() - 1, -1, -1):
		var h: Dictionary = shield_hits[i]
		h.t += dt
		var a = 1.0 - h.t / 0.55
		if a <= 0.0 or not is_instance_valid(h.n):
			if is_instance_valid(h.n):
				_qf(h.n)
			shield_hits.remove_at(i)
			continue
		(h.m as ShaderMaterial).set_shader_parameter("a", a)


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
	root.set_meta("mxf", m.transform)
	root.set_meta("flip", SHIPS[idx][2])
	root.set_meta("bb", AABB(Vector3(-bb.size.x * 0.5, 0.0, -bb.size.z * 0.5) * s, bb.size * s))
	_dmg_fx_build(root)
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
		if p.z < 0.0:
			# hintere Antigrav-Felder strahlen nach unten: echtes Licht, damit der nasse Asphalt den Schein spiegelt
			var gl = OmniLight3D.new()
			gl.light_color = Color(0.35, 0.9, 1.0)
			gl.light_energy = 5.0
			gl.light_specular = 2.0
			gl.omni_range = 1.9
			gl.omni_attenuation = 1.4
			gl.shadow_enabled = false
			gl.position = Vector3(p.x, -0.06, p.z)
			root.add_child(gl)
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
uniform sampler2D sc : hint_screen_texture, filter_linear_mipmap;
void fragment(){
	vec2 uv=SCREEN_UV;
	// Aufnahme-Look: Farben fast raus, leicht kalt-blau, Bildzeilen, rollender Streifen, dunkle Ecken, roter Rahmen
	vec3 c=texture(sc,uv).rgb;
	float l=dot(c,vec3(.3,.59,.11));
	// Schwarzweiß – nur Feuer und Explosionen (hell, kräftig, warm) bleiben bunt
	float mx=max(c.r,max(c.g,c.b));float mn=min(c.r,min(c.g,c.b));
	float sat=(mx-mn)/(mx+.001);
	float keep=smoothstep(.35,.75,mx)*smoothstep(.2,.55,sat)*smoothstep(.05,.3,c.r-c.b);
	c=mix(vec3(l)*vec3(.92,.97,1.05),c*1.15,keep)*1.06;
	float line=step(.5,fract(FRAGCOORD.y*.25))*.12;
	float vig=smoothstep(.45,.95,length((uv-.5)*vec2(.8,1.)));
	float roll=exp(-pow(abs((fract(uv.y-TIME*.12)-.5)*40.),2.))*.07;
	c=c*(1.-line)*(1.-vig*.6)+roll;
	vec2 px=uv/SCREEN_PIXEL_SIZE;vec2 rs=1./SCREEN_PIXEL_SIZE;
	float e=min(min(px.x,rs.x-px.x),min(px.y,rs.y-px.y));
	float br=step(e,10.)*(.6+.4*step(.5,fract(TIME*.8)));
	c=mix(c,vec3(1.,.1,.08),br);
	COLOR=vec4(c,1.);
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
	t3.offset_top = -255
	t3.modulate = Color(1, 1, 1, 0.85)
	cl.add_child(t3)
	kco.ts = t3
	# großes „REPLAY“ unten, damit man nie denkt, es sei das laufende Rennen
	var t5 = _lbl("◀◀  REPLAY", 44)
	t5.anchor_right = 1.0
	t5.anchor_top = 1.0
	t5.anchor_bottom = 1.0
	t5.offset_top = -350
	t5.modulate = Color(1.0, 0.3, 0.25, 0.95)
	cl.add_child(t5)
	kco.rp = t5
	# Überspringen nur über diesen Knopf (sonst würde jedes Lenken die Kill-Cam wegdrücken)
	var sk = _skip_btn()
	sk.mouse_filter = Control.MOUSE_FILTER_IGNORE   # der Tipp wird in _input über die Fläche erkannt
	cl.add_child(sk)
	kco.skip = sk


# Daumen-Knöpfe am Bildschirmrand (auf Höhe von REPLAY): Handy bleibt in der Spielhaltung.
# Links SKIP, rechts RACE AGAIN – abwechselnd tippen, schon ist man im nächsten Rennen.
func _edge_btn(txt: String, right: bool, pri := false) -> Button:
	var b = _btn(txt, pri)
	if not pri:
		_solid(b)
	# Halbkreis, der am Bildschirmrand angeschnitten ist: nur die Innenseite rund, außen bündig ohne Rand
	var h = 246.0
	for st in ["normal", "hover", "focus", "pressed"]:
		var sbx = (b.get_theme_stylebox(st) as StyleBoxFlat).duplicate()
		sbx.set_corner_radius_all(0)
		sbx.set_border_width_all(3)
		if right:
			sbx.corner_radius_top_left = int(h * 0.5)
			sbx.corner_radius_bottom_left = int(h * 0.5)
			sbx.border_width_right = 0
		else:
			sbx.corner_radius_top_right = int(h * 0.5)
			sbx.corner_radius_bottom_right = int(h * 0.5)
			sbx.border_width_left = 0
		sbx.corner_detail = 16
		sbx.content_margin_left = 22.0 if right else 4.0   # Schrift etwas zur Rundung hin, weg vom Rand
		sbx.content_margin_right = 4.0 if right else 22.0
		b.add_theme_stylebox_override(st, sbx)
	var w = h * 0.5
	var m = 0.0
	b.anchor_left = 1.0 if right else 0.0
	b.anchor_right = b.anchor_left
	b.offset_left = (-w - m) if right else m
	b.offset_right = -m if right else (m + w)
	b.anchor_top = 0.62
	b.anchor_bottom = 0.62
	b.offset_top = -6
	b.offset_bottom = 240
	b.custom_minimum_size = Vector2(w, 246)
	b.add_theme_font_size_override("font_size", 25)
	for fc in ["font_color", "font_pressed_color", "font_hover_color", "font_focus_color"]:
		b.add_theme_color_override(fc, Color(1, 1, 1))
	return b


func _skip_btn() -> Button:
	return _edge_btn("SKIP\n▶▶", false)


var kco = {}


func _hud() -> void:
	var cl = CanvasLayer.new()
	add_child(cl)
	hud.layer = cl
	var drops = ColorRect.new()   # Tropfen auf der Scheibe (über dem Bild, unter Cockpit und Anzeigen)
	drops.set_anchors_preset(Control.PRESET_FULL_RECT)
	drops.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drops.visible = false
	drops.material = _shader_mat("""
shader_type canvas_item;
uniform sampler2D scr:hint_screen_texture,filter_linear_mipmap;
uniform float wet=0.;
uniform float fog=0.;
float h(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5);}
float vn(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(h(i),h(i+vec2(1,0)),f.x),mix(h(i+vec2(0,1)),h(i+1.),f.x),f.y);}
void fragment(){
	vec2 uv=SCREEN_UV;
	vec2 off=vec2(0.);
	float m=0.,hi=0.;
	for(int L=0;L<3;L++){
		float sc=6.+float(L)*5.;
		vec2 cs=vec2(sc*.5,sc);
		vec2 g=uv*cs;
		vec2 id=floor(g);
		vec2 f=fract(g)-.5;
		float r=h(id+float(L)*13.1);
		if(r<wet*.85){
			// Lebenszeit kurz: aufklatschen, dann reißt der Fahrtwind den Spritzer nach außen weg
			float per=.22+.25*h(id+2.3);
			float ph=fract(TIME/per+h(id+7.7));
			vec2 cen=(id+.5)/cs;
			vec2 dd=cen-vec2(.5,.42);
			vec2 dir=normalize(dd*cs+vec2(.0001,.0));
			vec2 c=vec2(h(id+3.1)-.5,h(id+5.7)-.5)*.35+dir*ph*1.4;
			vec2 d=f-c;
			float al=dot(d,dir);
			float pp=dot(d,vec2(-dir.y,dir.x));
			float len=.05+ph*.65;                      // Schliere wird beim Wegfliegen länger
			float w=.05+.04*h(id+9.3);
			float sk=smoothstep(w,w*.3,abs(pp))*smoothstep(len,0.,-al)*smoothstep(w*1.2,0.,al);
			float a=sk*(1.-ph)*(1.-ph);
			m=max(m,a);
			off+=dir*a*.05;
			hi+=a*smoothstep(w*.5,0.,abs(pp))*.6;
		}
	}
	vec3 col=textureLod(scr,uv-off*.4,1.).rgb*1.05+hi*.5+vec3(.6,.8,1.)*m*.22;   // helle, gischtige Schlieren
	float al=clamp(m*1.2,0.,1.)*clamp(wet*1.5,0.,1.);
	if(fog>.005){
		// Wasserwand auf der Scheibe: weißlich, verschwommen; wird von der Mitte aus nach außen weggeblasen
		vec2 d=(uv-vec2(.5,.45))*vec2(1.,.62);
		float r=length(d);
		vec2 dir=d/max(r,.001);
		float ang=atan(d.y,d.x);
		float strk=vn(vec2(ang*9.,r*3.-TIME*5.))*.6+vn(vec2(ang*23.,r*8.-TIME*9.))*.4;   // radiale Schlieren nach außen
		float clr=(1.-fog)*.75;
		float fm=smoothstep(clr-.08,clr+.18,r+(strk-.5)*.2)*smoothstep(0.,.25,fog);
		fm=max(fm,smoothstep(.55,1.,fog)*.9);
		vec2 wo=dir*(strk-.5)*.05*fog;
		vec3 blur=textureLod(scr,uv+wo,3.5).rgb;
		vec3 fc=mix(blur*1.2,vec3(.82,.9,.98),.55+.25*strk)+vec3(1.)*pow(strk,4.)*.35;
		col=mix(col,fc,fm);
		al=max(al,fm*.93);
	}
	COLOR=vec4(col,al);
}""")
	cl.add_child(drops)
	hud.drops = drops
	_ck_build(cl)
	_radio_build(cl)
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
	# Kamera umschalten (Verfolger ↔ Cockpit): rechts neben Pause, ebenfalls nur Anzeige, Tipp in _input
	var vwb = Button.new()
	vwb.text = "CAM"
	vwb.add_theme_font_size_override("font_size", 24)
	vwb.add_theme_stylebox_override("normal", _style(Color(0, 0, 0, 0.35), Color(1, 1, 1, 0.3)))
	vwb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vwb.focus_mode = Control.FOCUS_NONE
	vwb.anchor_left = 0.5
	vwb.anchor_right = 0.5
	vwb.offset_left = 60
	vwb.offset_right = 160
	vwb.offset_top = 26
	vwb.offset_bottom = 106
	vwb.visible = false
	cl.add_child(vwb)
	hud.viewbtn = vwb
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
	var rdc = Control.new()
	rdc.set_anchors_preset(Control.PRESET_FULL_RECT)
	rdc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(rdc)
	rdc.draw.connect(func(): _rear_draw(rdc))
	hud.rear = rdc
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
		if int(cfg.get("hud", 2)) == 2:
			return   # Altar-HUD zeichnet den Autopilot-Bogen selbst (im Ring des Rahmens)
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
	rdim.color = Color(0, 0, 0, 0.72)
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
	bx.anchor_top = 0.62
	bx.anchor_bottom = 0.62
	bx.offset_left = -150   # schmal, damit links und rechts die Daumen-Knöpfe Platz haben
	bx.offset_right = 150
	bx.offset_top = 0
	bx.offset_bottom = 380
	bx.add_theme_constant_override("separation", 22)
	bx.visible = false
	cl.add_child(bx)
	var b1 = _solid(_btn("REPLAY"))
	b1.pressed.connect(_replay_start)
	bx.add_child(b1)
	# „Nochmal“ als Daumen-Knopf am rechten Rand (SKIP sitzt gegenüber am linken)
	var b2 = _edge_btn("RACE\nAGAIN\n▶▶", true, true)
	b2.pressed.connect(func(): _race_again())
	b2.visible = false
	cl.add_child(b2)
	hud.again = b2
	var b3 = _solid(_btn("MENU"))
	b3.pressed.connect(func(): _to_menu())
	bx.add_child(b3)
	_fit(bx)
	# Leistungsbericht in die Zwischenablage – zum Einfügen im Chat
	var b4 = _solid(_btn("COPY PERFORMANCE REPORT"))
	b4.add_theme_font_size_override("font_size", 22)
	b4.custom_minimum_size = Vector2(0, 64)
	b4.pressed.connect(func():
		DisplayServer.clipboard_set(bench.get("txt", "") if state == "bench" else _perf_text())
		b4.text = "REPORT COPIED ✓")
	bx.add_child(b4)
	bx.offset_bottom = 470
	hud.perfbtn = b4
	hud.resb = bx
	hud.resbtn = [b1, b3, b4]
	# Ergebnistafel: alle vier Fahrer – erst Zeiten, dann abwechselnd ausgeteilter Schaden
	# auf eigener dunkler Tafel, damit nichts vom Rennbild durchscheint
	var bpn = PanelContainer.new()
	var bsb = StyleBoxFlat.new()
	bsb.bg_color = Color(0.03, 0.03, 0.06, 0.9)
	bsb.border_color = Color(1, 0.55, 0.15, 0.55)
	bsb.set_border_width_all(2)
	bsb.set_corner_radius_all(22)
	bsb.content_margin_left = 30
	bsb.content_margin_right = 30
	bsb.content_margin_top = 20
	bsb.content_margin_bottom = 24
	bpn.add_theme_stylebox_override("panel", bsb)
	bpn.anchor_left = 0.06
	bpn.anchor_right = 0.94
	bpn.anchor_top = 0.4
	bpn.anchor_bottom = 0.4
	bpn.visible = false
	cl.add_child(bpn)
	var bd = VBoxContainer.new()
	bd.add_theme_constant_override("separation", 10)
	bpn.add_child(bd)
	hud.board = bpn
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
	var rb = _solid(_btn("EXIT REPLAY"))
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
	var pz = _solid(_btn("II"))
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
	sv.custom_minimum_size = Vector2(0, 80)   # sonst wächst er auf 112 und überlappt die Fahrerwahl darunter
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
	var fl = _solid(_btn("◀"))
	fl.custom_minimum_size = Vector2(80, 76)
	fl.pressed.connect(func(): _rp_follow(-1))
	fr.add_child(fl)
	var fn = _lbl("YOU", 30)
	fn.custom_minimum_size = Vector2(150, 0)
	fr.add_child(fn)
	hud.flw = fn
	var frb = _solid(_btn("▶"))
	frb.custom_minimum_size = Vector2(80, 76)
	frb.pressed.connect(func(): _rp_follow(1))
	fr.add_child(frb)
	# Foto: nur das reine Bild, ohne Knöpfe, in die Galerie (Bilder › AntiGrav)
	var ph = _btn("PHOTO", true)
	ph.add_theme_font_size_override("font_size", 24)
	ph.custom_minimum_size = Vector2(0, 80)   # sonst wächst er auf 112 und überlappt die Fahrerwahl darunter
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
	vb.custom_minimum_size = Vector2(0, 80)   # sonst wächst er auf 112 und überlappt die Fahrerwahl darunter
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
	var vo = _solid(_btn("OK"))
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
	if hud.has("again") and is_instance_valid(hud.again):
		hud.again.visible = hud.resb.visible
	if not hud.resb.visible:
		if hud.has("ga") and hud.ga != null:
			(hud.ga as CanvasItem).modulate.a = 1.0
		return
	resb_t += dt
	# kurze Pause (ein noch liegender Lenk-Finger löst nichts aus), dann sofort bedienbar
	if not resb_armed and resb_t > 0.35 and fingers.is_empty():
		resb_armed = true
	var a = clampf((resb_t - 0.35) / 0.15, 0.0, 1.0) if resb_armed else 0.0
	hud.resb.modulate.a = a
	if hud.has("again") and is_instance_valid(hud.again):
		hud.again.modulate.a = a
		hud.again.mouse_filter = Control.MOUSE_FILTER_STOP if resb_armed else Control.MOUSE_FILTER_IGNORE
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
	b.button_down.connect(func(): _snd("click", -6.0))
	return b


# Knopf über dem laufenden Spielbild: dunkel und deckend, damit die Schrift lesbar bleibt
func _solid(b: Button) -> Button:
	# voll deckend mit kräftigem Rand – über hellen Szenen (Explosionen, Neon) sonst kaum zu sehen
	var n = _style(Color(0.06, 0.06, 0.1, 1.0), Color(1, 0.62, 0.38, 0.95))
	n.set_border_width_all(3)
	n.shadow_color = Color(0, 0, 0, 0.6)
	n.shadow_size = 8
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", n)
	b.add_theme_stylebox_override("focus", n)
	var pr = _style(Color(0.2, 0.13, 0.1, 1.0), Color(1, 1, 1, 0.95))
	pr.set_border_width_all(3)
	b.add_theme_stylebox_override("pressed", pr)
	b.add_theme_color_override("font_color", Color(1, 1, 1))
	b.add_theme_color_override("font_pressed_color", Color(1, 1, 1))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
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
	for it in [["speed", 0.5, 4.0], ["ai", 0.7, 1.4], ["res", 0.5, 1.0], ["glow", 0.0, 1.5], ["neon", 0.2, 1.5], ["vol", 0.0, 1.0], ["music", 0.0, 1.0], ["voice", 0.0, 2.0]]:
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
	lcol.add_child(_lbl("Track (Color & Noir)", 32))
	var tkr = HBoxContainer.new()
	tkr.add_theme_constant_override("separation", 10)
	lcol.add_child(tkr)
	ui.trk = []
	for q in range(2):
		var b = _btn(["Classic", "Extreme"][q])
		b.add_theme_font_size_override("font_size", 30)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.toggle_mode = true
		b.pressed.connect(func():
			if int(cfg.get("trk", 1)) != q:
				cfg.trk = q
				_save_cfg()
				_reload())
		tkr.add_child(b)
		ui.trk.append(b)
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
	var bbn = _btn("Performance test (50 s)")
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
	var bvb = _btn("Vibration: " + ("On" if int(cfg.get("vib", 1)) == 1 else "Off"))
	bvb.add_theme_font_size_override("font_size", 30)
	bvb.pressed.connect(func():
		cfg.vib = 1 - int(cfg.get("vib", 1))
		_save_cfg()
		bvb.text = "Vibration: " + ("On" if int(cfg.vib) == 1 else "Off")
		_vib(60, 0.8))
	sp.add_child(bvb)
	var bkc = _btn("Kill cam: " + ("On" if int(cfg.get("kcam", 0)) == 1 else "Off"))
	bkc.add_theme_font_size_override("font_size", 30)
	bkc.pressed.connect(func():
		cfg.kcam = 1 - int(cfg.get("kcam", 0))
		_save_cfg()
		bkc.text = "Kill cam: " + ("On" if int(cfg.kcam) == 1 else "Off"))
	sp.add_child(bkc)
	var bmc = _btn("Missile cam: " + ("On" if int(cfg.get("mcam", 1)) == 1 else "Off"))
	bmc.add_theme_font_size_override("font_size", 30)
	bmc.pressed.connect(func():
		cfg.mcam = 1 - int(cfg.get("mcam", 1))
		_save_cfg()
		bmc.text = "Missile cam: " + ("On" if int(cfg.mcam) == 1 else "Off"))
	sp.add_child(bmc)
	var HN = ["Classic", "Dragon gauge", "Gothic altar"]
	var bhd = _btn("HUD style: " + HN[clampi(int(cfg.get("hud", 2)), 0, 2)])
	bhd.add_theme_font_size_override("font_size", 30)
	bhd.pressed.connect(func():
		cfg.hud = (int(cfg.get("hud", 2)) + 1) % 3
		_save_cfg()
		bhd.text = "HUD style: " + HN[int(cfg.hud)])
	sp.add_child(bhd)
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
	ui.credit.text = "Ship: " + SHIPS[int(cfg.ship)][3] + " · Hologram: John, 3D via Tripo AI, dance by Mixamo (Adobe) · Textures: ambientCG (CC0) · Voices: ElevenLabs · Characters & start girl: John, 3D via Tripo AI · “Jungle Tree” by gelmi.com.br, CC BY 4.0 · private use only"
	ui.sl.speed.text = "Speed  %d %%" % int(round(float(cfg.speed) * 100.0))
	ui.sl.ai.text = "Rivals speed  %d %%" % int(round(float(cfg.ai) * 100.0))
	ui.sl.res.text = "Resolution  %d %%" % int(round(float(cfg.res) * 100.0))
	for q in range(3):
		ui.look[q].button_pressed = int(cfg.look) == q
	ui.sl.glow.text = "Glow  %d %%" % int(round(float(cfg.glow) * 100.0))
	ui.sl.neon.text = "Neon lights  %d %%" % int(round(float(cfg.neon) * 100.0))
	ui.sl.vol.text = "Volume  %d %%" % int(round(float(cfg.vol) * 100.0))
	ui.sl.music.text = "Music  %d %%" % int(round(float(cfg.music) * 100.0))
	ui.sl.voice.text = "Voices  %d %%" % int(round(float(cfg.voice) * 100.0))
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
	for q in range(ui.get("trk", []).size()):
		var on5 = int(cfg.get("trk", 1)) == q
		ui.trk[q].button_pressed = on5
		var st5 = _style(Color(0.93, 0.41, 0.18) if on5 else Color(1, 1, 1, 0.08), Color(1, 0.7, 0.54) if on5 else Color(1, 1, 1, 0.22))
		for k in ["normal", "pressed", "hover"]:
			ui.trk[q].add_theme_stylebox_override(k, st5)
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
	_bc("start race")
	_dg_flush()
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
		_qf(e.mi)
		_qf(e.l)
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
			board_man = (_board_page() + 1) % 4
		if ev.pressed:
			if state == "kill":
				if kco.has("skip") and (kco.skip as Control).get_global_rect().grow(40).has_point(ev.position):
					_kc_end()
				return
			if hud.has("pausebtn") and (hud.pausebtn as Control).visible and (hud.pausebtn as Control).get_global_rect().grow(24).has_point(ev.position):
				_pause(true)
				return
			if hud.has("viewbtn") and (hud.viewbtn as Control).visible and (hud.viewbtn as Control).get_global_rect().grow(16).has_point(ev.position):
				cfg.view = (int(cfg.view) + 1) % 3   # außen → Cockpit → Helmvisier
				_save_cfg()
				return
			if state in ["race", "count"] and _ck_on() and _ck_core_hit(ev.position):
				cfg.vmode = (int(cfg.get("vmode", 0)) + 1) % VM_NAMES.size()
				_save_cfg()
				ckh.vt = 0.0
				ckh.gl = 0.9   # kurze Bildstörung beim Umschalten
				return
			if state == "race" and fire_rect.has_point(ev.position):
				fire_req = true
				return
			if not stt.is_empty() and _stt_hit(ev.position):
				return
			touches[ev.index] = ev.position.x
		else:
			touches.erase(ev.index)
	elif ev is InputEventScreenDrag:
		if touches.has(ev.index):
			touches[ev.index] = ev.position.x
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


# Rennmeldungen weg (Minen-Lämpchen, Trefferzeile) – vor Wiederholung und Kill-Cam
func _hud_quiet() -> void:
	if hud.get("mlamp") != null:
		(hud.mlamp as Control).visible = false
	if hud.has("msg"):
		hud.msg.text = ""
	msg_t = 0.0


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
var fl_frame = -1


# Blitz abklingen lassen – höchstens einmal pro Bild, egal wer es aufruft
func _flash_fade(amt: float) -> void:
	var fn = Engine.get_process_frames()
	if fn == fl_frame:
		return
	fl_frame = fn
	if flash_rect != null and flash_rect.color.a > 0.0:
		flash_rect.color.a = maxf(0.0, flash_rect.color.a - amt)


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
	if state == "kill":
		a = minf(a, 0.3)   # in der Zeitlupe nur ein kurzes Aufblitzen, sonst bleibt alles weiß
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
var race_gen = 0   # zählt die Neustarts ohne Neuladen („Race again“)


# in d Sekunden ausführen – aber nur, wenn bis dahin kein neues Rennen begonnen hat (sonst landete z. B. eine
# verzögerte Mine oder die Namenseingabe vom alten Rennen im neuen)
func _after(d: float, f: Callable) -> void:
	if d <= 0.0:
		f.call()
		return
	var gen = fx_gen
	get_tree().create_timer(d).timeout.connect(func():
		if gen == fx_gen:
			f.call())


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
	# Kill-Cam: Feuerball kleiner und nicht weißglühend – in der Zeitlupe überstrahlte er sonst das ganze Bild
	var kl = state == "kill"
	if kl:
		k *= 0.75
	_burst(pos, fxr.fire, int(16 * k * am), 1.0, 2.0 * k, 5.5 * k, 180.0, Vector3(0, 1.6, 0), 4.0, 1.1 * k, 1.9 * k,
		_ramp(_rh([[0.0, Color(4.5, 2.8, 1.2, 1) if kl else Color(12, 10, 7, 1)], [0.1, Color(3.6, 1.6, 0.4, 1) if kl else Color(9, 4.5, 1.2, 1)], [0.35, Color(4, 1.1, 0.15, 0.85)], [0.7, Color(1.0, 0.2, 0.04, 0.45)], [1.0, Color(0.1, 0.02, 0.01, 0)]], hu)),
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
					_qf(e[k])
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
	var sf0 = T.sframe(z, lat)   # folgt auch der Röhrenwand
	var pos: Vector3 = sf0.c + sf0.uu * 0.35
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
		if o.idx == 0:
			_vib(40, 0.45)


# Schild zerbricht: Funkenregen, Meldung, Schutz weg
func _shield_break(o: Dictionary) -> void:
	o.shield = 0.0
	o.shh = 0
	_shield_vis(o)
	var pos: Vector3 = (o.node as Node3D).global_position + Vector3(0, 0.2, 0)
	_fx_res()
	_burst(pos, fxr.spark, 90, 0.8, 4.0, 10.0, 180.0, Vector3(0, -5, 0), 0.5, 0.6, 1.3,
		_ramp([[0.0, Color(2, 5, 9, 1)], [1.0, Color(0.2, 0.5, 1, 0)]]), null, true, false, 0.4)
	_snd("shieldbreak", 2.0, 1.0, null if o.idx == 0 else pos)
	if o.idx == 0:
		_msg("SHIELD BROKEN", Color(0.5, 0.75, 1.0))
		shake = maxf(shake, 0.6)
	else:
		_msg("SHIELD BROKEN · %s" % NAMES[o.idx], Color(0.5, 0.75, 1.0))


func _prot(o: Dictionary) -> bool:
	return o.shield > 0.0 or o.orbs > 0.0 or (o.idx == 0 and (o.auto > 0.0 or not mc.is_empty()))


func _dmg(o: Dictionary, a: float, src := -1, kind := "", sup := false) -> void:
	if free_ride:
		return
	if o.out or state != "race":
		return
	if int(o.idx) == 0 and src > 0:
		_radio(src, "taunt", 0.6)    # ein Gegner hat dich erwischt: er lacht dich aus
	elif int(o.idx) > 0 and src == 0:
		_radio(int(o.idx), "whine", 0.5)   # du hast ihn erwischt: er schimpft
	if o.shield > 0.0 and float(o.get("mshield", 0.0)) > 0.0:
		_shield_ping(o)   # Mega-Schild: hält alles aus
		return
	if o.shield > 0.0:
		# Schild: hält einen Waffentreffer aus (Rakete, Orb, Mine, Wand, Beben …), beim zweiten ist er weg;
		# Superwaffen zerschlagen ihn sofort. Rempeln schluckt er einfach.
		if sup or (kind != "ram"):
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
	if o.idx == 0 and a > 0.0:
		_vib(450 if o.en <= 0.0 else int(clampf(50.0 + a * 700.0, 50.0, 320.0)), 1.0 if o.en <= 0.0 else clampf(0.45 + a * 2.2, 0.45, 1.0))
	if src >= 0 and src < ships.size() and src != o.idx:
		ships[src].dealt += before - o.en
	# wer austeilt, heilt sich: abgezogene Energie wird dir gutgeschrieben
	if src == 0 and o.idx != 0:
		ships[0].en = minf(1.0, ships[0].en + (before - o.en))
	var nm = NAMES[o.idx]
	if o.en <= 0.0:
		if OS.get_environment("KCDBG") != "":
			print("KCDBG out idx=", o.idx, " src=", src, " kind=", kind, " state=", state, " kc=", kc.is_empty(), " kcp=", kc_pending.is_empty())
		# Kill-Cam nur, wenn du einen Gegner ausgeschaltet hast (nicht beim Rempeln)
		if o.idx != 0 and src == 0 and kind != "ram" and state == "race" and kc_pending.is_empty() and kc.is_empty() and not free_ride:
			kc_pending = {"idx": o.idx, "t0": rec_clk, "kind": kind}
		o.out = true
		o.outT = race_t
		_explode(o.z, o.lat, true)
		_shatter(o)
		(o.node as Node3D).visible = false
		if (o.node as Node3D).has_meta("eng"):
			((o.node as Node3D).get_meta("eng") as AudioStreamPlayer3D).stop()
		_big("ELIMINATED" if o.idx == 0 else "CONTENDER\nELIMINATED", Color(1, 0.3, 0.25) if o.idx == 0 else Color(1, 0.82, 0.25))
		var kp: Vector3 = (o.node as Node3D).global_position
		_snd("ko_boom", 3.0, randf_range(0.92, 1.05), null if o.idx == 0 else kp)
		get_tree().create_timer(0.35).timeout.connect(func(): _snd("debris", 0.0, randf_range(0.9, 1.1), null if o.idx == 0 else kp))
		if o.idx != 0:
			_msg(nm.to_upper(), Color(1, 0.85, 0.5))
			_snd("vo_elim", 4.0)
	elif o.idx == 0:
		_msg("−%d %% ENERGY" % int(round(a * 100.0)), Color(1, 0.48, 0.35))
	else:
		_msg("HIT · %s %d %%" % [nm, int(round(o.en * 100.0))], Color(1, 0.75, 0.5))


var rocket_ps: PackedScene


# Raketenmodell (Tripo) als Kind des Schusses: Spitze zeigt in Flugrichtung (lokal +Y), Oberseite zur Fahrbahn-Normale (lokal −Z)
func _rocket_model(sc: float) -> Node3D:
	if rocket_ps == null:
		rocket_ps = load("res://ships/rocket.glb")
	var m: Node3D = rocket_ps.instantiate()
	var bs = Basis(Vector3(0, -1, 0), Vector3(0, 0, -1), Vector3(1, 0, 0)).scaled(Vector3.ONE * sc)
	m.transform = Transform3D(bs, -(bs * Vector3(0, 0.21, 0)))
	m.set_meta("rkm", true)
	for c in m.find_children("*", "GeometryInstance3D", true, false):
		(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


func _add_shot(from: Dictionary, at_player := false, homing := false, dir := 1.0, cl := false, sp := false) -> void:
	var X: Dictionary = fx.rak
	var cap = CapsuleMesh.new()   # Plasma-Flamme am Heck (glüht, flackert)
	cap.radius = 0.028 * float(X.size)
	cap.height = 0.2 * float(X.size)
	var mi = _glow_node(cap, _hs(Color(1.0, 0.6, 0.2), float(X.hue)), 8.0)
	var rl = 0.72 * float(X.size) * (1.35 if (cl or sp) else 1.0)   # Länge des Modells
	mi.mesh = null
	var fl = MeshInstance3D.new()
	fl.mesh = cap
	fl.material_override = mi.material_override
	fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fl.position = Vector3(0, -rl * 0.5 - cap.height * 0.35, 0)
	mi.add_child(fl)
	mi.set_meta("fl", fl)
	mi.add_child(_rocket_model(rl))
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
	if tg != null and tg.idx == 0 and from.idx != 0 and state == "race":
		_snd("incoming", -1.0)   # Warnung: Lenkrakete kommt auf dich zu
	shots.append({"z": from.z + 1.0 * dir, "lat": from.lat, "t": 0.0, "pl": at_player, "hm": homing, "tg": tg, "dl": tan(from.psi) * dir if not at_player else 0.0, "n": mi, "own": from.idx, "dir": dir, "cl": cl, "sup": sp or cl,
		"z0": from.z + 1.0 * dir, "lap1": not homing and not at_player and not cl and dir > 0.0})   # normale Rakete: eine ganze Runde auf ihrer Spur
	if cl or sp:
		# Superwaffe: gold, größer, heller
		(mi.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.78, 0.2)
		(mi.material_override as StandardMaterial3D).emission = Color(1.0, 0.78, 0.2)
		(mi.material_override as StandardMaterial3D).emission_energy_multiplier = 16.0
		cap.radius *= 1.4
		cap.height *= 1.4
		lt.light_color = Color(1.0, 0.75, 0.25)
		lt.light_energy *= 2.5
	_snd("rak", -2.0, 1.0, (from.node as Node3D).global_position if from.idx != 0 else null)


# Spiral-Raketen (Super: 2, Mega: 3): fliegen als Zopf umeinander gedreht, getroffen wird über die gemeinsame Bahn.
# Lage der k-ten Rakete von n um die Flugbahn – Radius wächst kurz nach dem Start auf, dann dreht der Zopf
func _braid_off(f: Dictionary, n: int, k: int, t: float) -> Vector3:
	if n <= 1:
		return Vector3.ZERO
	var r = 0.24 * clampf(t / 0.18, 0.0, 1.0)
	var a = t * 13.0 + TAU * float(k) / float(n)
	return f.rr * (cos(a) * r) + f.uu * (sin(a) * r + 0.1)


func _braid(sh: Dictionary, n: int) -> void:
	sh.br = n
	sh.ex = []
	var src: MeshInstance3D = sh.n
	for k in range(1, n):
		var mi = Node3D.new()
		for c in src.get_children():
			if c is OmniLight3D:
				continue   # Licht nur einmal pro Zopf
			mi.add_child(c.duplicate())
		add_child(mi)
		sh.ex.append(mi)


# Rakete geht hoch: normal ein schwarzes Loch, Super-Rakete (Streubombe) zerplatzt in fünf kleine über die ganze Breite
func _shot_boom(sh: Dictionary, z: float, lat: float, hit: int) -> void:
	if not sh.get("cl", false):
		_gbomb(z, lat, sh.own, hit, 1.0, sh.get("sup", false))
		return
	for i in range(5):
		var la = lerpf(-T.TW * 0.8, T.TW * 0.8, i / 4.0)
		var zz = z + 1.0 + randf() * 2.5
		_after(0.05 * i + 0.01, func(): _gbomb(zz, la, sh.own, -1, 0.5, true))
	_snd("boom", 0.0, 1.3)


# Minen fallen nacheinander hinten aus dem Schiff: „dupp, dupp, dupp“; Super-Minen: Teppich über die ganze Breite
var mine_grp = 0


func _drop_mines(o: Dictionary, sup := false) -> void:
	mine_grp += 1   # ein Teppich = eine Gruppe: wer hineinfliegt, bekommt nur einmal Schaden
	var gid = mine_grp
	if sup:
		for k in range(9):
			var la = lerpf(-T.TW + 0.35, T.TW - 0.35, k / 8.0)
			_after(k * 0.05, func(): _drop_one(o, k, la, 0.6 * (k % 2), gid))
		return
	for k in range(3):
		_after(k * 0.14, func(): _drop_one(o, k, 999.0, 0.0, gid))


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
	if float(o.get("blk", 0.0)) > 0.0:
		o.blk = maxf(0.0, float(o.blk) - dt)
		if racing and not o.out:
			o.slow = minf(float(o.slow), 0.8)   # im Dunkeln: Fuß vom Gas
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
		"blk":
			# Licht aus, sobald jemand in der Nähe ist (vor oder hinter ihm)
			for x in ships:
				if x.idx != o.idx and not x.out and absf(x.z - o.z) < 35.0:
					_blackout(o, 7.0 if sup else 5.0)
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
	if not orb_n.is_empty() and not is_instance_valid(orb_n[0]):
		orb_n.clear()   # weggeräumt (Neustart/Kill-Cam): neu bauen
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
	if not ships.is_empty():
		var fw0 = str(ships[0].wpn)
		if fw0 == "mine":
			_vib(14, 0.22)        # Mine legen: nur ein ganz kleines Zucken
		elif fw0 in ["rak", "lenk"]:
			_vib(45, 0.55)        # Rakete: spürbarer Rückstoß
		elif fw0 != "":
			_vib(30, 0.4)
	_bc("fire %s" % (str(ships[0].wpn) if not ships.is_empty() else ""))
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
			if sup:
				_braid(shots[shots.size() - 1], 2)   # Super: zwei Raketen im Zopf
		"lenk":
			_add_shot(g, false, true, 1.0, false, sup)
			if sup:
				_braid(shots[shots.size() - 1], 2)
			if g.idx == 0:
				_mc_start(shots[shots.size() - 1])
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
			_snd("quake", 3.0)
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
		"blk":
			_blackout(g, 7.0 if sup else 5.0)


# Blackout: allen anderen geht das Licht aus – nur Neon bleibt. Gegner fahren unsicher, du (als Opfer) siehst fast nichts mehr.
func _blackout(src: Dictionary, dur: float) -> void:
	_snd("blackout", 2.0)
	for x in ships:
		if x.idx == src.idx or x.out:
			continue
		if x.idx == 0:
			blk_t = maxf(blk_t, dur)
			blk_d = maxf(blk_t, 0.1)
			_msg("BLACKOUT", Color(0.72, 1.0, 0.12))
			_vib(80, 0.7)
			_after(0.35, func(): _snd("vo_blk", 3.0))   # geflüstert, während das Licht ausgeht
		else:
			x.blk = maxf(float(x.get("blk", 0.0)), dur)
	if src.idx == 0:
		_msg("LIGHTS OUT FOR THEM", Color(0.72, 1.0, 0.12))
		_flash(Color(0.0, 0.0, 0.0), 0.25)


# MEGA: jede Waffe hat ihre eigene, große Wirkung – stark, aber kein Sofortsieg (höchstens ~40 % Schaden je Gegner)
func _fire_mega(g: Dictionary, w: String) -> void:
	_flash(Color(1.0, 0.45, 0.95), 0.3)
	shake = maxf(shake, 0.8)
	match w:
		"rak", "lenk":
			# drei Raketen im Zopf, die dem Gegner vor dir hinterherjagen (Lenkrakete: dem eingerasteten Ziel)
			_add_shot(g, false, true, 1.0, false, true)
			var ms: Dictionary = shots[shots.size() - 1]
			ms.mega = true
			ms.lap1 = false
			_braid(ms, 3)
			if g.idx == 0 and w == "lenk":
				_mc_start(ms)
		"mine":
			# zwei Minenteppiche hintereinander über die ganze Breite
			_drop_mines(g, true)
			_after(0.35, func(): _drop_mines(g, true))
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
			_after(0.8, func():
				if state == "race" and not g.out:
					_backwave(g))
			_snd("boost", 2.0, 0.85)
		"beben":
			# Super-Quake in beide Richtungen, dazu eine zweite Welle nach vorn
			_fire_w(g, "beben", true)
			_after(0.8, func():
				if state == "race":
					quake = _quake_make(g.z + 3.0, 1.0, quake)
					quake.sup = true
					quake.full = true
					_snd("boom", 3.0, 0.55))
		"auto":
			# 8 s Autopilot, dabei geschützt
			g.auto = 8.0
			g.ahold = false
			g.sauto = true
			g.shield = maxf(g.shield, 8.0)
			g.mshield = 8.0
			_snd("shield")
		"blk":
			# 9 s Blackout für alle anderen
			_blackout(g, 9.0)
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
		_qf(old.n)
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
	if q.get("full", false):
		qmax = T.LAP - 3.0   # Mega: einmal um die ganze Strecke, bis sie hinter dir ankommt
	q.z += base_spd * 3.2 * float(QX.speed) * dt * dir
	q.age += dt
	for o in ships:
		if o.idx != 0 and not o.out and not q.hit.has(o.idx) and absf(wrapf(o.z - q.z, -T.LAP * 0.5, T.LAP * 0.5)) < 2.6:
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
	if OS.get_environment("QDBG") != "" and Engine.get_process_frames() % 6 == 0:
		print("QDBG z=", snappedf(q.z, 0.1), " qs=", snappedf(qs, 0.01), " pipe=", snappedf(T.pipe_k(q.z), 0.01), " gz=", snappedf(g.z, 0.1))
	var sfx = "" if dir > 0.0 else "2"
	_rset("qz" + sfx, q.z)
	_rset("qs" + sfx, qs)
	shake = maxf(shake, 0.35 * clampf(1.0 - absf(q.z - g.z) / 40.0, 0.0, 1.0) * float(QX.shake))
	if dist > qmax or q.age > (40.0 if q.get("full", false) else 16.0) * qd:
		_qf(q.n)
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
			_qf(w.n)
	bwaves.clear()


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
			_qf(mi)
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
		"blk":
			# Auge mit Strich: Licht aus
			c.draw_arc(p + Vector2(0, s * 0.55), s * 0.95, -PI * 0.8, -PI * 0.2, 20, col, lw, true)
			c.draw_arc(p - Vector2(0, s * 0.55), s * 0.95, PI * 0.2, PI * 0.8, 20, col, lw, true)
			c.draw_circle(p, s * 0.22, col)
			c.draw_line(p + Vector2(-s * 0.8, s * 0.8), p + Vector2(s * 0.8, -s * 0.8), col, lw, true)
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
	for w in ["rak", "lenk", "mine", "orbs", "wand", "beben", "schild", "turbo", "auto", "blk"]:
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
	"sound.beeps": "Lautstärke der Countdown-Pieptöne."
}
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
	var msg = JSON.stringify({"ver": fx_ver, "b": steer_btn, "c": 0, "sx": -1.0, "vx": -1.0, "px": -1.0, "rx": -1.0,
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
				its.append({"k": it[0], "n": it[1], "lo": it[2], "hi": it[3], "d": it[4], "v": float(fx[t[0]][it[0]]), "i": FX_INFO.get(t[0] + "." + it[0], ""), "m": []})
			tabs.append({"g": t[0], "n": t[1], "it": its})
		_live_send(c, "application/json", JSON.stringify({"ver": fx_ver, "tabs": tabs, "ctrl": 0, "cn": [], "cc": []}))
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
	elif path.begins_with("/ping"):
		_live_send(c, "text/plain", "ok")
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
function modeBar(){let mb=document.getElementById('mb');if(!CN.length){if(mb)mb.remove();return;}if(!mb){mb=document.createElement('div');mb.id='mb';mb.style.cssText='display:flex;gap:6px;flex-wrap:wrap;align-items:center;margin:6px 0';document.querySelector('header').insertBefore(mb,document.getElementById('st'));}
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
var lk_snd = false   # Erfassungsklang schon gespielt
var lk_n: MeshInstance3D
var lk_im: ImmediateMesh
var lk_mat: ShaderMaterial
var lk_txt: Label
const LK_T = 1.3     # Sekunden bis zum Einrasten (× Regler)
const LK_R = 90.0    # Reichweite


# Zielhülle: eng anliegende, leuchtende Hülle in Schiffsform – orange = anvisiert, rot (mit Aufblitzen) = eingerastet
const HULL_CODE = """
shader_type spatial;
render_mode unshaded,blend_add,cull_back,depth_draw_never,shadows_disabled,fog_disabled;
uniform vec3 c=vec3(1.,.55,.1);uniform float k=1.;uniform float fl=0.;uniform float gr=.035;
void vertex(){float s=length(MODEL_MATRIX[0].xyz);VERTEX+=NORMAL*gr/max(s,1e-4);}
void fragment(){
	float fr=clamp(1.-abs(dot(NORMAL,VIEW)),0.,1.);
	float p=.78+.22*sin(TIME*8.);
	ALBEDO=c*(pow(fr,1.5)*2.+.1)*k*p+c*fl*2.5;
}"""
var hull_mat: ShaderMaterial
var hull_on = null      # Schiff, das gerade die Hülle trägt
var hull_fl = 0.0       # Aufblitzen beim Einrasten
var hull_lk = false


func _hull_meshes(nd: Node3D) -> Array:
	if not nd.has_meta("hullm"):
		var lst = []
		if nd.get_child_count() > 0:
			for mi in nd.get_child(0).find_children("*", "MeshInstance3D", true, false):
				lst.append(mi)
		nd.set_meta("hullm", lst)
	return nd.get_meta("hullm")


func _hull_update(tg, locked: bool, dt: float) -> void:
	if hull_mat == null:
		hull_mat = _shader_mat(HULL_CODE)
	if hull_on != null and (tg == null or hull_on != tg):
		for mi in _hull_meshes(hull_on.node):
			if is_instance_valid(mi):
				(mi as MeshInstance3D).material_overlay = null
		hull_on = null
	if tg == null or tg.out:
		hull_lk = false
		return
	if hull_on == null:
		hull_on = tg
		for mi in _hull_meshes(tg.node):
			(mi as MeshInstance3D).material_overlay = hull_mat
	if locked and not hull_lk:
		hull_fl = 1.0
	hull_lk = locked
	hull_fl = maxf(0.0, hull_fl - dt / 0.3)
	hull_mat.set_shader_parameter("c", _v3(Color(1.0, 0.08, 0.06) if locked else Color(1.0, 0.5, 0.08)))
	hull_mat.set_shader_parameter("k", 0.95 if locked else 0.6)
	hull_mat.set_shader_parameter("fl", hull_fl)


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
		lk_snd = false
	if tg == null:
		_hull_update(null, false, dt)
		if lk_n != null and lk_n.visible:
			lk_n.visible = false
			lk_txt.visible = false
		return
	var L: Dictionary = fx.lock
	lk_t += dt
	if demo and lk_t > 1.3 * float(L.time) + 1.6:
		lk_t = 0.0   # Vorschau: von vorn
		lk_snd = false
	lk_k = clampf(lk_t / maxf(0.05, LK_T * float(L.time)), 0.0, 1.0)
	_hull_update(tg, lk_k >= 1.0, dt)
	_lock_vis(tg, dt)
	# Piepsen: immer schneller, eingerastet ein schnelles Dauersirren
	lk_bt -= dt
	var vol = float(L.vol)
	if lk_bt <= 0.0 and vol > 0.01:
		var db = linear_to_db(vol)
		if lk_k < 1.0 and not lk_snd:
			lk_snd = true   # Zielerfassung: immer schneller piepsend bis zum Dauerton (ein Klang)
			_snd("lock", db - 3.0, clampf(1.5 / maxf(0.3, LK_T * float(L.time)), 0.7, 1.6))
			lk_bt = 0.05


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
	# Magnet: kurz vor einer Waffensäule zieht sie dich sanft auf ihre Spur (danebenzielen wird verziehen, hinsteuern musst du trotzdem)
	var can_pick = g.wpn == "" or not g.get("mega", false)
	if racing and can_pick and not g.air:
		for kk in [wk, wk + 1]:
			if posmod(kk, 2) != 0 or kk == g.wpK or not _pad_ok(_wzp(kk)):
				continue
			var dz = _wzp(kk) - zz
			var dl = _wpx(kk) - float(g.lat)
			var reach = 1.5 + 0.9 * T.pipe_k(zz)
			if dz > -0.5 and dz < 16.0 and absf(dl) < reach:
				var pull = (1.0 - clampf(dz / 16.0, 0.0, 1.0)) * (3.2 + 2.0 * T.pipe_k(zz))
				g.lat = float(g.lat) + dl * clampf(pull * dt, 0.0, 0.5)
	var hitw = float(fx.pillar.get("hitw", 0.5)) * (1.0 + 0.8 * T.pipe_k(zz))   # in der Röhre breiter
	if racing and posmod(wk, 2) == 0 and wz < maxf(1.75, g.spd * dt * 1.3) / 35.0 and not g.air and absf(g.lat - _wpx(wk)) < hitw and wk != g.wpK and (g.wpn == "" or not g.get("mega", false)):
		g.wpK = wk
		if g.wpn == "":
			g.wpn = _pick_w()
			g.wpc = 1
			_snd("load_weapon", 0.0)   # durchs Energiefeld, Waffe rastet ein – gleich danach die Ansage
			var wv = "vo_" + g.wpn
			get_tree().create_timer(0.3).timeout.connect(func(): _snd(wv, 3.0))
			if g.wpn == "orbs" and g.orbs > 0.0:
				g.sup = true
				get_tree().create_timer(1.05).timeout.connect(func(): _snd("vo_super", 3.0))
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
	if hud.has("viewbtn"):
		hud.viewbtn.visible = state in ["count", "race"] and fin.is_empty()
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
	# in der Wiederholung keine Renn-Anzeige: sie lag über den Wiederholungs-Knöpfen
	var rpv = state == "replay"
	hud.gh.visible = goth and not rpv
	hud.ga.visible = alt and not rpv
	if alt:
		_ga_frame(g, dt)
	(hud.rear as Control).queue_redraw()
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
		# Lenkrakete: nur etwas schneller als ein Gleiter in Normalfahrt – mit Boost und sauberer Linie entkommt man ihr
		var hmk = sh.hm and not sh.pl and not sh.get("mega", false)
		var vs = spd
		if hmk:
			vs = base_spd * (1.82 if sh.get("sup", false) else 1.68) * float(fx.rak.speed)
		elif sh.get("mega", false):
			vs = base_spd * 5.0 * float(fx.rak.speed)   # Mega: ein Blitz – selbst eine ganze Runde dauert nur Sekunden
		sh.z += vs * dt * sdir
		if sh.pl:
			sh.lat += (g.lat - sh.lat) * minf(1.0, dt * 3.0)
		elif sh.hm:
			var mg = sh.get("mega", false)
			if mg:
				# Mega-Lenkrakete: jagt über die ganze Runde (auch wer hinter ihr ist, wird nach einer Runde eingeholt), bis sie trifft
				if sh.tg == null or sh.tg.out or fposmod(float(sh.tg.z) - float(sh.z), T.LAP) > T.LAP - 1.5:
					sh.tg = null
					var bm = T.LAP + 1.0
					for o in ships:
						if o.idx != sh.own and not o.out:
							var dm = fposmod(float(o.z) - float(sh.z) + 1.0, T.LAP)
							if dm < bm:
								bm = dm
								sh.tg = o
			elif sh.tg == null or sh.tg.out or (sh.tg.z - sh.z) * sdir < -1.5:
				sh.tg = null
				var bd = 200.0
				for o in ships:
					if o.idx != sh.own and not o.out and (o.z - sh.z) * sdir > -1.0 and (o.z - sh.z) * sdir < bd:
						bd = (o.z - sh.z) * sdir
						sh.tg = o
			if sh.tg != null:
				# je näher, desto härter auf die Spur des Ziels – die Lenkrakete schlägt direkt ein
				var dzt = absf(sh.tg.z - sh.z)
				var dlat = float(sh.tg.lat) - float(sh.lat)
				if T.pipe_full(sh.z):   # geschlossene Röhre: kürzester Weg rundherum
					var cc = TAU * T.PR
					dlat = wrapf(dlat, -cc * 0.5, cc * 0.5)
				sh.lat += dlat * minf(1.0, dt * (5.0 + 60.0 / maxf(1.0, dzt)))
		else:
			sh.lat += sh.dl * spd * dt
		# Raketen bleiben immer auf der Fahrbahn: an der Bande entlang gleiten, in der Röhre einmal rundherum
		var slim = T.lim(sh.z) - 0.2
		if T.pipe_full(sh.z):
			var circ2 = TAU * T.PR
			if absf(sh.lat) > circ2 * 0.5:
				sh.lat -= signf(sh.lat) * circ2
		elif absf(sh.lat) > slim:
			sh.lat = signf(sh.lat) * slim
			if not sh.hm and not sh.pl:
				sh.dl = 0.0
		# Kraftfeldwand hält fremde Raketen auf: wer durch seine eigene Wand gefahren ist, hat sie als Schild im Rücken
		var walled = false
		for w in walls:
			if int(w.get("own", -1)) == int(sh.own):
				continue
			var wzz = float(w.z) + T.LAP * round((float(sh.z) - float(w.z)) / T.LAP)
			if (z0 - wzz) * (float(sh.z) - wzz) <= 0.0 and z0 != float(sh.z):
				walled = true
				w.hf = 1.0
				_explode(wzz - 0.3 * sdir, sh.lat, false, 0.6)
				_snd("zap", 1.0, 1.2, (w.n as Node3D).global_position if is_instance_valid(w.n) else null)
				if int(w.get("own", -1)) == 0 and state == "race":
					_msg("BLOCKED", Color(0.1, 0.95, 0.85))
				break
		if walled:
			_qf(sh.n)
			for e in sh.get("ex", []):
				_qf(e)
			shots.remove_at(i)
			continue
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
			var oz = float(o.z)
			if sh.get("mega", false) or sh.get("lap1", false):
				oz += T.LAP * round((float(sh.z) - oz) / T.LAP)   # Rakete kann eine Runde weiter sein: gleiche Stelle der Strecke zählt
			if oz > zlo and oz < zhi and absf(sh.lat - o.lat) < lw:
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
		elif hmk and sh.t > 5.0:
			# Lenkrakete: nach 5 s ist der Sprit alle – sie verpufft ohne Schaden
			_explode(sh.z, sh.lat, false, 0.45)
			dead = true
		elif (sh.t > 6.0 and not sh.get("mega", false) and not sh.get("lap1", false)) or (sh.get("mega", false) and sh.t > 40.0) or (sh.get("lap1", false) and absf(float(sh.z) - float(sh.z0)) > T.LAP) or (sh.cl and sh.t > 0.42) or (state == "lab" and absf(sh.z - LZ) > 18.0):
			if sh.get("mega", false):
				_explode(sh.z, sh.lat, false, 0.8)   # Mega-Salve: daneben = nur ein Knall, kein Loch
			else:
				_shot_boom(sh, sh.z, sh.lat, -1)
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
		if dead and OS.get_environment("RKW") != "":
			print("SHOTDEAD t=", snappedf(sh.t, 0.01), " z=", snappedf(sh.z, 0.1), " lat=", snappedf(sh.lat, 0.01), " hit=", hit.idx if hit != null else -1, " tg=", sh.tg.idx if sh.tg != null else -1, " mega=", sh.get("mega", false), " br=", sh.get("br", 1))
		if dead:
			_qf(sh.n)
			for e in sh.get("ex", []):
				_qf(e)
			shots.remove_at(i)
		else:
			var f = T.sframe(sh.z, sh.lat)
			var bn: int = sh.get("br", 1)
			var bp: Vector3 = f.c + f.uu * 0.25
			var bb = Basis(f.rr, f.fw, -f.uu)
			sh.n.global_transform = Transform3D(bb, bp + _braid_off(f, bn, 0, sh.t))
			var fln = sh.n.get_meta("fl", null)
			if fln != null and is_instance_valid(fln):
				var fk = 0.75 + 0.5 * randf()   # Antrieb flackert
				(fln as Node3D).scale = Vector3(fk * 0.9, fk, fk * 0.9)
			for k in range(1, bn):
				(sh.ex[k - 1] as Node3D).global_transform = Transform3D(bb, bp + _braid_off(f, bn, k, sh.t))
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
		if not boom and ((quake != null and absf(wrapf(m.z - quake.z, -T.LAP * 0.5, T.LAP * 0.5)) < 2.6) or (quake2 != null and absf(wrapf(m.z - quake2.z, -T.LAP * 0.5, T.LAP * 0.5)) < 2.6)):
			boom = true
		if state == "lab" and m.t > 1.8:
			boom = true
		if boom or m.t > float(fx.mine.life):
			if boom:
				_explode(m.z, m.lat, false, float(fx.mine.boom))
			_qf(m.n)
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
			_qf(w.n)
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
			_qf(e.mi)
			_qf(e.l)
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
			# Druckwelle in der Kill-Cam schwächer – in Zeitlupe stand sie sonst als grellweißer Ring vor der Kamera
			e.rm.set_shader_parameter("rk", float(fx.boom.ring) * (0.3 if state == "kill" else 1.0))
			if u >= 1.0:
				_qf(e.ring)
				e.ring = null
		# Licht: greller Blitz, dann langes oranges Nachglühen
		var lt2: OmniLight3D = e.l
		var tl = e.t
		# in der Kill-Cam (Zeitlupe) gedämpft: der grelle Blitz dauert dort fünfmal so lang und brennt die Fahrbahn weiß aus
		var kdim = 0.18 if state == "kill" else 1.0
		lt2.light_energy = (38.0 * kdim * exp(-tl * 7.0) + 7.0 * (0.6 if state == "kill" else 1.0) * pow(clampf(1.0 - tl / 2.2, 0.0, 1.0), 1.6) * (1.0 + 0.15 * sin(tl * 37.0))) * e.get("lk", 1.0)
		lt2.light_color = _hs(Color(1.0, 0.92, 0.8).lerp(Color(1.0, 0.4, 0.08), clampf(tl * 2.2, 0.0, 1.0)), e.get("hu", 0.0))
		lt2.omni_range = e.rg * (0.7 + 0.5 * exp(-tl * 3.0))
		if tl >= 2.2:
			_qf(lt2)
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
		for k in range(int(x.get("br", 1))):
			w.append([x.z, x.lat, int(x.own), float(x.dir), int(x.get("br", 1)), k, float(x.t)])
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
	_hud_quiet()
	if hud.has("ga") and hud.ga != null:
		(hud.ga as CanvasItem).visible = false
	if hud.has("gh") and hud.gh != null:
		(hud.gh as CanvasItem).visible = false
	_bc("replay start")
	_dg_flush()
	if rec.size() < 10 or state == "replay":
		return
	rp = {"t": 0.0, "i": 0, "ei": -1, "ci": 0, "ct": 0.0, "sp": null, "sk": 1.0, "fix": -1, "paused": false, "scrub": false,
		"fyaw": 0.6, "fpitch": 0.45, "fdist": 7.0, "follow": 0}
	hud.rppause.text = "II"
	rtouch = {}
	# Effekte aus dem laufenden Rennen weg – im Replay entstehen sie aus der Aufzeichnung
	for n in get_children():
		if n is GPUParticles3D or n.has_meta("deb"):
			n.queue_free()
	debris.clear()
	for e in fxs:
		for k in ["ring", "l", "core", "sw", "sph"]:
			if e.has(k) and e[k] != null and is_instance_valid(e[k]):
				_qf(e[k])
	fxs.clear()
	for e in zaps:
		_qf(e.mi)
		_qf(e.l)
	zaps.clear()
	_bwaves_clear()
	if quake != null:
		_qf(quake.n)
		quake = null
	if quake2 != null:
		_qf(quake2.n)
		quake2 = null
	fx_gen += 1
	# was gerade gelöscht wird, nicht als „gehört zur Szene“ merken
	rp.base = get_children().filter(func(n): return not n.is_queued_for_deletion())
	_rp_follow_lbl()
	state = "replay"
	hud.resb.visible = false
	if hud.has("again") and is_instance_valid(hud.again):
		hud.again.visible = false
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
		_qf(x.n)
	walls.clear()
	for x in shots:
		_qf(x.n)
		for e in x.get("ex", []):
			_qf(e)
	shots.clear()
	for x in mines:
		_qf(x.n)
	mines.clear()


func _replay_end() -> void:
	_bc("replay end")
	_dg_flush()
	if state != "replay":
		return
	if vx.get("on", false):
		_vx_finish()
		return
	if not vx.is_empty():
		return
	for k in ["shots", "mines", "walls", "swalls"]:
		for n in rp.get(k, []):
			_qf(n)
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
				"shat":
					_shatter(ships[ev[1]], ev[2])
	_debris_update(dt)
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
		var wo: Vector3 = _braid_off(fr, int(f0.w[i][4]), int(f0.w[i][5]), float(f0.w[i][6])) if (f0.w[i] as Array).size() >= 7 else Vector3.ZERO
		ps[i].global_transform = Transform3D(Basis(fr.rr, fr.fw, -fr.uu), fr.c + fr.rr * f0.w[i][1] + fr.uu * 0.25 + wo)
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
	if hud.has("layer") and is_instance_valid(hud.layer):
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
	if not hud.has("rpphoto") or not is_instance_valid(hud.rpphoto):
		return   # Replay inzwischen verlassen
	hud.rpphoto.text = "SAVED ✓" if ok else "ERROR"
	get_tree().create_timer(1.5).timeout.connect(func():
		if hud.has("rpphoto") and is_instance_valid(hud.rpphoto):
			hud.rpphoto.text = "PHOTO")


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
		var st = _style(Color(0.93, 0.41, 0.18) if on else Color(0.06, 0.06, 0.1, 1.0), Color(1, 0.75, 0.6) if on else Color(1, 0.62, 0.38, 0.9))
		st.set_border_width_all(3)
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
			_qf(n)
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
		# an den Tribünen nicht zwischen die Zuschauer stellen, sondern direkt an die Bande
		var lzs = T.lz(float(rp.sp))
		var trib = false
		for tz in TRIB_Z:
			if lzs > tz[0] - 2.0 and lzs < tz[1] + 2.0:
				trib = true
		ro = T.world(rp.sp, rp.sk * (T.TW * 0.8 if inT else (T.TW + 0.55 if trib else T.TW + 1.5)), 1.3 if inT else (1.15 if trib else 0.9))
		ta = S0 + f.fw * 0.6
	elif cm == "cock":
		ro = S0 + SU * CK_EYE.y - SF * CK_EYE.x
		ta = S0 + SF * 12.0 + SU * CK_EYE.z
		up = f.uu.lerp(SU, 0.4).normalized()
	elif cm == "heli":
		ro = S0 - f.fw * 6.0 + Vector3.UP * 6.0 + f.rr * 2.0
		ta = S0 + f.fw * 4.0
	else:
		ro = S0 + f.fw * 6.5 + f.uu * 1.0 + f.rr * 0.9
		ta = S0 + f.uu * 0.15
	shake = maxf(0.0, shake - dt * 1.8)
	_flash_fade(dt * 2.2)
	cam.global_position = ro
	cam.look_at(ta, up)
	cam.fov = 38.0 if cm == "side" else (CK_FOV * minf(1.35, 1.0 + 0.25 * post_spd) if cm == "cock" else 52.0)
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
		# Start-Mädel (Hologramm-Shader auf einer Figur mit Skelett) einmal mitzeichnen: sonst baut das Handy dieses
		# Grafik-Programm erst, wenn sie beim Countdown auftaucht – genau dort hing der Vorbeiflug kurz
		var wf = T.frame(zf + 2.0)
		var wn: Node3D = load("res://holo/fig_woman3.glb").instantiate()
		var wm = _shader_mat(HOLO_CODE)
		for mi in wn.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_override = wm
			(mi as MeshInstance3D).extra_cull_margin = 2.0
		add_child(wn)
		wn.global_position = wf.c + wf.uu * 0.2
		# Comic-Bilder schon jetzt laden (sonst kommen sie erst beim ersten Comic von der Platte)
		for c3 in ["ren", "kato", "mira", "vega"]:
			for k3 in ["0", "1", "2"]:
				_cm_img(c3 + "_" + k3)
			if c3 != "ren":
				_cm_img("ko_" + c3)
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
		_qf(e.mi)
		_qf(e.l)
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
	# Kill-Cam abgeschaltet (Standard): nur das K.o.-Comic, kein Replay
	if int(cfg.get("kcam", 0)) != 1 and (not shot_s.contains("rkctest") or OS.get_environment("KCOFF") != ""):
		var vk: int = int(kc_pending.get("idx", -1))
		kc_pending = {}
		if int(cfg.get("comic", 1)) == 1 and vk >= 1 and vk <= 3:
			_comic_start("ko", vk)
		return
	if rec_clk >= kc_pending.t0 + 1.0:
		_kc_start()


func _kc_start() -> void:
	_hud_quiet()
	_bc("killcam start victim=%s kind=%s" % [kc_pending.get("idx", -1), kc_pending.get("kind", "")])
	_dg_flush()
	var t0: float = kc_pending.t0
	var F = rec
	var ts = t0 - 5.0   # gut 5 s vorher einsteigen: man sieht, wie es dazu kam
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
		if (n is GPUParticles3D or n is MeshInstance3D or n is OmniLight3D or n.has_meta("deb")) and not tun_l.has(n) and n.visible:
			n.visible = false
			hidden.append(n)
	# Ort des Treffers vorab aus der Aufnahme (für die feste Kamera beim Einschlag)
	var dzl = Vector2(ships[kc_pending.idx].z, ships[kc_pending.idx].lat)
	for fr in F:
		if float(fr.t) >= t0 - 0.02:
			var sv: Array = fr.s[kc_pending.idx]
			dzl = Vector2(float(sv[0]), float(sv[1]))
			break
	# Bebenwelle: welche (vorwärts/rückwärts) war beim Treffer am Opfer – bestimmt die Blickrichtung der Einschlag-Kamera
	var qdir = 1.0
	var qbest = 1e9
	for fr in F:
		if float(fr.t) >= t0 - 0.6 and float(fr.t) <= t0 + 0.05:
			for qk in [["q", 1.0], ["q2", -1.0]]:
				if fr.get(qk[0]) != null:
					var dd = absf(wrapf(dzl.x - float(fr[qk[0]][0]), -T.LAP * 0.5, T.LAP * 0.5))
					if dd < qbest:
						qbest = dd
						qdir = qk[1]
	kc = {"qd": qdir, "t0": t0, "end": t0 + 2.4, "victim": kc_pending.idx, "imp": dzl, "kind": kc_pending.kind, "saved": saved, "hidden": hidden,
		"before": get_children(), "fxs": fxs.duplicate(), "zaps": zaps.duplicate(), "top": hud.top.text, "side": 1.0 if randf() < 0.5 else -1.0,
		"dpos": Vector3.ZERO, "dz": 0.0, "dlat": 0.0}
	if OS.get_environment("KCDBG") != "":
		print("KCDBG imp=", dzl, " lz=", wrapf(dzl.x, T.ZST, T.ZST + T.LAP), " tun=", T.in_tun(wrapf(dzl.x, T.ZST, T.ZST + T.LAP), 8.0))
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
	# Vorlauf normal, Anflug etwas langsamer, Einschlag lange in starker Zeitlupe (Trümmer fliegen), dann Rundflug
	var rate = 1.0 if rel < -1.6 else (0.55 if rel < -0.4 else (0.2 if rel < 0.9 else 0.6))
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
	kco.rp.visible = fmod(tt, 1.4) < 1.0
	kco.ts.text = "%s   ×%.2f" % [_fmt(maxf(0.0, rp.t)), rate]
	hud.top.text = kc.top
	if rp.t >= kc.end:
		_kc_end()


func _kc_end() -> void:
	if kc.is_empty():
		return
	_bc("killcam end")
	_dg_flush()
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
			_qf(e.mi)
			_qf(e.l)
	zaps = keep_z
	for n in get_children():
		if not kc.before.has(n) and not tun_l.has(n) and not n.has_meta("keep") and (n is GPUParticles3D or n is MeshInstance3D or n is OmniLight3D or n.has_meta("deb")):
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


# nur zum Testen: Bilder der Kill-Cam zu bestimmten Zeiten relativ zum Treffer (KCSHOT="-1.0,0.2", Pfad SHOTPATH)
func _kc_shot(rel: float) -> void:
	if OS.get_environment("KCSHOT") == "":
		return
	var ks = OS.get_environment("KCSHOT").split(",")
	var kk = int(kc.get("sk", 0))
	if kk < ks.size() and rel >= float(ks[kk]):
		kc.sk = kk + 1
		var kpath = OS.get_environment("SHOTPATH").replace(".png", "_%d.png" % kk)
		if OS.get_environment("KCX") == "nofx":
			for nd in get_tree().root.find_children("*", "GPUParticles3D", true, false):
				(nd as Node3D).visible = false
		if OS.get_environment("KCX") == "noq":
			_rset("qs", 0.0)
			_rset("qs2", 0.0)
		if OS.get_environment("KCX") == "nolight":
			for nd in get_tree().root.find_children("*", "OmniLight3D", true, false):
				(nd as Node3D).visible = false
		if OS.get_environment("KCNEAR") != "":
			for nd in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
				var gi: GeometryInstance3D = nd
				if gi.is_visible_in_tree():
					var ab: AABB = gi.global_transform * gi.get_aabb()
					var cp: Vector3 = cam.global_position
					var dd = (ab.get_center() - cp).length()
					if dd < 9.0 or ab.has_point(cp):
						print("NEAR k=", kk, " ", gi.get_path(), " cls=", gi.get_class(), " d=", snappedf(dd, 0.1), " size=", ab.size, " mat=", gi.material_override.resource_name if gi.material_override else "")
		get_tree().process_frame.connect(func(): get_viewport().get_texture().get_image().save_png(kpath), CONNECT_ONE_SHOT)


# Abstand der Einschlag-Kamera so wählen, dass sie nicht direkt in einem der Leuchtringe über der Strecke steht
# (die Ringe füllten sonst als grellweiße Bögen das Bild)
func _kc_free_d(z: float, dir: float, base: float) -> float:
	for dd in [0.0, -1.0, 1.0, -2.0, 2.0, -3.0, 3.0]:
		var d = base + dd
		var lz = T.lz(z + d * dir)
		var ok = true
		for rz in ([] if _jungle() else T.RINGS):
			if absf(lz - float(rz)) < 2.4:
				ok = false
				break
		if ok:
			return d
	return base


func _kc_cam() -> bool:
	# Blitz und Überbelichtung in der Kill-Cam schnell abklingen lassen (vorher blieb das Bild beim Einschlag weiß stehen)
	_flash_fade(0.06)
	expo_v = minf(expo_v, 0.3)
	# Kill-Cam je nach Waffe: Rakete = Kamera fliegt auf der Rakete mit; Schockwelle = reitet auf der Welle;
	# Mine = flach auf der Fahrbahn neben der Mine; Kraftfeld & Rest = von hinten. Nach dem Knall: kurzer Rundflug über den Trümmern.
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
	var fr: Dictionary = rec[mini(rp.i, rec.size() - 1)]
	var g0: Dictionary = ships[0]
	var rel = rp.t - kc.t0
	if rel >= -0.4 and rel < 0.9:
		# Einschlag: feste Kamera mit Abstand, schräg von vorn-seitlich und etwas erhöht – man sieht das Schiff
		# hereinrasen, den Treffer und die Brocken fliegen
		var ip: Vector2 = kc.imp
		var fi = T.frame(ip.x)
		var I: Vector3 = fi.c + fi.rr * ip.y + fi.uu * 0.3
		var sdi = sd if absf(ip.y) < 1.2 else -signf(ip.y)
		var lat_c = clampf(ip.y + sdi * 2.6, -(T.TW - 0.25), T.TW - 0.25)   # innerhalb der Banden (sonst steht die Wand im Bild)
		if T.in_tun(T.lz(ip.x), 3.0):
			# im Tunnel: tiefer und näher, sonst steckt die Kamera in der Decke
			lat_c = clampf(ip.y + sdi * 1.6, -(T.TW - 0.45), T.TW - 0.45)
			cam.global_position = fi.c + fi.rr * lat_c + fi.fw * 6.0 + fi.uu * 0.95
			cam.look_at(I - fi.fw * 0.3, fi.uu)
		else:
			if kc.kind in ["quake", "mega", "wave"]:
				# Bebenwelle: Kamera steht dort, wo die Welle herkommt, und schaut ihr nach – der glühende Kamm rollt
				# vom Bild weg aufs Opfer zu, statt direkt durch die Kamera (das machte alles weiß)
				var qd: float = kc.get("qd", 1.0)
				cam.global_position = fi.c + fi.rr * lat_c * 0.6 - fi.fw * (_kc_free_d(ip.x, -qd, 17.0) * qd) + up * 6.0
				cam.look_at(I + fi.fw * (1.5 * qd), up)
				if OS.get_environment("KCDBG") != "":
					print("KCI rel=", snappedf(rel, 0.01), " wavedir=", qd, " camfw·wavedir=", snappedf((-cam.global_transform.basis.z).dot(fi.fw * qd), 0.02))
			else:
				cam.global_position = fi.c + fi.rr * (lat_c * 0.55) + fi.fw * _kc_free_d(ip.x, 1.0, 14.0) + up * 4.4   # eher mittig: am Rand stehen Laternen
				cam.look_at(I - fi.fw * 0.4, up)
		cam.fov = 52.0
		# Bebenwelle in der Zeitlupe nur angedeutet: der glühende Fahrbahnkamm brennt sonst als weiße Fläche das halbe Bild aus
		if kc.kind in ["quake", "mega", "wave"]:
			var qf = clampf((rel + 0.4) / 0.25, 0.0, 1.0)
			var f0q: Dictionary = rec[mini(rp.i, rec.size() - 1)]
			_rset("qs", (float(f0q.q[1]) if f0q.get("q") != null else 0.0) * (1.0 - qf))
			_rset("qs2", (float(f0q.q2[1]) if f0q.get("q2") != null else 0.0) * (1.0 - qf))
		# andere Schiffe, die dicht an der Kamera vorbeirasen (meist du selbst), ausblenden – sonst füllt ein greller Rumpf das Bild
		for o in ships:
			if o.idx != kc.victim and (o.node as Node3D).visible and (o.node as Node3D).global_position.distance_to(cam.global_position) < 7.0:
				(o.node as Node3D).visible = false
		_kc_shot(rel)
		return true
	# Rakete: deine Rakete suchen, die das Opfer trifft (die nächste hinter ihm, nur deine, nur vorwärts geflogen)
	var rk = null
	if alive and kc.kind == "rocket":
		var best = 1e9
		for w in fr.get("w", []):
			if (w as Array).size() >= 4 and (int(w[2]) != 0 or float(w[3]) < 0.0):
				continue
			var dz = z - float(w[0])
			if dz > -0.5 and dz < 60.0 and dz < best:
				best = dz
				rk = w
	if rk != null:
		# Kamera fliegt mit: knapp hinter und etwas über der Rakete, Blick in Flugrichtung aufs Ziel
		var fs = T.frame(float(rk[0]))
		var S: Vector3 = fs.c + fs.rr * float(rk[1]) + fs.uu * 0.25
		var dirv: Vector3 = fs.fw
		var fp: Dictionary = rec[maxi(0, mini(rp.i, rec.size() - 1) - 3)]
		var bp = null
		var bd = 1e9
		for w2 in fp.get("w", []):
			if (w2 as Array).size() >= 4 and (int(w2[2]) != 0 or float(w2[3]) < 0.0):
				continue
			var dd = absf(float(w2[0]) - float(rk[0])) + absf(float(w2[1]) - float(rk[1]))
			if dd < bd:
				bd = dd
				bp = w2
		if bp != null and bd < 6.0:
			var fb = T.frame(float(bp[0]))
			var P: Vector3 = fb.c + fb.rr * float(bp[1]) + fb.uu * 0.25
			if (S - P).length() > 0.05:
				dirv = (S - P).normalized()
		if dirv.dot(fs.fw) < 0.3:
			dirv = fs.fw
		var dist = (V - S).length()
		# Kamera auf der Linie Ziel–Rakete, knapp dahinter: Rakete mittig unten im Bild, Ziel genau davor
		var los: Vector3 = (V - S).normalized()
		if los.dot(dirv) < 0.3:
			los = dirv
		ro = S - los * 2.0 + fs.uu * 0.22
		ta = S + los * 30.0 + fs.uu * 0.12
		cam.global_position = ro
		cam.look_at(ta, up)
		# Zoom: weit weg = Teleblick (Ziel gut zu sehen), kurz vorm Treffer weitwinklig
		cam.fov = lerpf(55.0, 30.0, clampf((dist - 4.0) / 20.0, 0.0, 1.0))
		kc.rk_dot = (-cam.global_transform.basis.z).dot((V - ro).normalized())
		kc.rk_fly = dirv.dot((V - S).normalized())
		if OS.get_environment("KCDBG") != "":
			print("KCR rel=", snappedf(rel, 0.01), " cam->victim=", snappedf(kc.rk_dot, 0.02), " rocketdir->victim=", snappedf(kc.rk_fly, 0.02), " dist=", snappedf(dist, 0.1), " fov=", snappedf(cam.fov, 1), " own=", rk[2] if (rk as Array).size() > 2 else -1)
		_kc_shot(rel)
		return true
	if alive and rp.t < kc.t0 - 1.6 and not g0.out:
		# Vorlauf: über deine Schulter, Blick auf den Gegner – so sieht man, wie es dazu kam
		var fg = T.frame(g0.z)
		var G: Vector3 = fg.c + fg.rr * g0.lat + fg.uu * (0.3 + g0.h)
		ro = G - fg.fw * 2.6 + up * 1.1 + fg.rr * (0.5 * sd)
		ta = G.lerp(V, 0.7)
	elif alive:
		match kc.kind:
			"rocket":
				ro = V - f.fw * 4.0 + up * 0.8
				ta = V
			"quake", "mega", "wave":
				# die Welle, die das Opfer erwischt: vorwärts (q) oder rückwärts (q2) – die näher am Opfer
				var qz = z - 3.0
				var qd = 1.0
				var qb = 1e9
				for qk in [["q", 1.0], ["q2", -1.0]]:
					if fr.get(qk[0]) != null:
						var wz = float(fr[qk[0]][0])
						var dd = absf(wrapf(z - wz, -T.LAP * 0.5, T.LAP * 0.5))
						if dd < qb:
							qb = dd
							qz = wz
							qd = qk[1]
				# Kamera reitet hinter dem Kamm mit und schaut in Laufrichtung der Welle aufs Opfer
				var fq = T.frame(qz)
				ro = fq.c + fq.uu * 1.0 - fq.fw * (2.2 * qd) + fq.rr * (0.6 * sd)
				var wf: Vector3 = fq.fw * qd
				ta = V if (V - ro).normalized().dot(wf) > 0.2 else fq.c + wf * 6.0 + fq.uu * 0.3
				if OS.get_environment("KCDBG") != "":
					print("KCQ rel=", snappedf(rel, 0.01), " wavedir=", qd, " camfw·wavedir=", snappedf((ta - ro).normalized().dot(wf), 0.02), " camfw·toVictim=", snappedf((ta - ro).normalized().dot((V - ro).normalized()), 0.02), " wave-victim=", snappedf(wrapf(z - qz, -T.LAP * 0.5, T.LAP * 0.5), 0.1))
			"mine":
				# flach neben der Mine, die vor dem Opfer liegt; der Gegner rast drüber
				var mz = z + 3.0
				var ml = lat
				var bm = 1e9
				for m in fr.get("m", []):
					var dz = float(m[0]) - z
					if dz > -1.0 and dz < bm:
						bm = dz
						mz = float(m[0])
						ml = float(m[1])
				var fm = T.frame(mz)
				ro = fm.c + fm.rr * (ml + 0.9 * sd) + fm.uu * 0.12 + fm.fw * 1.2
				ta = V
			_:
				ro = V - f.fw * 4.2 + up * 1.0 + f.rr * (0.8 * sd)
				ta = V + f.fw * 2.0
	else:
		# Rundflug von schräg oben um die Trümmer (Mitte = Schwerpunkt der Brocken dieses Knalls)
		var C = V
		var cn = 0
		var acc = Vector3.ZERO
		for d in debris:
			if is_instance_valid(d.n) and (d.n as Node3D).visible:
				var p: Vector3 = (d.n as Node3D).global_position
				if p.distance_to(V) < 25.0:
					acc += p
					cn += 1
		if cn > 0:
			C = C.lerp(acc / cn, 0.6)
		var k = clampf((rp.t - kc.t0 - 0.9) / 1.5, 0.0, 1.0)
		var a = sd * (0.6 + k * 1.6)
		if T.in_tun(T.lz(z), 3.0):
			# im Tunnel enger und flacher kreisen
			ro = C + (f.fw * cos(a) + f.rr * sin(a) * 0.7) * (1.7 + k * 0.4) + f.uu * (0.75 + k * 0.15)
			up = f.uu
		else:
			ro = C + (f.fw * cos(a) + f.rr * sin(a)) * (2.4 + k * 1.0) + up * (1.5 + k * 0.6)
		ta = C
	cam.global_position = ro
	cam.look_at(ta, up)
	cam.fov = 55.0
	_kc_shot(rel)
	if OS.get_environment("KCDBG") != "":
		var cf: Vector3 = -cam.global_transform.basis.z
		print("KCV rel=", snappedf(rel, 0.01), " alive=", alive, " camfw·toVictim=", snappedf(cf.dot((V - ro).normalized()), 0.02), " camfw·trackfw=", snappedf(cf.dot(f.fw), 0.02), " camz-vz=", snappedf((ro - V).dot(f.fw), 0.1), " shots=", fr.get("w", []).size())
	_flash_fade(0.05)
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
		_snd("minewarn", -2.0)
	lamp.visible = true
	lamp.queue_redraw()


# Ergebnistafel nach dem Rennen
var board_t = 0.0
var board_man = -1   # -1 = wechselt von selbst; 0–3 = von Hand gewählte Seite, bleibt dann stehen
var board_pg = -1    # zuletzt gezeigte Seite (Bestenliste nur beim Umblättern neu laden)
var board_hs = []    # Bestenliste „Fastest race“ für die Tafel
const BOARD_DUR = [5.0, 4.0, 4.0, 4.0]   # Ergebnis, Schaden, Bestenliste 1–4, Bestenliste 5–8


func _board_page() -> int:
	if OS.get_environment("BOARDPG") != "":   # Test: Seite fest einstellen
		return int(OS.get_environment("BOARDPG"))
	if board_man >= 0:
		return board_man
	var t = fmod(board_t, 17.0)
	for i in range(4):
		if t < BOARD_DUR[i]:
			return i
		t -= BOARD_DUR[i]
	return 0


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
	var pg = _board_page()
	if pg >= 2:
		if board_pg != pg:
			var c = ConfigFile.new()
			c.load(REC_PATH)
			board_hs = _rec_list(c, _rec_key(), "total")
		board_pg = pg
		var a0 = (pg - 2) * 4
		hud.boardt.text = "HIGHSCORE  %d–%d" % [a0 + 1, a0 + 4]
		for i in range(4):
			var cols2: Array = hud.rows[i]
			var r = a0 + i
			cols2[0].text = "%d." % (r + 1)
			if r < board_hs.size():
				cols2[1].text = str(board_hs[r][1]).to_upper()
				cols2[2].text = _fmt(float(board_hs[r][0]))
			else:
				cols2[1].text = "—"
				cols2[2].text = ""
			# eigene Zeit aus diesem Rennen hervorheben
			var mine = r < board_hs.size() and ships[0].fin > 0.0 and absf(float(board_hs[r][0]) - float(ships[0].fin)) < 0.005
			for l in cols2:
				l.modulate = Color(1, 0.85, 0.4) if mine else Color(1, 1, 1)
		return
	board_pg = pg
	var dmg_mode = pg == 1
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
	# Fahrphysik wie im HTML-Spiel: die Nase lenkt, die Flugrichtung folgt mit begrenzter Haftung
	s.u += (inp - s.u) * (1.0 - exp(-dt / (0.03 if is_p else 0.08)))
	var turn: float = T.kap(z) * s.spd
	var yk = YAW_P * float(fx.steer.power) if is_p else YAW_AI
	if is_p:
		# bei hohem Tempo etwas sanfter (fest eingebaut, war dein Wunsch)
		s.sps = lerpf(float(s.get("sps", s.spd)), s.spd, 1.0 - exp(-dt / 0.5))
		yk /= 1.0 + 0.25 * maxf(0.0, float(s.sps) / maxf(1.0, base_spd) - 0.8)
	s.psi = clampf(s.psi + (s.u * yk + turn) * dt, -0.9, 0.9)
	if is_p and not s.air:
		# loslassen: die Nase stellt sich wieder gerade (fest eingebaut, war dein Wunsch)
		var ce = 4.0 * (1.0 - clampf(absf(s.u) * 1.6, 0.0, 1.0))
		s.psi -= s.psi * (1.0 - exp(-dt * ce))
	var grip = 0.8 if s.air else (9.5 if is_p else 7.0)
	var on_w = not s.air and T.in_water(T.lz(z))
	if on_w:
		grip *= 0.3   # über Wasser: wenig Haftung, das Heck schwimmt
	s.vpsi = clampf(s.vpsi + ((s.psi - s.vpsi) * grip + turn) * dt, -0.9, 0.9)
	if is_p and not s.air and racing and not s.out:
		_assist(s, dt)
	var ap = is_p and (s.auto > 0.0 or state == "done" or state == "replay" or not mc.is_empty()) and not s.out
	if ap:
		# Autopilot wie im alten Spiel: ruhig auf die Mittellinie gleiten, dann schnurgerade, nichts bremst ihn
		s.u = 0.0
		var dl = (0.0 - s.lat) * (1.0 - exp(-dt / 1.4))
		s.vpsi = atan2(dl / maxf(dt, 1e-4), maxf(1.0, s.spd))
		s.psi += (s.vpsi - s.psi) * (1.0 - exp(-dt / 0.15))
		s.slow = 1.0
		s.slowT = 0.0
	s.slow += (1.0 - s.slow) * (1.0 - exp(-dt / 1.4))
	s.boost *= exp(-dt / 1.4)
	if s.out:
		s.spd = 0.0
		return
	if s.slowT > 0.0:
		s.slowT -= dt
	s.spd = base_spd * s.sk * (1.0 + 0.6 * s.boost) * s.slow * (0.75 if s.slowT > 0.0 else 1.0) if (racing or state == "done") and not party_on else 0.0
	if on_w:
		s.spd *= 0.92   # Wasser bremst etwas
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
	# Schutzschild-Röhre um die Strecke: wer über die Leitplanke hinausfliegt oder zu hoch springt, prallt ab –
	# Schild blitzt auf, kleiner Energieverlust, etwas Tempo weg
	if s.air and not s.out:
		var slim = T.TW + 0.1
		if absf(s.lat) > slim and signf(s.lat) == signf(sin(s.vpsi)):
			var sd = signf(s.lat)
			s.lat = sd * slim
			s.vpsi = -s.vpsi * 0.6
			s.psi = -s.psi * 0.6
			_ship_shield_hit(s, Vector3(sd, 0.0, 0.0))
		elif absf(s.lat) > slim:
			s.lat = signf(s.lat) * slim
		if s.h > SHIELD_H - 0.25 and s.vy > 0.0:
			s.h = SHIELD_H - 0.25
			s.vy = -s.vy * 0.4
			_ship_shield_hit(s, Vector3(0.0, 1.0, 0.0))
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
	var ml = T.lim(s.z) - 0.3
	if T.pipe_full(s.z):
		# geschlossene Röhre: keine Bande, einmal rundherum kommt man auf der anderen Seite wieder an
		var circ = TAU * T.PR
		if absf(s.lat) > circ * 0.5:
			s.lat -= signf(s.lat) * circ
	elif absf(s.lat) > ml and not s.air and T.pipe_k(s.z) > 0.001:
		# Übergang Röhre → Bahn: wer zu weit oben fährt, wird sanft die Wand hinunter getragen (keine Bande, kein Abbremsen)
		s.lat = signf(s.lat) * ml
		s.vpsi -= s.vpsi * minf(1.0, dt * 3.0)
	elif absf(s.lat) > ml and not s.air:
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
				_vib(45, 0.6)
	# Boost-Feld
	var k = int(round(s.z / 35.0))
	var fz = (s.z - _bzp(k)) / 35.0
	if fz >= 0.0 and fz < 0.08 and _pad_ok(_bzp(k)) and not s.air and absf(s.lat - _bpx(k)) < PAD_HW and k != s.padK and racing:
		s.padK = k
		s.boost = 1.0
		if is_p:
			_snd("boost", -3.0)
			_vib(55, 1.0)
			get_tree().create_timer(0.09).timeout.connect(func(): _vib(140, 0.6))


# Gegner fahren ruhig: eigene Spur, sanft zur Kurvenaußenseite (Boost-Felder), Regler auf Wunsch-Querbewegung statt Pendeln
func _ai_inp(o: Dictionary, t: float, dt: float) -> float:
	var zz: float = o.z
	var spd = maxf(1.0, o.spd)
	var d2 = T.d2px(zz + 14.0)
	var tg = o.lane + signf(d2) * minf(0.5, absf(d2) * 45.0)
	if T.pipe_k(zz + 14.0) > 0.9:
		tg = 0.75 * PI * T.PR * sin(zz * 0.03 + float(o.ai) * 1.7)   # in der Röhre: Gegner kreisen an Wände und Decke
	var bk = float(o.get("blk", 0.0))
	if bk > 0.0:
		# geblendet: schlingert unsicher hin und her und trifft öfter die Bande
		tg += (sin(race_t * 1.25 + float(o.ai)) * 1.4 + sin(race_t * 2.9 + float(o.ai) * 2.3) * 0.7) * clampf(bk, 0.0, 1.0)
	o.tl += (tg - o.tl) * (1.0 - exp(-dt / (0.5 if bk > 0.0 else 1.2)))
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
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_APPLICATION_RESUMED:
		_dg_mark("run")
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		_dg_mark("exit")
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		_bc("app in background")
		_dg_flush()
		_dg_mark("bg")
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
const BENCH = [["base", "Everything on (your settings)"], ["msaa2", "Edge smoothing MSAA 2×"], ["msaa4", "Edge smoothing MSAA 4×"], ["fxaa", "Edge smoothing FXAA"], ["res75", "Resolution 75 %"], ["fsr", "Resolution 75 % + FSR sharpening"],
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
		"msaa2":
			vp.msaa_3d = Viewport.MSAA_2X
		"msaa4":
			vp.msaa_3d = Viewport.MSAA_4X
		"fxaa":
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
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
	t += "Settings: gfx %s · res %d %% · 3D scale %.2f · MSAA %s · fps cap %s · refresh %d Hz\n\n" % [["Low", "Medium", "High"][int(cfg.gfx)], int(float(cfg.res) * 100),
		get_viewport().scaling_3d_scale, ["off", "2×", "4×", "8×"][clampi(int(get_viewport().msaa_3d), 0, 3)], "60" if int(cfg.cap) == 1 else "max", maxi(0, int(DisplayServer.screen_get_refresh_rate()))]
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
	return "speed%d" % int(round(float(cfg.speed) * 100.0)) + ("x" if T.X else "") + ("" if T.LAPS == 3 else "_l%d" % T.LAPS)   # Extreme und 5-Runden-Rennen haben eigene Bestenlisten


const REC_N = 8   # Plätze je Liste (auf der Ergebnistafel als zwei Seiten à vier)
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
	var rg = race_gen
	get_tree().create_timer(1.2).timeout.connect(func():
		if rg == race_gen:   # nicht mehr, wenn inzwischen „Race again“ getippt wurde
			_name_entry(hits))


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
	# kein automatischer Fokus: die Tastatur kommt erst, wenn man ins Feld tippt (der gespeicherte Name steht schon drin)


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
	if deco != null and not party_on:
		deco.position = Vector3(0, 0, l0 * T.LAP)
	blimp_off = l0 * T.LAP
	for i in range(laps.size()):
		var p = Vector3(0, 0, (l0 - 1 + i) * T.LAP)
		if laps[i].position != p:
			laps[i].position = p


func _process(delta: float) -> void:
	var dt = minf(delta, 0.05)
	# Blitz und Explosions-Helligkeit klingen in JEDEM Zustand ab (vorher nur in einzelnen Kameras –
	# beim Rennende blieb das Bild sonst überstrahlt hängen, bis in die Siegerfeier)
	_flash_fade(dt * 2.2)
	expo_v = maxf(0.0, expo_v - dt * 2.2)
	if wenv != null and wenv.tonemap_exposure != 1.0 + expo_v:
		wenv.tonemap_exposure = 1.0 + expo_v
	if flash_rect != null and flash_rect.visible and flash_rect.color.a <= 0.003:
		flash_rect.visible = false   # unsichtbare Vollbild-Fläche nicht jedes Bild zeichnen
	t_state += dt
	_cp("frame")
	_dg_tick(delta)
	_measure(delta)
	_live_poll(dt)
	_duck(delta / maxf(0.01, Engine.time_scale))
	_perf(delta)
	var g: Dictionary = ships[0]
	if warm_t >= 0.0:
		_warm_step(delta)
	if state == "menu" and bench_req and warm_t < 0.0 and not dg_reloading:   # nicht die alte Szene, die gerade neu geladen wird
		bench_req = false
		_bench_begin()
	if state == "bench":
		_bench_step(dt)
		return
	if state == "menu" and restart and warm_t < 0.0 and rpf.is_empty() and not dg_reloading:
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
		_cp("kc_step")
		_kc_step(dt)
		_cp("kc_view")
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
	_cp("fin_update")
	_fin_update(dt)
	if not cm.is_empty():
		_cp("comic_update")
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
	# Lenkung wie im HTML-Spiel: linke oder rechte Bildschirmhälfte halten. Erst gleich gut die Hälfte Kraft,
	# dann steigt sie in „Reaktion“ Sekunden auf voll (Kurve wie damals: 0,55 + 0,45 · x^2,3)
	var b = _steer_input()
	if b != steer_btn:
		steer_btn = b
		btn_t = 0.0
	btn_t += dt
	var steer = 0.0
	if b != 0:
		var x = minf(1.0, btn_t / maxf(0.05, float(fx.steer.ramp)))
		steer = b * (0.55 + 0.45 * pow(x, 2.3))
	last_steer = steer
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
	if OS.get_environment("QFAKE") != "":
		_rset("qz", float(OS.get_environment("QFAKE")))   # nur zum Testen: stehende Bebenwelle
		_rset("qs", 1.3)
	if OS.get_environment("PLAT") != "" and racing and T.pipe_k(g.z) > 0.5:
		g.lat = float(OS.get_environment("PLAT"))   # nur zum Testen: Spieler auf feste Stelle der Röhre (Wand, Decke)
	if OS.get_environment("SPDT") != "" and racing:
		g.boost = float(OS.get_environment("SPDT"))   # nur zum Testen: fester Boost-Wert (Tempo-Effekte ansehen)
	if OS.get_environment("BOT") != "" and Engine.get_process_frames() % 300 == 0:
		var outs = 0
		for o in ships:
			outs += 1 if o.out else 0
		print("BOT f=", Engine.get_process_frames(), " state=", state, " t=", snappedf(race_t, 0.1), " z=", snappedf(g.z, 1.0), " out=", outs, " en=", snappedf(g.en, 0.01), " shots=", shots.size(), " debris=", debris.size(), " kids=", get_child_count())
	if OS.get_environment("BOTK") != "" and racing:
		for i in range(1, ships.size()):
			ships[i].en = minf(ships[i].en, float(OS.get_environment("BOTK")))   # nur zum Testen: Gegner fast kaputt → viele K.o. kurz hintereinander
		g.en = 1.0
	if OS.get_environment("BOT") != "" and racing and not g.out:
		# nur zum Testen: Spieler fährt wie ein Gegner und schießt alles ab, was er aufsammelt
		if not g.has("lane"):
			g.lane = 0.0
			g.tl = g.lat
		steer = _ai_inp(g, Time.get_ticks_msec() / 1000.0, dt)
		if g.wpn != "" and randf() < 0.03:
			_fire()
	_cp("phys_player")
	for k in range(n):
		_phys(g, steer, true, hdt, racing)
	_cp("ai")
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
			if lk < T.LAPS:
				_snd("lap", -3.0)
				if lk == T.LAPS - 1:
					_stadium("an_final", 0.0)
					get_tree().create_timer(2.0).timeout.connect(func(): _snd("vo_final", 3.0))
			# schneller als jede gespeicherte Runde (Bestenliste dieser Strecke)?
			if lt > 1.0 and not free_ride and not T.S:
				var rc = ConfigFile.new()
				rc.load(REC_PATH)
				var rl = _rec_list(rc, _rec_key(), "lap")
				if rl.is_empty() or lt < float(rl[0][0]):
					get_tree().create_timer(1.6 if lk == T.LAPS - 1 else 0.6).timeout.connect(func(): _snd("vo_lrec", 3.0))
	# Ziel
	var finish = T.ZST + T.LAPS * T.LAP
	var place = 1
	for i in range(1, ships.size()):
		if ships[i].z > g.z and not ships[i].out:
			place += 1
	_cp("collide")
	_collide(dt)
	_cp("debris")
	_debris_update(dt)
	_cp("props")
	_props_update(dt)
	_cp("charge")
	_chg_update(dt, racing)
	_cp("weapons")
	_weapons(dt, racing)
	_cp("mine_warn")
	_mine_warn(dt, racing)
	_cp("race_end_check")
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
		_snd("win", 2.5)
		get_tree().create_timer(0.9).timeout.connect(func(): _snd("vo_p1", 3.0))
		hud.res.text = "1st  ·  LAST ONE STANDING\n%s" % _fmt(race_t)
		_fin_flow(1)
		_records_end(false)
	elif racing and g.z >= finish and not free_ride:
		state = "done"
		t_state = 0.0
		g.fin = race_t
		_snd("win", 2.5 if place == 1 else -1.0)
		var pv = "vo_p%d" % clampi(place, 1, 4)
		_stadium("an_p%d" % clampi(place, 1, 4), 0.0)
		_snd("crowd_roar", -2.0 if place == 1 else -6.0)
		if place == 1:
			get_tree().create_timer(3.0).timeout.connect(func(): _stadium("an_wow", 0.0))
		get_tree().create_timer(3.4 if place == 1 else 1.6).timeout.connect(func(): _snd(pv, 3.0))
		hud.res.text = "%s  ·  %s" % [["1st", "2nd", "3rd", "4th"][place - 1], _fmt(race_t)]
		_fin_flow(place)
		_records_end(true)
	_cp("board")
	_board_update(dt)
	_resb_arm(dt)
	_cp("hud")
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
	_cp("record")
	_record(dt)
	_cp("kc_check")
	_kc_check()
	# Rundenkopien mitwandern lassen
	_cp("lap_tunnel")
	_lap_pos(g.z)
	_tunnel(dt)
	_cp("pose")
	_pose_all(dt)
	_cp("camera")
	_camera(dt)
	_cp("sound")
	_sound_update(dt)
	_cp("post")
	_post_update(dt)
	_cp("end")
	_shot()


# ---------------------------------------------------------------- FX Lab: Teststrecke für alle Effekte, mit Reglern
const LZ = 40.0
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
		for tu in T.tuns():
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
	_flash_fade(dt * 2.2)
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
		for a in (OS.get_cmdline_user_args() if OS.get_environment("AG_RELOADED") == "" else []):
			if a.begins_with("--shot="):
				shot_s = a
	if shot_s == "":
		return
	if OS.get_environment("CMTAP") != "":
		# nur zum Testen: Daumen-Tipps während des Comics simulieren und mitschreiben, was der Comic macht
		var fr_n = Engine.get_process_frames()
		var vs: Vector2 = get_viewport().get_visible_rect().size
		for ft in OS.get_environment("CMTAP").split(","):
			for ph in [0, 2]:
				if fr_n == int(ft) + ph:
					var te = InputEventScreenTouch.new()
					te.index = 0
					te.position = Vector2(vs.x * 0.15, vs.y * 0.85)
					te.pressed = ph == 0
					Input.parse_input_event(te)
					# wie auf dem Handy: der erste Finger kommt zusätzlich als Maus-Klick an
					var me = InputEventMouseButton.new()
					me.button_index = MOUSE_BUTTON_LEFT
					me.position = te.position
					me.global_position = te.position
					me.pressed = te.pressed
					Input.parse_input_event(me)
		if fr_n % 10 == 0 and cm.has("t"):
			print("CMT f=", fr_n, " t=", snappedf(cm.t, 0.01), " skip=", snappedf(cm.skip, 0.01), " fade=", snappedf(float(cm.get("fade", 1.0)), 0.01), " fingers=", fingers.size())
		if OS.get_environment("CMSKIP") != "" and fr_n == int(OS.get_environment("CMSKIP")) and cm.has("sb"):
			(cm.sb as Button).pressed.emit()
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
			if shot_n == 2 and p.size() > 2 and p[2] != "menu" and p[2] != "stay":
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
					if OS.get_environment("MAGT") != "":   # Test: neben die nächste Waffensäule setzen (Magnet)
						var mk = int(ceil((float(ships[0].z) - 17.0) / 35.0))
						if posmod(mk, 2) != 0:
							mk += 1
						ships[0].lat = _wpx(mk) + float(OS.get_environment("MAGT"))
						print("MAGT pad z=", _wzp(mk), " lat=", _wpx(mk))
					if OS.get_environment("PLUMET") != "":   # Test: Gegner direkt vor dich setzen (Gischtfahne)
						ships[1].z = ships[0].z + float(OS.get_environment("PLUMET"))
						ships[1].lat = ships[0].lat
						ships[1].spd = ships[0].spd
				if OS.get_environment("MCT") != "":   # Test: Gegner vor dich setzen und Lenkrakete feuern (Raketenkamera)
					if shot_n == 30:
						ships[1].z = ships[0].z + float(OS.get_environment("MCT"))
						ships[1].lat = ships[0].lat + float(OS.get_environment("MCL")) if OS.get_environment("MCL") != "" else ships[0].lat + 0.8
						if OS.get_environment("MCB") != "":
							ships[1].boost = float(OS.get_environment("MCB"))
						if OS.get_environment("MCRAK") != "":
							_fire_w(ships[0], "rak", false)
						elif OS.get_environment("MCMEGA") != "":
							_fire_mega(ships[0], "lenk")
						else:
							_fire_w(ships[0], "lenk", false)
					if shot_n % 4 == 0:
						print("MC n=", shot_n, " on=", not mc.is_empty(), " hold=", snappedf(float(mc.get("hold", -9.0)), 0.01), " camd=", snappedf(cam.global_position.distance_to((ships[0].node as Node3D).global_position), 0.1), " lat=", snappedf(float(ships[0].lat), 0.01), " shots=", shots.size(), " spd=", snappedf(float(ships[0].spd), 0.1), "/", snappedf(float(ships[1].spd), 0.1), " dz=", snappedf(float(ships[1].z) - (float(shots[0].z) if shots.size() > 0 else 0.0), 0.1), " base=", base_spd)
				if OS.get_environment("WALLT") != "":   # Test: eigene Wand, durchfahren, dann Rakete von hinten
					if shot_n == 20:
						_fire_w(ships[0], "wand", false)
					if shot_n == int(OS.get_environment("WALLT")):
						ships[1].z = ships[0].z - 8.0
						ships[1].lat = ships[0].lat
						_add_shot(ships[1], false, true)
						print("WALLT fire z=", ships[0].z, " wall=", walls[0].z if not walls.is_empty() else -1)
					if shot_n % 5 == 0:
						print("WALLT n=", shot_n, " pz=", snappedf(float(ships[0].z), 0.1), " shots=", shots.size(), " en=", snappedf(float(ships[0].en), 0.01))
				if OS.get_environment("BLKFIRE") != "":   # Test: du feuerst Blackout
					if shot_n == 40:
						_blackout(ships[0], 5.0)
					if shot_n % 10 == 0:
						print("BLK n=", shot_n, " ", ships.map(func(x): return [snappedf(float(x.lat), 0.01), snappedf(float(x.get("blk", 0.0)), 0.1), snappedf(float(x.spd), 0.1)]))
				if OS.get_environment("MAGT") != "" and shot_n % 5 == 0:
					print("MAG z=", snappedf(float(ships[0].z), 0.1), " lat=", snappedf(float(ships[0].lat), 0.01), " wpn=", ships[0].wpn)
				if OS.get_environment("PLUMET") != "" and shot_n % 10 == 0:
					print("PLUME z=", snappedf(float(ships[0].z), 0.1), " lat=", snappedf(float(ships[0].lat), 0.01), " ai z=", snappedf(float(ships[1].z), 0.1), " lat=", snappedf(float(ships[1].lat), 0.01), " blind=", snappedf(blind, 0.01))
				return
			if shot_s.contains("resbtest") and shot_n % 50 == 0 and hud.has("resb"):
				print("RESB n=", shot_n, " a=", (hud.resb as CanvasItem).modulate.a, " armed=", resb_armed, " t=", resb_t, " fingers=", fingers.size(), " vis=", hud.resb.visible)
			if shot_n == 50 and shot_s.contains("resbtest"):
				state = "done"
				t_state = 0.0
				_show_resb()
				if OS.get_environment("SKIPVIEW") != "":   # Test: SKIP-Knopf dazu, um beide Randknöpfe zu sehen
					hud.layer.add_child(_skip_btn())
			if shot_s.contains("locktest") and shot_n >= 41:
				ships[0].wpn = "lenk"
				ships[1].z = ships[0].z + 7.0
				ships[1].lat = ships[0].lat + 1.2
				ships[1].spd = ships[0].spd
			if shot_s.contains("srtest") and shot_n == int(OS.get_environment("SRN") if OS.get_environment("SRN") != "" else "45"):
				if OS.get_environment("SRN") == "":
					print("SR ret=", _soft_reset(), " props=", props.size(), " state=", state)
					state = "race"
				else:
					_race_again()
					print("SR again state=", state)
			if OS.get_environment("SRN") != "" and shot_n == int(OS.get_environment("SRN")) + 200:
				print("MUSIC valid=", is_instance_valid(music_p), " playing=", music_p.playing if is_instance_valid(music_p) else false, " k=", music_k, " f=", music_f)
			if shot_s.contains("srtest") and shot_n == 50:
				print("SR valid=", props.map(func(d): return is_instance_valid(d.n)))
			if shot_s.contains("prtest") and shot_n > 41 and shot_n % 4 == 0:
				print("PRT n=", shot_n, " z=", snappedf(ships[0].z, 0.1), " lat=", snappedf(ships[0].lat, 0.01))
			if shot_s.contains("prtest") and shot_n == 41:
				ships[0].z = 268.0
				ships[0].lat = -1.0
				ships[0].vpsi = 0.0
				ships[0].psi = 0.0
				for i in range(1, ships.size()):
					ships[i].z = ships[0].z - 40.0 - i * 3.0
			if shot_s.contains("shtest"):
				if shot_n == 41:
					ships[0].air = true
					ships[0].h = 0.6
					ships[0].vy = 4.5
					ships[0].lat = 1.6
					ships[0].vpsi = 0.45
					ships[0].psi = 0.45
				if shot_n > 41 and shot_n < 90:
					print("SH n=", shot_n, " lat=", snappedf(ships[0].lat, 0.01), " h=", snappedf(ships[0].h, 0.01), " vpsi=", snappedf(ships[0].vpsi, 0.01), " en=", snappedf(ships[0].en, 0.01), " slow=", snappedf(ships[0].slow, 0.01), " hits=", shield_hits.size())
			if shot_n == 41 and not blimp.is_empty() and OS.get_environment("BLIMPDBG") != "":
				print("BLIMP pos=", (blimp.n as Node3D).global_position, " cam=", cam.global_position, " c=", blimp.c, " r=", blimp.rx, ",", blimp.rz)
			if shot_s.contains("rkctest") and shot_n % 5 == 0:
				print("RKC n=", shot_n, " state=", state, " kcp=", kc_pending, " out1=", ships[1].out, " en1=", ships[1].en, " shots=", shots.map(func(x): return [snappedf(x.z - ships[0].z, 0.1), x.lat]), " z1=", snappedf(ships[1].z - ships[0].z, 0.1), " prot=", _prot(ships[1]))
			if shot_n == 41 and shot_s.contains("rkctest"):
				ships[1].z = ships[0].z + float(OS.get_environment("RKD") if OS.get_environment("RKD") != "" else "14")
				ships[1].lat = ships[0].lat + float(OS.get_environment("RKL") if OS.get_environment("RKL") != "" else "0")
				ships[1].en = 0.05
				ships[1].shield = 0.0
				ships[2].z = ships[0].z - 30.0
				ships[3].z = ships[0].z - 35.0
				ships[0].wpn = "lenk"
				lk_tg = ships[1]
				lk_k = 1.0
				if OS.get_environment("RKQ") == "fwd":
					ships[0].wpn = "beben"
				if OS.get_environment("RKW") != "":
					# nur zum Testen: Waffe und Stufe (z. B. „rak,sup“ oder „lenk,mega“)
					var rw = OS.get_environment("RKW").split(",")
					ships[0].wpn = rw[0]
					ships[0].sup = rw.size() > 1 and rw[1] != ""
					ships[0].mega = rw.size() > 1 and rw[1] == "mega"
					ships[1].en = 1.0
				if OS.get_environment("RKQ") == "back":
					ships[1].z = ships[0].z - float(OS.get_environment("RKD") if OS.get_environment("RKD") != "" else "14")
					quake2 = _quake_make(ships[0].z - 3.0, -1.0, quake2)
				else:
					_fire()
				print("RKC fired shots=", shots.size(), " wpn=", ships[0].wpn)
			if shot_n == 41 and shot_s.contains("dmgtest"):
				ships[0].en = 0.12
				ships[1].en = 0.3
				ships[2].en = 0.5
			if shot_n == 42 and shot_s.contains("kotest"):
				ships[1].z = ships[0].z + 7.0
				ships[1].lat = ships[0].lat + 0.4
				ships[1].shield = 0.0
				_dmg(ships[1], 2.0, -1 if shot_s.contains("kotest2") else 0)
			if shot_s.contains("coltest") and shot_n >= 41 and shot_n <= 44:
				ships[1].z = ships[0].z + 0.6
				ships[1].lat = ships[0].lat + 0.25
				print("COLTEST before z=%.2f/%.2f lat=%.2f/%.2f" % [ships[0].z, ships[1].z, ships[0].lat, ships[1].lat])
			if shot_s.contains("coltest") and shot_n == 46:
				print("COLTEST after z=%.2f/%.2f lat=%.2f/%.2f pairs=%s" % [ships[0].z, ships[1].z, ships[0].lat, ships[1].lat, str(col_pairs)])
			if shot_n == 42 and shot_s.contains("debtest"):
				ships[1].z = ships[0].z + 6.0
				ships[1].lat = ships[0].lat + 0.6
				_pose_all(0.0)
				ships[1].out = true
				if OS.get_environment("DEBSPD") != "":
					ships[1].spd = float(OS.get_environment("DEBSPD"))
					ships[1].z = 60.0
					ships[1].lat = 0.0
					_pose_all(0.0)
				_shatter(ships[1])
				(ships[1].node as Node3D).visible = false
			if shot_s.contains("debtest") and shot_n > 42 and shot_n < 60:
				var ds = ""
				for d in debris:
					ds += "[z%.1f l%.2f h%.2f n%d vis%s] " % [d.z - ships[0].z, d.lat, d.h, (d.n as Node3D).get_child_count(), str((d.n as Node3D).is_visible_in_tree())]
				print("DEB ", shot_n, " ", ds)
				if not debris.is_empty():
					var c0: Node3D = debris[0].n
					var m0: MeshInstance3D = c0.get_child(0)
					print("DEB2 chunk=", c0.global_position, " piece=", m0.global_transform, " ship0=", (ships[0].node as Node3D).global_position, " cam=", cam.global_position, " vis=", m0.is_visible_in_tree(), " layers=", m0.layers)
			if shot_s.contains("frz") and shot_n == int(OS.get_environment("KOF") if OS.get_environment("KOF") != "" else "60"):
				Engine.time_scale = 0.0001   # Test: Trümmer einfrieren, damit die Aufnahme sie zeigt
			if shot_s.contains("chgtest"):
				if shot_n == 41:
					ships[0].z = 50.0
					ships[0].lat = 1.85
					ships[0].vpsi = 0.0
					ships[0].psi = 0.0
					ships[0].en = 0.5
				if shot_n > 41 and shot_n % 5 == 0:
					print("CHG n=", shot_n, " z=", snappedf(ships[0].z, 0.1), " lat=", snappedf(ships[0].lat, 0.01), " en=", snappedf(ships[0].en, 0.001))
			if shot_s.contains("autotest") and shot_n >= 41:
				ships[0].auto = 3.0
			if OS.get_environment("FIN2") != "" and shot_n == int(OS.get_environment("FIN2")):
				print("FIN2 state=", state, " party=", party.is_empty())
				state = "done"
				t_state = 0.0
				_fin_flow(1)
			if OS.get_environment("PTDBG") != "" and shot_n % 100 == 0:
				print("PT n=", shot_n, " state=", state, " fin=", fin.get("phase", -1), " pt=", fin.get("pt", -1), " party=", not party.is_empty())
			if shot_n == 60 and shot_s.contains("finwin"):
				state = "done"
				t_state = 0.0
				_fin_flow(1)
			if shot_n == 60 and shot_s.contains("finlose"):
				state = "done"
				t_state = 0.0
				ships[2].fin = 1.0
				_fin_flow(3)
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
						print("AGAIN soft=", ok, " race0=", race0.size(), " ships0=", ships0.size(), " rpf=", rpf.size(), " vx=", vx.size(), " warm_t=", warm_t)
						_start()
				if shot_n == 64:
					print("AGAIN after kids=", get_child_count(), " fx=", fxs.size(), " mines=", mines.size(), " out2=", ships[2].out, " vis2=", (ships[2].node as Node3D).visible, " z=", ships[0].z, " en2=", ships[2].en, " state=", state, " race_t=", race_t)
			if OS.get_environment("NOSE") != "" and shot_n == 41:
				fx.steer.nosev = float(OS.get_environment("NOSE"))
			if OS.get_environment("NOSE") != "" and shot_n == 53:
				var g0: Dictionary = ships[0]
				var fz = T.frame(g0.z)
				var fwn: Vector3 = (g0.node as Node3D).global_transform.basis.z
				print("NOSETEST roll=%.3f vpsi=%.3f psi=%.3f nodeyaw=%.3f" % [g0.roll, g0.vpsi, g0.psi, atan2(fwn.dot(fz.rr), fwn.dot(fz.fw))])
			if shot_s.contains("holdtest") and state == "race":
				# Test: rechte Hälfte 0,6 s halten, dann loslassen; Lenkung, Querlage und Neigung mitschreiben
				var W = get_viewport().get_visible_rect().size.x
				if shot_n == 45 or shot_n == 57:
					var te = InputEventScreenTouch.new()
					te.index = 0
					te.pressed = shot_n == 45
					te.position = Vector2(W * 0.85, 700)
					_input(te)
				if shot_n == 56:
					var nd0: Node3D = ships[0].node
					var f0 = T.frame(ships[0].z)
					print("HT axes rr=", f0.rr, " shipX=", nd0.global_transform.basis.x, " shipUp=", nd0.global_transform.basis.y, " roll=", ships[0].roll)
					get_viewport().get_texture().get_image().save_png(p[0].replace(".png", "_56.png"))
				if shot_n >= 44 and shot_n <= 80:
					print("HT n=", shot_n, " t=", snappedf(race_t, 0.01), " steer=", snappedf(last_steer, 0.01), " u=", snappedf(ships[0].u, 0.01), " psi=", snappedf(ships[0].psi, 0.01), " lat=", snappedf(ships[0].lat, 0.01), " roll=", snappedf(float(ships[0].get("roll", 0.0)), 0.01))
			if shot_s.contains("assisttest") and state == "race":
				# Test: knapp neben einem Boost-Feld anfliegen – trifft die Lenkhilfe es?
				var g = ships[0]
				if shot_n == 40:
					fx.steer.assist = float(OS.get_environment("ASSIST"))
					var k = int(ceil((g.z + 25.0) / 35.0))
					while not _pad_ok(_bzp(k)):
						k += 1
					g.z = _bzp(k) - 22.0
					g.lat = _bpx(k) + float(OS.get_environment("OFF"))
					g.psi = 0.0
					g.vpsi = 0.0
					set_meta("ak", k)
				if shot_n > 40 and shot_n < 75:
					var k2 = int(get_meta("ak"))
					print("AS n=", shot_n, " dz=", snappedf(_bzp(k2) - g.z, 0.1), " lat=", snappedf(g.lat, 0.01), " pad=", snappedf(_bpx(k2), 0.01), " boost=", snappedf(g.boost, 0.01), " padK=", g.padK, " k=", k2)
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
			if shot_n == 50 and shot_s.contains("pathtest"):
				# Test: Pause → Restart/Menu von hier aus; danach muss die (neu geladene) Szene wieder laufen
				var act = OS.get_environment("PATHACT")
				var tree = get_tree()
				var spath = p[0]
				_pause(true)
				print("PATH before act=", act, " state=", state, " T.S=", T.S, " free=", free_ride)
				if act == "menu":
					_to_menu()
				else:
					_race_again()
				var tm3 = tree.create_timer(14.0, true)
				tm3.timeout.connect(func():
					var sc = tree.current_scene
					print("PATH after paused=", tree.paused, " state=", sc.get("state"), " warm_t=", sc.get("warm_t"), " T.S=", T.S, " free=", sc.get("free_ride"), " race_t=", sc.get("race_t"))
					tree.root.get_viewport().get_texture().get_image().save_png(spath)
					tree.quit())
			if shot_n == 50 and shot_s.contains("pausetest"):
				_pause(true)
				var tm = get_tree().create_timer(1.5, true)
				tm.timeout.connect(func():
					get_viewport().get_texture().get_image().save_png(p[0])
					print("PAUSESHOT paused=", get_tree().paused)
					get_tree().quit())
			if shot_n == 60 and shot_s.contains(",ko"):
				_comic_start("ko", 1)
			if shot_n == 95 and shot_s.contains(",ko2"):
				_comic_start("ko", 2)   # zweiter K.o., während das erste Comic noch steht (so stürzte Build 185 ab)
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
			if shot_n == ({"repb": 84, "repf": 85, "armed": 50, "kill1": 75, "kill4": 160, "kill2": 90, "kill3": 110, "long": 700, "xlong": 4000, "pr1": 58, "pr2": 64, "pr3": 72, "pr4": 95, "i1": 22, "i2": 38, "i3": 52, "orbs": 47, "rep0": 85, "rep1": 85, "rep2": 85, "rep4": 85, "rep5": 85, "wand": 56, "boom": 42, "boom2": 70, "beben": 47, "gb1": 47, "gb2": 53, "schild": 44, "mega1": 46, "mega2": 52, "rs1": 43, "rs2": 50, "rs3": 58, "armed2": 130, "kc5": 125, "kc6": 140, "kc7": 150}.get(p[3], 90) if p.size() > 3 else 90):
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
	_neon_live(get_process_delta_time())
	_blimp_live(get_process_delta_time())
	_starter_live()
	# Explosions-Helligkeitsstoß abklingen lassen
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
	for tu in ([] if _jungle() else T.tuns()):   # Erdtunnel bleibt dunkel
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
		var f = T.sframe(s.z, s.lat)   # Rahmen dort, wo das Schiff fährt (in der Röhre auch an Wand und Decke)
		var SX: Dictionary = fx.ship
		var bob = 0.012 * float(SX.bob) * sin(tt * 2.7 + s.ai)
		var pos: Vector3 = f.c + f.uu * (0.16 * float(SX.height) + s.h + bob)
		var dir: Vector3 = (f.fw * cos(s.psi) + f.rr * sin(s.psi)).normalized()
		if state != "replay" and state != "kill":
			# Feder: Neigen in Kurven und Nicken beim Beschleunigen schwingen je nach „Wobble“ nach
			var om = 9.0 * float(SX.stiff)
			var ze = 1.0 / (1.0 + float(SX.wobble))
			var acc = (s.spd - s.get("lspd", s.spd)) / maxf(dt, 1e-4)
			s.lspd = s.spd
			s.pacc = lerpf(s.get("pacc", 0.0), acc, 1.0 - exp(-dt / 0.2))
			# Kurvenneigung: halb nach dem Lenkeinschlag, halb nach der tatsächlichen Querbewegung –
			# zieht das Schiff kräftig zur Seite, legt es sich deutlich hinein; fährt es gerade, richtet es sich auf
			var vl = s.spd * sin(s.vpsi)
			# bei 100 %: voll eingelenkt rund 45°, wie ein Motorrad in der Kurve (Regler bis 300 % → bis ~70°)
			var tr = clampf(0.8 * float(fx.steer.bank) * clampf(0.6 * s.u + 0.6 * clampf(absf(s.u) * 2.0, 0.2, 1.0) * clampf(vl / 4.0, -1.0, 1.0), -1.0, 1.0), -1.2, 1.2)
			var tp = clampf((s.pacc * 0.006 + s.boost * 0.035) * float(SX.pitch), -0.35, 0.35)
			var nsub = maxi(1, int(ceil(dt * om * maxf(1.0, float(fx.steer.recover)) / 0.25)))
			var sdt = dt / nsub
			for _i in range(nsub):
				# zurück in die Gerade: eigene, schnellere Feder („Aufrichten“), beim Hineinlegen die normale
				# reine Optik: „Hineinlegen“ = Tempo der Feder beim Reinlegen, „Nachwippen“ = weniger Dämpfung
				var outw = absf(tr) < absf(s.roll)
				var omr = om * (float(fx.steer.recover) if outw else float(fx.steer.get("leanin", 1.0)))
				var zw = 1.0 / (1.0 + 3.0 * float(fx.steer.get("wob", 0.0)))
				var zr = (maxf(ze, 0.85) if outw else ze) * zw
				s.rv = s.get("rv", 0.0) + (omr * omr * (tr - s.roll) - 2.0 * zr * omr * s.get("rv", 0.0)) * sdt
				s.roll += s.rv * sdt
				s.pv = s.get("pv", 0.0) + (om * om * (tp - s.get("pit", 0.0)) - 2.0 * ze * om * s.get("pv", 0.0)) * sdt
				s.pit = s.get("pit", 0.0) + s.pv * sdt
		# Optik: Nase dreht mit der Neigung in die Kurve (bzw. Heck schwingt raus) – ändert die Fahrlinie nicht
		var nz = float(fx.steer.get("nosev", 1.0))
		if absf(nz - 1.0) > 0.001 and state != "replay":
			# sichtbare Nasendrehung: 100 % = wie gefahren, 0 % = Nase zeigt längs der Strecke (nur Optik)
			dir = (f.fw * cos(s.psi * nz) + f.rr * sin(s.psi * nz)).normalized()
		var up: Vector3 = f.uu.rotated(dir, s.roll)
		var x = up.cross(dir).normalized()
		up = dir.cross(x).normalized()
		var nd: Node3D = s.node
		nd.global_transform = Transform3D(Basis(x, up, dir), pos)
		# Nase hoch beim Gasgeben; „Nose trim“ kippt die ganze Grundhaltung nach vorn (Nase Richtung Boden)
		var pitch_t = -float(s.get("pit", 0.0)) + float(SX.trim) * 0.25
		if absf(pitch_t) > 0.0001:
			nd.rotate_object_local(Vector3(1, 0, 0), pitch_t)
		_dmg_fx_step(s, nd)
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
# ---------------------------------------------------------------- Raketenkamera
# Feuerst du eine Lenkrakete, fliegt die Kamera mit ihr bis zum Einschlag, bleibt danach noch gut eine Sekunde
# auf der Explosion und springt dann zurück. Solange steuert der Autopilot (und du bist geschützt).
var mc = {}


func _mc_start(sh: Dictionary) -> void:
	if int(cfg.get("mcam", 1)) != 1 or state != "race":   # immer mitfliegen – auch ohne Ziel, bis sie verpufft
		return
	mc = {"sh": sh, "t": 0.0, "hold": -1.0, "p": Vector3.ZERO, "l": Vector3.ZERO, "pm": Vector3.ZERO, "up": Vector3.UP, "new": true}
	_flash(Color(1, 1, 1), 0.12)
	if hud.has("mcl") and is_instance_valid(hud.mcl):
		hud.mcl.queue_free()
	var lb = Label.new()
	lb.text = "●  MISSILE CAM"
	lb.add_theme_font_size_override("font_size", 26)
	lb.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	lb.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	lb.add_theme_constant_override("outline_size", 6)
	lb.set_anchors_preset(Control.PRESET_TOP_WIDE)
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.offset_top = get_viewport().get_visible_rect().size.y * 0.165
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.layer.add_child(lb)
	hud.mcl = lb


func _mc_end() -> void:
	if mc.is_empty():
		return
	mc = {}
	if hud.has("mcl") and is_instance_valid(hud.mcl):
		hud.mcl.queue_free()
	hud.erase("mcl")
	if state == "race":
		_flash(Color(1, 1, 1), 0.1)


func _mc_cam(dt: float) -> bool:
	if mc.is_empty():
		if hud.has("mcl"):   # nach Neustart übrig gebliebene Anzeige wegräumen
			if is_instance_valid(hud.mcl):
				hud.mcl.queue_free()
			hud.erase("mcl")
		return false
	if state != "race" or ships.is_empty() or ships[0].out:
		_mc_end()
		return false
	mc.t += dt
	if hud.has("mcl") and is_instance_valid(hud.mcl):
		(hud.mcl as Label).modulate.a = 0.55 + 0.45 * (1.0 if fmod(mc.t, 0.8) < 0.5 else 0.0)
	var sh: Dictionary = mc.sh
	if mc.hold < 0.0:
		if shots.has(sh) and is_instance_valid(sh.n) and mc.t < (41.0 if sh.get("mega", false) else 6.0):
			var P: Vector3 = (sh.n as Node3D).global_position
			var f = T.sframe(float(sh.z), float(sh.lat))
			var fw: Vector3 = f.fw * float(sh.dir)
			# Blick stur in Flugrichtung (Rakete wie mit Kamera auf dem Rücken), nur leicht mit der Seitenlage der Rakete
			var f2 = T.sframe(float(sh.z) + 10.0 * float(sh.dir), float(sh.lat))
			var look: Vector3 = f2.c + f2.uu * 0.3
			var want = P - fw * 1.5 + f.uu * 0.42
			mc.p = want if mc.new else (mc.p as Vector3).lerp(want, 1.0 - exp(-dt * 20.0))
			mc.l = look if mc.new else (mc.l as Vector3).lerp(look, 1.0 - exp(-dt * 14.0))
			mc.pm = P
			mc.up = f.uu
			mc.new = false
		else:
			mc.hold = 1.2   # Einschlag: noch kurz draufhalten
			mc.l = mc.pm
	else:
		mc.hold -= dt
		# langsam zurückweichen und etwas steigen, Blick bleibt auf der Explosion
		var back: Vector3 = ((mc.p as Vector3) - (mc.pm as Vector3)).normalized()
		mc.p = (mc.p as Vector3) + (back * 2.2 + (mc.up as Vector3) * 0.8) * dt
		if mc.hold <= 0.0:
			_mc_end()
			return false
	cam.global_position = mc.p
	if ((mc.l as Vector3) - (mc.p as Vector3)).length() > 0.01:
		cam.look_at(mc.l, mc.up)
	cam.fov = 74.0
	return true


func _camera(dt: float) -> void:
	_ck_update(dt)
	if state == "replay" and _rp_cam(dt):
		return
	if state == "kill" and _kc_cam():
		return
	if _mc_cam(dt):
		return
	if state == "done" and _fly_cam(dt):
		return
	if state == "done" and _party_live(dt):
		return
	if OS.get_environment("CLOSECAM") != "" and not ships.is_empty():
		# Test: Nahaufnahme des eigenen Schiffs schräg von hinten oben
		var nd0: Node3D = ships[0].node
		var bz = nd0.global_transform.basis
		cam.global_position = nd0.global_position - bz.z * 1.1 + bz.y * 0.75 + bz.x * 0.55
		var cc = OS.get_environment("CLOSECAM").split(",")
		if cc.size() == 3:   # Versatz in Schiffsachsen: seitlich, hoch, längs
			cam.global_position = nd0.global_position + bz.x * float(cc[0]) + bz.y * float(cc[1]) + bz.z * float(cc[2])
		cam.look_at(nd0.global_position + bz.y * 0.1, Vector3.UP)
		cam.fov = 50.0
		return
	if OS.get_environment("BLIMPCAM") != "" and not blimp.is_empty():
		var bn: Node3D = blimp.n
		var dd = float(OS.get_environment("BLIMPCAM"))
		cam.global_position = bn.global_position + bn.global_transform.basis.x * dd + Vector3.UP * (-dd * 0.35)
		cam.look_at(bn.global_position, Vector3.UP)
		cam.fov = 50.0
		return
	if OS.get_environment("BLIMPCAM") != "" and not blimp.is_empty():
		# nur zum Testen: seitlicher Blick auf den Zeppelin und seine Lichtkegel
		var bp: Vector3 = (blimp.n as Node3D).global_position
		var bo = OS.get_environment("BLIMPCAM").split(",")
		cam.global_position = bp + Vector3(float(bo[0]), float(bo[1]), float(bo[2]))
		cam.look_at(bp - Vector3(0, 14, 0), Vector3.UP)
		cam.fov = 60.0
		return
	if OS.get_environment("CSAT") != "" and state == "race" and race_t > 1.0 and not has_meta("csat"):
		set_meta("csat", 1)
		var ca = OS.get_environment("CSAT").split(",")
		var rnc = RandomNumberGenerator.new()
		rnc.seed = 7
		var fo = {"z": float(ca[0]), "lat": float(ca[1]), "spd": 20.0}
		var fcz = T.frame(fo.z)
		_crash_site(fo, fcz.c + fcz.rr * fo.lat, fcz, rnc)
	if OS.get_environment("CSDBG") != "" and Engine.get_process_frames() % 60 == 0:
		var nsm = 0
		for d in debris:
			if d.get("small", false):
				nsm += 1
		print("CSDBG f=", Engine.get_process_frames(), " debris=", debris.size(), " small=", nsm, " first=", (debris[0].z if not debris.is_empty() else -1), ",", (debris[0].lat if not debris.is_empty() else 0))
	if OS.get_environment("VIEWCAM") != "":
		# nur zum Testen: freie Kamera „z,seitlich,Höhe,Drehung(Grad)“ – schaut längs der Strecke, gedreht um die Hochachse
		var vp = OS.get_environment("VIEWCAM").split(",")
		var rel = vp[0].begins_with("s")   # „s…“ = relativ zum Spieler, Schiffe bleiben sichtbar
		if rel:
			vp[0] = str(float(ships[0].z) + float(vp[0].substr(1)))
			vp[1] = str(float(ships[0].lat) + float(vp[1]))
		var vf = T.frame(float(vp[0]))
		var ya = deg_to_rad(float(vp[3]))
		cam.global_position = vf.c + vf.rr * float(vp[1]) + vf.uu * float(vp[2])
		var pt = float(vp[4]) if vp.size() > 4 else -0.08
		cam.look_at(cam.global_position + vf.fw * cos(ya) + vf.rr * sin(ya) + vf.uu * pt, vf.uu)
		cam.fov = 60.0
		if not rel:
			for o in ships:
				(o.node as Node3D).visible = false
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
	var f = T.sframe(g.z, g.lat)   # in der Röhre: Rahmen an der Stelle des Schiffs (Wand, Decke)
	var S0: Vector3 = f.c + f.uu * (0.16 + g.h)
	cam_psi += (g.psi - cam_psi) * (1.0 - exp(-dt / 0.25))
	var tc = minf(1.0, g.boost) * 0.55
	cam_d += (tc - cam_d) * (1.0 - exp(-dt / (0.14 if tc > cam_d else 0.8)))
	var cp = cam_psi * 0.6
	var fc: Vector3 = (f.fw * cos(cp) + f.rr * sin(cp)).normalized()
	# in der Röhre rollt die Kamera ganz mit: wo du fährst, ist unten – die Welt dreht sich um dich
	var twk = clampf(T.pipe_k(g.z) * 2.5, 0.0, 1.0)
	var uc: Vector3 = (Vector3.UP * 0.25 * (1.0 - twk) + f.uu * (0.75 + 0.25 * twk)).normalized()
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
	var ckm = (state == "race" or state == "count") and _ck_on()
	if ckm:
		# Cockpit: Augen knapp über dem Gleiter, Blick längs der Schiffsnase (rollt mit dem Schiff, das Cockpit-Bild bleibt fest davor)
		var nb: Basis = (g.node as Node3D).global_transform.basis
		var SF: Vector3 = nb.z.normalized()
		var SU: Vector3 = nb.y.normalized()
		ro = S0 + SU * CK_EYE.y - SF * CK_EYE.x
		ta = S0 + SF * 12.0 + SU * CK_EYE.z
		uc = f.uu.lerp(SU, 0.4).normalized()   # Horizont kippt nur zu 40 % mit (volle 45° Schräglage wären zu wild)
		# Fliehkraft: beim Boost in den Sitz gedrückt (Blick weicht zurück), beim Aufsetzen ein Ruck nach unten
		ro += -SF * 0.16 * float(ckh.push) - SU * 0.06 * float(ckh.lj)
		ta += -SU * 0.6 * float(ckh.lj)
	shake = maxf(0.0, shake - dt * 1.8)
	_flash_fade(dt * 2.2)
	if shake > 0.0:
		var tt2 = Time.get_ticks_msec() / 1000.0
		ro += Vector3(sin(tt2 * 61.0), sin(tt2 * 53.0 + 1.0) * 0.7, sin(tt2 * 47.0 + 2.0) * 0.5) * shake * (0.04 if ckm else 0.09)
	# Tempo-Zittern: bei normaler Fahrt kaum spürbar, bei Boost deutlich (die Kamera vibriert, das Bild wackelt leicht mit)
	if (state == "race" or state == "replay") and post_spd > 0.01:
		var rum = (0.003 + 0.02 * maxf(0.0, post_spd - 0.32) / 0.68) * clampf(post_spd / 0.32, 0.0, 1.0)
		var t3 = Time.get_ticks_msec() / 1000.0
		var jr = (sin(t3 * 71.0) + sin(t3 * 113.0 + 1.3)) * 0.5
		var ju = (sin(t3 * 83.0 + 0.7) + sin(t3 * 131.0 + 2.1)) * 0.5
		ro += (f.rr * jr + f.uu * ju) * rum
		ta += (f.rr * ju - f.uu * jr) * rum * 3.0
	if OS.get_environment("SPDDBG") != "" and Engine.get_process_frames() % 20 == 0:
		print("SPD state=", state, " spd=", snappedf(g.spd, 0.1), " boost=", snappedf(g.boost, 0.01), " post=", snappedf(post_spd, 0.01), " fov=", snappedf(52.0 * minf(1.42, 1.0 + 0.1 * minf(1.5, g.boost) + 0.3 * post_spd), 0.1), " shake_px~=", snappedf((ro - (S0 - fc * (2.6 + cam_d) + uc * (0.95 - 0.15 * cam_d) - f.uu * g.h * 0.5)).length() * 1000.0, 0.1), "mm")
	cam.global_position = ro
	cam.look_at(ta, uc)
	# Sichtfeld weitet sich mit dem Tempo: Stand 52°, normale Fahrt ~57°, Boost bis ~74°
	cam.fov = 52.0 * minf(1.42, 1.0 + 0.1 * minf(1.5, g.boost) + 0.3 * post_spd)
	if ckm:
		cam.fov = CK_FOV * minf(1.35, 1.0 + 0.08 * minf(1.5, g.boost) + 0.25 * post_spd)
		return
	cam.rotate_object_local(Vector3(0, 0, 1), -g.u * 0.05)   # leichtes Mitneigen beim Lenken


# ---------------------------------------------------------------- Funkbilder: Gegner melden sich per wackeliger Videoverbindung
# Beim Überholen und bei Treffern: Gesicht (Comic-Panel) mit Rauschen, Streifen und Flackern, Name, Spruch, Pegelbalken
var radio = {}
var radio_cd = 0.0
var radio_side = {}


func _radio_build(cl: CanvasLayer) -> void:
	var box = Control.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.visible = false
	cl.add_child(box)
	var bg = Panel.new()
	var st = StyleBoxFlat.new()
	st.bg_color = Color(0.02, 0.03, 0.05, 0.82)
	st.border_color = Color(0.4, 0.9, 1.0, 0.7)
	st.set_border_width_all(2)
	st.set_corner_radius_all(10)
	bg.add_theme_stylebox_override("panel", st)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(bg)
	var face = TextureRect.new()
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	face.clip_contents = true
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.material = _shader_mat("""
shader_type canvas_item;
uniform vec3 tint=vec3(1.);
uniform float jit=0.;
uniform float sig=1.;
float h(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5);}
void fragment(){
	vec2 uv=UV;
	float row=floor(uv.y*90.);
	// Zeilen springen seitlich, ab und zu reißt ein Streifen weg
	uv.x+=(h(vec2(row,floor(TIME*20.)))-.5)*.03*jit+step(.985,h(vec2(floor(uv.y*14.),floor(TIME*9.))))*.08*(1.-sig);
	vec3 c=texture(TEXTURE,uv).rgb;
	float l=dot(c,vec3(.3,.55,.15));
	c=mix(vec3(l),c,.5)*tint*1.2;                         // farbstichig wie ein alter Bildschirm
	c*=.8+.2*sin(UV.y*360.+TIME*14.);                     // Zeilenraster
	c+=(h(UV*vec2(160.,190.)+floor(TIME*30.))-.5)*.14;    // Rauschen
	c*=.85+.15*h(vec2(floor(TIME*24.),3.));               // Flackern
	c*=mix(.35,1.,sig);
	float v=smoothstep(.85,.35,length(UV-.5));
	COLOR=vec4(c*v,1.);
}""")
	box.add_child(face)
	var nm = Label.new()
	nm.add_theme_font_size_override("font_size", 26)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(nm)
	var tx = Label.new()
	tx.add_theme_font_size_override("font_size", 28)
	tx.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tx.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
	box.add_child(tx)
	var lv = Control.new()   # Pegelbalken
	lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lv.draw.connect(_radio_lv_draw.bind(lv))
	box.add_child(lv)
	hud.radio = {"box": box, "bg": bg, "st": st, "face": face, "nm": nm, "tx": tx, "lv": lv}


func _radio(who: int, kind: String, chance := 1.0) -> void:
	if radio_cd > 0.0 or not radio.is_empty() or who <= 0 or who >= CHARS.size() or randf() > chance:
		return
	if state != "race" or race_t < 3.0 or not hud.has("radio"):
		return
	var k: String = CHARS[who][3]
	var lines: Array = []
	if kind == "taunt":
		lines = CM_LINES.get(k, []) + CM_LOSE.get(k, [])
	else:
		lines = CM_WIN.get(k, []) + CM_KO.get(k, [])
	if lines.is_empty():
		return
	var txt = str(_pick(lines)).replace("\n", " ")
	radio = {"who": who, "t": 0.0, "dur": 2.8, "txt": txt, "img": "%s_%d" % [k, randi() % 3]}
	radio_cd = 9.0
	var R: Dictionary = hud.radio
	(R.face as TextureRect).texture = _cm_img(radio.img)
	var col: Color = CHARS[who][2]
	R.nm.text = "◉ " + str(CHARS[who][0]) + "  ·  CH %d" % (who + 1)
	R.nm.add_theme_color_override("font_color", col.lerp(Color(1, 1, 1), 0.25))
	R.tx.text = "“" + txt + "”"
	(R.st as StyleBoxFlat).border_color = Color(col.lerp(Color(1, 1, 1), 0.2), 0.8)
	_sp(R.face.material, "tint", Vector3(0.75 + col.r * 0.4, 0.75 + col.g * 0.4, 0.75 + col.b * 0.4))
	_snd("radio", -4.0)


func _radio_tick(dt: float) -> void:
	radio_cd = maxf(0.0, radio_cd - dt)
	if not hud.has("radio"):
		return
	var R: Dictionary = hud.radio
	if not is_instance_valid(R.box):
		return
	# Überholen erkennen: wechselt ein Gegner die Seite (vor/hinter dir), meldet er sich
	if state == "race" and not ships.is_empty() and not ships[0].out:
		var g: Dictionary = ships[0]
		for i in range(1, ships.size()):
			var o: Dictionary = ships[i]
			if o.out:
				continue
			var dz = float(o.z) - float(g.z)
			var sd = 1 if dz > 0.6 else (-1 if dz < -0.6 else 0)
			var prev = int(radio_side.get(i, 0))
			if sd != 0 and prev != 0 and sd != prev and absf(dz) < 6.0:
				_radio(i, "taunt" if sd > 0 else "whine", 0.7)
			if sd != 0:
				radio_side[i] = sd
	if OS.get_environment("RADIO") != "" and radio.is_empty() and state == "race" and race_t > float(OS.get_environment("RADIOT") if OS.get_environment("RADIOT") != "" else "3.2") and radio_cd <= 0.0:
		_radio(int(OS.get_environment("RADIO")), "taunt")   # nur zum Testen
	var on = not radio.is_empty() and state == "race"
	R.box.visible = on
	if not on:
		if not radio.is_empty() and state != "race":
			radio = {}
		return
	radio.t = float(radio.t) + dt
	var t = float(radio.t)
	var dur = float(radio.dur)
	if t > dur:
		radio = {}
		R.box.visible = false
		_snd("radio", -8.0, 0.8)
		return
	var vp = get_viewport().get_visible_rect().size
	var u = vp.x / 540.0
	# Platz: links unter POS/LAP, über der Strecke
	var W = 380.0 * u
	var H = 150.0 * u
	var x0 = 12.0 * u
	var y0 = vp.y * 0.205
	# Verbindung baut sich auf: kurz zusammenklappen/aufziehen wie ein alter Monitor
	var op = clampf(t / 0.18, 0.0, 1.0) * clampf((dur - t) / 0.2, 0.0, 1.0)
	R.box.position = Vector2(x0, y0 + H * 0.5 * (1.0 - op))
	R.box.size = Vector2(W, H * op)
	R.box.modulate.a = 0.4 + 0.6 * op
	R.bg.position = Vector2.ZERO
	R.bg.size = R.box.size
	var fs = H * op - 12.0 * u
	R.face.position = Vector2(6.0 * u, 6.0 * u)
	R.face.size = Vector2(fs * 1.05, fs)
	# Stimme: Silben-Rhythmus aus Rauschen; das Bild zuckt im Takt, der Pegel schlägt aus
	var talk = 1.0 if t < dur * 0.8 else 0.0
	var env = talk * clampf(absf(sin(t * 11.0)) * (0.6 + 0.4 * sin(t * 3.7 + 1.0)) + randf() * 0.25, 0.0, 1.0)
	radio["env"] = env
	_sp(R.face.material, "jit", 0.4 + env * 1.4)
	_sp(R.face.material, "sig", 0.75 + 0.25 * (1.0 - float(randf() < 0.04)))
	R.face.position.x += (randf() - 0.5) * 3.0 * u * env
	var tx0 = 6.0 * u + fs * 1.05 + 10.0 * u
	R.nm.position = Vector2(tx0, 4.0 * u)
	R.nm.add_theme_font_size_override("font_size", int(17.0 * u))
	R.tx.position = Vector2(tx0, 30.0 * u)
	R.tx.size = Vector2(W - tx0 - 8.0 * u, H * op - 46.0 * u)
	R.tx.add_theme_font_size_override("font_size", int(20.0 * u))
	R.tx.visible_ratio = clampf(t / (dur * 0.55), 0.0, 1.0)   # Text läuft wie beim Funkspruch mit
	R.lv.position = Vector2(tx0, H * op - 20.0 * u)
	R.lv.size = Vector2(W - tx0 - 10.0 * u, 11.0 * u)
	(R.lv as Control).queue_redraw()


func _radio_lv_draw(c: Control) -> void:
	if not hud.has("radio") or hud.radio.lv != c or radio.is_empty():
		return
	var n = 14
	var e = float(radio.get("env", 0.0))
	var bw = c.size.x / n
	var col: Color = CHARS[int(radio.who)][2].lerp(Color(1, 1, 1), 0.3)
	for i in range(n):
		var lit = float(i) / n < e * (0.85 + 0.15 * sin(float(i) * 1.7 + float(radio.t) * 30.0))
		c.draw_rect(Rect2(i * bw + 1.0, 0, bw - 2.0, c.size.y), Color(col, 0.95 if lit else 0.15))


# ---------------------------------------------------------------- Cockpit-Ansicht
# Zwei flache Bilder vor der Kamera: der Gleiter-Rand (art/ck/body.png) und die Hände an den Griffen mit dem
# Hologramm-Kern (art/ck/hands.png). Beide sind 852 px breit und werden auf Bildschirmbreite gezogen, unten bündig.
# Die Hände kippen beim Lenken um den Kern, der Kern pulsiert mit dem Tempo und leuchtet beim Boost auf.
const CK_EYE = Vector3(0.12, 0.34, -0.1)   # Auge: x = hinter der Mitte, y = über der Mitte, z = Höhe des Blickziels
const CK_FOV = 62.0
const CK_HS = 0.9                           # Größe der Hände relativ zur Bildschirmbreite
const CK_ROLLK = 1.25                       # Schiffs-Schräglage → Lenkausschlag der Hände (voll eingelenkt ≈ 0,8 → 1)
const CK_CORE = Vector2(426.0, 185.0)      # Mitte des Hologramm-Kerns im Hände-Bild (Pixel)
const CK_TIP = 216.0                        # Spitze des Dreiecks im Hände-Bild (y)
const CK_STRIP = Vector3(372.0, 482.0, 167.0)   # magenta Lichtstreifen im Armaturenbrett: x von, x bis, y (Gleiter-Bild)
const VM_NAMES = ["NORMAL VISION", "INFRARED", "GRID VISION"]
var ck = {}
var ck_hid = false
var ck_rot = 0.0
var ck_snd = 0.0   # 0 = draußen, 1 = im Cockpit (gleitet beim Umschalten)
var ck_hb = 0.0    # Herzschlag-Stärke
var wat_snd = 0.0
var ck_bus_v = -1.0


func _ck_bus(v: float) -> void:
	if absf(v - ck_bus_v) < 0.004:
		return
	ck_bus_v = v
	var gi = AudioServer.get_bus_index("Game")
	if gi < 0 or AudioServer.get_bus_effect_count(gi) < 2:
		return
	var on = v > 0.01
	AudioServer.set_bus_effect_enabled(gi, 0, on)
	AudioServer.set_bus_effect_enabled(gi, 1, on)
	var vi = AudioServer.get_bus_index("Voice")
	if vi >= 0 and AudioServer.get_bus_effect_count(vi) >= 5:
		for k in range(2, 5):
			AudioServer.set_bus_effect_enabled(vi, k, v > 0.5)
	if not on:
		return
	var lp = AudioServer.get_bus_effect(gi, 0) as AudioEffectLowPassFilter
	lp.cutoff_hz = 20000.0 * pow(1400.0 / 20000.0, v)   # 20 kHz → 1,4 kHz
	var eq = AudioServer.get_bus_effect(gi, 1) as AudioEffectEQ6
	eq.set_band_gain_db(0, 5.0 * v)    # 32 Hz
	eq.set_band_gain_db(1, 4.0 * v)    # 100 Hz
	eq.set_band_gain_db(2, 1.5 * v)    # 320 Hz


func _ck_build(cl: CanvasLayer) -> void:
	var root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.visible = false
	cl.add_child(root)
	var floor_r = ColorRect.new()   # Cockpitboden unter dem Bild (das Bild sitzt über der unteren HUD-Leiste)
	floor_r.color = Color(0.09, 0.085, 0.1)
	floor_r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(floor_r)
	# Licht auf Armaturen und Handschuhen: Reflex-Band beim Vorbeiflug an Lampen, rotes Warnlicht von unten, Schadens-Flackern
	var cksh = _shader_mat("""
shader_type canvas_item;
uniform float ry=-1.;
uniform vec3 rc=vec3(1.);
uniform float ra=0.;
uniform float df=1.;
void fragment(){
	vec4 c=COLOR;
	vec2 s=SCREEN_UV;
	float lum=dot(c.rgb,vec3(.33));
	if(ry>-.5){
		float b=exp(-pow((s.y+(s.x-.5)*.45-ry)*11.,2.));
		c.rgb+=rc*b*(.08+lum*1.1);
	}
	c.rgb+=vec3(1.,.07,.04)*ra*smoothstep(.5,1.,s.y)*(.3+lum*1.2);
	c.rgb*=df;
	COLOR=c;
}""")
	var body = TextureRect.new()
	body.texture = load("res://art/ck/body.png")
	body.material = cksh
	body.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	body.stretch_mode = TextureRect.STRETCH_SCALE
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(body)
	var pgt = GradientTexture2D.new()
	pgt.fill = GradientTexture2D.FILL_RADIAL
	pgt.fill_from = Vector2(0.5, 0.5)
	pgt.fill_to = Vector2(1.0, 0.5)
	pgt.width = 64
	pgt.height = 64
	var pgr = Gradient.new()
	pgr.set_color(0, Color(1.0, 0.85, 1.0, 1.0))
	pgr.set_color(1, Color(1.0, 0.2, 0.85, 0.0))
	pgr.add_point(0.35, Color(1.0, 0.4, 0.95, 0.7))
	pgt.gradient = pgr
	var ptr = TextureRect.new()   # heller Fleck auf dem Lichtstreifen, genau unter der Dreiecksspitze
	ptr.texture = pgt
	ptr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ptr.stretch_mode = TextureRect.STRETCH_SCALE
	ptr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pm = CanvasItemMaterial.new()
	pm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	ptr.material = pm
	root.add_child(ptr)
	var hdc = Control.new()
	hdc.set_anchors_preset(Control.PRESET_FULL_RECT)
	hdc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hdc.draw.connect(_ck_hud_draw.bind(hdc))
	root.add_child(hdc)
	var hands = TextureRect.new()
	hands.texture = load("res://art/ck/hands.png")
	hands.material = cksh
	hands.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hands.stretch_mode = TextureRect.STRETCH_SCALE
	hands.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hands)
	# Leuchten über dem Kern (additiv), dreht mit den Händen mit
	var gt = GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 128
	gt.height = 128
	var gr = Gradient.new()
	gr.set_color(0, Color(0.75, 0.55, 1.0, 1.0))
	gr.set_color(1, Color(0.2, 0.9, 1.0, 0.0))
	gr.add_point(0.45, Color(0.4, 0.8, 1.0, 0.45))
	gt.gradient = gr
	var glow = TextureRect.new()
	glow.texture = gt
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gm = CanvasItemMaterial.new()
	gm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = gm
	hands.add_child(glow)
	root.move_child(ptr, -1)   # Zeiger-Licht über den Händen, sonst verschluckt es der Hologramm-Ring
	# Rauch bei starkem Schaden: kräuselt unten aus dem Cockpit hoch
	var sgt = GradientTexture2D.new()
	sgt.fill = GradientTexture2D.FILL_RADIAL
	sgt.fill_from = Vector2(0.5, 0.5)
	sgt.fill_to = Vector2(1.0, 0.5)
	sgt.width = 64
	sgt.height = 64
	var sgr = Gradient.new()
	sgr.set_color(0, Color(0.55, 0.55, 0.58, 0.9))
	sgr.set_color(1, Color(0.3, 0.3, 0.32, 0.0))
	sgt.gradient = sgr
	var smoke = CPUParticles2D.new()
	smoke.texture = sgt
	smoke.amount = 26
	smoke.lifetime = 2.2
	smoke.emitting = false
	smoke.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	smoke.direction = Vector2(0, -1)
	smoke.spread = 28.0
	smoke.gravity = Vector2(0, -30)
	smoke.local_coords = false
	var scr2 = Gradient.new()
	scr2.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	scr2.colors = PackedColorArray([Color(0.6, 0.6, 0.63, 0.0), Color(0.62, 0.62, 0.66, 0.85), Color(0.45, 0.45, 0.5, 0.0)])
	smoke.color_ramp = scr2
	root.add_child(smoke)
	# Funken an der Bande: fliegen dicht am Cockpit vorbei nach hinten weg
	var kgt = GradientTexture2D.new()
	kgt.width = 4
	kgt.height = 18
	kgt.fill_from = Vector2(0.5, 0.0)
	kgt.fill_to = Vector2(0.5, 1.0)
	var kgr = Gradient.new()
	kgr.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	kgr.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.0)])
	kgt.gradient = kgr
	var sparks = []
	for sd in [-1.0, 1.0]:
		var sp = CPUParticles2D.new()
		sp.texture = kgt
		sp.amount = 70
		sp.lifetime = 0.55
		sp.emitting = false
		sp.local_coords = false
		sp.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		sp.direction = Vector2(sd * 0.55, 1.0)
		sp.spread = 22.0
		sp.gravity = Vector2(0, 1400)
		sp.particle_flag_align_y = true
		var kcr = Gradient.new()
		kcr.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
		kcr.colors = PackedColorArray([Color(1.0, 1.0, 0.85, 1.0), Color(1.0, 0.7, 0.2, 1.0), Color(1.0, 0.2, 0.05, 0.0)])
		sp.color_ramp = kcr
		var km = CanvasItemMaterial.new()
		km.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		sp.material = km
		root.add_child(sp)
		sparks.append(sp)
	# Helmvisier (dritte Ansicht): Rand des Visiers, feine Spiegelungen, Atem-Beschlag, Tunnelblick beim Boost
	var visor = ColorRect.new()
	visor.set_anchors_preset(Control.PRESET_FULL_RECT)
	visor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visor.material = _shader_mat("""
shader_type canvas_item;
uniform float bo=0.;
uniform float br=0.;
uniform float dm=0.;
float h(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5);}
void fragment(){
	vec2 uv=UV;
	vec2 q=(uv-vec2(.5,.47))*2.;
	// Visier als abgerundetes Fenster (Superellipse), außen das dunkle Helminnere
	float d=pow(pow(abs(q.x)/.99,4.)+pow(abs(q.y)/.95,4.),.25);
	float fr=smoothstep(.955,1.0,d);
	float rim=smoothstep(.88,.955,d)*(1.-fr);
	// Tunnelblick: beim Boost zieht sich das Bild zusammen
	float r=length(q*vec2(1.,.82));
	float tv=smoothstep(.75-.42*bo,1.25-.45*bo,r)*(.25+.7*bo);
	// Spiegelungen: zwei weiche, schräge Lichtbahnen, die langsam wandern
	float rf=smoothstep(.92,1.,sin((uv.x*1.3+uv.y*.7)*5.5+TIME*.25))*.06+smoothstep(.97,1.,sin((uv.x*.8-uv.y*1.1)*7.+1.7-TIME*.18))*.05;
	// Atem beschlägt das Visier unten, stärker bei wenig Energie
	float fog=smoothstep(.62,1.,uv.y)*smoothstep(.75,.15,abs(uv.x-.5))*br*(.75+.25*h(floor(uv*60.)));
	vec3 col=vec3(.015,.018,.03)*fr+vec3(.25,.75,1.)*rim*.5+vec3(.85,.92,1.)*(rf+fog*.6);
	float a=clamp(max(max(fr,tv),rim*.45)+rf+fog*.45,0.,1.);
	// Schaden: Riss-Flackern am Rand
	a=max(a,dm*step(.97,h(floor(uv*vec2(40.,80.))+floor(TIME*12.)))*smoothstep(.6,1.,d));
	COLOR=vec4(col,a);
}""")
	visor.visible = false
	root.add_child(visor)
	# Rückspiegel (im Cockpit): eine zweite, kleine Kamera schaut nach hinten
	var rmv = SubViewport.new()
	rmv.size = Vector2i(320, 104)
	rmv.render_target_update_mode = SubViewport.UPDATE_DISABLED
	rmv.msaa_3d = Viewport.MSAA_DISABLED
	var rcam = Camera3D.new()
	rcam.fov = 46.0
	rcam.far = 220.0
	rmv.add_child(rcam)
	rcam.current = true
	add_child(rmv)
	var mir = TextureRect.new()
	mir.texture = rmv.get_texture()
	mir.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mir.stretch_mode = TextureRect.STRETCH_SCALE
	mir.flip_h = true   # gespiegelt wie ein echter Rückspiegel
	mir.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mfr = Panel.new()
	var mst = StyleBoxFlat.new()
	mst.bg_color = Color(0, 0, 0, 0)
	mst.border_color = Color(0.35, 0.9, 1.0, 0.85)
	mst.set_border_width_all(3)
	mst.set_corner_radius_all(14)
	mst.shadow_color = Color(0.2, 0.8, 1.0, 0.35)
	mst.shadow_size = 6
	mfr.add_theme_stylebox_override("panel", mst)
	mfr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(mir)
	root.add_child(mfr)
	ck = {"root": root, "body": body, "hands": hands, "glow": glow, "floor": floor_r, "hud": hdc, "ptr": ptr, "sh": cksh, "smoke": smoke, "sparks": sparks,
		"visor": visor, "rmv": rmv, "rcam": rcam, "mir": mir, "mfr": mfr}


func _ck_on() -> bool:
	if ships.is_empty():
		return false
	if state == "race" or state == "count":
		return int(cfg.get("view", 0)) >= 1 and not ships[0].out and mc.is_empty()
	return state == "replay" and not rp.is_empty() and RP_CAMS[rp.ci][0] == "cock"


func _ck_update(dt: float) -> void:
	var on = _ck_on()
	# Pause- und Kamera-Knopf oben nur im Rennen (blieben sonst z. B. im Replay grau stehen)
	if hud.has("viewbtn") and is_instance_valid(hud.viewbtn):
		hud.viewbtn.visible = state in ["count", "race"] and fin.is_empty()
		hud.viewbtn.text = "CAM"
	if hud.has("pausebtn") and is_instance_valid(hud.pausebtn) and not state in ["intro", "count", "race"]:
		hud.pausebtn.visible = false
	# eigenes Schiff im Rennen ausblenden, solange man drinsitzt (im Replay macht das die Replay-Wiedergabe selbst)
	if (state == "race" or state == "count") and on:
		(ships[0].node as Node3D).visible = false
		ck_hid = true
	elif ck_hid:
		ck_hid = false
		if not ships.is_empty() and state != "replay":
			(ships[0].node as Node3D).visible = not ships[0].out
	if ck.is_empty() or not is_instance_valid(ck.root):
		return
	ck.root.visible = on
	if not on:
		(ck.rmv as SubViewport).render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	var g: Dictionary = _focus()
	var vp = get_viewport().get_visible_rect().size
	var sc = vp.x / 852.0
	# Helmvisier statt Cockpit (nur im Rennen; im Replay zeigt „Cockpit“ das Cockpit)
	var vis = int(cfg.get("view", 0)) == 2 and state != "replay"
	for k in ["body", "hands", "floor", "ptr", "smoke"]:
		(ck[k] as CanvasItem).visible = not vis
	ck.visor.visible = vis
	if vis:
		var en = float(g.en)
		_sp(ck.visor.material, "bo", clampf(float(g.boost), 0.0, 1.0) * 0.6 + clampf(post_spd - 0.32, 0.0, 1.0) * 0.4)
		var brt = Time.get_ticks_msec() / 1000.0
		var brs = 0.2 + 0.5 * clampf((0.4 - en) / 0.35, 0.0, 1.0)   # schneller und stärker, wenn's eng wird
		_sp(ck.visor.material, "br", (0.12 + 0.35 * brs) * (0.5 + 0.5 * sin(brt * (1.3 + 2.0 * brs))))
		_sp(ck.visor.material, "dm", clampf((0.3 - en) / 0.25, 0.0, 1.0) if state in ["race", "count"] else 0.0)
	# Rückspiegel: auf Wunsch abgeschaltet (auf dem Handy kaum zu erkennen) – wird nie gezeigt und nie gerendert
	var mon = false
	ck.mir.visible = mon
	ck.mfr.visible = mon
	if mon:
		var mw = vp.x * 0.5
		var mh = mw * 104.0 / 320.0
		var mr = Rect2(Vector2((vp.x - mw) * 0.5, vp.y * 0.105), Vector2(mw, mh))
		ck.mir.position = mr.position
		ck.mir.size = mr.size
		ck.mfr.position = mr.position - Vector2(3, 3)
		ck.mfr.size = mr.size + Vector2(6, 6)
		var nb: Basis = (g.node as Node3D).global_transform.basis
		var gp: Vector3 = (g.node as Node3D).global_position
		var mup = nb.y.normalized()
		var mfw = nb.z.normalized()
		var rc: Camera3D = ck.rcam
		rc.global_position = gp + mup * 0.55 - mfw * 0.3
		rc.look_at(gp - mfw * 12.0 + mup * 0.3, mup)
		(ck.rmv as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE if Engine.get_process_frames() % 2 == 0 else SubViewport.UPDATE_DISABLED
	else:
		(ck.rmv as SubViewport).render_target_update_mode = SubViewport.UPDATE_DISABLED
	# unten bündig mit der Mitte der unteren HUD-Leiste: die Leiste verdeckt den Schnitt an den Unterarmen,
	# und der Hologramm-Kern sitzt frei über dem Waffen-Rad (bei jedem Seitenverhältnis)
	var by = vp.y - 192.0 * vp.x / GA_W + (float(ckh.push) * 16.0 + float(ckh.lj) * 18.0) * sc
	var bs: Vector2 = (ck.body as TextureRect).texture.get_size() * sc
	ck.body.position = Vector2(0.0, by - bs.y)
	ck.body.size = bs
	ck.floor.position = Vector2(0.0, by - 2.0)
	ck.floor.size = Vector2(vp.x, vp.y - by + 2.0)
	var hs: Vector2 = (ck.hands as TextureRect).texture.get_size() * sc * CK_HS
	# Lenken: Hände kippen um den Kern (bis 18°), dazu ein kleines Mitschwingen zur Seite
	var tgt = clampf(float(g.roll) * CK_ROLLK, -1.0, 1.0)
	ck_hud_tick(dt, g)
	if OS.get_environment("CKEN") != "":
		g.en = float(OS.get_environment("CKEN"))   # nur zum Testen: feste Energie (Schaden, Herzschlag)
	if OS.get_environment("CKWARN") != "":
		ckh.mis = OS.get_environment("CKWARN") == "mis"
		ckh.mine = OS.get_environment("CKWARN") == "mine"
		ckh.al = 1.0
		ckh.mang = 2.4
	if OS.get_environment("CKSCR") != "":
		ckh.scr = int(OS.get_environment("CKSCR"))
	if OS.get_environment("CKREFL") != "":
		ckh.rf = float(OS.get_environment("CKREFL"))
	if OS.get_environment("CKROT") != "":
		tgt = float(OS.get_environment("CKROT"))   # nur zum Testen: fester Lenkausschlag der Hände
	ck_rot += (tgt - ck_rot) * (1.0 - exp(-dt / 0.08))
	var jit = Vector2.ZERO
	if shake > 0.0:
		var tj = Time.get_ticks_msec() / 1000.0
		jit = Vector2(sin(tj * 57.0), sin(tj * 43.0 + 1.0)) * shake * 9.0 * sc
	ck.hands.size = hs
	# so tief, dass die Dreiecksspitze knapp über dem magenta Lichtstreifen im Armaturenbrett steht
	var tip_y = ck.body.position.y + (CK_STRIP.z - 7.0) * sc
	ck.hands.position = Vector2(vp.x * (1.0 - CK_HS) * 0.5 + ck_rot * 6.0 * sc, tip_y - CK_TIP * sc * CK_HS + absf(ck_rot) * 3.0 * sc) + jit
	# Zeiger: das Dreieck zeigt beim Lenken auf eine Stelle des Streifens, dort leuchtet er auf
	var px = clampf(ck.hands.position.x + CK_CORE.x * sc * CK_HS - sin(deg_to_rad(18.0) * ck_rot) * 170.0 * sc, (CK_STRIP.x + 8.0) * sc, (CK_STRIP.y - 8.0) * sc)
	var pw = 80.0 * sc
	var ph = 30.0 * sc
	ck.ptr.size = Vector2(pw, ph)
	ck.ptr.position = Vector2(px - pw * 0.5, ck.body.position.y + CK_STRIP.z * sc - ph * 0.5)
	ck.ptr.modulate = Color(1.6, 1.3, 1.6, 0.85 + 0.15 * sin(Time.get_ticks_msec() / 1000.0 * 6.0))
	# Licht und Schaden auf die Cockpit-Bilder
	var tnow = Time.get_ticks_msec() / 1000.0
	var rf = float(ckh.rf)
	_sp(ck.sh, "ry", lerpf(0.5, 1.1, rf) if rf < 1.0 else -1.0)
	var rcc: Color = ckh.rc
	_sp(ck.sh, "rc", Vector3(rcc.r, rcc.g, rcc.b))
	_sp(ck.sh, "ra", float(ckh.al) * (0.5 + 0.5 * sin(tnow * 5.0)) * 0.7)
	var dmg = clampf((0.3 - float(g.en)) / 0.25, 0.0, 1.0) if state in ["race", "count"] else 0.0
	_sp(ck.sh, "df", 1.0 - (0.35 if dmg > 0.0 and fmod(tnow * 9.3, 1.0) < 0.12 * dmg else 0.0))
	ck.smoke.emitting = dmg > 0.05
	ck.smoke.modulate.a = 0.4 + 0.6 * dmg
	ck.smoke.position = Vector2(vp.x * 0.5, by - 330.0 * sc)   # aus den Spalten neben den Griffen, über dem Waffen-Rad
	ck.smoke.emission_rect_extents = Vector2(vp.x * 0.38, 40.0 * sc)
	ck.smoke.initial_velocity_min = 120.0 * sc
	ck.smoke.initial_velocity_max = 240.0 * sc
	ck.smoke.scale_amount_min = 2.4 * sc
	ck.smoke.scale_amount_max = 4.5 * sc
	for i in range(2):
		var sp: CPUParticles2D = ck.sparks[i]
		var on_s = int(ckh.scr) == (-1 if i == 0 else 1)
		sp.emitting = on_s
		sp.position = Vector2(vp.x * (0.06 if i == 0 else 0.94), vp.y * 0.5)
		sp.emission_rect_extents = Vector2(6.0 * sc, vp.y * 0.12)
		sp.initial_velocity_min = 700.0 * sc
		sp.initial_velocity_max = 1300.0 * sc
		sp.direction = Vector2(-0.4 if i == 0 else 0.4, 1.0)   # nach unten-außen: fliegen am Cockpit vorbei nach hinten
		sp.scale_amount_min = 2.6 * sc
		sp.scale_amount_max = 4.6 * sc
	ck.hands.pivot_offset = CK_CORE * sc * CK_HS
	ck.hands.rotation = deg_to_rad(18.0) * ck_rot
	# Kern: pulsiert schneller und heller mit dem Tempo, beim Boost kräftig
	var t = Time.get_ticks_msec() / 1000.0
	var pul = 0.5 + 0.5 * sin(t * (3.0 + 9.0 * post_spd))
	var gs = (150.0 + 22.0 * pul + 40.0 * minf(1.0, float(g.boost))) * sc
	ck.glow.size = Vector2(gs, gs)
	gs *= CK_HS
	ck.glow.size = Vector2(gs, gs)
	ck.glow.position = CK_CORE * sc * CK_HS - Vector2(gs, gs) * 0.5
	ck.glow.modulate.a = clampf(0.18 + 0.22 * pul * (0.4 + post_spd) + 0.45 * minf(1.0, float(g.boost)), 0.0, 0.9)
	if OS.get_environment("CKDBG") != "" and Engine.get_process_frames() == 400:
		for k in hud.keys():
			if hud[k] is Control and (hud[k] as Control).is_visible_in_tree():
				var rr: Rect2 = (hud[k] as Control).get_global_rect()
				if rr.end.y > vp.y * 0.6 and rr.size.y < vp.y * 0.6:
					print("CKHUD ", k, " ", rr, " vp=", vp)
	if OS.get_environment("CKDBG") != "" and Engine.get_process_frames() % 20 == 0:
		print("CKDBG state=", state, " roll=", snappedf(float(g.roll), 0.001), " rot=", snappedf(ck_rot, 0.01), " u=", snappedf(float(g.get("u", 0.0)), 0.01), " glow=", snappedf(ck.glow.modulate.a, 0.01), " fov=", snappedf(cam.fov, 0.1))


# Head-up-Display im Cockpit: schwebende Neon-Linien vor dir (Zielkreis mit Tempo, Horizont-Striche, Waffe groß darüber,
# Zielrahmen um Gegner vor dir, Pfeile für Gegner dicht hinter dir). Flimmert leicht, wackelt bei Treffern, schwimmt beim Lenken nach.
var ckh = {"w": "", "wt": 9.0, "sw": Vector2.ZERO, "gl": 0.0, "vt": 9.0, "mis": false, "mang": 0.0, "mine": false, "al": 0.0,
	"rf": 9.0, "rc": Color(0.4, 0.95, 1.0), "lmp": -1, "push": 0.0, "kick": 0.0, "bo": 0.0, "lj": 0.0, "ljt": 9.0, "air": false, "scr": 0}


func _ck_core_hit(p: Vector2) -> bool:
	if ck.is_empty() or not is_instance_valid(ck.glow) or not (ck.root as Control).visible or not (ck.hands as Control).visible:
		return false
	var gr: Rect2 = (ck.glow as Control).get_global_rect()
	return p.distance_to(gr.get_center()) < gr.size.x * 0.55


func ck_hud_tick(dt: float, g: Dictionary) -> void:
	var w = str(g.get("wpn", ""))
	if w != ckh.w:
		if w != "":
			ckh.wt = 0.0   # gerade eingesammelt: Symbol springt groß auf
		ckh.w = w
	ckh.wt = float(ckh.wt) + dt
	ckh.vt = float(ckh.vt) + dt
	var racing_now = state in ["race", "count"] and not g.out
	# Warnung: Lenkrakete auf dich (Richtung merken) – Minen voraus in deiner Spur
	var mis = false
	var best = 999.0
	if racing_now:
		for sh in shots:
			var tg = sh.get("tg")
			if tg != null and typeof(tg) == TYPE_DICTIONARY and int(tg.get("idx", -1)) == int(g.idx):
				var dz = float(sh.z) - float(g.z)
				if absf(dz) < best:
					best = absf(dz)
					mis = true
					ckh.mang = atan2(float(sh.lat) - float(g.lat), -dz * 0.25)
	var mine = false
	if racing_now:
		for m in mines:
			if m.get("own", 0) == 0:
				continue
			var mz: float = m.z - g.z
			if mz > 1.0 and mz < 35.0 and absf(m.lat - g.lat) < 1.4:
				mine = true
				break
	ckh.mis = mis
	ckh.mine = mine
	ckh.al = move_toward(float(ckh.al), 1.0 if (mis or mine) else 0.0, dt * 3.0)
	# Lichtreflex: alle 6 Einheiten steht eine Lampe auf der Bande – beim Vorbeiflug huscht ein Lichtband über das Cockpit
	ckh.rf = float(ckh.rf) + dt * clampf(float(g.spd) / 4.0, 3.0, 9.0)
	if not _jungle() and racing_now:
		var lzv = T.lz(float(g.z))
		var lmp = int(floor((lzv - 24.0) / 6.0))
		if lmp != int(ckh.lmp):
			if int(ckh.lmp) >= 0 and lzv > 24.0 and lzv < 719.0:
				ckh.rf = 0.0
				ckh.rc = Color(0.45, 0.95, 1.0) if lmp % 2 == 0 else Color(1.0, 0.4, 0.9)
			ckh.lmp = lmp
	# Fliehkraft: dauernd etwas beim Boost, dazu ein Stoß, wenn der Boost einsetzt
	var bo = float(g.boost)
	if bo > 0.45 and float(ckh.bo) < 0.15:
		ckh.kick = 1.0
	ckh.bo = bo
	ckh.kick = maxf(0.0, float(ckh.kick) - dt * 2.5)
	var pt = 0.35 * minf(1.0, bo) + 0.65 * float(ckh.kick)
	ckh.push = lerpf(float(ckh.push), pt, 1.0 - exp(-dt / 0.12))
	# Aufsetzen nach einem Sprung: gedämpftes Nachfedern
	var air = bool(g.get("air", false))
	if bool(ckh.air) and not air:
		ckh.ljt = 0.0
	ckh.air = air
	ckh.ljt = float(ckh.ljt) + dt
	ckh.lj = sin(float(ckh.ljt) * 26.0) * exp(-float(ckh.ljt) * 7.0) if float(ckh.ljt) < 1.0 else 0.0
	# an der Bande schrammen: Seite merken (−1 links, 1 rechts)
	ckh.scr = 0
	if racing_now and absf(float(g.lat)) >= T.TW - 0.31 and not air and float(g.spd) > 1.0 and float(g.shield) <= 0.0:
		ckh.scr = 1 if float(g.lat) > 0.0 else -1
	# Schaden: bei wenig Energie Bildstörungen im Head-up-Display
	if racing_now and float(g.en) < 0.3 and randf() < dt * (1.0 + 6.0 * (0.3 - float(g.en)) / 0.3):
		ckh.gl = maxf(float(ckh.gl), randf_range(0.3, 0.7))
	# Nachschwimmen: das Bild hängt beim Lenken kurz hinterher
	var sw_t = Vector2(-ck_rot * 26.0, absf(ck_rot) * 6.0)
	ckh.sw = (ckh.sw as Vector2).lerp(sw_t, 1.0 - exp(-dt / 0.18))
	# kurze Bildstörung bei Treffern
	ckh.gl = maxf(float(ckh.gl) - dt * 3.0, 0.0)
	if shake > 0.35:
		ckh.gl = maxf(float(ckh.gl), shake)
	if ck.has("hud") and is_instance_valid(ck.hud):
		(ck.hud as Control).queue_redraw()


# Linien mit weichem Schein (breit und schwach, darüber schmal und hell)
func _hl(c: Control, a: Vector2, b: Vector2, col: Color, w: float, aa := true) -> void:
	c.draw_line(a, b, Color(col, col.a * 0.22), w * 3.2, aa)
	c.draw_line(a, b, Color(col.lerp(Color(1, 1, 1), 0.25), minf(1.0, col.a * 1.15)), w, aa)


func _ha(c: Control, p: Vector2, r: float, a0: float, a1: float, n: int, col: Color, w: float, aa := true) -> void:
	c.draw_arc(p, r, a0, a1, n, Color(col, col.a * 0.22), w * 3.2, aa)
	c.draw_arc(p, r, a0, a1, n, Color(col.lerp(Color(1, 1, 1), 0.25), minf(1.0, col.a * 1.15)), w, aa)


func _hp(c: Control, pts: PackedVector2Array, col: Color, w: float, aa := true) -> void:
	c.draw_polyline(pts, Color(col, col.a * 0.22), w * 3.2, aa)
	c.draw_polyline(pts, Color(col.lerp(Color(1, 1, 1), 0.25), minf(1.0, col.a * 1.15)), w, aa)


# Schrift mit dunklem, weichem Rand, damit sie auch vor hellem Neon lesbar bleibt
func _ht(c: Control, font: Font, p: Vector2, txt: String, al: int, wd: float, fs: int, col: Color) -> void:
	c.draw_string_outline(font, p, txt, al, wd, fs, maxi(3, int(fs * 0.22)), Color(0.0, 0.02, 0.06, 0.55 * col.a))
	c.draw_string(font, p, txt, al, wd, fs, col)


func _ck_hud_draw(c: Control) -> void:
	if not ck.has("hud") or ck.hud != c or ships.is_empty() or not (ck.root as Control).visible:
		return
	var g: Dictionary = _focus()
	var vp = c.size
	var u = vp.x / 540.0
	var t = Time.get_ticks_msec() / 1000.0
	var font = ThemeDB.fallback_font
	var CY = Color(0.35, 0.95, 1.0)
	var MG = Color(1.0, 0.3, 0.85)
	var fl = 0.82 + 0.1 * sin(t * 37.0) * sin(t * 11.0) + 0.08 * float(fmod(t * 7.3, 1.0) < 0.05)   # Flimmern
	if float(g.en) < 0.3 and state in ["race", "count"]:
		fl *= 0.55 + 0.45 * float(fmod(t * 13.7, 1.0) > 0.18 * (1.0 - float(g.en) / 0.3))   # Schaden: Anzeige setzt kurz aus
	var jit = Vector2.ZERO
	if float(ckh.gl) > 0.0:
		jit = Vector2(sin(t * 91.0) * 7.0, sin(t * 67.0) * 2.0) * float(ckh.gl) * u
	var C = Vector2(vp.x * 0.5, vp.y * 0.4) + (ckh.sw as Vector2) * u + jit
	var bo = clampf(float(g.boost), 0.0, 1.0)
	var spc = CY.lerp(MG, bo)
	var lw = maxf(2.0, 2.6 * u)
	# --- Horizont-Striche links und rechts
	for sd in [-1.0, 1.0]:
		_hl(c, C + Vector2(sd * 74.0, 0) * u, C + Vector2(sd * 150.0, 0) * u, Color(CY, 0.55 * fl), lw, true)
		_hl(c, C + Vector2(sd * 150.0, 0) * u, C + Vector2(sd * 150.0, 8) * u, Color(CY, 0.55 * fl), lw, true)
		for k in range(1, 3):
			var yy = 34.0 * k
			_hl(c, C + Vector2(sd * 96.0, -yy) * u, C + Vector2(sd * 130.0, -yy) * u, Color(CY, 0.22 * fl), lw * 0.8, true)
			_hl(c, C + Vector2(sd * 96.0, yy) * u, C + Vector2(sd * 130.0, yy) * u, Color(CY, 0.22 * fl), lw * 0.8, true)
	# --- Zielkreis: vier Bogenstücke, innen ein Punkt
	var rr = 40.0 * u
	for k in range(4):
		var a0 = TAU * k / 4.0 + 0.25 + t * 0.4
		_ha(c, C, rr, a0, a0 + 1.0, 12, Color(CY, 0.8 * fl), lw, true)
	c.draw_circle(C, 2.5 * u, Color(CY, 0.9 * fl))
	# --- Tempo-Bogen außen (270°), wird beim Boost magenta
	var sv = clampf(float(g.spd) / maxf(1.0, base_spd * 1.6), 0.0, 1.0)
	var a_s = PI * 0.75
	_ha(c, C, 54.0 * u, a_s, a_s + PI * 1.5, 40, Color(CY, 0.18 * fl), lw * 2.0, true)
	if sv > 0.01:
		_ha(c, C, 54.0 * u, a_s, a_s + PI * 1.5 * sv, 40, Color(spc, 0.85 * fl), lw * 2.0, true)
	# Tempo als Zahl unter dem Kreis
	var vs = str(int(round(float(hud.get("gs", 0.0)) * 12.0)))
	var fs = int(30.0 * u)
	var vw = font.get_string_size(vs, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_ht(c, font, C + Vector2(-vw * 0.5, 92.0 * u), vs, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(spc, 0.95 * fl))
	var ks = "BOOST" if bo > 0.02 else "KM/H"
	var kf = int(13.0 * u)
	var kw = font.get_string_size(ks, HORIZONTAL_ALIGNMENT_LEFT, -1, kf).x
	_ht(c, font, C + Vector2(-kw * 0.5, 108.0 * u), ks, HORIZONTAL_ALIGNMENT_LEFT, -1, kf, Color(spc, 0.7 * fl))
	# Boost: Winkel-Pfeile wandern vom Kreis nach außen
	if bo > 0.02:
		for k in range(3):
			var ph = fmod(t * 2.2 + k / 3.0, 1.0)
			var dx = (70.0 + 70.0 * ph) * u
			var al = (1.0 - ph) * bo * fl
			for sd in [-1.0, 1.0]:
				var q = C + Vector2(sd * dx, 0)
				_hp(c, PackedVector2Array([q + Vector2(-sd * 7, -9) * u, q, q + Vector2(-sd * 7, 9) * u]), Color(MG, al), lw * 1.3, true)
	# --- Waffe: großes Symbol über dem Kreis, springt beim Einsammeln auf
	var w = str(ckh.w)
	if w != "":
		var wc: Color = WC.get(w, CY)
		if g.get("mega", false):
			wc = Color(1.0, 0.25, 0.3)
		elif g.get("sup", false):
			wc = Color(1.0, 0.85, 0.3)
		var wt = float(ckh.wt)
		var pop = 1.0 + 1.2 * exp(-wt * 6.0) * cos(wt * 14.0)
		var P = C + Vector2(0, -112.0) * u
		var ws = 22.0 * u * pop
		var bs = 34.0 * u * pop
		var ba = clampf(0.55 + 0.45 * sin(t * 5.0), 0.0, 1.0) * fl
		# Eck-Klammern um das Symbol
		for cx in [-1.0, 1.0]:
			for cy in [-1.0, 1.0]:
				var q = P + Vector2(cx, cy) * bs
				_hl(c, q, q - Vector2(cx * 12.0, 0) * u, Color(wc, 0.6 + 0.4 * ba), lw, true)
				_hl(c, q, q - Vector2(0, cy * 12.0) * u, Color(wc, 0.6 + 0.4 * ba), lw, true)
		_wicon(c, P, ws, w, Color(wc, 0.95 * fl))
		var nm = str(WN.get(w, ""))
		if g.get("mega", false):
			nm = "MEGA " + nm
		elif g.get("sup", false):
			nm = "SUPER " + nm
		var nf = int(14.0 * u)
		var nw = font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, nf).x
		_ht(c, font, P + Vector2(-nw * 0.5, bs + 20.0 * u), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, nf, Color(wc, 0.85 * fl))
		if wt < 0.5:   # Ring, der beim Einsammeln aufgeht
			_ha(c, P, bs * (1.0 + wt * 4.0), 0.0, TAU, 32, Color(wc, (1.0 - wt * 2.0) * 0.9), lw * 1.5, true)
	# --- Gegner vor dir: Zielrahmen mit Name und Abstand
	if state in ["race", "count", "replay"]:
		for i in range(ships.size()):
			var o: Dictionary = ships[i]
			if int(o.idx) == int(g.idx) or o.out:
				continue
			var dz = float(o.z) - float(g.z)
			var pc: Color = CHARS[i][2] if i < CHARS.size() else CY
			pc = pc.lerp(Color(1, 1, 1), 0.3)
			if dz > 2.5 and dz < 80.0:
				var wp = (o.node as Node3D).global_position
				if cam.is_position_behind(wp):
					continue
				var sp: Vector2 = cam.unproject_position(wp) * (vp.x / maxf(1.0, get_viewport().get_visible_rect().size.x))
				var bz = clampf(260.0 / dz, 9.0, 34.0) * u
				var al = clampf(1.2 - dz / 80.0, 0.3, 1.0) * fl
				for cx in [-1.0, 1.0]:
					for cy in [-1.0, 1.0]:
						var q = sp + Vector2(cx * bz * 1.4, cy * bz)
						_hl(c, q, q - Vector2(cx * bz * 0.5, 0), Color(pc, al), lw, true)
						_hl(c, q, q - Vector2(0, cy * bz * 0.5), Color(pc, al), lw, true)
				var lab = "%s %dm" % [CHARS[i][0] if i < CHARS.size() else "?", int(dz * 4.0)]
				var lf = int(12.0 * u)
				_ht(c, font, sp + Vector2(bz * 1.4 + 4.0 * u, -bz + lf), lab, HORIZONTAL_ALIGNMENT_LEFT, -1, lf, Color(pc, al * 0.9))
			elif dz < -0.5 and dz > -18.0:
				# dicht hinter dir: Pfeil unten am Anzeigefeld, links/rechts nach Spur
				var x = C.x + clampf((float(o.lat) - float(g.lat)) / T.TW, -1.0, 1.0) * 120.0 * u
				var y = C.y + 132.0 * u
				var al2 = clampf(1.0 + dz / 18.0, 0.2, 1.0) * (0.6 + 0.4 * sin(t * 9.0)) * fl
				var q2 = Vector2(x, y)
				c.draw_colored_polygon(PackedVector2Array([q2 + Vector2(-9, -5) * u, q2 + Vector2(9, -5) * u, q2 + Vector2(0, 6) * u]), Color(pc, al2))
				var lab2 = "%dm" % int(-dz * 4.0)
				var lf2 = int(11.0 * u)
				var lw2 = font.get_string_size(lab2, HORIZONTAL_ALIGNMENT_LEFT, -1, lf2).x
				_ht(c, font, q2 + Vector2(-lw2 * 0.5, 20.0 * u), lab2, HORIZONTAL_ALIGNMENT_LEFT, -1, lf2, Color(pc, al2 * 0.9))
	# --- Warnung: Dreieck mit Ausrufezeichen, darunter was kommt; bei Raketen ein Pfeil am Zielkreis aus der Richtung
	if bool(ckh.mis) or bool(ckh.mine):
		var bl = 0.5 + 0.5 * sin(t * 10.0)
		var RD = Color(1.0, 0.18, 0.12)
		var W = C + Vector2(0, -210.0) * u
		var tri = PackedVector2Array([W + Vector2(0, -26) * u, W + Vector2(28, 22) * u, W + Vector2(-28, 22) * u, W + Vector2(0, -26) * u])
		c.draw_colored_polygon(tri, Color(RD, 0.18 + 0.2 * bl))
		_hp(c, tri, Color(RD, 0.65 + 0.35 * bl), lw * 1.4)
		_hl(c, W + Vector2(0, -12) * u, W + Vector2(0, 6) * u, Color(1, 0.9, 0.85, 0.7 + 0.3 * bl), lw * 1.6)
		c.draw_circle(W + Vector2(0, 13) * u, 2.6 * u, Color(1, 0.9, 0.85, 0.7 + 0.3 * bl))
		var wn = "MISSILE" if bool(ckh.mis) else "MINES AHEAD"
		var wf = int(18.0 * u)
		var ww = font.get_string_size(wn, HORIZONTAL_ALIGNMENT_LEFT, -1, wf).x
		_ht(c, font, W + Vector2(-ww * 0.5, 48.0 * u), wn, HORIZONTAL_ALIGNMENT_LEFT, -1, wf, Color(RD.lerp(Color(1, 1, 1), 0.2), 0.75 + 0.25 * bl))
		if bool(ckh.mis):
			var dv = Vector2(sin(float(ckh.mang)), -cos(float(ckh.mang)))
			var ap = C + dv * 72.0 * u
			var nv = Vector2(-dv.y, dv.x)
			var arr = PackedVector2Array([ap + dv * 14.0 * u, ap - dv * 6.0 * u + nv * 10.0 * u, ap - dv * 6.0 * u - nv * 10.0 * u])
			c.draw_colored_polygon(arr, Color(RD, 0.6 + 0.4 * bl))
	# --- Sicht gewechselt: Name kurz groß einblenden
	if float(ckh.vt) < 1.4:
		var vn = VM_NAMES[int(cfg.get("vmode", 0)) % VM_NAMES.size()]
		var va = clampf(1.4 - float(ckh.vt), 0.0, 1.0) * fl
		var vf = int(24.0 * u)
		var vwd = font.get_string_size(vn, HORIZONTAL_ALIGNMENT_LEFT, -1, vf).x
		var vcol = [CY, Color(1.0, 0.55, 0.15), Color(0.2, 1.0, 0.55)][int(cfg.get("vmode", 0)) % 3]
		_ht(c, font, C + Vector2(-vwd * 0.5, -170.0 * u), vn, HORIZONTAL_ALIGNMENT_LEFT, -1, vf, Color(vcol, va))
	# --- feine Zeilen über allem, wie bei einer Projektion
	var sl = int(vp.y * 0.18 / (6.0 * u))
	for k in range(sl):
		var yy = C.y - 150.0 * u + k * 6.0 * u + fmod(t * 20.0, 6.0) * u
		c.draw_line(Vector2(C.x - 160.0 * u, yy), Vector2(C.x + 160.0 * u, yy), Color(CY, 0.03 * fl), 1.0)


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
	_bc("comic %s who=%d" % [kind, who])
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
	# Start-Comic: Tippen geht durch (die Daumen liegen schon zum Lenken auf dem Display) – überspringen nur per SKIP-Knopf
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE if kind == "ko" or kind == "start" else Control.MOUSE_FILTER_STOP
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
				pn.append({"ch": ch2, "img": _cm_img(ch2[3] + "_1"), "line": _pick(CM_WIN[ch2[3]]), "t0": 0.8 + k2 * 0.3, "fy": 0.45, "vo": "cv_%s_lose" % ch2[3] if k2 == vk else ""})
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
			pn.append({"ch": v, "img": _cm_img("ko_" + v[3]), "line": _pick(CM_KO[v[3]]), "t0": 0.0, "fy": 0.5, "noname": false, "vo": "cv_%s_mad" % v[3]})
			stamp = ["K.O.!", Color(1.0, 0.85, 0.15)]
			end = 3.3
			_snd("cm_crash", -3.0)
	var ns = pn.size()
	var st = pn[ns - 1].t0 + 0.5
	cm = {"kind": kind, "who": who, "t": 0.0, "layer": layer, "c": c, "pn": pn, "end": end if end > 0.0 else 6.0,
		"skip": -1.0, "hit": -1, "stamp": stamp, "st": st, "hold": hold}
	c.draw.connect(_comic_draw.bind(c))
	# nur der erste Tipp zählt – vorher setzte jeder weitere Tipp das Ausblenden zurück, und der Comic tauchte wieder auf
	c.gui_input.connect(func(ev):
		if (ev is InputEventScreenTouch or ev is InputEventMouseButton) and ev.pressed and cm.has("c") and cm.t > 0.6 and cm.skip < 0.0:
			cm.skip = cm.t)
	if kind == "start":
		var sb = _skip_btn()
		sb.pressed.connect(func():
			if cm.has("c") and cm.get("skip", 0.0) < 0.0:
				cm.skip = cm.t)
		layer.add_child(sb)
		cm.sb = sb


func _comic_end() -> void:
	if cm.has("layer") and is_instance_valid(cm.layer):
		(cm.layer as CanvasLayer).queue_free()
	cm = {}


func _comic_update(dt: float) -> void:
	if cm.has("pending"):
		if warm_t < 0.0:
			_comic_build(cm.pending)
		return
	if not cm.has("c") or not is_instance_valid(cm.c):
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
	# K.o.-Seite: erst flucht der Getroffene, dann setzt Ren kühl nach („Verschwinde.“)
	if cm.kind == "ko" and cm.t >= 2.15 and not cm.get("rko", false) and cm.skip < 0.0:
		cm.rko = true
		_snd("cv_ren_ko", 2.0)
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
	if cm.has("sb") and is_instance_valid(cm.sb):
		(cm.sb as Control).modulate.a = cm.fade
		(cm.sb as Control).visible = cm.skip < 0.0
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


func _comic_draw(c: Control) -> void:
	# Nur das Comic zeichnen, das gerade dran ist. Ein altes Bild, das im selben Moment noch einmal neu gezeichnet wird
	# (zweiter K.o., während das erste Comic noch steht), fand hier früher kein „c“ mehr → Absturz in Build 185.
	if not cm.has("c") or not is_instance_valid(c) or cm.c != c:
		return
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
	if kind != "ko" and kind != "start":
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
	if OS.get_environment("FINFLASH") != "":
		# nur zum Testen: Rennende direkt nach einer Explosion, mit dem längsten Ergebnistext
		hud.res.text = "1st  ·  LAST ONE STANDING\n0:40.41"
		_flash(Color(1.0, 0.9, 0.8), 1.0)
		expo_v = 1.5
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
		# zu lange Zeilen umbrechen („LAST ONE“ / „STANDING“), die Schrift bleibt groß;
		# nur wenn ein einzelnes Wort nicht passt, wird sie kleiner
		var vw: float = get_viewport().get_visible_rect().size.x * 0.9 - 28.0
		var fnt: Font = l.get_theme_font("font")
		var fs = 84
		var src: PackedStringArray = l.text.split("\n")
		var out: Array = []
		while true:
			out.clear()
			var fits = true
			for ln in src:
				var cur = ""
				for wd in ln.split(" ", false):
					if fnt.get_string_size(wd, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > vw:
						fits = false
					var tr = wd if cur == "" else cur + " " + wd
					if cur != "" and fnt.get_string_size(tr, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > vw:
						out.append(cur)
						cur = wd
					else:
						cur = tr
				out.append(cur)
			if fits or fs <= 30:
				break
			fs -= 2
		l.text = "\n".join(out)
		l.add_theme_font_size_override("font_size", fs)
		cl.add_child(l)
		create_tween().tween_property(l, "modulate:a", 1.0, 0.4)
		fin.lbl = cl
	if fin.phase == 0:
		var wait = fly_t if fin.fly else 1.2
		if fin.t >= wait:
			if fin.has("lbl") and is_instance_valid(fin.lbl):
				_qf(fin.lbl)
			if fin.win and not ships[0].out and not free_ride and not _jungle():
				fin.phase = 5   # Siegerfeier am Ziel, danach die Comic-Seite
				fin.pt = 0.0
				_party_start()
			else:
				fin.phase = 1
				_comic_start("win" if fin.win else "lose", fin.who)
	elif fin.phase == 5:
		fin.pt = float(fin.pt) + dt
		if OS.get_environment("FEETDBG") != "" and not party.is_empty() and int(fin.get("fdb", 0)) == 0 and float(fin.pt) > 1.0:
			fin.fdb = 1
			for fg in (party.n as Node3D).find_children("*", "Skeleton3D", true, false):
				var skf: Skeleton3D = fg
				var lo = 1e9
				for bn in ["mixamorig_LeftToe_End", "mixamorig_LeftToeBase", "mixamorig_LeftFoot", "mixamorig_RightToe_End", "mixamorig_RightFoot"]:
					var bi = skf.find_bone(bn)
					if bi >= 0:
						lo = minf(lo, (skf.global_transform * skf.get_bone_global_pose(bi).origin).y)
				var fz = T.frame(float(party.z))
				print("FEET ", skf.get_parent().get_parent().name if skf.get_parent() else "?", " lowest foot bone above road=", snappedf(lo - fz.c.y, 0.001))
		if OS.get_environment("PARTYT") != "":
			# nur zum Testen: mehrere Bilder der Feier (Zeiten mit Komma), Pfad SHOTPATH + _n.png
			var ts = OS.get_environment("PARTYT").split(",")
			var k = int(fin.get("pk", 0))
			if k < ts.size() and fin.pt >= float(ts[k]):
				get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOTPATH").replace(".png", "_%d.png" % k))
				fin.pk = k + 1
				if k + 1 >= ts.size():
					get_tree().quit()
		if fin.pt >= PARTY_T or fin.get("skip", false):
			fin.phase = 1
			_party_end()
			_comic_start("win", fin.who)
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
	dg_reloading = true
	_bc("reload")
	# Pause unbedingt aufheben – sonst lädt die neue Szene eingefroren und der Ladebalken bleibt stehen
	get_tree().paused = false
	if paused_ui != null and is_instance_valid(paused_ui):
		paused_ui.queue_free()
	paused_ui = null
	Engine.time_scale = 1.0
	AudioServer.playback_speed_scale = 1.0
	OS.set_environment("AG_RELOADED", "1")   # Testaufrufe vom Rechner (--shot, --steertest …) gelten nur für den ersten Start
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
	# nur noch eine Lenkung: linke / rechte Bildschirmhälfte halten
	var mh = _lbl("Lenken: linke oder rechte Bildschirmhälfte halten", 24)
	mh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mh.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mh.modulate = Color(1, 1, 1, 0.8)
	vb.add_child(mh)
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
		(e[1] as Label).text = ("%.2f s" % v) if r[1] == "ramp" else ("Aus" if v < 0.01 else "%d %%" % int(round(v * 100.0)))


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
				_snd("beep", -5.0, 1.0)
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
const GA_RC = Vector2(468.0, 1361.0)   # Mitte des orangen Rings im Rahmen (nachgemessen)
const GA_RR = 143.0
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
	f.offset_left = -150.0 * k
	f.offset_right = 150.0 * k
	f.offset_top = -(GA_H - 1200.0) * k
	f.offset_bottom = -(GA_H - 1560.0) * k
	# neue Waffe: sofort da (kein Roulette mehr), springt nur kurz ins Rad
	var w: String = g.wpn
	if w != ga_last:
		if w != "" and state == "race":
			ga_rl = {"t": 0.0, "seq": [w], "i": 0}
		ga_last = w
	if not ga_rl.is_empty():
		ga_rl.t += dt
		if ga_rl.t > 0.6:
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
	c.draw_texture_rect_region(ga_tex, Rect2(0, 0, GA_W, 460), Rect2(0, 0, GA_W, 460))
	_ga_txt(c, Vector2(78, 163), "POS", 22, OR2)
	if free_ride:
		_ga_txt(c, Vector2(78, 213), "FREE", 46, TXT, 0, 6)
	else:
		var pl = str(hud.pl.text).substr(0, 1)
		_ga_txt(c, Vector2(156, 215), pl if pl != "" else "-", 62, Color(1, 1, 1), 2, 6)
		_ga_txt(c, Vector2(162, 215), str(hud.pln.text), 34, TXT, 0, 5)
	var lap = clampi(int(floor((g.z - T.ZST) / T.LAP)) + 1, 1, 99)
	_ga_txt(c, Vector2(636, 165), "LAP", 22, OR2)
	_ga_txt(c, Vector2(866, 175), ("%d" % lap) if free_ride else ("%d/%d" % [mini(lap, T.LAPS), T.LAPS]), 44, Color(1, 1, 1), 2, 6)
	_ga_txt(c, Vector2(632, 255), "TIME", 20, OR2)
	_ga_txt(c, Vector2(866, 263), _fmt(race_t), 32, TXT, 2, 5)
	# ---- unten
	var oy = vp.y - GA_H * k
	c.draw_set_transform(Vector2(0, oy), 0.0, Vector2(k, k))
	c.draw_texture_rect_region(ga_tex, Rect2(0, 1100, GA_W, GA_H - 1100), Rect2(0, 1100, GA_W, GA_H - 1100))
	# Tempo
	var bo = clampf(g.boost, 0.0, 1.0)
	var sc = Color(1.0, 0.3, 0.2) if bo > 0.02 else Color(1, 1, 1)
	_ga_txt(c, Vector2(66, 1469), "BOOST" if bo > 0.02 else "SPEED", 20, Color(1.0, 0.3, 0.2) if bo > 0.02 else OR2)
	_ga_txt(c, Vector2(236, 1512), str(int(round(float(hud.gs) * 12.0))), 52, sc, 2, 6)
	_ga_txt(c, Vector2(244, 1510), "KM/H", 16, TXT)
	# Energie: zehn schräge Segmente
	var en = clampf(g.en, 0.0, 1.0)
	var low = en <= 0.25 and not g.out
	var ec = OR2 if en > 0.5 else (Color(1.0, 0.85, 0.25) if en > 0.25 else Color(1.0, 0.2, 0.15))
	_ga_txt(c, Vector2(628, 1469), "ENERGY", 20, ec)
	_ga_txt(c, Vector2(872, 1469), "%d %%" % int(round(en * 100.0)), 20, TXT, 2)
	for i in range(10):
		var x0 = 630.0 + i * 24.0
		var fl = clampf(en * 10.0 - i, 0.0, 1.0)
		var col = Color(0.18, 0.1, 0.06, 0.9).lerp(ec, fl)
		if low and fl > 0.0 and fmod(t * 7.0 + i * 0.37, 1.0) > 0.6:
			col.a *= 0.4
		c.draw_colored_polygon(PackedVector2Array([Vector2(x0 + 9, 1478), Vector2(x0 + 29, 1478), Vector2(x0 + 20, 1506), Vector2(x0, 1506)]), col)
	# Waffenrad: Mitte = deine Waffe, links/rechts die Nachbarn; beim Einsammeln rattert es durch (Roulette)
	var w: String = g.wpn
	var cw = w
	var spin = false
	var ci = _ga_widx(cw)
	var mega = g.get("mega", false)
	var sup = g.get("sup", false)
	var gc = Color(1.0, 0.15, 0.2) if mega else (Color(1.0, 0.8, 0.25) if sup else WC.get(cw, OR2))
	if cw != "":
		var bounce = 0.0
		if not ga_rl.is_empty():
			var since = float(ga_rl.t)
			bounce = sin(since * 22.0) * exp(-since * 7.0) * 6.0
		var pu = 0.5 + 0.5 * sin(t * 5.0)
		if not spin:
			# Glühen hinter dem mittleren Feld
			var tr = PackedVector2Array([Vector2(388, 1250), Vector2(552, 1250), Vector2(502, 1383), Vector2(440, 1383), Vector2(388, 1250)])
			c.draw_polyline(tr, Color(gc, 0.35 + 0.4 * pu), 9.0, true)
			c.draw_polyline(tr, Color(gc, 0.9), 3.0, true)
		_wicon(c, Vector2(471, 1292 + bounce), 40.0, cw, Color(1, 1, 1, 0.95) if not spin else Color(1, 1, 1, 0.75))
		var nm = str(WN.get(cw, "")).replace("FORCE FIELD", "FIELD")
		_ga_txt(c, Vector2(471, 1357 + bounce), nm, 22 if nm.length() < 7 else 18, Color(gc, 1.0) if not spin else TXT, 1, 5)
		if (sup or mega) and not spin:
			_ga_txt(c, Vector2(471, 1244), "MEGA" if mega else "SUPER", 18, gc, 1, 5)
	elif g.auto > 0.0:
		_wicon(c, Vector2(471, 1292), 40.0, "auto", Color(0.5, 0.95, 1.0, 0.9))
		_ga_txt(c, Vector2(471, 1357), "AUTO %.1f" % g.auto, 20, Color(0.5, 0.95, 1.0), 1, 5)
	else:
		_ga_txt(c, Vector2(471, 1322), "—", 30, Color(1, 1, 1, 0.25), 1)
	# Autopilot-Restzeit als Bogen ums Rad
	if g.auto > 0.0 and state == "race":
		var ac = Color(1.0, 0.78, 0.2) if g.get("sauto", false) else Color(0.4, 0.95, 1.0)
		c.draw_arc(GA_RC, GA_RR, 0.0, TAU, 64, Color(ac, 0.15), 6.0, true)
		if g.get("ahold", false):
			# wartet auf eine Gerade: pulsiert
			c.draw_arc(GA_RC, GA_RR, 0.0, TAU, 64, Color(ac, 0.3 + 0.5 * (0.5 + 0.5 * sin(t * 8.0))), 6.0, true)
		else:
			c.draw_arc(GA_RC, GA_RR, -PI * 0.5, -PI * 0.5 + TAU * clampf(g.auto / 5.0, 0.0, 1.0), 64, Color(ac, 0.9), 6.0, true)
	# FIRE-Knopf: Schwert und Schrift, glüht, wenn eine Waffe bereit ist
	var armed = w != "" and not spin
	var fp = Vector2(470, 1498)
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


# Einstellleiste der Teststrecke: die einzige Stelle, an der die Lenkung eingestellt wird
const STT_ROWS = [["steer", "ramp", "Reaktion  (weniger = sofort volle Lenkkraft)", 0.05], ["steer", "power", "Lenkkraft  (mehr = engere Kurven)", 0.05],
	["steer", "assist", "Lenkhilfe zu den Feldern  (0 = aus)", 0.1], ["steer", "bank", "Kurvenneigung  (Optik)", 0.1],
	["steer", "recover", "Aufrichten  (mehr = richtet sich schneller auf)", 0.25],
	["steer", "leanin", "Hineinlegen  (mehr = legt sich schneller rein)", 0.1],
	["steer", "wob", "Nachwippen  (0 = keins, mehr = schwingt nach)", 0.1],
	["steer", "nosev", "Nase drehen  (0 = Nase geradeaus, Schiff kippt nur)", 0.1]]


func _stt_rows() -> void:
	var vb: VBoxContainer = stt.rowbox
	for c in vb.get_children():
		c.queue_free()
	stt.rows = []
	for r in STT_ROWS:
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


# ---------------------------------------------------------------- Neustart ohne Neuladen und Pause
# „Race again“ und „Menu“ bauen die Strecke nicht neu auf: Schiffe und Rennzustand gehen auf den Stand
# direkt nach dem Vorwärmen zurück, Effekte des letzten Rennens werden weggeräumt – das geht sofort.
const RACE_VARS = ["shots", "mines", "fxs", "walls", "quake", "quake2", "bwaves", "fire_req", "t_state", "race_t", "steer_btn", "btn_t",
	"last_steer", "touches", "cam_psi", "cam_d", "post_spd", "scr_v", "gl_v", "expo_v", "kmax", "sg_a",
	"resb_t", "resb_armed", "msg_t", "last_place", "pl_flash", "big_t", "shake", "live_bursts", "fx_age", "mine_grp",
	"lk_tg", "lk_k", "lk_bt", "lk_t", "zaps", "rec", "rec_ev", "rec_clk", "rec_acc", "rec_pl", "rp", "kc", "kc_pending", "mine_bt",
	"en_low", "board_t", "board_man", "board_pg", "fin", "ga_rl", "ga_last",
	"last_c", "tun_k", "cm", "debris", "scorch", "col_pairs", "whale", "whale_lap", "wet", "blind", "blk_t", "blk_v", "mc", "radio", "radio_cd", "radio_side"]
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


# Knoten wegräumen, aber nur, wenn es ihn noch gibt (ein Aufruf auf einen schon gelöschten Knoten lässt die Handy-Fassung abstürzen)
func _qf(x) -> void:
	if typeof(x) == TYPE_OBJECT and is_instance_valid(x) and x is Node:
		(x as Node).queue_free()


func _free_fx_entry(e) -> void:
	if typeof(e) == TYPE_OBJECT:
		if is_instance_valid(e) and e is Node:
			_qf(e)
	elif e is Dictionary:
		for v in (e as Dictionary).values():
			if is_instance_valid(v) and v is Node and not (v as Node).has_meta("keep"):
				var isship = false
				for o in ships:
					if o.node == v:
						isship = true
				if not isship:
					_qf(v)


# Rennen zurücksetzen (Strecke bleibt stehen). false = geht nicht, dann klassisch neu laden.
func _soft_reset() -> bool:
	_bc("soft reset")
	_dg_flush()
	if race0.is_empty() or ships0.size() != ships.size() or not rpf.is_empty() or T.S or free_ride or not vx.is_empty():
		return false
	get_tree().paused = false
	if paused_ui != null and is_instance_valid(paused_ui):
		paused_ui.queue_free()
	paused_ui = null
	_hull_update(null, false, 0.0)
	_party_end()
	for o in ships:
		(o.node as Node3D).visible = true
	_props_reset()
	Engine.time_scale = 1.0
	AudioServer.playback_speed_scale = 1.0
	# Effekte des letzten Rennens wegräumen
	for k in ["shots", "mines", "fxs", "walls", "bwaves", "zaps"]:
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
		_qf(fin.lbl)
	for n in get_children():
		if n.has_meta("rfx"):
			n.queue_free()
		elif (n is GPUParticles3D or n is MeshInstance3D or n is OmniLight3D) and not race_kids.has(n) and not tun_l.has(n) and not nlights.has(n) and n != lk_n and not n.has_meta("keep"):
			n.queue_free()
		elif n is GPUParticles3D:
			n.speed_scale = 1.0
		elif (n is AudioStreamPlayer or n is AudioStreamPlayer3D) and not loops.values().has(n) and n != music_p and n != chg_p:
			n.queue_free()   # noch klingende Einzel-Geräusche
	if not cm.is_empty():
		for v in cm.values():
			if is_instance_valid(v) and v is CanvasLayer:
				v.queue_free()
	# Rennzustand zurück
	for k in RACE_VARS:
		var v = race0[k]
		set(k, v.duplicate(true) if (v is Array or v is Dictionary) else v)
	fx_gen += 1
	race_gen += 1
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
	if hud.has("again") and is_instance_valid(hud.again):
		hud.again.visible = false
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
	_bc("pause %s" % on)
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
	var b2 = _solid(_btn("RESTART"))
	b2.pressed.connect(func(): _race_again())
	bx.add_child(b2)
	var b3 = _solid(_btn("MENU"))
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
	return "Hold the left or right half of the screen."


# Lenkhilfe: zielst du schon fast auf ein Boost- oder Waffenfeld, zieht sie dich sanft das letzte Stück hin.
# Lenkst du davon weg, hilft sie nicht – du behältst immer die Kontrolle.
func _assist(s: Dictionary, dt: float) -> void:
	var a = float(fx.steer.assist)
	if a <= 0.001:
		return
	var z: float = s.z
	var tv = tan(s.vpsi)
	var best_dz = 1e9
	var best_l = 0.0
	var k0 = int(floor(z / 35.0))
	for k in [k0, k0 + 1]:
		for kind in [0, 1]:
			if kind == 1 and posmod(k, 2) != 0:
				continue
			var zt = (_bzp(k) + 1.2) if kind == 0 else _wzp(k)
			if not _pad_ok(zt):
				continue
			var dz = zt - z
			if dz < 2.5 or dz > 30.0 or dz >= best_dz:
				continue
			var tl = _bpx(k) if kind == 0 else _wpx(k)
			var miss = tl - (s.lat + dz * tv)
			if absf(miss) > LANE_W * 0.7:
				continue
			if steer_btn != 0 and absf(miss) > 0.05 and int(signf(miss)) != steer_btn:
				continue
			best_dz = dz
			best_l = tl
	if best_dz > 1e8:
		return
	var want = atan2(best_l - s.lat, best_dz)
	var k = a * 4.0 * (1.0 - 0.6 * clampf(absf(s.u), 0.0, 1.0))
	var f = 1.0 - exp(-dt * k)
	s.vpsi += (want - s.vpsi) * f
	s.psi += (want - s.psi) * f * 0.6


# Lautstärke der Kanäle: Stimmen deutlich lauter (Begrenzer verhindert Übersteuern), Musik nach Regler
func _bus_levels() -> void:
	var vi = AudioServer.get_bus_index("Voice")
	if vi >= 0:
		AudioServer.set_bus_volume_db(vi, 6.0 + linear_to_db(maxf(0.001, float(cfg.get("voice", 1.0)))))


var music_p: AudioStreamPlayer
var music_k = ""
var music_f = 0.0


func _music_update(dt: float) -> void:
	if music_p == null:
		return
	if not is_instance_valid(music_p):
		# (wurde früher beim Neustart des Rennens mit weggeräumt – dann war die Musik stumm)
		music_p = AudioStreamPlayer.new()
		music_p.bus = "Music"
		music_p.volume_db = -80.0
		add_child(music_p)
		music_k = ""
		music_f = 0.0
	var want = "music_menu" if state in ["menu", "lab", "bench"] else "music_race"
	if float(cfg.get("music", 0.6)) < 0.01:
		want = ""
	if want != music_k:
		# alte Musik ausblenden, dann die neue einblenden
		music_f = maxf(0.0, music_f - dt / 0.6)
		if music_f <= 0.0:
			music_k = want
			if want == "":
				music_p.stop()
			else:
				music_p.stream = _looped(snd[want])
				music_p.play()
	else:
		music_f = minf(1.0, music_f + dt / 1.2)
	music_p.volume_db = linear_to_db(maxf(0.0005, music_f))


# ================================================================ Fehlerprotokoll
# Schreibt mit, was im Spiel passiert (Ereignisse, alle 2 s ein Lebenszeichen, Fehlermeldungen der Engine) und welcher Teil
# der Hauptschleife gerade läuft. Stürzt die App ab, merkt sie das beim nächsten Start und bietet an, den Bericht zu kopieren.
const DG_DIR = "user://diag"
const DG_MAX = 260


class DgLogger extends Logger:
	var mx = Mutex.new()
	var buf: Array = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		var t = "%s %s:%d %s — %s" % [["ERROR", "WARNING", "SCRIPT", "SHADER"][clampi(error_type, 0, 3)], file.get_file(), line, function, rationale if rationale != "" else code]
		for bt in script_backtraces:
			if bt != null and not bt.is_empty():
				t += "\n" + bt.format(4, 6)
		mx.lock()
		buf.append(t)
		if buf.size() > 60:
			buf.pop_front()
		mx.unlock()

	func _log_message(message: String, error: bool) -> void:
		pass

	func take() -> Array:
		mx.lock()
		var b = buf.duplicate()
		buf.clear()
		mx.unlock()
		return b


var dg_t = 0.0
var dg_state = ""


func _dg_start() -> void:
	if dg_init:
		return
	dg_init = true
	DirAccess.make_dir_recursive_absolute(DG_DIR)
	var testing = OS.get_cmdline_user_args().size() > 0 or OS.get_environment("SHOTPATH") != ""
	# letzter Lauf ohne sauberes Ende (stand auf „run“) = Absturz
	var st = FileAccess.get_file_as_string(DG_DIR + "/state.txt").strip_edges()
	if (st == "run" and not testing) or OS.get_environment("DGFAKE") != "":
		var cp = FileAccess.get_file_as_string(DG_DIR + "/cp.txt").strip_edges()
		var tr = FileAccess.get_file_as_string(DG_DIR + "/trail.txt")
		dg_report = "AntiGrav 3D – Absturzbericht\nVersion: %s · Gerät: %s (%s) · %s\nLetzter Haltepunkt (Hauptschleife): %s\n\n--- Verlauf (älteste zuerst) ---\n%s" % [
			str(ProjectSettings.get_setting("application/config/version", "?")), OS.get_model_name(), OS.get_name(), Time.get_datetime_string_from_system(), cp, tr]
		var f = FileAccess.open(DG_DIR + "/crash_report.txt", FileAccess.WRITE)
		if f != null:
			f.store_string(dg_report)
			f.close()
	_dg_mark("run")
	dg_cpf = FileAccess.open(DG_DIR + "/cp.txt", FileAccess.WRITE)
	dg_logger = DgLogger.new()
	OS.add_logger(dg_logger)
	_bc("app start %s" % OS.get_model_name())


func _exit_tree() -> void:
	# Szene wird beim Neustart nur neu geladen – das ist kein Ende der App
	if dg_reloading:
		dg_reloading = false
		return
	_bc("app exit")
	_dg_flush()
	_dg_mark("exit")


func _dg_mark(v: String) -> void:
	var f = FileAccess.open(DG_DIR + "/state.txt", FileAccess.WRITE)
	if f != null:
		f.store_string(v)
		f.close()


# Ereignis in die Spur schreiben (im Speicher; auf die Platte alle 2 s und bei wichtigen Momenten)
func _bc(msg: String) -> void:
	dg_trail.append("%8.2f  %-7s r%6.1f  %s" % [Time.get_ticks_msec() / 1000.0, str(state), race_t, msg])
	if dg_trail.size() > DG_MAX:
		dg_trail.pop_front()


# Haltepunkt: welcher Teil der Hauptschleife läuft gerade – sofort auf die Platte (überlebt einen Absturz)
func _cp(nm: String) -> void:
	if dg_cpf == null:
		return
	dg_cpf.seek(0)
	dg_cpf.store_string(("%s · %s · r%.1f" % [nm, str(state), race_t]).rpad(72))
	dg_cpf.flush()


func _dg_flush() -> void:
	if dg_logger != null:
		for e in (dg_logger as DgLogger).take():
			_bc(e)
	var f = FileAccess.open(DG_DIR + "/trail.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(dg_trail))
		f.close()


func _dg_tick(delta: float) -> void:
	if OS.get_environment("FTDBG") != "":
		# nur zum Testen: lange Bilder (Hänger) mit Zustand mitschreiben
		var now = Time.get_ticks_usec()
		var ft = (now - int(get_meta("ftl", now))) / 1000.0
		set_meta("ftl", now)
		if ft > float(OS.get_environment("FTDBG")):
			print("FT %.0f ms state=%s t=%.2f warm=%.2f" % [ft, state, t_state, warm_t])
	if OS.get_environment("BENCHBTN") != "" and OS.get_environment("AG_RELOADED") == "" and not has_meta("bb") and Engine.get_process_frames() > 20:
		# nur zum Testen: wie der Knopf „Performance test“ in den Einstellungen
		set_meta("bb", 1)
		print("BENCHBTN press state=", state, " warm_t=", warm_t)
		bench_req = true
		_reload()
	if OS.get_environment("BENCHBTN") != "" and Engine.get_process_frames() % 30 == 0:
		print("BENCHST f=", Engine.get_process_frames(), " state=", state, " warm_t=", warm_t, " bench_req=", bench_req, " reloaded=", OS.get_environment("AG_RELOADED"), " step=", bench.get("i", -9), " msaa=", get_viewport().msaa_3d, " ssaa=", get_viewport().screen_space_aa)
	if OS.get_environment("SETOPEN") != "":
		# nur zum Testen: Einstellungen öffnen und ganz nach unten scrollen
		var fn = Engine.get_process_frames()
		if not has_meta("setopen") and Engine.get_process_frames() > 15:
			set_meta("setopen", fn)
			print("SETOPEN at ", fn)
			_show_settings(true)
		if has_meta("setopen") and fn == int(get_meta("setopen")) + 10:
			for sc in get_tree().root.find_children("*", "ScrollContainer", true, false):
				if (sc as Control).is_visible_in_tree():
					(sc as ScrollContainer).scroll_vertical = int(OS.get_environment("SETOPEN"))
	if str(state) != dg_state:
		_bc("state %s -> %s" % [dg_state, state])
		dg_state = str(state)
	dg_t += delta
	if dg_t >= 2.0:
		dg_t = 0.0
		var g: Dictionary = ships[0] if not ships.is_empty() else {}
		_bc("hb z=%.1f en=%.2f wpn=%s fps=%d kids=%d fx=%d zaps=%d deb=%d mines=%d shots=%d shh=%d party=%s kc=%s cm=%s" % [
			float(g.get("z", 0.0)), float(g.get("en", 0.0)), str(g.get("wpn", "")), Engine.get_frames_per_second(), get_child_count(),
			fxs.size(), zaps.size(), debris.size(), mines.size(), shots.size(), shield_hits.size(), not party.is_empty(), not kc.is_empty(), not cm.is_empty()])
		_dg_flush()
	# Bericht vom letzten Absturz anbieten, sobald das Menü steht
	if dg_report != "" and not dg_shown and state == "menu" and warm_t < 0.0 and menu_t > 1.0:
		dg_shown = true
		_dg_popup()


func _dg_popup() -> void:
	var cl = CanvasLayer.new()
	cl.layer = 40
	add_child(cl)
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	cl.add_child(dim)
	var pc = PanelContainer.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.04, 0.07, 0.97)
	sb.border_color = Color(1, 0.55, 0.15, 0.6)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(18)
	sb.set_content_margin_all(28)
	pc.add_theme_stylebox_override("panel", sb)
	pc.anchor_left = 0.06
	pc.anchor_right = 0.94
	pc.anchor_top = 0.5
	pc.anchor_bottom = 0.5
	pc.grow_vertical = Control.GROW_DIRECTION_BOTH
	cl.add_child(pc)
	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 22)
	pc.add_child(vb)
	var t = _lbl("Absturz beim letzten Mal", 40)
	t.add_theme_color_override("font_color", Color(1, 0.6, 0.25))
	vb.add_child(t)
	var l = _lbl("Das Spiel hat mitgeschrieben, was kurz davor passiert ist. Kopier den Bericht und füg ihn im Chat ein – damit lässt sich der Fehler finden.", 28)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(l)
	var b1 = _btn("Bericht kopieren", true)
	b1.pressed.connect(func():
		DisplayServer.clipboard_set(dg_report)
		_toast("Kopiert – jetzt einfach im Chat einfügen")
		cl.queue_free())
	vb.add_child(b1)
	var b2 = _btn("Schließen")
	b2.pressed.connect(func(): cl.queue_free())
	vb.add_child(b2)


# ================================================================ Ladestreifen
# Auf der Start-Ziel-Geraden rechts am Rand: wer drüberfährt, lädt Energie nach – die ganze Länge bringt höchstens ~28 %.
# Dafür verlässt man die Ideallinie. Gilt für alle Schiffe.
const CHG_Z = [58.0, 98.0]
const CHG_L = [1.45, 2.25]
const CHG_MAX = 0.28
const CHG_CODE = """
shader_type spatial;
render_mode unshaded,blend_add,cull_disabled,depth_draw_never,shadows_disabled;
uniform float on=0.;
void fragment(){
	// UV.x quer (0..1), UV.y längs in Einheiten: Pfeile laufen in Fahrtrichtung
	float ch=fract(UV.y*.5-abs(UV.x-.5)*.9-TIME*1.6);
	float arrow=smoothstep(.0,.08,ch)*smoothstep(.35,.27,ch);
	float edge=smoothstep(.12,.0,UV.x)+smoothstep(.88,1.,UV.x);
	vec3 c=vec3(.15,1.,.45);
	ALBEDO=c*(.18+arrow*.75+edge*1.1)*(1.+on*1.2);
}"""
var chg_mat: ShaderMaterial = null
var chg_p: AudioStreamPlayer = null
var chg_on = false
var chg_vt = 0.0


func _chg_build() -> void:
	if deco == null or T.S:
		return
	if chg_mat == null:
		chg_mat = _shader_mat(CHG_CODE)
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var z: float = CHG_Z[0]
	while z < CHG_Z[1] - 0.001:
		var z2 = minf(z + 1.0, CHG_Z[1])
		var f1 = T.frame(z)
		var f2 = T.frame(z2)
		var a1: Vector3 = f1.c + f1.rr * CHG_L[0] + f1.uu * 0.014
		var b1: Vector3 = f1.c + f1.rr * CHG_L[1] + f1.uu * 0.014
		var a2: Vector3 = f2.c + f2.rr * CHG_L[0] + f2.uu * 0.014
		var b2: Vector3 = f2.c + f2.rr * CHG_L[1] + f2.uu * 0.014
		var u1 = z - CHG_Z[0]
		var u2 = z2 - CHG_Z[0]
		for v in [[a1, Vector2(0, u1)], [b1, Vector2(1, u1)], [b2, Vector2(1, u2)], [a1, Vector2(0, u1)], [b2, Vector2(1, u2)], [a2, Vector2(0, u2)]]:
			st.set_uv(v[1])
			st.add_vertex(v[0])
		z = z2
	var mi = MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = chg_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	deco.add_child(mi)
	# Schrift auf der Fahrbahn an der Einfahrt
	var l = Label3D.new()
	l.text = "CHARGE"
	l.font_size = 96
	l.pixel_size = 0.006
	l.outline_size = 14
	l.modulate = Color(0.5, 1.0, 0.65) * 2.0
	l.outline_modulate = Color(0.1, 0.8, 0.3, 0.6)
	l.shaded = false
	var f0 = T.frame(CHG_Z[0] + 1.5)
	deco.add_child(l)
	# flach auf die Fahrbahn gelegt, lesbar für den Ankommenden
	var bx: Vector3 = f0.rr
	var bz: Vector3 = f0.uu
	var by: Vector3 = f0.fw
	l.global_transform = Transform3D(Basis(bx, by, bz), f0.c + f0.rr * ((CHG_L[0] + CHG_L[1]) * 0.5) + f0.uu * 0.02)


func _chg_update(dt: float, racing: bool) -> void:
	if T.S or chg_mat == null:
		return
	var pl_on = false
	for o in ships:
		if o.out or o.air or not racing:
			continue
		var lz = wrapf(float(o.z), 20.0, 20.0 + T.LAP)
		if lz >= CHG_Z[0] and lz <= CHG_Z[1] and o.lat >= CHG_L[0] - 0.2 and o.lat <= CHG_L[1] + 0.2:
			var dz = maxf(0.0, o.spd * cos(o.vpsi)) * dt
			var before: float = o.en
			o.en = minf(1.0, o.en + CHG_MAX * dz / (CHG_Z[1] - CHG_Z[0]))
			if o.idx == 0 and o.en > before:
				pl_on = true
				var pr = clampf((lz - CHG_Z[0]) / (CHG_Z[1] - CHG_Z[0]), 0.0, 1.0)
				chg_vt -= dt
				if chg_vt <= 0.0:
					chg_vt = lerpf(0.22, 0.045, pr)
					_vib(16 + int(pr * 14.0), 0.3 + 0.45 * pr)
	if pl_on != chg_on:
		chg_on = pl_on
		_sp(chg_mat, "on", 1.0 if pl_on else 0.0)
		if pl_on:
			_snd("load_weapon", -6.0, 1.25)
			_msg("CHARGING", Color(0.45, 1.0, 0.6))
		if chg_p == null or not is_instance_valid(chg_p):
			chg_p = AudioStreamPlayer.new()
			chg_p.bus = "Game"
			chg_p.stream = _looped(snd["neon_buzz"]) if snd.has("neon_buzz") else null
			chg_p.pitch_scale = 1.7
			chg_p.volume_db = -14.0
			add_child(chg_p)
		if pl_on and chg_p.stream != null:
			chg_p.play()
		else:
			chg_p.stop()


# ================================================================ Vibration
# Kurze Rückmeldungen am Handy: Stärke 0–1 (ab Android 8 echte Abstufung), abschaltbar in den Einstellungen.
var vib_until = 0.0
var vib_amp = 0.0


func _vib(ms: int, amp: float) -> void:
	if int(cfg.get("vib", 1)) == 0 or state == "replay" or state == "kill":
		return
	var now = Time.get_ticks_msec() / 1000.0
	# läuft schon ein stärkeres Rütteln, das nicht unterbrechen
	if now < vib_until and amp <= vib_amp:
		return
	vib_until = now + ms / 1000.0
	vib_amp = amp
	Input.vibrate_handheld(ms, clampf(amp, 0.05, 1.0))
