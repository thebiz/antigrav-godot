# AntiGrav 3D – erste Godot-Version: Neon Night, ein Gleitermodell, drei Gegner, echte Beleuchtung,
# Bildschirm-Spiegelungen, Schatten, Glühen. Alles wird beim Start im Code aufgebaut.
extends Node3D

# gespeichertes Replay, das nach dem Neuladen der Szene abgespielt werden soll (bleibt über reload_current_scene erhalten)
static var pending_rp = ""
static var restart = false   # „Race again“: nach dem Neuladen direkt losfahren

const T = preload("res://track.gd")
# Gleiter: Datei, Name, Nase zeigt im Modell nach hinten (wird umgedreht), Herkunft
const SHIPS = [
	["res://ships/qirex.glb", "Qirex", false, "“WipeOut – Qirex” by Nobby76, CC BY 4.0"],
	["res://ships/assegai/scene.gltf", "Assegai", false, "“WipeOut – Assegai” by Nobby76, CC BY 4.0"],
	["res://ships/apex.glb", "Apex", false, "“Apex Wipeout Anti-grav Racer” by rafta, CC BY-NC 4.0"],
	["res://ships/rhsx/scene.gltf", "RHS-X", true, "“RHS-X” by Hassan Bassassi, CC BY 4.0"]]
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
var lap_mesh: ArrayMesh
var bld_mm: MultiMesh
var cam: Camera3D
var ships: Array = []  # Zustand je Gleiter (Dictionary), [0] = du
var state = "menu"
var cfg = {"pads": 0, "ship": 0, "speed": 1.0, "gfx": 2, "glow": 0.5, "neon": 0.8, "vol": 0.9, "ai": 1.05, "look": 0, "res": 0.85}
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
const WN = {"rak": "ROCKET", "lenk": "HOMING", "mine": "MINES", "schild": "SHIELD", "turbo": "TURBO", "beben": "QUAKE", "auto": "AUTO", "wand": "WALL", "orbs": "ORBS"}
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
	if OS.get_cmdline_user_args().has("--noir"):
		cfg.look = 1
	if _noir():
		CY = Color(0.9, 0.92, 0.95)
		MG = OR
		AM = OR
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
			"vo_rak.wav", "vo_lenk.wav", "vo_mine.wav", "vo_orbs.wav", "vo_wand.wav", "vo_beben.wav", "vo_schild.wav", "vo_auto.wav", "vo_turbo.wav", "vo_elim.wav", "vo_enlow.wav", "vo_super.wav", "minedrop.wav"]:
		snd[n.get_basename()] = load("res://sfx/" + n)
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
	var scr = on and absf(g.lat) >= T.TW - 0.31 and not g.air and g.spd > 1.0
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
uniform vec4 hz0=vec4(0.);uniform vec4 hz1=vec4(0.);uniform vec4 hz2=vec4(0.);uniform vec4 hz3=vec4(0.);
float h21(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float vn(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);
	return mix(mix(h21(i),h21(i+vec2(1.,0.)),f.x),mix(h21(i+vec2(0.,1.)),h21(i+vec2(1.,1.)),f.x),f.y);}
