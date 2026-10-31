# AntiGrav 3D – erste Godot-Version: Neon Night, ein Gleitermodell, drei Gegner, echte Beleuchtung,
# Bildschirm-Spiegelungen, Schatten, Glühen. Alles wird beim Start im Code aufgebaut.
extends Node3D

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
const BASE_DEF = 12.0  # Grundtempo (Einheiten/s) bei Tempo 100 %
const NAMES = ["You", "Vega", "Kato", "Mira"]

var laps: Array[Node3D] = []
var lap_mesh: ArrayMesh
var bld_mm: MultiMesh
var cam: Camera3D
var ships: Array = []  # Zustand je Gleiter (Dictionary), [0] = du
var state = "menu"
var cfg = {"ship": 0, "speed": 1.0, "gfx": 2, "glow": 0.5, "neon": 0.8, "vol": 0.9}
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
const WP = [["rak", 0.22], ["lenk", 0.22], ["mine", 0.13], ["schild", 0.1], ["turbo", 0.12], ["beben", 0.09], ["auto", 0.05], ["wand", 0.07]]
const WN = {"rak": "MISSILE", "lenk": "HOMING", "mine": "MINES", "schild": "SHIELD", "turbo": "TURBO", "beben": "QUAKE", "auto": "AUTO", "wand": "WALL"}
var shots = []
var mines = []
var fxs = []
var walls = []
var quake = null
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


func _ready() -> void:
	_load_cfg()
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
	_menu()
	_sounds()
	_apply_cfg()


# ---------------------------------------------------------------- Klänge aus dem alten Spiel (Dateien in sfx/)
func _sounds() -> void:
	for n in ["boom.ogg", "count.ogg", "engine.wav", "idle.wav", "mine.ogg", "pick.ogg", "rak.ogg", "shield.ogg", "start.ogg", "win.ogg", "wallon.ogg",
			"boost.wav", "zap.wav", "beep.wav", "go.wav", "pass.wav", "land.wav", "field.wav", "gbomb.wav", "phase.wav"]:
		snd[n.get_basename()] = load("res://sfx/" + n)
	for k in ["engine", "idle", "field"]:
		var p = AudioStreamPlayer.new()
		p.stream = _looped(snd[k])
		p.volume_db = -80.0
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
	if not snd.has(k):
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
uniform sampler2D scr:hint_screen_texture,filter_linear_mipmap;
uniform float spd=0.;
uniform vec2 gc=vec2(.5);
uniform float gs=0.;
uniform float gr=-1.;
uniform float gk=0.;
uniform float gl=0.;
uniform float asp=.46;
float h21(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
void fragment(){
	vec2 uv=SCREEN_UV;
	// Gravitationsbombe: Bild wird zur Mitte gesogen, danach läuft eine Welle nach außen
	vec2 dd=uv-gc;dd.x*=asp;float r=length(dd)+1e-4;vec2 dir=dd/r;dir.x/=asp;
	float pull=gs*.05/(r*r*30.+.12)*smoothstep(0.,.03,r);
	float rip=gr>=0.?sin((r-gr)*60.)*exp(-pow((r-gr)*9.,2.))*.022*gk:0.;
	uv-=dir*(pull-rip);
	// Phasen-Glitch: Zeilen verrutschen, Farben laufen auseinander
	float band=floor(uv.y*46.+floor(TIME*24.)*3.1);float go=(h21(vec2(band,floor(TIME*30.)))-.5)*.05*gl*step(.55,h21(vec2(band,1.7)));
	uv.x+=go;
	// Geschwindigkeit: radiale Zoom-Unschärfe mit Farbversatz zu den Rändern
	vec2 cd=uv-vec2(.5,.47);float e=smoothstep(.12,.75,length(cd*vec2(asp,1.)));
	float ca=.004*spd*e+.006*gl+.01*abs(gs);
	vec3 col=vec3(0.);
	for(int i=0;i<8;i++){float f=1.-float(i)*.011*spd*e;vec2 q=vec2(.5,.47)+cd*f;
		col+=vec3(texture(scr,q-cd*ca).r,texture(scr,q).g,texture(scr,q+cd*ca).b);}
	col/=8.;
	// schwarzer Kern und leuchtender Ring der Bombe
	float gp=max(gs,0.);
	col*=1.-smoothstep(.06*gp+.01,.0,r)*gp;
	col+=vec3(.75,.55,1.)*exp(-pow((r-.075*gp)*55.,2.))*gp*1.6;
	if(gr>=0.)col+=vec3(.6,.45,1.)*exp(-pow((r-gr)*30.,2.))*gk*.8;
	// Speed-Linien: helle Streifen fliegen von der Mitte nach außen
	float an=atan(cd.y,cd.x*asp);float lane=floor(an*70.);float hl=h21(vec2(lane,3.));
	float sl=step(.93,hl)*smoothstep(.0,.15,fract(length(cd)*2.2-TIME*(2.5+hl*3.)+hl))*smoothstep(.5,.1,fract(length(cd)*2.2-TIME*(2.5+hl*3.)+hl));
	col+=vec3(.75,.88,1.)*sl*spd*e*.45;
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
	post.set_shader_parameter("gs", gs * bk)
	post.set_shader_parameter("gr", (t - 0.55) * 1.1 if t >= 0.55 else -1.0)
	post.set_shader_parameter("gk", bk * clampf(1.0 - (t - 0.55) / 0.8, 0.0, 1.0))


var post_spd = 0.0
var gl_v = 0.0


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
	moon.shadow_enabled = q >= 1
	get_viewport().msaa_3d = Viewport.MSAA_4X if q >= 2 else (Viewport.MSAA_2X if q == 1 else Viewport.MSAA_DISABLED)
	get_viewport().scaling_3d_scale = [0.7, 0.85, 1.0][q]
	wenv.glow_intensity = 1.6 * float(cfg.glow)
	wenv.glow_strength = 0.6 + 0.6 * float(cfg.glow)
	for nm in neon_mats:
		nm[0].emission_energy_multiplier = nm[1] * float(cfg.neon)
	for b in lights_nodes:
		b.light_energy = 2.2 * float(cfg.neon)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.001, float(cfg.vol))))


