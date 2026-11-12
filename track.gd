# Strecke „Neon Night“ – dieselbe Mathematik wie in der HTML-Version (eine Runde = 700 Einheiten entlang z).
# Achsen: y oben, z vorwärts. „lat“ ist der seitliche Abstand zur Mitte, positiv = rechts auf dem Bildschirm.
extends RefCounted

const LAP := 700.0
const ZST := 20.0
const LAPS := 3
const TW := 2.4  # halbe Fahrbahnbreite
const W := 0.0089759790  # 2π / 700
# Neon Night wie im alten Spiel: wenige lange, runde Kurven, sanfte Hügel
const SEG := [[80.0, 120.0, 18.0], [240.0, 140.0, -26.0], [420.0, 110.0, 14.0], [560.0, 110.0, -6.0]]
const HILL := [[2.4, 2.0, 0.0], [0.8, 5.0, 1.0]]
const RINGS := [90, 96, 102, 108, 114, 290, 296, 302, 308, 314, 440, 446, 452, 458, 464, 625, 631, 637, 643, 649]
const TUN := [[160.0, 245.0], [510.0, 595.0]]
# Korkenzieher-Röhre (nur Neon Night): die Fahrbahn dreht sich einmal ganz um die Fahrtrichtung – man fährt über Wand und Decke
const TWZ := [326.0, 390.0]
# Wasser-Abschnitt (nur Extreme): die Fahrbahn endet, man gleitet über einen See
const WAT := [436.0, 500.0]
# Dschungel: turbotauglich – weite, fließende Kurven (Summe weniger Sinuswellen, keine hektischen Wechsel),
# langer sanfter Anstieg (120–400), steile lange Abfahrt (440–520) und direkt danach die lange Steilkurve (500–690)
static var J := false
static var X := false   # Extreme-Strecke: Neon Night mit Korkenzieher-Röhre und Wasser-Abschnitt
static var S := false   # Lenk-Teststrecke: ganz gerade und flach
const SEG_J := []
const CRV_J := [[1.0, 22.0, -3.9225], [2.0, 10.0, -9.4158], [3.0, 4.5, -14.9091], [4.0, 2.0, -20.4024]]   # [Welle, Weite, Phase] – große Kurve um z 632
const DROP := [[80.0, 250.0, 38.0], [420.0, 160.0, -38.0]]   # Anstieg, dann die lange steile Abfahrt
const TUN_J := [[605.0, 655.0]]   # Erdtunnel mitten in der Steilkurve


static func tuns() -> Array:
	if S:
		return []
	return TUN_J if J else TUN


static func seg() -> Array:
	return SEG_J if J else SEG


static func lz(z: float) -> float:
	return fposmod(z - 20.0, 700.0) + 20.0