// Hitzeflimmern: weiche, wabernde Wolken aus Rauschen, ziehen vom Triebwerk weg
vec2 haze(vec2 uv,vec4 h){
	if(h.w<=0.)return vec2(0.);
	vec2 q=uv-h.xy;q.x*=asp;q.y-=h.z*.4;
	float m=smoothstep(1.,.1,length(q*vec2(1.,.7))/h.z)*h.w;
	if(m<=.001)return vec2(0.);
	vec2 p=q/h.z*3.2+vec2(0.,-TIME*2.6);
	vec2 o=vec2(vn(p)+.5*vn(p*2.1+5.2),vn(p+vec2(9.7,3.1))+.5*vn(p*2.1+vec2(1.3,7.7)))-.75;
	return o*.0075*m;
}
void fragment(){
	vec2 uv=SCREEN_UV;
	// Gravitationsbombe: Bild wird zur Mitte gesogen, danach läuft eine Welle nach außen
	vec2 dd=uv-gc;dd.x*=asp;float r=length(dd)+1e-4;vec2 dir=dd/r;dir.x/=asp;
	r/=max(gz,.05);   // Gesamtgröße des schwarzen Lochs
	float pull=gs*.05/(r*r*30.+.12)*smoothstep(0.,.03,r);
	float rip=gr>=0.?sin((r-gr)*60.)*exp(-pow((r-gr)*9.,2.))*.022*gk:0.;
	uv-=dir*(pull-rip)*min(gz,2.);
	// Phasen-Glitch: Zeilen verrutschen, Farben laufen auseinander
	float band=floor(uv.y*46.+floor(TIME*24.)*3.1);float go=(h21(vec2(band,floor(TIME*30.)))-.5)*.05*gl*step(.55,h21(vec2(band,1.7)));
	uv.x+=go;
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
	float gp=max(gs,0.);
	col*=1.-smoothstep(.06*gp+.01,.0,r)*gp*gd;
	col+=grc*exp(-pow((r-.075*gp)*55./grw,2.))*gp*1.6*grb;
	if(gr>=0.)col+=vec3(.6,.45,1.)*exp(-pow((r-gr)*30.,2.))*gk*.8;
	// Speed-Linien: helle Streifen fliegen von der Mitte nach außen
	float an=atan(cd.y,cd.x*asp);float lane=floor(an*70.);float hl=h21(vec2(lane,3.));
	float sl=step(.93,hl)*smoothstep(.0,.15,fract(length(cd)*2.2-TIME*(2.5+hl*3.)+hl))*smoothstep(.5,.1,fract(length(cd)*2.2-TIME*(2.5+hl*3.)+hl));
	col+=vec3(.75,.88,1.)*sl*spd*e*.45;
	// knackig: Kanten schärfen, feines Filmkorn
	vec2 px=SCREEN_PIXEL_SIZE;
	vec3 bl=(texture(scr,uv+px*vec2(1.,.5)).rgb+texture(scr,uv-px*vec2(1.,.5)).rgb)*.5;
	col+=(c0-bl)*shp;
	col=max(col,vec3(0.));
	col+=(h21(floor(uv/px)+fract(TIME*7.3)*91.)-.5)*grn*(.5+.5*(1.-clamp(dot(col,vec3(.33)),0.,1.)));
	// Vignette bei Tempo
	col*=1.-spd*.25*smoothstep(.3,.9,length(cd*vec2(asp,1.))*1.4);
	COLOR=vec4(col,1.);
}""")
	r.material = post
	cl.add_child(r)


func _post_update(dt: float) -> void:
	if post == null:
		return
	var vp = get_viewport().get_visible_rect().size
	post.set_shader_parameter("asp", vp.x / maxf(1.0, vp.y))
	post.set_shader_parameter("shp", 0.9 if _noir() else 0.6)
	post.set_shader_parameter("grn", 0.06 if _noir() else 0.035)
	var g: Dictionary = ships[0]
	var q = int(cfg.gfx)
	var sp = 0.0
	if state == "race" or state == "done":
		sp = clampf((g.spd / BASE_DEF - 1.1) * 0.35 + g.boost * 0.55 + (0.4 if g.turbo > 0.0 else 0.0), 0.0, 1.0)
	post_spd += (sp - post_spd) * (1.0 - exp(-dt / 0.25))
	post.set_shader_parameter("spd", post_spd * (1.0 if q >= 1 else 0.0))
	gl_v = maxf(0.0, gl_v - dt * 1.4)
	post.set_shader_parameter("gl", gl_v)
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
		post.set_shader_parameter("gs", 0.0)
		post.set_shader_parameter("gr", -1.0)
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
	"wall": [["height", "Height", 0.2, 8.0, 1.0], ["dur", "Duration", 0.2, 8.0, 1.0], ["bolts", "Lightning", 0.0, 8.0, 1.0], ["glow", "Glow", 0.0, 8.0, 1.0],
		["hue", "Color", -0.5, 0.5, 0.0]],
	"shield": [["size", "Size", 0.5, 4.0, 1.0], ["glow", "Glow", 0.0, 10.0, 1.0], ["edge", "Edge sharpness", 0.2, 6.0, 1.0], ["flicker", "Flicker", 0.0, 8.0, 1.0],
		["hue", "Color", -0.5, 0.5, 0.0]],
	"orbs": [["shue", "Super orbs color", -0.5, 0.5, 0.0], ["sglow", "Super orbs glow", 0.0, 10.0, 1.0], ["size", "Size", 0.2, 6.0, 1.0], ["radius", "Orbit radius", 0.3, 5.0, 1.0], ["speed", "Orbit speed", 0.1, 6.0, 1.0], ["trail", "Trail length", 0.0, 6.0, 1.0],
		["glow", "Glow", 0.0, 10.0, 1.0], ["hue", "Color", -0.5, 0.5, 0.0]],
	"haze": [["amp", "Shimmer", 0.0, 10.0, 1.0], ["fine", "Fineness", 0.3, 6.0, 1.0], ["speed", "Speed", 0.0, 8.0, 1.0], ["size", "Size", 0.2, 6.0, 1.0],
		["len", "Length", 0.2, 6.0, 1.0], ["boost", "Extra with boost", 0.0, 8.0, 1.0]],
	"pillar": [["speed", "Ring speed", 0.0, 6.0, 1.0], ["size", "Ring size", 0.3, 5.0, 1.0], ["glow", "Ring glow", 0.0, 10.0, 1.0], ["squash", "Rubber squash", 0.0, 6.0, 1.0],
		["soft", "Soft bounce", 0.0, 2.0, 1.0], ["beam", "Pillar light", 0.0, 10.0, 1.0]],
	"ship": [["height", "Hover height", 0.2, 8.0, 1.0], ["bob", "Hover bob", 0.0, 10.0, 1.0], ["bank", "Lean in curves", 0.0, 6.0, 1.0], ["pitch", "Nose pitch", 0.0, 8.0, 1.0],
		["wobble", "Spring wobble", 0.0, 8.0, 0.0], ["stiff", "Spring stiffness", 0.2, 5.0, 1.0], ["steer", "Steering lag", 0.2, 8.0, 1.0]],
	"env": [["city", "Buildings", 0.0, 1.0, 1.0], ["dens", "Building count", 0.0, 5.0, 1.0], ["bh", "Height", 0.3, 6.0, 1.0], ["bw", "Width", 0.2, 6.0, 1.0],
		["bd", "Distance", 0.2, 6.0, 1.0], ["win", "Lit windows", 0.0, 2.5, 1.0], ["hue_w", "Window color", -0.5, 0.5, 0.0], ["edge", "Neon edges", 0.0, 10.0, 1.0],
		["hue_s", "Sky color", -0.5, 0.5, 0.0], ["skyb", "Sky brightness", 0.0, 6.0, 1.0], ["stars", "Stars", 0.0, 10.0, 1.0], ["skyl", "Skyline", 0.0, 5.0, 1.0],
		["fog", "Fog density", 0.0, 12.0, 1.0], ["hue_f", "Fog color", -0.5, 0.5, 0.0], ["moon", "Moon", 0.0, 6.0, 1.0], ["beams", "Light pillars", 0.0, 10.0, 1.0],
		["lamps", "Track lights", 0.0, 10.0, 1.0]],
}
const FXT = [["boom", "Boom"], ["mine", "Mine"], ["quake", "Quake"], ["gb", "Hole"], ["rak", "Rocket"], ["wall", "Wall"], ["shield", "Shield"], ["orbs", "Orbs"], ["haze", "Haze"], ["pillar", "Pillar"], ["ship", "Ship"], ["env", "World"]]
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


func _save_cfg() -> void:
	var c = ConfigFile.new()
	for k in cfg.keys():
		c.set_value("s", k, cfg[k])
	c.save(CFG_PATH)


# Grafikstufe: 0 niedrig, 1 mittel, 2 hoch
func _apply_cfg() -> void:
	base_spd = BASE_DEF * float(cfg.speed)
	var q = int(cfg.gfx)
	wenv.ssr_enabled = q >= 2
	wenv.ssao_enabled = q >= 2
	# Medium: ein einfacher, kurzer Schatten statt zwei Stufen, schnelle Kantenglättung (FXAA) statt MSAA
	moon.shadow_enabled = q >= 1
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if q >= 2 else DirectionalLight3D.SHADOW_ORTHOGONAL
	moon.directional_shadow_max_distance = 35.0 if q >= 2 else 18.0
	get_viewport().msaa_3d = Viewport.MSAA_4X if q >= 2 else Viewport.MSAA_DISABLED
	get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if q == 1 else Viewport.SCREEN_SPACE_AA_DISABLED
	get_viewport().scaling_3d_scale = [0.7, 0.8, 1.0][q] * float(cfg.res)
	wenv.glow_intensity = 1.6 * float(cfg.glow) * (0.7 if _noir() else 1.0)
	wenv.adjustment_contrast = 1.18 if _noir() else 1.05
	wenv.glow_strength = 0.6 + 0.6 * float(cfg.glow)
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
	if sky_m != null:
		sky_m.set_shader_parameter("sb", float(E.skyb))
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
	c+=(vec3(.9,.92,1.)*smoothstep(.9994,.9997,mo)*4.+vec3(.25,.3,.5)*pow(max(0.,mo),60.)*.35)*mn;
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
	var sky = Sky.new()
	sky.sky_material = sky_mat
	var env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.19, 0.19, 0.2) if _noir() else Color(0.16, 0.12, 0.26)
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
	env.ssr_enabled = true
	env.ssr_max_steps = 72
	env.ssr_fade_in = 0.1
	env.ssr_fade_out = 2.5
	env.ssr_depth_tolerance = 0.35
	env.ssao_enabled = true
	env.ssao_intensity = 1.6
	env.fog_enabled = true
	env.fog_light_color = Color(0.045, 0.045, 0.05) if _noir() else Color(0.05, 0.03, 0.09)
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
	moon.light_color = Color(0.85, 0.87, 0.9) if _noir() else Color(0.6, 0.66, 1.0)
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


var shader_cache = {}


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


func _noir() -> bool:
	return int(cfg.get("look", 0)) == 1


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


func _st(key: String) -> SurfaceTool:
	if not sts.has(key):
		var st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		sts[key] = st
	return sts[key]


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, ua = Vector2.ZERO, ub = Vector2.ZERO, uc = Vector2.ZERO) -> void:
	st.set_normal(n); st.set_uv(ua); st.add_vertex(a)
	st.set_normal(n); st.set_uv(ub); st.add_vertex(b)
	st.set_normal(n); st.set_uv(uc); st.add_vertex(c)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, ua = Vector2.ZERO, ub = Vector2.ZERO, uc = Vector2.ZERO, ud = Vector2.ZERO) -> void:
	_tri(st, a, b, c, n, ua, ub, uc)
	_tri(st, a, c, d, n, ua, uc, ud)


# Kasten im Streckenrahmen: Mitte (lat, h) an Stelle z, halbe Maße (seitlich, hoch, längs)
func _box(key: String, z: float, lat: float, h: float, hx: float, hy: float, hz: float) -> void:
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
	var st = _st(key)
	var z = z0
	var prev = []
	while z <= z1 + 0.001:
		var f = T.frame(z)
		var p: Array = [f.c + f.rr * la + f.uu * ha, f.c + f.rr * lb + f.uu * hb, f.uu]
		if prev.size() > 0 and not T.gap(z - 0.25):
			_quad(st, prev[0], prev[1], p[1], p[0], p[2])
		prev = p
		z += 0.5


# Ring um die Strecke (Röhre mit Radius rt), Bogen von -am bis am (Winkel 0 = oben)
func _ring(key: String, z: float, rad: float, cy: float, rt: float, am: float = PI, ns: int = 40) -> void:
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
func _build_track() -> void:
	var TW = T.TW
	# Fahrbahn: nasser Asphalt (Reihen alle 0,5 Einheiten, 8 Spalten)
	var road = _st("road")
	var prev = []
	var z = 20.0
	while z <= 720.0 + 0.001:
		var f = T.frame(z)
		var row = []
		for i in range(9):
			var x = -TW + 2.0 * TW * i / 8.0
			row.append(f.c + f.rr * x)
		if prev.size() > 0 and not T.gap(z - 0.25):
			for i in range(8):
				var u0 = float(i) / 8.0
				var u1 = float(i + 1) / 8.0
				_quad(road, prev[i], row[i], row[i + 1], prev[i + 1], f.uu, Vector2(u0, (z - 0.5) * 0.08), Vector2(u0, z * 0.08), Vector2(u1, z * 0.08), Vector2(u1, (z - 0.5) * 0.08))
		prev = row
		z += 0.5
	# Leitplanken: Metallwand innen, Deckel, Neonband (links Cyan, rechts Magenta)
	for sd in [-1.0, 1.0]:
		_strip("wall", 20.0, 720.0, sd * TW, sd * TW, -0.06, 0.46)
		_strip("wall", 20.0, 720.0, sd * TW, sd * (TW + 0.12), 0.46, 0.46)
		_strip("neonL" if sd < 0 else "neonR", 20.0, 720.0, sd * (TW - 0.012), sd * (TW - 0.012), 0.30, 0.36)
		# Leuchtkante auf der Fahrbahn
		_strip("neonL" if sd < 0 else "neonR", 20.0, 720.0, sd * (TW - 0.16), sd * (TW - 0.11), 0.006, 0.006)
	# Mittellinie, gestrichelt
	var zz = 20.0
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
		_strip("pad", zc, zc + 3.0, bx - 0.36, bx + 0.36, 0.008, 0.008)
	# Waffenfelder: bunter Ring auf jedem zweiten Feld
	for wk in range(0, 21, 2):
		var zw = _wzp(wk)
		if zw < 25.0 or zw > 715.0 or T.gap(zw + 1.0):
			continue
		var wx = _wpx(wk)
		_strip("wpad", zw - 0.25, zw + 2.25, wx - 0.5, wx + 0.5, 0.009, 0.009)
		wpads.append([zw + 1.0, wx])
	# Tore mit Lampen (nicht im Tunnel), Werbetafeln, Stützen
	var gk = 1
	while gk * 28 + 7 < 720:
		var zc = gk * 28.0 + 7.0
		if zc > 20.0 and not T.in_tun(zc, 2.0):
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
		if zc > 715.0 or T.in_tun(zc, 2.0):
			continue
		var sd = 1.0 if k % 2 == 0 else -1.0
		_box("metal", zc, sd * (TW + 0.42), 0.42, 0.03, 0.3, 1.6)
		_box("board" + str(k % 3), zc, sd * (TW + 0.385), 0.42, 0.006, 0.26, 1.5)
	for k in range(2, 51):
		var zc = k * 14.0 + 7.0
		if zc > 715.0 or T.in_tun(zc, 1.0) or T.gap(zc):
			continue
		_box("metal", zc, 0.0, -3.3, 0.16, 3.1, 0.16)
	# Neonringe in Gruppen
	for zr in T.RINGS:
		_ring("ringC" if int(floor(zr / 150.0)) % 2 == 0 else "ringM", float(zr), TW + 0.55, 0.95, 0.065)
	# Tunnel: Röhre innen, leuchtende Ringe, Deckenband
	for tu in T.TUN:
		var R = TW + 0.25
		var am = acos(maxf(-1.0, -0.56 / R))
		var na = 22
		var pr = []
		var z2: float = tu[0]
		while z2 <= tu[1] + 0.001:
			var f = T.frame(z2)
			var ring = []
			for i in range(na + 1):
				var ph = -am + 2.0 * am * i / na
				ring.append([f.c + f.uu * 0.4 + (f.rr * sin(ph) + f.uu * cos(ph)) * R, -(f.rr * sin(ph) + f.uu * cos(ph))])
			if pr.size() > 0:
				for i in range(na):
					_quad(_st("tube"), pr[i][0], ring[i][0], ring[i + 1][0], pr[i + 1][0], ring[i][1])
			pr = ring
			z2 += 1.0
		var zt: float = tu[0] + 1.0
		var ti = 0
		while zt < tu[1]:
			_ring("ringC" if ti % 5 != 4 else "ringM", zt, R - 0.03, 0.4, 0.025, am * 0.98, 30)
			zt += 1.43
			ti += 1
		_strip("tlight", tu[0], tu[1], -0.06, 0.06, 0.4 + R - 0.04, 0.4 + R - 0.04)
	# Materialien zusammenstellen
	mats["road"] = _shader_mat(_nz("""
