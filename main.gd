# AntiGrav 3D – erste Godot-Version: Neon Night, ein Gleitermodell, drei Gegner, echte Beleuchtung,
# Bildschirm-Spiegelungen, Schatten, Glühen. Alles wird beim Start im Code aufgebaut.
extends Node3D

const T = preload("res://track.gd")
const SHIP_SCENE = preload("res://ships/qirex.glb")

# Lenkung wie in der HTML-Version (von John abgestimmt)
const RAMP = 0.56
const START = 0.55
const SHAPE = 2.3
const YAW_P = 1.4
const YAW_AI = 1.5
const BASE = 5.5
const NAMES = ["You", "Vega", "Kato", "Mira"]

var laps: Array[Node3D] = []
var lap_mesh: ArrayMesh
var bld_mm: MultiMesh
var cam: Camera3D
var ships: Array = []  # Zustand je Gleiter (Dictionary), [0] = du
var state = "intro"
var t_state = 0.0
var race_t = 0.0
var steer_btn = 0
var btn_t = 0.0
var touches = {}
var hud = {}
var cam_psi = 0.0
var cam_d = 0.0


func _ready() -> void:
	_env()
	_build_track()
	_build_city()
	_spawn_ships()
	cam = Camera3D.new()
	cam.fov = 52.0
	cam.near = 0.08
	cam.far = 400.0
	add_child(cam)
	_hud()


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
	env.glow_intensity = 0.9
	env.glow_strength = 1.1
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
	var we = WorldEnvironment.new()
	we.environment = env
	add_child(we)
	# Mondlicht mit echten Schatten
	var moon = DirectionalLight3D.new()
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
		_strip("pad", zc, zc + 2.8, bx - 0.36, bx + 0.36, 0.008, 0.008)
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
	mats["road"] = _road_mat()
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
	mats["start"] = _shader_mat("""
shader_type spatial;
render_mode unshaded,cull_disabled;
void fragment(){vec2 q=floor(vec2(UV.x*12.,UV.y*2.));ALBEDO=vec3(mod(q.x+q.y,2.)*1.2+.02);}""")
	lap_mesh = ArrayMesh.new()
	for key in sts.keys():
		var st: SurfaceTool = sts[key]
		if key == "pad" or key == "start":
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
		add_child(n)
		laps.append(n)


var mats = {}
var lights = []


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
		var span = 5.6 if key == "pad" else 2.0
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
func _ship_node() -> Node3D:
	var root = Node3D.new()
	var m: Node3D = SHIP_SCENE.instantiate()
	root.add_child(m)
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
	for i in range(4):
		var s = {"z": starts[i][0], "lat": starts[i][1], "psi": 0.0, "vpsi": 0.0, "u": 0.0, "spd": 0.0, "boost": 0.0, "slow": 1.0,
			"h": 0.0, "vy": 0.0, "air": false, "padK": -1, "hitT": -9.0, "sk": 0.95 + (i - 1) * 0.03 if i > 0 else 1.0, "sk0": 0.0,
			"ai": randf() * 100.0, "node": _ship_node(), "fin": 0.0, "roll": 0.0}
		s.sk0 = s.sk
		ships.append(s)


# ---------------------------------------------------------------- Anzeige: Platz, Runde, Zeit, Lenkknöpfe
func _hud() -> void:
	var cl = CanvasLayer.new()
	add_child(cl)
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


func _input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch:
		if ev.pressed:
			touches[ev.index] = ev.position.x
			if state == "done" and t_state > 1.5:
				get_tree().reload_current_scene()
		else:
			touches.erase(ev.index)
	elif ev is InputEventScreenDrag:
		touches[ev.index] = ev.position.x


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
	s.spd = BASE * s.sk * (1.0 + 0.6 * s.boost) * s.slow if racing or state == "done" else 0.0
	var fwd: float = s.spd * cos(s.vpsi)
	s.z += fwd * dt
	s.lat += s.spd * sin(s.vpsi) * dt
	# Sprung: über der Lücke fliegt er, Schwerkraft holt ihn zurück (Weite begrenzt)
	if not s.air and T.gap(s.z):
		s.air = true
		s.h = 0.45
		var tf = 8.5 / maxf(1.0, fwd)
		s.vy = (2.0 * tf * tf - s.h) / tf
	if s.air:
		s.vy -= 4.0 * dt
		s.h += s.vy * dt
		if s.h <= 0.0 and not T.gap(s.z):
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
	# Boost-Feld
	var k = int(floor(s.z / 35.0))
	var fz = s.z / 35.0 - k
	if fz < 0.08 and not s.air and absf(s.lat - T.bpx(k)) < 0.36 and k != s.padK and racing:
		s.padK = k
		s.boost = 1.0


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


func _process(delta: float) -> void:
	var dt = minf(delta, 0.05)
	t_state += dt
	var g: Dictionary = ships[0]
	var racing = state == "race"
	if state == "intro" and t_state > 1.2:
		state = "count"
		t_state = 0.0
	elif state == "count":
		var c = 3 - int(floor(t_state))
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
	for k in range(n):
		_phys(g, steer, true, hdt, racing)
	var tt = Time.get_ticks_msec() / 1000.0
	for i in range(1, ships.size()):
		var o: Dictionary = ships[i]
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
		# Rempeln
		if absf(dz) < 1.4 and absf(o.lat - g.lat) < 0.4 and racing and not g.air and not o.air:
			var pu = signf(g.lat - o.lat) if g.lat != o.lat else 1.0
			g.lat += pu * 0.6 * dt * 6.0
			o.lat -= pu * 0.6 * dt * 6.0
		var fin = T.ZST + T.LAPS * T.LAP
		if o.z >= fin and o.fin == 0.0 and racing:
			o.fin = race_t
	# Ziel
	var finish = T.ZST + T.LAPS * T.LAP
	var place = 1
	for i in range(1, ships.size()):
		if ships[i].z > g.z:
			place += 1
	if racing and g.z >= finish:
		state = "done"
		t_state = 0.0
		g.fin = race_t
		hud.res.text = "%s  ·  %s\n\nTap to race again" % [["1st", "2nd", "3rd", "4th"][place - 1], _fmt(race_t)]
	var lap = clampi(int(floor((g.z - T.ZST) / T.LAP)) + 1, 1, T.LAPS)
	hud.top.text = "%d/4     Lap %d/%d     %s" % [place, lap, T.LAPS, _fmt(race_t)]
	# Rundenkopien mitwandern lassen
	var l0 = int(floor((g.z - 20.0) / T.LAP))
	for i in range(3):
		laps[i].position = Vector3(0, 0, (l0 - 1 + i) * T.LAP)
	_pose_all(dt)
	_camera(dt)
	_shot()


# Nur zum Testen am Rechner: godot -- --shot=Pfad,z  → setzt dich an die Stelle z und speichert ein Bild
var shot_n = 0
func _shot() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			var p = a.substr(7).split(",")
			shot_n += 1
			if shot_n == 3 and p.size() > 1:
				ships[0].z = float(p[1])
				for i in range(1, 4):
					ships[i].z = float(p[1]) + 2.0 + i * 2.5
			if shot_n == 90:
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
	cam.global_position = ro
	cam.look_at(ta, uc)
	cam.fov = 52.0 * (1.0 + 0.12 * minf(1.5, g.boost))