# ---------------------------------------------------------------- Umgebung: Himmel, Licht, Glühen, Spiegelungen, Nebel
func _env() -> void:
	var sky_mat = ShaderMaterial.new()
	sky_mat.shader = Shader.new()
	sky_mat.shader.code = """
shader_type sky;
float h21(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
void sky(){
	vec3 d=EYEDIR;float h=d.y;float an=atan(d.x,d.z);
	vec3 c=mix(vec3(.04,.02,.07),vec3(.002,.003,.012),smoothstep(0.,.5,h));
	vec2 sp=vec2(an*90.,h*160.);vec2 ci=floor(sp);
	c+=vec3(.8,.85,1.)*step(.986,h21(ci))*smoothstep(.03,.25,h)*(1.-step(.3,length(fract(sp)-.5)))*1.6;
	vec3 md=normalize(vec3(.5,.32,.8));float mo=dot(d,md);
	c+=vec3(.9,.92,1.)*smoothstep(.9994,.9997,mo)*4.+vec3(.25,.3,.5)*pow(max(0.,mo),60.)*.35;
	// Skyline in zwei Tiefen mit Fenstern und Neonkanten
	for(int k=0;k<2;k++){float fk=float(k);float s=55.-fk*20.;float bx=floor(an*s);
		float bh=(.014+.05*pow(h21(vec2(bx,fk)),2.2))*(1.+fk*.7);
		if(h<bh&&h>-.04){vec2 w=vec2(fract(an*s)*5.,h*s*6.);vec2 wi=floor(w);
			float lit=step(.68,h21(wi+bx*1.3+fk*7.))*step(.25,fract(w.x))*step(.3,fract(w.y));
			vec3 wc=h21(wi+3.1)>.8?vec3(.3,.8,1.):vec3(1.,.7,.45);
			c=vec3(.004,.005,.01)*(1.+fk)+wc*lit*(.6-fk*.2);
			if(h>bh-.0025)c+=(h21(vec2(bx,9.))>.5?vec3(0.,.78,1.):vec3(1.,.06,.42))*1.5;}}
	c+=vec3(.5,.12,.45)*exp(-abs(h)*22.)*.22;
	if(h<-.04)c=mix(c,vec3(.006,.005,.012),smoothstep(-.04,-.15,h));
	COLOR=c;
}
"""
	var sky = Sky.new()
	sky.sky_material = sky_mat
	var env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.16, 0.12, 0.26)
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
	env.fog_light_color = Color(0.05, 0.03, 0.09)
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
	moon.light_color = Color(0.6, 0.66, 1.0)
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


func _shader_mat(code: String) -> ShaderMaterial:
	var m = ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = code
	return m


const CY = Color(0.0, 0.78, 1.0)
const MG = Color(1.0, 0.06, 0.42)
const AM = Color(1.0, 0.62, 0.08)


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
		var zc = k * 35.0
		if zc < 25.0 or zc > 715.0 or T.gap(zc + 1.4):
			continue
		var bx = T.bpx(k)
		_strip("pad", zc, zc + 3.0, bx - 0.36, bx + 0.36, 0.008, 0.008)
	# Waffenfelder: bunter Ring auf jedem zweiten Feld
	for wk in range(0, 21, 2):
		var zw = wk * 35.0 + 17.0
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
	mats["road"] = _shader_mat("""
shader_type spatial;
// Fahrbahn wie bei Wipeout: dunkelgraues, gebürstetes Metall in Platten, feine Fugen, Randmarkierung; glatt, leicht glänzend
float h11(float x){return fract(sin(x*91.7)*4371.3);}
float h21(vec2 p){return fract(sin(dot(p,vec2(12.9898,78.233)))*43758.5453);}
// Bebenwelle: Kamm bei qz, davor ein kleiner Anlauf, dahinter ein Tal und Nachschwingen
uniform float qz=-1000.;uniform float qs=0.;
varying float wz;varying float qh;
float quake(float z){float d=z-qz;return qs*(1.6*exp(-pow(d/2.6,2.))-.5*exp(-pow((d+6.)/2.6,2.))+.22*exp(-pow((d+12.)/2.4,2.)));}
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
	float cr=max(qh,0.)/max(qs,.01);   // glühender Kamm, aufgerissene Fugen
	EMISSION=(vec3(1.,.42,.08)*pow(cr,1.5)*6.+vec3(1.,.25,.05)*seam*cr*14.)*step(.01,qs);
}""")
	mats["wall"] = _metal(Color(0.07, 0.075, 0.09), 0.22)
	mats["metal"] = _metal(Color(0.09, 0.095, 0.11), 0.3)
	mats["tube"] = _metal(Color(0.035, 0.03, 0.05), 0.35, 0.6)
	mats["neonL"] = _neon(CY, 5.0)
	mats["neonR"] = _neon(MG, 5.0)
	mats["ringC"] = _neon(CY, 7.0)
	mats["ringM"] = _neon(MG, 7.0)
	mats["line"] = _neon(Color(0.8, 0.85, 1.0), 0.6)
	mats["tlight"] = _neon(Color(0.9, 0.95, 1.0), 3.0)
	mats["board0"] = _neon(Color(0.1, 0.4, 1.0), 2.2)
	mats["board1"] = _neon(Color(1.0, 0.2, 0.5), 2.2)
	mats["board2"] = _neon(Color(1.0, 0.7, 0.1), 2.2)
	mats["pad"] = _shader_mat("""
shader_type spatial;
render_mode unshaded,cull_disabled;
void fragment(){
	vec2 u=UV;float ch=step(abs(fract(u.x*6.-TIME*2.)-.5-abs(u.y-.5)*.9),.14);
	ALBEDO=mix(vec3(.05,.6,1.),vec3(1.,.85,.15),ch)*(1.6+ch*1.8);
}""")
	mats["wpad"] = _shader_mat("""
shader_type spatial;
render_mode unshaded,cull_disabled;
void fragment(){
	vec2 q=vec2((UV.x-.5)*2.5,(UV.y-.5)*1.);float r=length(q);
	float ring=smoothstep(.05,0.,abs(r-.38))+smoothstep(.04,0.,abs(r-.24))*.8+smoothstep(.12,0.,r);
	vec3 c=.5+.5*cos(6.2832*(atan(q.y,q.x)/6.2832+TIME*.4+vec3(0.,.33,.67)));
	ALBEDO=c*(3.5+1.5*sin(TIME*6.));ALPHA=clamp(ring,0.,1.);
}""")
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
void fragment(){
	vec3 c=.5+.5*cos(6.2832*(UV.x+TIME*.3+vec3(0.,.33,.67)));
	float f=pow(1.-UV.y,0.0)*(1.-UV.y)*(1.-UV.y);
	ALBEDO=c*1.6*(UV.y)*(.6+.4*sin(TIME*5.+UV.y*12.));
}""")
		for wp in wpads:
			var cy = CylinderMesh.new()
			cy.top_radius = 0.42
			cy.bottom_radius = 0.42
			cy.height = 5.0
			cy.cap_top = false
			cy.cap_bottom = false
			var bm = MeshInstance3D.new()
			bm.mesh = cy
			bm.material_override = beam_mat
			bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var f = T.frame(wp[0])
			bm.transform = Transform3D(Basis(f.rr, f.uu, f.fw), f.c + f.rr * wp[1] + f.uu * 2.5)
			n.add_child(bm)
		laps.append(n)


var mats = {}
var lights = []
var lights_nodes = []
var wpads = []
var beam_mat: ShaderMaterial


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
	box.material = _shader_mat("""