shader_type spatial;
// Fahrbahn wie bei Wipeout: dunkelgraues, gebürstetes Metall in Platten, feine Fugen, Randmarkierung; glatt, leicht glänzend
float h11(float x){return fract(sin(x*91.7)*4371.3);}
float h21(vec2 p){return fract(sin(dot(p,vec2(12.9898,78.233)))*43758.5453);}
// Bebenwelle: Kamm bei qz, davor ein kleiner Anlauf, dahinter ein Tal und Nachschwingen
uniform float qz=-1000.;uniform float qs=0.;uniform float qz2=-1000.;uniform float qs2=0.;uniform vec3 qc=vec3(1.,.42,.08);uniform float qg=1.;
varying float wz;varying float qh;
float qw(float d,float s){return s*(1.6*exp(-pow(d/2.6,2.))-.5*exp(-pow((d+6.)/2.6,2.))+.22*exp(-pow((d+12.)/2.4,2.)));}
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
	base*=1.-seam*.7;
	ALBEDO=base;METALLIC=.8;ROUGHNESS=.38+.1*br+seam*.3+edge*.2;SPECULAR=.45;
	float cr=max(qh,0.)/max(max(qs,qs2),.01);   // glühender Kamm, aufgerissene Fugen
	EMISSION=(qc*pow(cr,1.5)*6.+qc*vec3(1.,.6,.62)*seam*cr*14.)*step(.01,qs+qs2)*qg;
}""", [["vec3(.75,.62,.08)", "vec3(.8,.3,.02)"]]))
	mats["wall"] = _metal(Color(0.07, 0.075, 0.09), 0.22)
	mats["metal"] = _metal(Color(0.09, 0.095, 0.11), 0.3)
	mats["tube"] = _metal(Color(0.012, 0.012, 0.016), 0.28, 0.9)
	mats["neonL"] = _neon(CY, 5.0)
	mats["neonR"] = _neon(MG, 5.0)
	mats["ringC"] = _neon(CY, 7.0)
	mats["ringM"] = _neon(MG, 7.0)
	mats["line"] = _neon(Color(0.8, 0.85, 1.0), 0.6)
	mats["tlight"] = _neon(Color(0.9, 0.95, 1.0), 4.0)
	mats["board0"] = _neon(Color(0.8, 0.8, 0.85) if _noir() else Color(0.1, 0.4, 1.0), 2.2)
	mats["board1"] = _neon(OR if _noir() else Color(1.0, 0.2, 0.5), 2.2)
	mats["board2"] = _neon(Color(0.35, 0.35, 0.37) if _noir() else Color(1.0, 0.7, 0.1), 2.2)
	mats["pad"] = _shader_mat(_nz("""
shader_type spatial;
render_mode unshaded,cull_disabled;
void fragment(){
	vec2 u=UV;float ch=step(abs(fract(u.x*6.-TIME*2.)-.5-abs(u.y-.5)*.9),.14);
	ALBEDO=mix(vec3(.05,.6,1.),vec3(1.,.85,.15),ch)*(1.6+ch*1.8);
}""", [["vec3(.05,.6,1.),vec3(1.,.85,.15)", "vec3(.8),vec3(1.,.36,.03)"]]))
	mats["wpad"] = _shader_mat(_nz("""
shader_type spatial;
render_mode unshaded,cull_disabled;
void fragment(){
	vec2 q=vec2((UV.x-.5)*2.5,(UV.y-.5)*1.);float r=length(q);
	float ring=smoothstep(.05,0.,abs(r-.38))+smoothstep(.04,0.,abs(r-.24))*.8+smoothstep(.12,0.,r);
	vec3 c=.5+.5*cos(6.2832*(atan(q.y,q.x)/6.2832+TIME*.4+vec3(0.,.33,.67)));
	ALBEDO=c*(3.5+1.5*sin(TIME*6.));ALPHA=clamp(ring,0.,1.);
}""", [["vec3 c=.5+.5*cos(6.2832*(atan(q.y,q.x)/6.2832+TIME*.4+vec3(0.,.33,.67)));", "vec3 c=mix(vec3(1.,.36,.03),vec3(1.),.5+.5*sin(atan(q.y,q.x)*3.+TIME*4.));"]]))
	mats["start"] = _shader_mat("""