static func s5(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	return u * u * u * (u * (u * 6.0 - 15.0) + 10.0)


static func s1(u: float) -> float:
	if u < 0.0 or u > 1.0:
		return 0.0
	return 30.0 * u * u * (u - 1.0) * (u - 1.0)


static func s2(u: float) -> float:
	if u < 0.0 or u > 1.0:
		return 0.0
	return 60.0 * u * (u - 1.0) * (2.0 * u - 1.0)


static func px(z: float) -> float:
	if S:
		return 0.0
	var l := lz(z)
	var r := 0.0
	if J:
		for c in CRV_J:
			r += c[1] * sin(c[0] * W * (l - 20.0) + c[2])
	for s in seg():
		r += s[2] * s5((l - s[0]) / s[1])
	return r


static func dpx(z: float) -> float:
	if S:
		return 0.0
	var l := lz(z)
	var r := 0.0
	if J:
		for c in CRV_J:
			r += c[1] * c[0] * W * cos(c[0] * W * (l - 20.0) + c[2])
	for s in seg():
		r += s[2] / s[1] * s1((l - s[0]) / s[1])
	return r


static func d2px(z: float) -> float:
	if S:
		return 0.0
	var l := lz(z)
	var r := 0.0
	if J:
		for c in CRV_J:
			r -= c[1] * c[0] * c[0] * W * W * sin(c[0] * W * (l - 20.0) + c[2])
	for s in seg():
		r += s[2] / (s[1] * s[1]) * s2((l - s[0]) / s[1])
	return r


static func py(z: float) -> float:
	if S:
		return 0.0
	var l := z - 20.0
	var r := 0.0
	for h in HILL:
		r += h[0] * sin(l * h[1] * W + h[2])
	if J:
		var lj := lz(z)
		for d in DROP:
			r += d[2] * s5((lj - d[0]) / d[1])
	return r


static func dpy(z: float) -> float:
	if S:
		return 0.0
	var l := z - 20.0
	var r := 0.0
	for h in HILL:
		r += h[0] * h[1] * W * cos(l * h[1] * W + h[2])
	if J:
		var lj := lz(z)
		for d in DROP:
			r += d[2] / d[1] * s1((lj - d[0]) / d[1])
	return r


# Sprungschanze vor der Lücke bei 410–417
static func rmp(z: float) -> float:
	if S:
		return 0.0
	z = lz(z)
	var jn := ceilf((z - 60.0) / 350.0) * 350.0 + 60.0
	if jn < 300.0 or jn > 700.0:
		return 0.0
	var u := clampf((z - (jn - 10.0)) / 10.0, 0.0, 1.0)
	return 0.45 * u * u


static func gap(z: float) -> bool:
	if S:
		return false
	z = lz(z)
	var j := floorf((z - 60.0) / 350.0) * 350.0 + 60.0
	if j < 300.0:
		return false
	return z > j and z < j + 7.0


static func in_tun(zl: float, m: float = 0.0) -> bool:
	for t in tuns():
		if zl >= t[0] - m and zl <= t[1] + m:
			return true
	return false


# Steilkurve: die Außenseite hebt sich
static func bank(z: float) -> float:
	if J:
		# Dschungel: normale Kurven mäßig geneigt, die große Kurve bis etwa 60° – man hängt an der Wand
		var d := d2px(z)
		var b := d * 70.0 + signf(d) * 0.65 * clampf((absf(d) - 0.006) / 0.0035, 0.0, 1.0)
		return clampf(b, -1.05, 1.05)
	return clampf(d2px(z) * 45.0, -0.42, 0.42) + twist(z)


# Drehung der Fahrbahn in der Röhre (0 … 2π, weich ein- und ausgeblendet)
static func twist(z: float) -> float:
	if J or S or not X:
		return 0.0
	var l := lz(z)
	if l <= TWZ[0] or l >= TWZ[1]:
		return 0.0
	return TAU * s5((l - TWZ[0]) / (TWZ[1] - TWZ[0]))


static func in_twist(zl: float, m: float = 0.0) -> bool:
	return X and not J and not S and zl >= TWZ[0] - m and zl <= TWZ[1] + m


static func in_water(zl: float, m: float = 0.0) -> bool:
	return X and not J and not S and zl >= WAT[0] - m and zl <= WAT[1] + m


# Abschnitte von a bis b ohne den Wasser-Abschnitt (für Fahrbahn, Bande und alles, was über dem See fehlt)
static func dry(a: float, b: float) -> Array:
	if not X or J or S or b <= WAT[0] or a >= WAT[1]:
		return [[a, b]]
	var r = []
	if a < WAT[0]:
		r.append([a, WAT[0]])
	if b > WAT[1]:
		r.append([WAT[1], b])
	return r


# Krümmung für die Fahrphysik (Kurve läuft dem Gleiter davon, wenn man nicht lenkt)
static func kap(z: float) -> float:
	var d := dpx(z)
	return d2px(z) / pow(1.0 + d * d, 1.5)


# Rahmen an der Stelle z: Mitte, vorwärts, rechts, oben (mit Steilkurve)
static func frame(z: float) -> Dictionary:
	var c := Vector3(px(z), py(z) + rmp(z), z)
	var fw := Vector3(dpx(z), dpy(z), 1.0).normalized()
	var r0 := fw.cross(Vector3.UP).normalized()
	var u0 := r0.cross(fw)
	var b := bank(z)
	var rr := r0 * cos(b) + u0 * sin(b)
	var uu := u0 * cos(b) - r0 * sin(b)
	return {"c": c, "fw": fw, "rr": rr, "uu": uu}


static func world(z: float, lat: float, h: float) -> Vector3:
	var f := frame(z)
	return f.c + f.rr * lat + f.uu * h


# Boost-Feld k: liegt auf der Kurvenaußenseite
static func bpx(k: int) -> float:
	return signf(d2px(k * 35.0 + 6.0)) * 0.5 * TW / 1.6