shader_type spatial;
varying vec3 wp;varying vec3 wn;varying vec4 cd;
void vertex(){wp=(MODEL_MATRIX*vec4(VERTEX,1.)).xyz;wn=normalize((MODEL_MATRIX*vec4(NORMAL,0.)).xyz);cd=INSTANCE_CUSTOM;}
float h21(vec2 p){return fract(sin(dot(p,vec2(12.9898,78.233)))*43758.5453);}
void fragment(){
	float side=1.-step(.9,abs(wn.y));float u=abs(wn.x)>.5?wp.z:wp.x;
	vec2 g=vec2(u*.55,wp.y*.42);vec2 gi=floor(g),gf=fract(g);
	float win=step(.22,gf.x)*step(gf.x,.78)*step(.3,gf.y)*step(gf.y,.82)*side;float hh=h21(gi+floor(cd.a*3.));
	vec3 wc=hh>.93?vec3(.4,.85,1.):(hh>.86?vec3(1.,.4,.75):vec3(1.,.78,.5));
	ALBEDO=vec3(.015,.017,.025);METALLIC=.7;ROUGHNESS=.18;
	EMISSION=wc*win*step(.6,hh)*2.2+cd.rgb*smoothstep(cd.a-.8,cd.a-.3,wp.y)*step(wp.y,cd.a)*side*5.;
}""")
	bld_mm = MultiMesh.new()
	bld_mm.transform_format = MultiMesh.TRANSFORM_3D
	bld_mm.use_custom_data = true
	var items = []
	var rng = RandomNumberGenerator.new()
	rng.seed = 7
	var k = 0
	while k * 16 < 700:
		var zc = 20.0 + k * 16.0 + 8.0
		var f = T.frame(zc)
		for sd in [-1.0, 1.0]:
			if rng.randf() < 0.3:
				continue
			var lat: float = sd * (T.TW + 11.0 + rng.randf() * 38.0)
			var H = 22.0 + pow(rng.randf(), 1.6) * 80.0
			var w = 3.0 + rng.randf() * 5.0
			var d = 3.0 + rng.randf() * 5.0
			var pos = Vector3(f.c.x - lat, -42.0 + H / 2.0, zc + (rng.randf() - 0.5) * 6.0)
			items.append([Transform3D(Basis.from_scale(Vector3(w / 2.0, H / 2.0, d / 2.0)), pos), _neo(rng.randf()), pos.y + H / 2.0])
		k += 1
	bld_mm.instance_count = items.size()
	for i in range(items.size()):
		bld_mm.set_instance_transform(i, items[i][0])
		var c: Color = items[i][1]
		bld_mm.set_instance_custom_data(i, Color(c.r, c.g, c.b, items[i][2]))
	for n in laps:
		var mmi = MultiMeshInstance3D.new()
		mmi.multimesh = bld_mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(mmi)


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
	var lt = OmniLight3D.new()
	lt.light_color = Color(0.6, 0.4, 1.0)
	lt.light_energy = 1.4
	lt.omni_range = 4.0
	lt.position = Vector3(0, 0.15, -0.95)
	root.add_child(lt)
	root.set_meta("jets", jets)
	root.set_meta("light", lt)
	add_child(root)
	return root


var shield_mat: ShaderMaterial


func _shield_for(root: Node3D) -> Node3D:
	if shield_mat == null:
		shield_mat = _shader_mat("""
shader_type spatial;
render_mode unshaded,blend_add,cull_back,depth_draw_never,shadows_disabled;
void fragment(){
	float fr=pow(1.-clamp(dot(NORMAL,VIEW),0.,1.),2.2);
	float fl=.75+.25*sin(TIME*28.+VERTEX.y*30.+VERTEX.x*20.);
	ALBEDO=vec3(.3,.8,1.)*(fr*2.6+.06)*fl;
}""")
	var piv: Node3D = root.get_child(0)
	var m: Node3D = piv.get_child(0)
	var c: Node3D = m.duplicate()
	for n in c.find_children("*", "", true, false):
		if str(n.name).contains("Boost") or str(n.name).contains("Glow"):
			n.queue_free()
	for mi in c.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = shield_mat
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	c.scale = m.scale * 1.08
	c.position = m.position * 1.08 - Vector3(0, 0.03, 0)
	piv.add_child(c)
	root.set_meta("shield", c)
	# Phasen-Geister: zwei verschobene Kopien in Magenta und Cyan
	var gh = []
	for col in [Color(1.0, 0.2, 0.7), Color(0.2, 0.9, 1.0)]:
		var gm = _shader_mat("""