shader_type spatial;
render_mode unshaded,cull_disabled;
void fragment(){vec2 q=floor(vec2(UV.x*12.,UV.y*2.));ALBEDO=vec3(mod(q.x+q.y,2.)*1.2+.02);}""")
	lap_mesh = ArrayMesh.new()
	for key in sts.keys():
		var st: SurfaceTool = sts[key]
		if key == "pad" or key == "start" or key == "wpad":
			_fix_uv(st, key)
		st.commit(lap_mesh)
		lap_mesh.surface_set_material(lap_mesh.get_surface_count() - 1, mats[key])
	# drei Kopien der Runde: hinter dir, unter dir, vor dir – wandern mit
	for i in range(3):
		var n = Node3D.new()
		var mi = MeshInstance3D.new()
		mi.mesh = lap_mesh
		n.add_child(mi)
		for l in lights:
			var om = OmniLight3D.new()
			om.light_color = l[1]
			om.light_energy = 2.2
			om.omni_range = 7.0
			om.omni_attenuation = 1.6
			om.position = T.world(l[0], 0.0, 1.1)
			n.add_child(om)
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


# Boost-Felder und Startlinie: UV aus der Lage im Streifen (x längs, y quer)
func _fix_uv(st: SurfaceTool, key: String) -> void:
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
	sts[key] = st2


# ---------------------------------------------------------------- Hochhäuser neben der Strecke (eine Instanz-Liste, Fenster im Shader)
func _build_city() -> void:
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
	_city_fill()
	for n in laps:
		var mmi = MultiMeshInstance3D.new()
		mmi.multimesh = bld_mm
		mmi.extra_cull_margin = 60.0
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(mmi)


var city_mat: ShaderMaterial


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
	var E: Dictionary = fx.env
	var dens = float(E.dens) if float(E.city) > 0.5 else 0.0
	var items = []
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
		zc += stepz
	bld_mm.instance_count = 0
	bld_mm.instance_count = items.size()
	for i in range(items.size()):
		bld_mm.set_instance_transform(i, items[i][0])
		var c: Color = items[i][1]
		bld_mm.set_instance_custom_data(i, Color(c.r, c.g, c.b, items[i][2]))


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
	var lt = OmniLight3D.new()
	lt.light_color = Color(0.6, 0.4, 1.0)
	lt.light_energy = 1.4
	lt.omni_range = 4.0
	lt.position = Vector3(0, 0.15, -0.95)
	root.add_child(lt)
	root.set_meta("jets", jets)
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
	add_child(root)
	return root


const HAZE_CODE = """
shader_type spatial;
render_mode unshaded,blend_mix,depth_draw_never,cull_disabled,shadows_disabled,fog_disabled;
uniform sampler2D scr:hint_screen_texture,filter_linear;
uniform float k=.6;uniform float hs=1.;uniform float hv=1.;uniform float hf=1.;
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
	ALBEDO=texture(scr,SCREEN_UV+o*.0045*m*hs).rgb;
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
	float fr=pow(1.-abs(dot(NORMAL,VIEW)),2.6*se);
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
		if shn.visible:
			var X: Dictionary = fx.shield
			shn.scale = (shn.get_meta("bs") as Vector3) * float(X.size)
			shield_mat.set_shader_parameter("sc", _v3(_hs(Color(0.12, 0.45, 1.0), float(X.hue))))
			shield_mat.set_shader_parameter("sg", float(X.glow))
			shield_mat.set_shader_parameter("sf", float(X.flicker))
			shield_mat.set_shader_parameter("se", float(X.edge))


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
			sm = clampi(int(rpf.sm[i]), 0, SHIPS.size() - 1)
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
	float roll=smoothstep(.0,.02,abs(fract(uv.y-TIME*.12)-.5))*.0+exp(-pow((fract(uv.y-TIME*.12)-.5)*40.,2.))*.05;
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
	hud.en_bg.size = Vector2(200, 12)
	cl.add_child(hud.en_bg)
	hud.en = ColorRect.new()
	hud.en.color = Color(0.36, 1.0, 0.6)
	hud.en.size = Vector2(200, 12)
	hud.en_bg.add_child(hud.en)
	# Fortschritt über die ganze Strecke: drei Abschnitte (= drei Runden), füllt sich live
	var pg = Control.new()
	pg.position = Vector2(36, 112)
	pg.size = Vector2(200, 10)
	cl.add_child(pg)
	hud.pg = pg
	hud.pgf = []
	for k in range(T.LAPS):
		var w = (200.0 - 2 * 6.0) / T.LAPS
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
	el.position = Vector2(36, 156)
	hud.el = el
	el.modulate = Color(1, 1, 1, 0.7)
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
		# pulsierender Außenring
		ring.draw_arc(c, 112.0 + 9.0 * pu, 0.0, TAU, 64, Color(oc.r, oc.g, oc.b, 0.55 * (1.0 - pu) + 0.15), 3.0, true)
		# drei drehende Bogenstücke
		for k in range(3):
			var a0 = t * 2.2 + k * TAU / 3.0
			ring.draw_arc(c, 104.0, a0, a0 + 1.2, 24, Color(oc.r, oc.g, oc.b, 0.95), 6.0, true))
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
	hud.fire.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
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
	hud.res.anchor_right = 1.0
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
	b2.pressed.connect(func():
		restart = true
		get_tree().reload_current_scene())
	bx.add_child(b2)
	var b3 = _btn("MENU")
	b3.pressed.connect(func(): get_tree().reload_current_scene())
	bx.add_child(b3)
	hud.resb = bx
	hud.resbtn = [b1, b2, b3]
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
	if not hud.resb.visible:
		resb_t = 0.0
		resb_armed = false
	hud.resb.visible = true
	_resb_arm(0.0)


func _resb_arm(dt: float) -> void:
	if not hud.resb.visible:
		return
	resb_t += dt
	if not resb_armed and resb_t > 1.3 and fingers.is_empty():
		resb_armed = true
	var a = clampf((resb_t - 1.3) / 0.35, 0.0, 1.0) if resb_armed else 0.0
	hud.resb.modulate.a = a
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
	# Hauptseite
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	box.anchor_left = 0.06
	box.anchor_right = 0.94
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_top = -752
	box.offset_bottom = -70
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
	var brl = _btn("Replays")
	brl.pressed.connect(func(): _show_replays(true))
	box.add_child(brl)
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
	# Einstellungen
	var sp = VBoxContainer.new()
	sp.add_theme_constant_override("separation", 14)
	sp.anchor_left = 0.06
	sp.anchor_right = 0.94
	sp.anchor_top = 1.0
	sp.anchor_bottom = 1.0
	sp.offset_top = -1530
	sp.offset_bottom = -70
	sp.visible = false
	root.add_child(sp)
	ui.setp = sp
	sp.add_child(_lbl("SETTINGS", 40))
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
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.toggle_mode = true
		b.pressed.connect(func(): cfg.gfx = q; _refresh_ui(); _apply_cfg(); _save_cfg(); _rewarm())
		gr.add_child(b)
		ui.gfx.append(b)
	var twin = HBoxContainer.new()
	twin.add_theme_constant_override("separation", 24)
	sp.add_child(twin)
	var lcol = VBoxContainer.new()
	lcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	twin.add_child(lcol)
	lcol.add_child(_lbl("Look", 32))
	var lr = HBoxContainer.new()
	lr.add_theme_constant_override("separation", 10)
	lcol.add_child(lr)
	ui.look = []
	for q in range(2):
		var b = _btn(["Color", "Noir"][q])
		b.add_theme_font_size_override("font_size", 30)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.toggle_mode = true
		b.pressed.connect(func():
			if int(cfg.look) != q:
				cfg.look = q
				_save_cfg()
				get_tree().reload_current_scene())
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
				get_tree().reload_current_scene())
		pr.add_child(b)
		ui.pads.append(b)
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
			get_tree().reload_current_scene())
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
	ui.setp.visible = on
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
	ui.credit.text = "Ship: " + SHIPS[int(cfg.ship)][3] + " · private use only"
	ui.sl.speed.text = "Speed  %d %%" % int(round(float(cfg.speed) * 100.0))
	ui.sl.ai.text = "Rivals speed  %d %%" % int(round(float(cfg.ai) * 100.0))
	ui.sl.res.text = "Resolution  %d %%" % int(round(float(cfg.res) * 100.0))
	for q in range(2):
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
		var on3 = int(cfg.pads) == q
		var st3 = _style(Color(0.93, 0.41, 0.18) if on3 else Color(1, 1, 1, 0.08), Color(1, 0.7, 0.54) if on3 else Color(1, 1, 1, 0.22))
		for k in ["normal", "pressed", "hover"]:
			ui.pads[q].add_theme_stylebox_override(k, st3)
	for q in range(2):
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


func _start() -> void:
	for i in range(1, ships.size()):
		ships[i].sk = (1.0 + (i - 1) * 0.035) * float(cfg.ai)
		ships[i].sk0 = ships[i].sk
	state = "intro"
	t_state = 0.0
	ui.root.visible = false
	hud.layer.visible = true


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
	var i = 0
	while i < F.size() - 2 and F[i + 1].t <= rp.t:
		i += 1
	rp.i = i
	rp.ei = i
	rp.dirty = true   # Effekte passend zur neuen Zeit neu aufbauen


const FX_DUR = {"boom": 4.0, "gb": 2.0, "zap": 2.6}


# alle Effekte so aufbauen, wie sie zur Replay-Zeit rp.t aussehen (Explosionen mittendrin, Rauch, schwarze Löcher …)
func _rp_rebuild_fx() -> void:
	var keep = rp.get("base", [])
	var pools = []
	for k in ["shots", "mines", "walls"]:
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
	warm = true   # kein Ton, kein Blitz beim Aufbauen
	fx_rebuild = true
	live_bursts = 0
	while j >= 0 and F[j].t >= rp.t - 8.0:
		for ev in F[j].ev:
			var age: float = rp.t - F[j].t
			if age < 0.0 or age > FX_DUR.get(ev[0], 0.0):
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
	for n in get_children():
		if n is GPUParticles3D:
			n.speed_scale = 0.0 if on else 1.0


func _input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch:
		if ev.pressed:
			fingers[ev.index] = true
		else:
			fingers.erase(ev.index)
	if state == "lab":
		_lab_input(ev)
		return
	if state == "replay" and vx.is_empty() and not rp.is_empty():
		_rp_input(ev)
	if ev is InputEventScreenTouch:
		if ev.pressed:
			if state == "kill":
				_kc_end()
				return
			if state == "race" and fire_rect.has_point(ev.position):
				fire_req = true
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
	return T.bpx(k) if pad_seed == 0 else pb_lat[posmod(k, 20)]


func _bzp(k: int) -> float:
	return k * 35.0 + (0.0 if pad_seed == 0 else pb_off[posmod(k, 20)])


func _wzp(k: int) -> float:
	return k * 35.0 + 17.0 + (0.0 if pad_seed == 0 else pw_off[posmod(k, 20)])


# gibt es das Feld auf der Strecke wirklich? (nicht am Start, nicht über der Sprunglücke)
func _pad_ok(z: float) -> bool:
	var zl = fposmod(z - 20.0, 700.0) + 20.0
	return zl >= 25.0 and zl <= 715.0 and not T.gap(zl + 1.0)


func _wpx(k: int) -> float:
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
	flash_rect.color = Color(c.r, c.g, c.b, maxf(flash_rect.color.a, a))

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


# später ausführen – oder sofort, wenn der Effekt schon älter ist als die Verzögerung
func _later(d: float, f: Callable) -> void:
	if fx_age >= d:
		var old = fx_age
		fx_age = fx_age - d
		f.call()
		fx_age = old
	else:
		get_tree().create_timer(d - fx_age).timeout.connect(f)


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
func _gbomb(z: float, lat: float, own := -1, hit := -1, sc := 1.0) -> void:
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
	var sm = SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	core.mesh = sm
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
	fxs.append({"gb": true, "pos": pos, "core": core, "ring": ring, "l": lt, "t": fx_age, "f": f, "z": z, "lat": lat, "snap": false, "own": own, "hit": hit,
		"sz": gz, "ps": gsc, "ts": float(X.time), "wt": float(X.wthick), "ws": float(X.wspeed), "wz": float(X.wsize), "whu": hu + float(X.whue), "gr": float(X.gring),
		"rimw": float(X.rimw), "rimb": float(X.rimb), "rimh": hu + float(X.rimh), "dark": float(X.dark), "cs": float(X.core) * sqrt(float(X.size)) * gsc, "sp": float(X.sparks), "wv": float(X.wave), "lk": float(X.light), "lens": float(X.lens), "sh": float(X.shake), "hu": hu})
	_snd("gbomb", 3.0, 1.0, pos)


func _gb_damage(e: Dictionary) -> void:
	for o in ships:
		if o.out or o.idx == e.own:
			continue
		var dd = Vector2(o.z - e.z, o.lat - e.lat).length()
		var kk = clampf(1.0 - dd / (GB_R * e.get("sz", 1.0)), 0.0, 1.0)
		if kk > 0.0:
			_dmg(o, (0.45 * pow(kk, 1.2)) * (0.5 if o.idx == e.hit else 1.0), e.own, "rocket")
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
		fx_age = maxf(0.0, t - 0.55) if fx_rebuild else 0.0
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
	float fr=1.-abs(dot(NORMAL,VIEW));
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
		sph.visible = e.get("wv", 1.0) > 0.01
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
	# Ring zeigt immer zur Kamera
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
func _prot(o: Dictionary) -> bool:
	return o.shield > 0.0 or o.orbs > 0.0 or (o.idx == 0 and o.auto > 0.0)


func _dmg(o: Dictionary, a: float, src := -1, kind := "") -> void:
	if o.out or state != "race" or _prot(o):
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


func _add_shot(from: Dictionary, at_player := false, homing := false, dir := 1.0, cl := false) -> void:
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
	if homing:
		var bd = 220.0
		for o in ships:
			if o.idx != from.idx and not o.out and (o.z - from.z) * dir > 0.0 and (o.z - from.z) * dir < bd:
				bd = (o.z - from.z) * dir
				tg = o
	shots.append({"z": from.z + 1.0 * dir, "lat": from.lat, "t": 0.0, "pl": at_player, "hm": homing, "tg": tg, "dl": tan(from.psi) * dir if not at_player else 0.0, "n": mi, "own": from.idx, "dir": dir, "cl": cl})
	if cl:
		(mi.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.78, 0.2)
		(mi.material_override as StandardMaterial3D).emission = Color(1.0, 0.78, 0.2)
	_snd("rak", -2.0, 1.0, (from.node as Node3D).global_position if from.idx != 0 else null)


# Rakete geht hoch: normal ein schwarzes Loch, Super-Rakete (Streubombe) zerplatzt in fünf kleine über die ganze Breite
func _shot_boom(sh: Dictionary, z: float, lat: float, hit: int) -> void:
	if not sh.get("cl", false):
		_gbomb(z, lat, sh.own, hit)
		return
	for i in range(5):
		var la = lerpf(-T.TW * 0.8, T.TW * 0.8, i / 4.0)
		var zz = z + 1.0 + randf() * 2.5
		get_tree().create_timer(0.05 * i + 0.01).timeout.connect(func(): _gbomb(zz, la, sh.own, -1, 0.5))
	_snd("boom", 0.0, 1.3)


# Minen fallen nacheinander hinten aus dem Schiff: „dupp, dupp, dupp“; Super-Minen: Teppich über die ganze Breite
func _drop_mines(o: Dictionary, sup := false) -> void:
	if sup:
		for k in range(9):
			var la = lerpf(-T.TW + 0.35, T.TW - 0.35, k / 8.0)
			get_tree().create_timer(k * 0.05).timeout.connect(func(): _drop_one(o, k, la, 0.6 * (k % 2)))
		return
	for k in range(3):
		get_tree().create_timer(k * 0.14).timeout.connect(func(): _drop_one(o, k))


func _drop_one(o: Dictionary, k: int, lat_o := 999.0, back := 0.0) -> void:
	if o.out or not (state == "race" or state == "done" or state == "lab"):
		return
	var X: Dictionary = fx.mine
	var sp = SphereMesh.new()
	sp.radius = 0.12 * float(X.size)
	sp.height = 0.24 * float(X.size)
	var mi = _glow_node(sp, _hs(Color(1, 0.15, 0.1), float(X.hue)), 6.0 * float(X.glow))
	var z = o.z - 0.9 - back
	var lat = o.lat + (k - 1) * 0.22 if lat_o > 99.0 else lat_o
	mi.position = T.world(z, lat, 0.45)
	mines.append({"z": z, "lat": lat, "t": 0.0, "n": mi, "own": o.idx})
	_snd("minedrop", -1.0 if o.idx == 0 else 2.0, randf_range(0.92, 1.08), (o.node as Node3D).global_position if o.idx != 0 else null)


# Gegner sammeln an den Waffenfeldern auch etwas ein und setzen es klug ein
func _ai_weapons(o: Dictionary, dt: float, racing: bool) -> void:
	if not racing or o.out:
		return
	o.shield = maxf(0.0, o.shield - dt)
	if o.turbo > 0.0:
		o.turbo -= dt
		o.boost = maxf(o.boost, 1.5)
	var wk = int(round((o.z - 17.0) / 35.0))
	var wz = (o.z - _wzp(wk)) / 35.0
	if wz < 0.0 or not _pad_ok(_wzp(wk)):
		wz = 9.0
	if posmod(wk, 2) == 0 and wz < 0.08 and wk != o.wpK and o.wpn != "" and not o.get("sup", false):
		o.wpK = wk
		if randf() < 0.4:
			o.sup = true
	if posmod(wk, 2) == 0 and wz < 0.08 and wk != o.wpK and o.wpn == "":
		o.wpK = wk
		if randf() < 0.65:
			var r = randf()
			for w in WP_AI:
				r -= w[1]
				if r <= 0.0:
					o.wpn = w[0]
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
					_add_shot(o, false, o.wpn == "lenk", 1.0, sup and o.wpn == "rak")
					if sup and o.wpn == "lenk":
						_add_shot(o, false, true, -1.0)
					o.wpn = ""
					break
	if o.wpn == "":
		o.sup = false


# Orbs: zwei Kugeln kreisen um dich, schützen dich und rammen Gegner
var orb_n = []


func _orbs_update(dt: float, live: bool) -> void:
	var g: Dictionary = ships[0]
	if live:
		g.orbs = maxf(0.0, g.orbs - dt)
	var on = g.orbs > 0.0 and not g.out and (g.orbs > 1.2 or fmod(g.orbs, 0.25) < 0.15)
	if orb_n.is_empty():
		if not on:
			return
		_fx_res()
		var gt = GradientTexture2D.new()
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		var gr = Gradient.new()
		gr.set_color(0, Color(1, 1, 1, 1))
		gr.set_color(1, Color(1, 1, 1, 0))
		gt.gradient = gr
		gt.width = 32
		gt.height = 32
		for j in range(4):
			var sp = SphereMesh.new()
			sp.radius = 0.11
			sp.height = 0.22
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
				var sp2 = SphereMesh.new()
				sp2.radius = 0.09 * (1.0 - k * 0.14)
				sp2.height = sp2.radius * 2.0
				sp2.radial_segments = 12
				sp2.rings = 6
				var tn = _glow_node(sp2, Color(c.r * 1.5, c.g * 1.5, c.b * 1.5), 2.5, 0.45 * (1.0 - k * 0.15))
				(tn.material_override as StandardMaterial3D).blend_mode = BaseMaterial3D.BLEND_MODE_ADD
				tn.set_meta("keep", true)
				tr.append(tn)
			mi.set_meta("tr", tr)
			mi.set_meta("keep", true)
			orb_n.append(mi)
	var nd: Node3D = g.node
	var tt = Time.get_ticks_msec() / 1000.0
	var bb: AABB = nd.get_meta("bb")
	var ctr: Vector3 = nd.global_transform * (bb.get_center() + Vector3(0, 0.05, 0))
	var bx = nd.global_transform.basis
	var X: Dictionary = fx.orbs
	if g.orbs <= 0.0:
		g.sorb = false
	var so: bool = g.get("sorb", false)
	var no = 4 if so else 2
	var oc = _hs(Color(1.0, 0.5, 0.12) if _noir() else Color(0.35, 0.85, 1.0), float(X.hue))
	if so:
		oc = _hs(Color(1.0, 0.72, 0.18), float(X.shue))
	var orad = float(X.radius)
	var osz = float(X.size)
	var ogl = float(X.glow) * (float(X.sglow) if so else 1.0)
	var otr = float(X.trail)
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
				_dmg(o, 0.3 if so else 0.15, 0, "orbs")
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
	_fire_w(g, w, sup)