shader_type spatial;
render_mode unshaded,blend_add,cull_back,depth_draw_never,shadows_disabled;
uniform vec3 col;
void fragment(){float fr=pow(1.-clamp(dot(NORMAL,VIEW),0.,1.),1.6);ALBEDO=col*(fr*1.6+.12)*(.6+.4*sin(TIME*45.+VERTEX.z*25.));}""")
		gm.set_shader_parameter("col", Vector3(col.r, col.g, col.b))
		var gc2: Node3D = c.duplicate()
		for mi in gc2.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_override = gm
		piv.add_child(gc2)
		gh.append(gc2)
	root.set_meta("ghosts", gh)
	root.set_meta("base_pos", c.position)
	return c


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
		var s = {"z": starts[i][0], "lat": starts[i][1], "psi": 0.0, "vpsi": 0.0, "u": 0.0, "spd": 0.0, "boost": 0.0, "slow": 1.0,
			"h": 0.0, "vy": 0.0, "air": false, "padK": -1, "hitT": -9.0, "sk": 0.95 + (i - 1) * 0.03 if i > 0 else 1.0, "sk0": 0.0,
			"ai": randf() * 100.0, "node": _ship_node(sm), "sm": sm, "fin": 0.0, "roll": 0.0,
			"en": 1.0, "out": false, "wpn": "", "wpK": -1, "shield": 0.0, "auto": 0.0, "turbo": 0.0, "slowT": 0.0, "enL": 0, "idx": i}
		s.sk0 = s.sk
		ships.append(s)


# ---------------------------------------------------------------- Anzeige: Platz, Runde, Zeit, Lenkknöpfe
func _hud() -> void:
	var cl = CanvasLayer.new()
	add_child(cl)
	hud.layer = cl
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
	hud.mid = mk.call(120, HORIZONTAL_ALIGNMENT_CENTER)
	hud.mid.anchor_right = 1.0
	hud.mid.anchor_top = 0.3
	hud.mid.anchor_bottom = 0.3
	hud.msg = mk.call(32, HORIZONTAL_ALIGNMENT_CENTER)
	hud.msg.anchor_right = 1.0
	hud.msg.offset_top = 190
	hud.en_bg = ColorRect.new()
	hud.en_bg.color = Color(1, 1, 1, 0.15)
	hud.en_bg.position = Vector2(36, 140)
	hud.en_bg.size = Vector2(200, 12)
	cl.add_child(hud.en_bg)
	hud.en = ColorRect.new()
	hud.en.color = Color(0.36, 1.0, 0.6)
	hud.en.size = Vector2(200, 12)
	hud.en_bg.add_child(hud.en)
	var el = mk.call(16, HORIZONTAL_ALIGNMENT_LEFT)
	el.text = "ENERGY"
	el.position = Vector2(36, 156)
	el.modulate = Color(1, 1, 1, 0.7)
	hud.fire = mk.call(26, HORIZONTAL_ALIGNMENT_CENTER)
	hud.fire.anchor_left = 0.5
	hud.fire.anchor_right = 0.5
	hud.fire.anchor_top = 1.0
	hud.fire.anchor_bottom = 1.0
	hud.fire.offset_left = -110
	hud.fire.offset_right = 110
	hud.fire.offset_top = -250
	hud.fire.offset_bottom = -90
	hud.fire.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var fsb = StyleBoxFlat.new()
	fsb.bg_color = Color(1, 1, 1, 0.07)
	fsb.border_color = Color(1, 1, 1, 0.3)
	fsb.set_border_width_all(3)
	fsb.set_corner_radius_all(80)
	hud.fire.add_theme_stylebox_override("normal", fsb)
	hud.fire_sb = fsb
	hud.res = mk.call(34, HORIZONTAL_ALIGNMENT_CENTER)
	hud.res.anchor_right = 1.0
	hud.res.anchor_top = 0.42
	hud.res.anchor_bottom = 0.42
	for sd in [-1, 1]:
		var b = mk.call(70, HORIZONTAL_ALIGNMENT_CENTER)
		b.text = "‹" if sd < 0 else "›"
		b.modulate = Color(1, 1, 1, 0.45)
		b.anchor_top = 1.0
		b.anchor_bottom = 1.0
		b.anchor_left = 0.0 if sd < 0 else 1.0
		b.anchor_right = b.anchor_left
		b.offset_left = 30 if sd < 0 else -150
		b.offset_right = 150 if sd < 0 else -30
		b.offset_top = -230
		b.offset_bottom = -110


# ---------------------------------------------------------------- Menü: Gleiterwahl, Start, Einstellungen (Tempo, Grafik)
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
	# Hauptseite
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	box.anchor_left = 0.06
	box.anchor_right = 0.94
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_top = -620
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
	var bs = _btn("Settings")
	box.add_child(bs)
	ui.credit = _lbl("", 18)
	ui.credit.modulate = Color(1, 1, 1, 0.4)
	ui.credit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(ui.credit)
	# Einstellungen
	var sp = VBoxContainer.new()
	sp.add_theme_constant_override("separation", 22)
	sp.anchor_left = 0.06
	sp.anchor_right = 0.94
	sp.anchor_top = 1.0
	sp.anchor_bottom = 1.0
	sp.offset_top = -1180
	sp.offset_bottom = -70
	sp.visible = false
	root.add_child(sp)
	ui.setp = sp
	sp.add_child(_lbl("SETTINGS", 40))
	ui.sl = {}
	for it in [["speed", 0.5, 4.0], ["glow", 0.0, 1.5], ["neon", 0.2, 1.5], ["vol", 0.0, 1.0]]:
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
		b.pressed.connect(func(): cfg.gfx = q; _refresh_ui(); _apply_cfg(); _save_cfg())
		gr.add_child(b)
		ui.gfx.append(b)
	var back = _btn("Done", true)
	back.pressed.connect(func(): sp.visible = false; box.visible = true)
	sp.add_child(back)
	bs.pressed.connect(func(): box.visible = false; sp.visible = true)
	# Bildrate oben links (zum Prüfen, ob es flüssig läuft)
	var fl = CanvasLayer.new()
	fl.layer = 9
	add_child(fl)
	ui.fps = _lbl("", 20)
	ui.fps.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	ui.fps.position = Vector2(24, 24)
	ui.fps.modulate = Color(1, 1, 1, 0.55)
	fl.add_child(ui.fps)
	hud.layer.visible = false
	_refresh_ui()


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
	ui.sl.glow.text = "Glow  %d %%" % int(round(float(cfg.glow) * 100.0))
	ui.sl.neon.text = "Neon lights  %d %%" % int(round(float(cfg.neon) * 100.0))
	ui.sl.vol.text = "Volume  %d %%" % int(round(float(cfg.vol) * 100.0))
	for q in range(3):
		ui.gfx[q].button_pressed = int(cfg.gfx) == q
		var on = int(cfg.gfx) == q
		ui.gfx[q].add_theme_stylebox_override("normal", _style(Color(0.93, 0.41, 0.18) if on else Color(1, 1, 1, 0.08), Color(1, 0.7, 0.54) if on else Color(1, 1, 1, 0.22)))
		ui.gfx[q].add_theme_stylebox_override("pressed", ui.gfx[q].get_theme_stylebox("normal"))
		ui.gfx[q].add_theme_stylebox_override("hover", ui.gfx[q].get_theme_stylebox("normal"))


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
	state = "intro"
	t_state = 0.0
	ui.root.visible = false
	hud.layer.visible = true


func _input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch:
		if ev.pressed:
			if state == "race" and fire_rect.has_point(ev.position):
				fire_req = true
				return
			touches[ev.index] = ev.position.x
			if state == "done" and t_state > 1.5:
				get_tree().reload_current_scene()
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
func _wpx(k: int) -> float:
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


var fxr = {}
var flash_rect: ColorRect


func _flash(c: Color, a: float) -> void:
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
	q2.material = mk.call(false)
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
	var bx = BoxMesh.new()
	bx.size = Vector3(0.14, 0.05, 0.12)
	var bm = StandardMaterial3D.new()
	bm.albedo_color = Color(0.13, 0.13, 0.15)
	bm.metallic = 0.8
	bm.roughness = 0.4
	bm.emission_enabled = true
	bm.emission = Color(1.0, 0.4, 0.1)
	bm.emission_energy_multiplier = 0.6
	bx.material = bm
	fxr.debris = bx
	var ring = QuadMesh.new()
	ring.size = Vector2(2, 2)
	ring.orientation = PlaneMesh.FACE_Y
	fxr.ring = ring
	fxr.ring_code = """