func _fire_w(g: Dictionary, w: String, sup: bool) -> void:
	match w:
		"rak":
			_add_shot(g, false, false, 1.0, sup)
		"lenk":
			_add_shot(g, false, true)
			if sup:
				_add_shot(g, false, true, -1.0)   # zweite Lenkrakete nach hinten zum Verfolger
		"mine":
			_drop_mines(g, sup)
		"orbs":
			g.orbs = 10.0
			g.sorb = sup
			_snd("shield", 0.0, 1.0 if sup else 1.3)
		"schild":
			g.shield = 6.0
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
			if sup:
				quake2 = _quake_make(g.z - 3.0, -1.0, quake2)
			_snd("boom", 3.0, 0.6)
			_snd("boom", 0.0, 0.8)
			shake = maxf(shake, 1.5 * float(fx.quake.shake))
			_flash(_hs(Color(1.0, 0.5, 0.15), float(fx.quake.hue)), 0.45 * minf(1.0, float(fx.quake.glow)))
		"wand":
			var mi = _wall_node(sup)
			var z = g.z + 12.0
			_wall_pose(mi, z, 0.0, 0.0)
			walls.append({"z": z, "age": 0.0, "hit": [], "n": mi, "hf": 0.0, "sup": sup})
			_snd("wallon")
		"auto":
			g.auto = 5.0
			g.ahold = false
			g.sauto = sup
			_snd("shield")


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
	mats.road.set_shader_parameter("qc", _v3(_hs(Color(1.0, 0.42, 0.08), float(fx.quake.hue))))
	mats.road.set_shader_parameter("qg", float(fx.quake.glow))
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
			_dmg(o, 0.2, 0, "quake")
			if not o.out and not _prot(o):   # mit Schild: wird nicht hochgeworfen
				o.air = true
				o.vy = 5.8 * sqrt(float(QX.height))
				o.h = maxf(o.h, 0.6)
				o.slow = 0.25
	var f = T.frame(q.z)
	var dist = (q.z - g.z) * dir
	var qs = 1.3 * float(QX.height) * clampf(q.age / 0.25, 0.0, 1.0) * clampf((16.0 * qd - q.age) / 1.5, 0.0, 1.0) * clampf((qmax - dist) / (12.0 if state == "lab" else 40.0), 0.0, 1.0)
	q.n.global_transform = Transform3D(Basis(f.rr * dir, f.uu, f.fw * dir), f.c + f.uu * (qs * 1.6))
	q.l.light_energy = 8.0 * qs * float(QX.glow)
	q.qs = qs
	var sfx = "" if dir > 0.0 else "2"
	mats.road.set_shader_parameter("qz" + sfx, q.z)
	mats.road.set_shader_parameter("qs" + sfx, qs)
	shake = maxf(shake, 0.35 * clampf(1.0 - absf(q.z - g.z) / 40.0, 0.0, 1.0) * float(QX.shake))
	if dist > qmax or q.age > 16.0 * qd:
		q.n.queue_free()
		mats.road.set_shader_parameter("qs" + sfx, 0.0)
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
				_dmg(o, 0.06, w.own, "wave")
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
	if racing and posmod(wk, 2) == 0 and wz < 0.05 and not g.air and absf(g.lat - _wpx(wk)) < 0.34 and wk != g.wpK and (g.wpn == "" or not g.get("sup", false)):
		g.wpK = wk
		if g.wpn == "":
			g.wpn = _pick_w()
			_snd("pick", -4.0)
			_snd("vo_" + g.wpn, 3.0)   # Ansage, was du eingesammelt hast
			if g.wpn == "orbs" and g.orbs > 0.0:
				g.sup = true
				get_tree().create_timer(0.75).timeout.connect(func(): _snd("vo_super", 3.0))
		else:
			# Waffe noch nicht eingesetzt: mit etwas Glück gibt das Feld dieselbe noch einmal → Super-Waffe
			var nw = g.wpn if randf() < 0.4 else _pick_w()
			if nw == g.wpn:
				g.sup = true
				_snd("pick", -2.0, 1.35)
				_snd("vo_super", 3.0)
	if fire_req:
		fire_req = false
		if g.wpn != "" and racing:
			_fire()
	hud.fire.text = WN.get(g.wpn, "empty") + ("\n×2" if g.get("sup", false) and g.wpn != "" else "")
	if g.auto > 0.0 and g.wpn == "":
		hud.fire.text = ("SUPER\n" if g.get("sauto", false) else "") + "AUTO" + (" …" if g.get("ahold", false) else " %.1f" % g.auto)
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
	for o in ships:
		if o.idx > 0 and (o.node as Node3D).has_meta("bar"):
			var bar: MeshInstance3D = (o.node as Node3D).get_meta("bar")
			bar.set_instance_shader_parameter("fill", o.en)
			bar.visible = state == "race" and o.z - g.z > 1.5 and o.z - g.z < 40.0
	hud.en.size.x = 200.0 * g.en
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
				sh.lat += (sh.tg.lat - sh.lat) * minf(1.0, dt * 5.0)
		else:
			sh.lat += sh.dl * spd * dt
		var hit = null
		for o in ships:
			if o.out or o.idx == sh.own or (sh.pl and o.idx != 0):
				continue
			if absf(sh.z - o.z) < 0.8 + spd * dt * 1.5 and absf(sh.lat - o.lat) < (0.4 if sh.pl else 0.6):
				hit = o
				break
		var dead = false
		if hit != null:
			if not _prot(hit):
				hit.slow = 0.35
				hit.vpsi += randf_range(-0.25, 0.25)
			_dmg(hit, 0.3 if sh.pl else 0.35, sh.own, "rocket")
			_shot_boom(sh, sh.z, sh.lat, hit.idx)
			dead = true
		elif absf(sh.lat) > T.TW - 0.05 or sh.t > 6.0 or (sh.cl and sh.t > 0.42) or (state == "lab" and absf(sh.z - LZ) > 18.0):
			_shot_boom(sh, sh.z, clampf(sh.lat, -T.TW, T.TW), -1)
			dead = true
		else:
			# Annäherungszünder: fliegt die Rakete dicht an einem Gegner vorbei, geht sie sofort hoch
			for o in ships:
				if o.out or o.idx == sh.own or sh.pl:
					continue
				if absf(sh.z - o.z) < 0.8 + spd * dt * 1.5 and absf(sh.lat - o.lat) < 1.6:
					_shot_boom(sh, sh.z, sh.lat, -1)
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
				if not _prot(o):
					o.slow = 0.35
				_dmg(o, 0.2, m.get("own", 0), "mine")
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
				if not _prot(o):   # mit Schild: fliegt einfach durch
					o.slowT = 4.0 if ws else 2.5
				if ws and not _prot(o):
					o.slow = minf(o.slow, 0.35)
				w.hf = 1.0
				_dmg(o, 0.25 if ws else 0.1, 0, "wall")
				_zap_ship(o)
				_snd("zap", 2.0, 1.0, (o.node as Node3D).global_position)
		w.hf = maxf(0.0, w.hf - dt * 2.5)
		_wall_pose(w.n, w.z, w.age, w.hf)
		if w.age > 5.3 * float(fx.wall.dur):
			w.n.queue_free()
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
	c+=o*1.5*exp(-pow((fract(uv.y*.999-TIME*.8+sd)-.5)*9.,2.))*.35;
	c+=(wc+vec3(0.,.15,.15))*gk*smoothstep(.07,0.,min(uv.y,1.-uv.y))*2.8;
	c+=(wc+vec3(0.,.15,.15))*gk*smoothstep(.025,0.,min(uv.x,1.-uv.x))*2.2;
	for(int i=0;i<4;i++){
		float fi=float(i);float tq=floor(TIME*(11.+fi*2.)+fi*3.7+sd*5.);
		float on=step(.4-hit*.4,h11(tq*1.31+fi*9.1));
		float y0=.15+.7*h11(tq+fi*2.3);
		float pth=y0+(n1(uv.x*6.+tq*3.1)-.5)*.42+(n1(uv.x*21.+tq*5.7)-.5)*.14+(n1(uv.x*60.+tq)-.5)*.04;
		float d=abs(uv.y-pth);
		c+=(vec3(.75,.9,1.)*exp(-d*170.)*4.+vec3(.5,.6,1.)*exp(-d*28.)*.45)*on*bk;
	}
	ALBEDO=c*a*(1.+hit*2.5);
}"""


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
var rp = {}
const RP_CAMS = [["chase", "Chase", 6.0], ["side", "Trackside", 7.0], ["cock", "Cockpit", 6.0], ["side", "Trackside", 7.0], ["heli", "Aerial", 6.0], ["front", "Front", 5.0], ["free", "Free", 9999.0]]


func _rev(ev: Array) -> void:
	if state == "race" or state == "done":
		rec_ev.append(ev)


func _record(dt: float) -> void:
	if not (state == "race" or (state == "done" and t_state < 5.0)):
		return
	rec_clk += dt
	rec_acc += dt
	if rec_acc < 1.0 / 30.0 and not rec.is_empty() and rec_ev.is_empty():
		return
	rec_acc = 0.0
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
		wl.append([x.z, x.age, x.hf])
	rec.append({"t": rec_clk, "s": sh, "w": w, "m": m, "wl": wl, "q": [quake.z, quake.get("qs", 0.0)] if quake != null else null, "q2": [quake2.z, quake2.get("qs", 0.0)] if quake2 != null else null, "so": ships[0].get("sorb", false),
		"sh": ships[0].shield, "ob": ships[0].orbs, "ev": rec_ev, "pl": hud.top.text})
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
		for k in ["ring", "l", "core", "sw"]:
			if e.has(k) and e[k] != null and is_instance_valid(e[k]):
				e[k].queue_free()
	fxs.clear()
	for e in zaps:
		e.mi.queue_free()
		e.l.queue_free()
	zaps.clear()
	rp.base = get_children()
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
	for k in ["shots", "mines", "walls"]:
		for n in rp.get(k, []):
			n.queue_free()
	rp = {}
	if not rpf.is_empty():
		# Replay aus der Liste: zurück ins Menü
		get_tree().reload_current_scene()
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
	mats.road.set_shader_parameter("qs", 0.0)
	hud.fire.visible = true
	hud.en_bg.visible = true
	hud.el.visible = true
	hud.pg.visible = true
	hud.plbox.visible = true
	hud.top.text = rec[rec.size() - 1].pl
	for o in ships:
		(o.node as Node3D).visible = not o.out


func _replay(dt: float) -> void:
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
		var sp = SphereMesh.new()
		sp.radius = 0.12
		sp.height = 0.24
		return _glow_node(sp, Color(1, 0.15, 0.1), 6.0))
	for i in range(f0.m.size()):
		pm[i].position = T.world(f0.m[i][0], f0.m[i][1], 0.12)
	var pw = _pool("walls", f0.wl.size(), _wall_node)
	for i in range(f0.wl.size()):
		_wall_pose(pw[i], f0.wl[i][0], f0.wl[i][1], f0.wl[i][2])
	if f0.q != null:
		mats.road.set_shader_parameter("qz", f0.q[0])
		mats.road.set_shader_parameter("qs", f0.q[1])
	else:
		mats.road.set_shader_parameter("qs", 0.0)
	var q2 = f0.get("q2")
	mats.road.set_shader_parameter("qz2", q2[0] if q2 != null else -1000.0)
	mats.road.set_shader_parameter("qs2", q2[1] if q2 != null else 0.0)
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
	for k in ["shots", "mines", "walls"]:
		for n in rp.get(k, []):
			n.queue_free()
	rp = {"t": 0.0, "i": 0, "ei": -1, "ci": maxi(0, fix), "ct": 0.0, "sp": null, "sk": 1.0, "fix": fix}
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
	rp.ci = (rp.ci + 1) % RP_CAMS.size()
	rp.ct = 0.0
	rp.sp = null


func _rp_cam(dt: float) -> bool:
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
		return
	warm_t += delta
	if warm_before.is_empty():
		warm_before = get_children()
		warm = true
		var g: Dictionary = ships[0]
		var o: Dictionary = ships[1]
		var zf = g.z + 1.5
		_explode(zf, g.lat, true)
		_explode(zf, g.lat + 0.6, false)
		_gbomb(zf, g.lat - 0.6, -2)
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
		if not warm_before.has(n) and n != warm_cover and not tun_l.has(n):
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
	for k in ["shots", "mines", "walls"]:
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
		mats.road.set_shader_parameter("qs", 0.0)
	hud.top.text = kc.top
	kc = {}
	state = "race"
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
	if best > 100.0:
		hud.mw.visible = false
		mine_bt = 0.0
		return
	var k = clampf(best / 35.0, 0.0, 1.0)
	hud.mw.visible = fmod(Time.get_ticks_msec() / 1000.0, 0.4) < 0.26
	mine_bt -= dt
	if mine_bt <= 0.0:
		_snd("beep", -2.0, 1.25 + (1.0 - k) * 0.55)
		mine_bt = lerpf(0.09, 0.5, k)


# Ergebnistafel nach dem Rennen
var board_t = 0.0


func _board_update(dt: float) -> void:
	var show = state == "done" and hud.resb.visible
	hud.board.visible = show
	hud.rdim.visible = show
	hud.ring.visible = not show
	if show:
		hud.fire.visible = false
	if not show:
		board_t = 0.0
		return
	board_t += dt
	var dmg_mode = fmod(board_t, 9.0) > 5.0
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
var pf = {"n": 0, "sum": 0.0, "hist": [0, 0, 0, 0, 0], "sec": [], "acc": 0.0, "an": 0, "aw": 0.0, "sp": [], "ev": {}}


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
	if state != "race":
		return
	var ms = delta / maxf(0.01, Engine.time_scale) * 1000.0
	pf.n += 1
	pf.sum += ms
	var b = 0 if ms < 18.0 else (1 if ms < 25.0 else (2 if ms < 34.0 else (3 if ms < 50.0 else 4)))
	pf.hist[b] += 1
	pf.acc += delta
	pf.an += 1
	pf.aw = maxf(pf.aw, ms)
	if pf.acc >= 1.0:
		pf.sec.append("%5.1f  %3d fps  worst %3d ms  %s" % [race_t, int(round(pf.an / pf.acc)), int(pf.aw), _perf_ctx()])
		pf.acc = 0.0
		pf.an = 0
		pf.aw = 0.0
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
	s.psi = clampf(s.psi + (s.u * (YAW_P if is_p else YAW_AI) + turn) * dt, -0.9, 0.9)
	var grip = 0.8 if s.air else (9.5 if is_p else 7.0)
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
	s.slow += (1.0 - s.slow) * (1.0 - exp(-dt / 1.4))
	s.boost *= exp(-dt / 1.4)
	if s.out:
		s.spd = 0.0
		return
	if s.slowT > 0.0:
		s.slowT -= dt
	s.spd = base_spd * s.sk * (1.0 + 0.6 * s.boost) * s.slow * (0.75 if s.slowT > 0.0 else 1.0) if racing or state == "done" else 0.0
	var fwd: float = s.spd * cos(s.vpsi)
	s.z += fwd * dt
	s.lat += s.spd * sin(s.vpsi) * dt
	# Sprung: über der Lücke fliegt er, Schwerkraft holt ihn zurück (Weite begrenzt)
	if not s.air and T.gap(s.z):
		s.air = true
		s.h = 0.45
		var tf = maxf(8.5 / maxf(1.0, fwd), 0.6)  # flacher, gut sichtbarer Sprung, kurze Flugzeit
		s.vy = (2.0 * tf * tf - s.h) / tf
	if s.air:
		s.vy -= 4.0 * dt
		s.h += s.vy * dt
		if s.h <= 0.0 and not T.gap(s.z):
			if is_p and s.vy < -1.2:
				_snd("land")
			s.h = 0.0
			s.air = false
			s.vy = 0.0
			if not ap:
				s.slow = minf(s.slow, 0.9)
	# Leitplanke: weich parallel ausrichten, etwas bremsen
	var ml = T.TW - 0.3
	if absf(s.lat) > ml and not s.air:
		s.lat = signf(s.lat) * ml
		s.psi -= s.psi * minf(1.0, dt * 6.0)
		s.vpsi -= s.vpsi * minf(1.0, dt * 6.0)
		if race_t - s.hitT > 0.45 and racing:
			s.hitT = race_t
			s.slow = minf(s.slow, 0.65)
			if is_p:
				_snd("zap", -2.0, randf_range(0.9, 1.1))
	# Boost-Feld
	var k = int(round(s.z / 35.0))
	var fz = (s.z - _bzp(k)) / 35.0
	if fz >= 0.0 and fz < 0.08 and _pad_ok(_bzp(k)) and not s.air and absf(s.lat - _bpx(k)) < 0.36 and k != s.padK and racing:
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
		if state == "menu":
			if ui.setp.visible:
				_show_settings(false)
			elif ui.has("rpl"):
				_show_replays(false)
			else:
				get_tree().quit()
		elif state == "replay":
			_replay_end()
		elif state == "kill":
			_kc_end()
		elif state == "lab":
			_lab_close()
		else:
			get_tree().reload_current_scene()


func _process(delta: float) -> void:
	var dt = minf(delta, 0.05)
	t_state += dt
	ui.fps.text = "%d fps" % Engine.get_frames_per_second()
	_duck(delta / maxf(0.01, Engine.time_scale))
	_perf(delta)
	var g: Dictionary = ships[0]
	if warm_t >= 0.0:
		_warm_step(delta)
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
			var lk = int(floor((g.z - 20.0) / T.LAP))
			for i in range(3):
				laps[i].position = Vector3(0, 0, (lk - 1 + i) * T.LAP)
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
			var lr = int(floor((_focus().z - 20.0) / T.LAP))
			for i in range(3):
				laps[i].position = Vector3(0, 0, (lr - 1 + i) * T.LAP)
			_tunnel(dt)
			_pose_all(dt)
			_camera(dt)
			_sound_update(dt)
			_post_update(dt)
			_shot()
			return
	var racing = state == "race"
	if state == "intro" and t_state > INTRO_T:
		state = "count"
		t_state = 0.0
	elif state == "count":
		var c = 3 - int(floor(t_state))
		if c != last_c:
			if last_c == 99:
				_snd("count")
				_snd("start")
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
	var b = _steer_input()
	if b != steer_btn:
		steer_btn = b
		btn_t = 0.0
	btn_t += dt
	var steer = 0.0
	if b != 0:
		var x = minf(1.0, btn_t / RAMP)
		steer = b * (START + (1.0 - START) * pow(x, SHAPE))
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
		# Gummiband: wer hinten liegt, holt auf; wer weit vorn ist, lässt etwas nach
		var dz: float = o.z - g.z
		var st: float = o.sk0
		if racing:
			if dz < -4.0:
				st = o.sk0 * (1.0 + minf(0.24, (-dz - 4.0) * 0.0065))
			elif dz > 18.0:
				st = o.sk0 * (1.0 - minf(0.12, (dz - 18.0) * 0.004))
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
		_show_resb()
	elif racing and kc_pending.is_empty() and ships.slice(1).all(func(x): return x.out):
		state = "done"
		t_state = 0.0
		g.fin = race_t
		_snd("win")
		_show_resb()
		hud.res.text = "1st  ·  LAST ONE STANDING\n%s" % _fmt(race_t)
	elif racing and g.z >= finish:
		state = "done"
		t_state = 0.0
		g.fin = race_t
		_snd("win")
		_show_resb()
		hud.res.text = "%s  ·  %s" % [["1st", "2nd", "3rd", "4th"][place - 1], _fmt(race_t)]
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
	var l0 = int(floor((g.z - 20.0) / T.LAP))
	for i in range(3):
		laps[i].position = Vector3(0, 0, (l0 - 1 + i) * T.LAP)
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
	for i in range(3):
		laps[i].position = Vector3(0, 0, (i - 1) * T.LAP)
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
	hint.modulate = Color(1, 1, 1, 0.5)
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
	grid.columns = 6
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
	for i in range(3):
		laps[i].position = Vector3(0, 0, (i - 1) * T.LAP)


func _lab_close() -> void:
	_fx_save()
	get_tree().reload_current_scene()


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
	lab.fire.disabled = lab.tab in ["env", "pillar"]
	lab.fire.modulate.a = 0.35 if lab.fire.disabled else 1.0
	lab.fire.text = "BOOST" if lab.tab in ["haze", "ship"] else "FIRE"


func _lab_val(it: Array, v: float) -> String:
	var k: String = it[0]
	if k.begins_with("hue"):
		return "%+d°" % int(round(v * 360.0))
	if k == "life":
		return "%d s" % int(round(v))
	if k == "city":
		return "On" if v > 0.5 else "Off"
	return "%d %%" % int(round(v * 100.0)) if v >= 0.995 or v == 0.0 else "%.1f %%" % (v * 100.0)


func _lab_tab(t: String) -> void:
	if lab.has("tab") and _lab_grp(lab.tab) != _lab_grp(t):
		var V = {"near": [0.35, 0.22, 5.5], "ship": [0.55, 0.2, 6.0], "pillar": [0.45, 0.12, 6.5]}.get(_lab_grp(t), [0.35, 0.22, 12.0])
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
		lab.lst.add_child(lb)
		var hs = HSlider.new()
		hs.min_value = it[2]
		hs.max_value = it[3]
		hs.step = 1.0 if key == "city" else (1.0 if key == "life" else 0.001)
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
		hs.value_changed.connect(upd)
		lb.text = "%s   %s" % [it[1], _lab_val(it, hs.value)]
		# − Regler +  (kleine Schritte; gedrückt halten wiederholt)
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var stp = 1.0 if key in ["city", "life"] else (0.005 if key.begins_with("hue") else 0.05)
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
	if t == "env":
		_city_fill()
		_env_apply()
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
	if lab.auto and not lab.tab in ["env", "pillar"]:
		lab.at -= dt
		if lab.at <= 0.0:
			_lab_fire()
			lab.at = {"ship": 4.0, "quake": 4.0, "wall": 5.3 * float(fx.wall.dur) + 0.4, "mine": 3.2, "shield": 6.3, "orbs": 10.3, "haze": 3.0}.get(lab.tab, 3.0)
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
		var l0 = int(floor((g.z - 20.0) / T.LAP))
		for i in range(3):
			laps[i].position = Vector3(0, 0, (l0 - 1 + i) * T.LAP)
	_weapons(dt, false)
	_tunnel(dt)
	_pose_all(dt)
	# Kamera kreist um die Teststelle bzw. fliegt im Reiter „Ship“ mit dem Gleiter mit
	var tzz = {"near": LZ + 0.3, "ship": g.z + 0.3, "pillar": LZ + 5.0}.get(grp, LZ + 7.0)
	var tll = g.lat if grp == "ship" else 0.0
	if grp == "ship" and absf(lab.get("tz", tzz) - tzz) < 3.0:
		lab.tz = tzz
	else:
		lab.tz = lerpf(lab.get("tz", LZ + 7.0), tzz, 1.0 - exp(-dt / 0.3))
	lab.tl = lerpf(lab.get("tl", 0.0), tll, 1.0 - exp(-dt / 0.15))
	var f = T.frame(lab.tz)
	var tg: Vector3 = f.c + f.rr * lab.tl + f.uu * {"near": 0.4, "ship": 0.4, "pillar": 1.1}.get(grp, 0.8)
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
	cam.rotate_object_local(Vector3(1, 0, 0), -0.29)
	_sound_update(dt)
	_post_update(dt)
	_shot()


# Nur zum Testen am Rechner: godot -- --shot=Pfad,z  → setzt dich an die Stelle z und speichert ein Bild
var shot_n = 0
func _shot() -> void:
	for a in OS.get_cmdline_user_args():
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
				var at = 60 + {"boom": 26, "mine": 26, "quake": 30, "gb": 36, "rak": 34, "wall": 40, "env": 30, "pillar": 70, "ship": 140}.get(p[3], 40)
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
					get_tree().reload_current_scene()
					return
			if shot_n == 2 and p.size() > 2:
				_start()
				if p[2] != "intro":
					state = "race"
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
				elif p[3] == "armed":
					ships[0].wpn = "lenk"
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
			if shot_n == ({"repb": 84, "repf": 85, "armed": 50, "kill1": 75, "kill4": 160, "kill2": 90, "kill3": 110, "long": 700, "i1": 22, "i2": 38, "i3": 52, "orbs": 47, "rep0": 85, "rep1": 85, "rep2": 85, "rep4": 85, "rep5": 85, "wand": 56, "boom": 42, "boom2": 70, "beben": 47, "gb1": 47, "gb2": 53, "schild": 44}.get(p[3], 90) if p.size() > 3 else 90):
				get_viewport().get_texture().get_image().save_png(p[0])
				if p.size() > 3 and p[3] == "long":
					print(_perf_text())
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
	for tu in T.TUN:
		k = maxf(k, clampf(minf(zl - tu[0] + 2.0, tu[1] - zl + 2.0) / 7.0, 0.0, 1.0))
	tun_k += (k - tun_k) * (1.0 - exp(-dt / 0.2))
	wenv.ambient_light_energy = lerpf(0.35, 0.02, tun_k)
	wenv.fog_density = lerpf(0.012 * float(fx.env.fog), 0.0, tun_k)
	wenv.fog_enabled = float(fx.env.fog) > 0.01
	wenv.background_energy_multiplier = lerpf(1.0, 0.05, tun_k)
	moon.light_energy = lerpf(0.45 * float(fx.env.moon), 0.0, tun_k)
	# im Tunnel sieht man den Mond nicht: Schattenberechnung sparen
	moon.shadow_enabled = int(cfg.gfx) >= 1 and tun_k < 0.6 and float(fx.env.moon) > 0.01
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
	for tu in T.TUN:
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
		if absf(s.get("pit", 0.0)) > 0.0001:
			nd.rotate_object_local(Vector3(1, 0, 0), -s.pit)   # Nase hoch beim Gasgeben
		var jets: Array = nd.get_meta("jets")
		for j in jets:
			j.visible = s.boost > 0.25
		var lt: OmniLight3D = nd.get_meta("light")
		lt.light_energy = (1.4 + 3.0 * s.boost) * (1.0 + 1.2 * tun_k)
		var HX: Dictionary = fx.haze
		for hm in nd.get_meta("haze"):
			hm.set_shader_parameter("k", 0.55 + 0.9 * float(HX.boost) * minf(1.0, s.boost))
			hm.set_shader_parameter("hs", float(HX.amp))
			hm.set_shader_parameter("hv", float(HX.speed))
			hm.set_shader_parameter("hf", float(HX.fine))
		var hzn: Array = nd.get_meta("hazen")
		for k in range(hzn.size()):
			var hn: MeshInstance3D = hzn[k]
			hn.scale = Vector3.ONE * (0.75 if k == 0 else 1.1) * float(HX.size)
			hn.position.z = -0.75 - (0.28 if k == 0 else 0.85) * float(HX.len)
			hn.visible = float(HX.amp) > 0.01
		lt.omni_range = 4.0 + 4.0 * tun_k
		lt.light_color = Color(0.6, 0.4, 1.0).lerp(Color(0.3, 0.8, 1.0), clampf(s.boost, 0.0, 1.0))


# Kamera: hinter dem Gleiter, folgt der Nase gedämpft, bleibt beim Boost kurz zurück
func _camera(dt: float) -> void:
	if state == "replay" and _rp_cam(dt):
		return
	if state == "kill" and _kc_cam():
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