shader_type spatial;
render_mode unshaded,blend_add,cull_disabled,depth_draw_never,shadows_disabled;
uniform float u=0.;
void fragment(){float r=length(UV-.5)*2.;float w=smoothstep(.12,0.,abs(r-.85))*(1.-u);ALBEDO=vec3(1.,.7,.4)*w*3.;}"""


func _ramp(cols: Array, hdr := true) -> GradientTexture1D:
	var g = Gradient.new()
	g.offsets = PackedFloat32Array(cols.map(func(c): return c[0]))
	g.colors = PackedColorArray(cols.map(func(c): return c[1]))
	var t = GradientTexture1D.new()
	t.gradient = g
	t.use_hdr = hdr
	return t


func _curve(pts: Array) -> CurveTexture:
	var c = Curve.new()
	c.max_value = 4.0
	for p in pts:
		c.add_point(Vector2(p[0], p[1]))
	var t = CurveTexture.new()
	t.curve = c
	return t


func _burst(pos: Vector3, mesh: Mesh, amount: int, life: float, vmin: float, vmax: float, spread: float, grav: Vector3, damp: float, smin: float, smax: float, ramp: GradientTexture1D, scurve: CurveTexture, align := false, spin := false, rad := 0.25) -> void:
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
	p.emitting = true
	get_tree().create_timer(life + 0.6).timeout.connect(p.queue_free)


# Feuerball aus vielen wabernden Flammen: grell weiß-gelb → orange → dunkelrot, steigt etwas auf
func _fire_ball(pos: Vector3, k: float) -> void:
	_burst(pos, fxr.fire, int(55 * k), 1.1, 2.0 * k, 6.0 * k, 180.0, Vector3(0, 1.6, 0), 4.0, 1.4 * k, 2.6 * k,
		_ramp([[0.0, Color(12, 10, 7, 1)], [0.1, Color(9, 4.5, 1.2, 1)], [0.35, Color(4, 1.1, 0.15, 0.85)], [0.7, Color(1.0, 0.2, 0.04, 0.45)], [1.0, Color(0.1, 0.02, 0.01, 0)]]),
		_curve([[0.0, 0.5], [0.2, 1.4], [1.0, 2.2]]), false, false, 0.5 * k)


# Gravitationsbombe: schwarzes Loch saugt Licht und Funken an, schnappt dann mit einer Welle zurück
func _gbomb(z: float, lat: float) -> void:
	_fx_res()
	var f = T.frame(z)
	var pos: Vector3 = f.c + f.rr * lat + f.uu * 0.6
	var core = MeshInstance3D.new()
	var sm = SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	core.mesh = sm
	var cm = StandardMaterial3D.new()
	cm.albedo_color = Color(0, 0, 0)
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core.material_override = cm
	core.position = pos
	core.scale = Vector3.ONE * 0.05
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(core)
	var ring = MeshInstance3D.new()
	var tm = TorusMesh.new()
	tm.inner_radius = 0.9
	tm.outer_radius = 1.12
	tm.rings = 48
	ring.mesh = tm
	var rmt = StandardMaterial3D.new()
	rmt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmt.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	rmt.albedo_color = Color(1.6, 1.2, 3.0)
	ring.material_override = rmt
	ring.position = pos
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	# Funken werden ins Loch gezogen
	var p = GPUParticles3D.new()
	var m = ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	m.emission_sphere_radius = 4.5
	m.radial_accel_min = -45.0
	m.radial_accel_max = -30.0
	m.gravity = Vector3.ZERO
	m.particle_flag_align_y = true
	m.color_ramp = _ramp([[0.0, Color(0.6, 0.4, 2.5, 0)], [0.3, Color(1.5, 1.0, 4.0, 1)], [1.0, Color(3, 2.5, 5, 1)]])
	p.process_material = m
	p.draw_pass_1 = fxr.spark
	p.amount = 120
	p.lifetime = 0.55
	p.one_shot = true
	p.explosiveness = 0.85
	p.position = pos
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-8, -8, -8), Vector3(16, 16, 16))
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)
	var lt = OmniLight3D.new()
	lt.light_color = Color(0.65, 0.5, 1.0)
	lt.omni_range = 12.0
	lt.light_energy = 0.0
	lt.position = pos
	add_child(lt)
	fxs.append({"gb": true, "pos": pos, "core": core, "ring": ring, "l": lt, "t": 0.0, "f": f, "lat": lat, "snap": false})
	_snd("gbomb", 3.0, 1.0, pos)


func _glow_mat(c: Color, e: float) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _gb_update(e: Dictionary, dt: float) -> bool:
	e.t += dt
	var t: float = e.t
	var cr: MeshInstance3D = e.core
	var rg: MeshInstance3D = e.ring
	if t < 0.55:
		var u = t / 0.55
		cr.scale = Vector3.ONE * (0.1 + 0.9 * pow(u, 1.5))
		rg.scale = Vector3.ONE * (2.6 - 1.4 * u)
		e.l.light_energy = 6.0 * u
	elif not e.snap:
		e.snap = true
		cr.visible = false
		rg.visible = false
		_fx_res()
		var f = e.f
		# Rückstoß: Funken und Lichtblitz nach außen, Ring über die Fahrbahn
		_burst(e.pos, fxr.spark, 140, 1.0, 10.0, 22.0, 180.0, Vector3(0, -6, 0), 0.8, 0.8, 1.6,
			_ramp([[0.0, Color(5, 4, 9, 1)], [0.6, Color(1.6, 1.0, 4.0, 1)], [1.0, Color(0.4, 0.2, 1.0, 0)]]), null, true, false, 0.3)
		_burst(e.pos - f.uu * 0.4, fxr.debris, 26, 1.8, 5.0, 12.0, 60.0, Vector3(0, -15, 0), 0.2, 0.8, 2.4, null, null, false, true, 0.3)
		var ring = MeshInstance3D.new()
		ring.mesh = fxr.ring
		var rm = _shader_mat(fxr.ring_code.replace("vec3(1.,.7,.4)", "vec3(.7,.5,1.)"))
		ring.material_override = rm
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ring)
		e.sw = ring
		e.swm = rm
		e.l.light_energy = 9.0
		var d = (e.pos - cam.global_position).length()
		var near = clampf(1.0 - d / 40.0, 0.0, 1.0)
		shake = maxf(shake, 1.6 * near)
		_flash(Color(0.75, 0.6, 1.0), 0.22 * near)
	else:
		var u = clampf((t - 0.55) / 0.7, 0.0, 1.0)
		rg.visible = false
		e.l.light_energy = 9.0 * pow(1.0 - u, 2.0)
		var f = e.f
		var sc = 0.6 + 9.0 * pow(u, 0.5)
		e.sw.global_transform = Transform3D(Basis(f.rr * sc, f.uu, f.fw * sc), f.c + f.rr * e.lat + f.uu * 0.03)
		e.swm.set_shader_parameter("u", u)
		if u >= 1.0:
			for k in ["core", "ring", "l", "sw"]:
				e[k].queue_free()
			return true
	# Ring zeigt immer zur Kamera
	rg.look_at(cam.global_position, Vector3.UP)
	rg.rotate_object_local(Vector3(1, 0, 0), PI / 2.0)
	return false


func _explode(z: float, lat: float, big := false) -> void:
	_fx_res()
	var k = 2.2 if big else 1.5
	var f = T.frame(z)
	var pos: Vector3 = f.c + f.rr * lat + f.uu * 0.35
	# Nachexplosionen: zwei, drei kleinere Feuerbälle rundherum, kurz versetzt
	for j in range(3 if big else 2):
		var off = f.rr * randf_range(-1.2, 1.2) + f.uu * randf_range(0.2, 1.4) + f.fw * randf_range(-1.0, 1.5)
		get_tree().create_timer(0.08 + j * 0.11).timeout.connect(func(): _fire_ball(pos + off, k * 0.6))
	# Feuerball: grell weiß-gelb → orange → dunkelrot
	_fire_ball(pos, k)
	# Rauch: steigt langsam auf, wird größer
	_burst(pos + f.uu * 0.6, fxr.smoke, int(26 * k), 3.0, 0.6, 2.2 * k, 70.0, Vector3(0, 0.9, 0), 1.2, 1.2 * k, 2.2 * k,
		_ramp([[0.0, Color(0.1, 0.08, 0.08, 0)], [0.12, Color(0.12, 0.1, 0.1, 0.65)], [1.0, Color(0.05, 0.05, 0.06, 0)]], false),
		_curve([[0.0, 0.5], [1.0, 3.0]]), false, false, 0.4 * k)
	# Funkenregen
	_burst(pos, fxr.spark, int(110 * k), 1.3, 7.0 * k, 18.0 * k, 180.0, Vector3(0, -10, 0), 0.6, 0.7, 1.4,
		_ramp([[0.0, Color(9, 6, 2.5, 1)], [0.6, Color(4, 1.2, 0.2, 1)], [1.0, Color(1, 0.2, 0.05, 0)]]), null, true, false, 0.2)
	# Trümmer: Stücke der Fahrbahn fliegen weg
	_burst(pos - f.uu * 0.2, fxr.debris, int(30 * k), 2.0, 5.0 * k, 12.0 * k, 60.0, Vector3(0, -15, 0), 0.2, 0.8, 2.6, null, null, false, true, 0.3)
	# Druckwelle auf der Fahrbahn
	var ring = MeshInstance3D.new()
	ring.mesh = fxr.ring
	var rm = _shader_mat(fxr.ring_code)
	ring.material_override = rm
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.global_transform = Transform3D(Basis(f.rr, f.uu, f.fw), f.c + f.rr * lat + f.uu * 0.03)
	add_child(ring)
	# Lichtblitz
	var lt = OmniLight3D.new()
	lt.light_color = Color(1.0, 0.65, 0.3)
	lt.omni_range = 14.0 * k
	lt.light_energy = 28.0
	lt.position = pos + f.uu * 0.6
	add_child(lt)
	fxs.append({"ring": ring, "rm": rm, "l": lt, "t": 0.0, "big": big, "f": f, "lat": lat})
	_snd("boom", 4.0 if big else 2.0, randf_range(0.85, 1.0), pos)
	_snd("boom", 2.0, 0.55, pos)   # tiefer Wumms darunter
	# Kamera rüttelt, je näher, desto stärker
	var d = (pos - cam.global_position).length()
	var near = clampf(1.0 - d / 35.0, 0.0, 1.0)
	shake = maxf(shake, (2.0 if big else 1.3) * near)
	_flash(Color(1.0, 0.7, 0.4), (0.55 if big else 0.35) * near)


# Schaden: Schild schützt; leer = ausgeschieden; Meldung oben
func _dmg(o: Dictionary, a: float) -> void:
	if o.out or state != "race" or (o.idx == 0 and o.shield > 0.0):
		return
	o.en = maxf(0.0, o.en - a)
	var nm = NAMES[o.idx]
	if o.en <= 0.0:
		o.out = true
		_explode(o.z, o.lat, true)
		(o.node as Node3D).visible = false
		if (o.node as Node3D).has_meta("eng"):
			((o.node as Node3D).get_meta("eng") as AudioStreamPlayer3D).stop()
		_msg("ELIMINATED" if o.idx == 0 else nm.to_upper() + " ELIMINATED", Color(1, 0.35, 0.3) if o.idx == 0 else Color(1, 0.85, 0.3))
	elif o.idx == 0:
		_msg("−%d %% ENERGY" % int(round(a * 100.0)), Color(1, 0.48, 0.35))
	else:
		_msg("HIT · %s %d %%" % [nm, int(round(o.en * 100.0))], Color(1, 0.75, 0.5))


func _add_shot(from: Dictionary, at_player := false, homing := false) -> void:
	var cap = CapsuleMesh.new()
	cap.radius = 0.06
	cap.height = 0.5
	var mi = _glow_node(cap, Color(1.0, 0.6, 0.2), 8.0)
	var lt = OmniLight3D.new()
	lt.light_color = Color(1.0, 0.55, 0.2)
	lt.omni_range = 4.0
	lt.light_energy = 3.0
	mi.add_child(lt)
	var tg = null
	if homing:
		var bd = 220.0
		for o in ships:
			if o.idx != 0 and not o.out and o.z - from.z > 0.0 and o.z - from.z < bd:
				bd = o.z - from.z
				tg = o
	shots.append({"z": from.z + 1.0, "lat": from.lat, "t": 0.0, "pl": at_player, "hm": homing, "tg": tg, "dl": tan(from.psi) if not at_player else 0.0, "n": mi})
	_snd("rak", -2.0, 1.0, mi.position if at_player else null)


func _fire() -> void:
	var g: Dictionary = ships[0]
	var w: String = g.wpn
	g.wpn = ""
	match w:
		"rak":
			_add_shot(g)
		"lenk":
			_add_shot(g, false, true)
		"mine":
			for k in range(3):
				var sp = SphereMesh.new()
				sp.radius = 0.12
				sp.height = 0.24
				var mi = _glow_node(sp, Color(1, 0.15, 0.1), 6.0)
				var z = g.z - 1.0 - k * 0.9
				var lat = g.lat + (k - 1) * 0.35
				mi.position = T.world(z, lat, 0.12)
				mines.append({"z": z, "lat": lat, "t": 0.0, "n": mi})
			_snd("mine", -4.0)
		"schild":
			g.shield = 6.0
			_snd("phase", 2.0)
			_snd("shield", -6.0)
			gl_v = 1.0
		"turbo":
			g.turbo = 2.2
			g.boost = 2.0
			_snd("boost")
		"beben":
			_fx_res()
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
					m.color_ramp = _ramp([[0.0, Color(9, 5, 2, 1)], [1.0, Color(2, 0.4, 0.05, 0)]])
				else:
					m.angular_velocity_min = -600.0
					m.angular_velocity_max = 600.0
					m.particle_flag_rotate_y = true
					m.scale_min = 0.7
					m.scale_max = 2.2
				p.process_material = m
				p.draw_pass_1 = fxr.spark if kind == 0 else fxr.debris
				p.amount = 160 if kind == 0 else 60
				p.lifetime = 0.9
				p.local_coords = false
				p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				p.visibility_aabb = AABB(Vector3(-20, -10, -20), Vector3(40, 30, 40))
				crest.add_child(p)
			var lt = OmniLight3D.new()
			lt.light_color = Color(1.0, 0.45, 0.12)
			lt.omni_range = 10.0
			lt.light_energy = 8.0
			lt.position = Vector3(0, 1.0, 0)
			crest.add_child(lt)
			quake = {"z": g.z + 3.0, "age": 0.0, "hit": [], "n": crest, "l": lt}
			_snd("boom", 3.0, 0.6)
			_snd("boom", 0.0, 0.8)
			shake = maxf(shake, 1.5)
			_flash(Color(1.0, 0.5, 0.15), 0.45)
		"wand":
			var bx = BoxMesh.new()
			bx.size = Vector3(T.TW * 2.0, 1.4, 0.06)
			var mi = _glow_node(bx, Color(1.0, 0.5, 0.1), 3.0, 0.45)
			var z = g.z + 12.0
			var f = T.frame(z)
			mi.global_transform = Transform3D(Basis(f.rr, f.uu, f.fw), f.c + f.uu * 0.7)
			walls.append({"z": z, "age": 0.0, "hit": [], "n": mi})
			_snd("wallon")
		"auto":
			g.auto = 5.0
			_snd("shield")


func _weapons(dt: float, racing: bool) -> void:
	var g: Dictionary = ships[0]
	msg_t -= dt
	if msg_t <= 0.0:
		hud.msg.text = ""
	# Waffenfeld: jedes zweite Feld (alle 70 Einheiten)
	var zz = g.z
	var wk = int(floor((zz - 17.0) / 35.0))
	var wz = (zz - 17.0) / 35.0 - wk
	if racing and posmod(wk, 2) == 0 and wz < 0.05 and not g.air and absf(g.lat - _wpx(wk)) < 0.34 and wk != g.wpK and g.wpn == "":
		g.wpK = wk
		g.wpn = _pick_w()
		_snd("pick")
	if fire_req:
		fire_req = false
		if g.wpn != "" and racing:
			_fire()
	hud.fire.text = WN.get(g.wpn, "empty")
	hud.fire.modulate = Color(1, 1, 1, 1.0 if g.wpn != "" else 0.45)
	hud.fire_sb.border_color = Color(1.0, 0.6, 0.25, 0.9) if g.wpn != "" else Color(1, 1, 1, 0.3)
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
	# Neue Runde: 25 % Energie zurück
	for o in ships:
		var ln = int(floor((o.z - T.ZST) / T.LAP))
		if ln > o.enL and not o.out:
			o.enL = ln
			o.en = minf(1.0, o.en + 0.25)
	var spd = base_spd * 2.8
	# Geschosse
	for i in range(shots.size() - 1, -1, -1):
		var sh = shots[i]
		sh.t += dt
		sh.z += spd * dt
		if sh.pl:
			sh.lat += (g.lat - sh.lat) * minf(1.0, dt * 3.0)
		elif sh.hm:
			if sh.tg == null or sh.tg.out or sh.tg.z < sh.z - 1.5:
				sh.tg = null
				var bd = 200.0
				for o in ships:
					if o.idx != 0 and not o.out and o.z - sh.z > -1.0 and o.z - sh.z < bd:
						bd = o.z - sh.z
						sh.tg = o
			if sh.tg != null:
				sh.lat += (sh.tg.lat - sh.lat) * minf(1.0, dt * 5.0)
		else:
			sh.lat += sh.dl * spd * dt
		var hit = null
		for o in ships:
			if o.out or (sh.pl != (o.idx == 0)):
				continue
			if absf(sh.z - o.z) < 0.8 + spd * dt * 1.5 and absf(sh.lat - o.lat) < (0.4 if sh.pl else 0.6):
				hit = o
				break
		var dead = false
		if hit != null:
			if not (hit.idx == 0 and hit.shield > 0.0):
				hit.slow = 0.35
				hit.vpsi += randf_range(-0.25, 0.25)
			_dmg(hit, 0.3 if sh.pl else 0.35)
			_gbomb(sh.z, sh.lat)
			dead = true
		elif absf(sh.lat) > T.TW - 0.05 or sh.t > 6.0:
			_gbomb(sh.z, clampf(sh.lat, -T.TW, T.TW))
			dead = true
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
		(m.n as MeshInstance3D).visible = fmod(m.t, 0.5) < 0.35
		var boom = false
		for o in ships:
			if o.idx != 0 and not o.out and absf(o.z - m.z) < 0.5 + o.spd * dt * 1.3 and absf(o.lat - m.lat) < 0.38:
				o.slow = 0.35
				_dmg(o, 0.2)
				boom = true
		if boom or m.t > 40.0:
			if boom:
				_explode(m.z, m.lat)
			m.n.queue_free()
			mines.remove_at(i)
	# Wall: Gegner, die durchfliegen, werden 1 s gebremst und verlieren 10 %
	for i in range(walls.size() - 1, -1, -1):
		var w = walls[i]
		w.age += dt
		for o in ships:
			if o.idx != 0 and not o.out and not w.hit.has(o.idx) and o.z >= w.z and o.z - o.spd * dt * 1.5 < w.z + 0.01:
				w.hit.append(o.idx)
				o.slowT = 1.0
				_dmg(o, 0.1)
				_snd("zap", 0.0, 1.0, (o.node as Node3D).global_position)
		var mat: StandardMaterial3D = (w.n as MeshInstance3D).material_override
		mat.albedo_color.a = 0.45 * clampf(minf(w.age / 0.3, (5.3 - w.age) / 0.4), 0.0, 1.0)
		if w.age > 5.3:
			w.n.queue_free()
			walls.remove_at(i)
	# Beben: rollt nach vorn, wirft Gegner hoch
	if quake != null:
		quake.z += base_spd * 3.2 * dt
		quake.age += dt
		for o in ships:
			if o.idx != 0 and not o.out and not quake.hit.has(o.idx) and absf(o.z - quake.z) < 2.6:
				quake.hit.append(o.idx)
				_dmg(o, 0.2)
				if not o.out:
					o.air = true
					o.vy = 5.8
					o.h = maxf(o.h, 0.6)
					o.slow = 0.25
		var f = T.frame(quake.z)
		var qs = 1.3 * clampf(quake.age / 0.25, 0.0, 1.0) * clampf((16.0 - quake.age) / 1.5, 0.0, 1.0) * clampf((560.0 - (quake.z - g.z)) / 40.0, 0.0, 1.0)
		quake.n.global_transform = Transform3D(Basis(f.rr, f.uu, f.fw), f.c + f.uu * (qs * 1.6))
		quake.l.light_energy = 8.0 * qs
		mats.road.set_shader_parameter("qz", quake.z)
		mats.road.set_shader_parameter("qs", qs)
		shake = maxf(shake, 0.35 * clampf(1.0 - (quake.z - g.z) / 40.0, 0.0, 1.0))
		if quake.z - g.z > 560.0 or quake.age > 16.0:
			quake.n.queue_free()
			quake = null
			mats.road.set_shader_parameter("qs", 0.0)
	# Explosionen: Druckwelle wächst, Licht verlischt
	for i in range(fxs.size() - 1, -1, -1):
		var e = fxs[i]
		if e.get("gb", false):
			if _gb_update(e, dt):
				fxs.remove_at(i)
			continue
		e.t += dt
		var u = clampf(e.t / (0.7 if e.big else 0.5), 0.0, 1.0)
		var sc = (0.6 + (8.0 if e.big else 5.5) * pow(u, 0.5))
		var f = e.f
		e.ring.global_transform = Transform3D(Basis(f.rr * sc, f.uu, f.fw * sc), f.c + f.rr * e.lat + f.uu * 0.03)
		e.rm.set_shader_parameter("u", u)
		e.l.light_energy = 28.0 * pow(1.0 - u, 2.0)
		if u >= 1.0:
			e.ring.queue_free()
			e.l.queue_free()
			fxs.remove_at(i)
	# Schild: leuchtende Hülle in Schiffsform
	var shn: Node3D = (g.node as Node3D).get_meta("shield") if (g.node as Node3D).has_meta("shield") else null
	if g.shield > 0.0 and shn == null:
		shn = _shield_for(g.node)
	if shn != null:
		var on = g.shield > 0.0 and (g.shield > 1.2 or fmod(g.shield, 0.25) < 0.15)
		shn.visible = on
		var tt = Time.get_ticks_msec() / 1000.0
		var bp: Vector3 = (g.node as Node3D).get_meta("base_pos")
		var gh: Array = (g.node as Node3D).get_meta("ghosts")
		for j in range(gh.size()):
			var sg = 1.0 if j == 0 else -1.0
			gh[j].visible = on
			gh[j].position = bp + Vector3(sg * (0.06 + 0.05 * sin(tt * 37.0 + j)), 0.02 * sin(tt * 53.0), sg * 0.04 * sin(tt * 29.0))
		# das Schiff selbst zittert leicht, ab und zu ein Glitch
		var piv: Node3D = (g.node as Node3D).get_child(0)
		piv.position = Vector3(randf_range(-0.02, 0.02), randf_range(-0.01, 0.01), 0.0) if on else Vector3.ZERO
		if on and randf() < dt * 1.5:
			gl_v = maxf(gl_v, 0.5)


# ---------------------------------------------------------------- Fahrphysik (wie HTML-Version: Nase lenken, Flugrichtung folgt mit begrenzter Haftung)
func _phys(s: Dictionary, inp: float, is_p: bool, dt: float, racing: bool) -> void:
	var z: float = s.z
	s.u += (inp - s.u) * (1.0 - exp(-dt / (0.03 if is_p else 0.08)))
	var turn: float = T.kap(z) * s.spd
	s.psi = clampf(s.psi + (s.u * (YAW_P if is_p else YAW_AI) + turn) * dt, -0.9, 0.9)
	var grip = 0.8 if s.air else (9.5 if is_p else 7.0)
	s.vpsi = clampf(s.vpsi + ((s.psi - s.vpsi) * grip + turn) * dt, -0.9, 0.9)
	s.slow += (1.0 - s.slow) * (1.0 - exp(-dt / 1.4))
	s.boost *= exp(-dt / 1.4)
	if s.out:
		s.spd = 0.0
		return
	if s.slowT > 0.0:
		s.slowT -= dt
	s.spd = base_spd * s.sk * (1.0 + 0.6 * s.boost) * s.slow * (0.5 if s.slowT > 0.0 else 1.0) if racing or state == "done" else 0.0
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
	var k = int(floor(s.z / 35.0))
	var fz = s.z / 35.0 - k
	if fz < 0.08 and not s.air and absf(s.lat - T.bpx(k)) < 0.36 and k != s.padK and racing:
		s.padK = k
		s.boost = 1.0
		if is_p:
			_snd("boost", -3.0)


func _ai_inp(o: Dictionary, t: float) -> float:
	var zz: float = o.z
	var d2 = T.d2px(zz + 10.0)
	var tl = signf(d2) * minf(0.55, absf(d2) * 55.0) * T.TW / 1.6
	var pk = int(floor((zz + 5.0) / 35.0))
	if (zz + 5.0) / 35.0 - pk < 0.12:
		tl = T.bpx(pk)
	tl += 0.1 * sin(t / 1.1 + o.ai)
	var turn_n: float = T.kap(zz) * o.spd
	var want = clampf((tl - o.lat) * 0.5, -0.3, 0.3)
	return clampf((want - o.vpsi) * 1.5 + (want - o.psi) * 0.5 - turn_n / YAW_AI, -1.0, 1.0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if state == "menu":
			if ui.setp.visible:
				ui.setp.visible = false
				ui.main.visible = true
			else:
				get_tree().quit()
		else:
			get_tree().reload_current_scene()


func _process(delta: float) -> void:
	var dt = minf(delta, 0.05)
	t_state += dt
	ui.fps.text = "%d fps" % Engine.get_frames_per_second()
	var g: Dictionary = ships[0]
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
	var racing = state == "race"
	if state == "intro" and t_state > 1.2:
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
		race_t += dt if racing else 0.0
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
	if state == "done":
		steer = clampf(-g.lat * 0.6 - g.vpsi * 2.0, -1.0, 1.0)
	var n = maxi(1, int(ceil(dt / 0.0125)))
	var hdt = dt / n
	var tt = Time.get_ticks_msec() / 1000.0
	if g.auto > 0.0:
		steer = _ai_inp(g, tt)
		g.auto -= dt
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
		var inp = _ai_inp(o, tt)
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
		if absf(dz) < 1.4 and absf(o.lat - g.lat) < 0.4 and racing and not g.air and not o.air:
			var pu = signf(g.lat - o.lat) if g.lat != o.lat else 1.0
			g.lat += pu * 0.6 * dt * 6.0
			o.lat -= pu * 0.6 * dt * 6.0
		var fin = T.ZST + T.LAPS * T.LAP
		if o.z >= fin and o.fin == 0.0 and racing:
			o.fin = race_t
		# Gegner schießen ab und zu von hinten auf dich
		if racing and dz < 0.0 and dz > -25.0 and randf() < dt * 0.02:
			_add_shot(o, true)
	# Ziel
	var finish = T.ZST + T.LAPS * T.LAP
	var place = 1
	for i in range(1, ships.size()):
		if ships[i].z > g.z and not ships[i].out:
			place += 1
	_weapons(dt, racing)
	if racing and g.out:
		state = "done"
		t_state = 0.0
		hud.res.text = "ELIMINATED\n\nTap to return"
	elif racing and g.z >= finish:
		state = "done"
		t_state = 0.0
		g.fin = race_t
		_snd("win")
		hud.res.text = "%s  ·  %s\n\nTap to race again" % [["1st", "2nd", "3rd", "4th"][place - 1], _fmt(race_t)]
	var lap = clampi(int(floor((g.z - T.ZST) / T.LAP)) + 1, 1, T.LAPS)
	hud.top.text = "%d/4     Lap %d/%d     %s" % [place, lap, T.LAPS, _fmt(race_t)]
	# Rundenkopien mitwandern lassen
	var l0 = int(floor((g.z - 20.0) / T.LAP))
	for i in range(3):
		laps[i].position = Vector3(0, 0, (l0 - 1 + i) * T.LAP)
	_pose_all(dt)
	_camera(dt)
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
			if shot_n == 2 and p.size() > 2:
				_start()
				state = "race"
			if shot_n == 3 and p.size() > 1 and float(p[1]) > 0.0:
				ships[0].z = float(p[1])
				for i in range(1, 4):
					ships[i].z = float(p[1]) + 2.0 + i * 2.5
			if shot_n == 40 and p.size() > 3:
				if p[3] == "boom":
					_explode(ships[0].z + 6.0, 0.0, true)
				elif p[3].begins_with("gb"):
					_gbomb(ships[0].z + 9.0, 0.0)
					ships[0].boost = 1.5
				else:
					ships[0].wpn = p[3]
					fire_req = true
			if shot_n == ({"boom": 42, "beben": 47, "gb1": 47, "gb2": 53, "schild": 44}.get(p[3], 90) if p.size() > 3 else 90):
				get_viewport().get_texture().get_image().save_png(p[0])
				get_tree().quit()


func _fmt(t: float) -> String:
	return "%d:%05.2f" % [int(t / 60.0), fmod(t, 60.0)]


# Lage der Gleiter: Bahnpunkt + seitlich + Schweben, Nase um psi gedreht, in Kurven leicht geneigt
func _pose_all(dt: float) -> void:
	var tt = Time.get_ticks_msec() / 1000.0
	for i in range(ships.size()):
		var s: Dictionary = ships[i]
		var f = T.frame(s.z)
		var bob = 0.012 * sin(tt * 2.7 + s.ai)
		var pos: Vector3 = f.c + f.rr * s.lat + f.uu * (0.16 + s.h + bob)
		var dir: Vector3 = (f.fw * cos(s.psi) + f.rr * sin(s.psi)).normalized()
		s.roll += (s.u * 0.32 - s.roll) * (1.0 - exp(-dt / 0.15))
		var up: Vector3 = f.uu.rotated(dir, s.roll)
		var x = up.cross(dir).normalized()
		up = dir.cross(x).normalized()
		var nd: Node3D = s.node
		nd.global_transform = Transform3D(Basis(x, up, dir), pos)
		var jets: Array = nd.get_meta("jets")
		for j in jets:
			j.visible = s.boost > 0.25
		var lt: OmniLight3D = nd.get_meta("light")
		lt.light_energy = 1.4 + 3.0 * s.boost
		lt.light_color = Color(0.6, 0.4, 1.0).lerp(Color(0.3, 0.8, 1.0), clampf(s.boost, 0.0, 1.0))


# Kamera: hinter dem Gleiter, folgt der Nase gedämpft, bleibt beim Boost kurz zurück
func _camera(dt: float) -> void:
	var g: Dictionary = ships[0]
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
		var u = clampf(t_state / 1.2, 0.0, 1.0)
		ro = ro.lerp(S0 + fc * 4.0 + uc * 2.5 + f.rr * 2.0, 1.0 - u)
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
