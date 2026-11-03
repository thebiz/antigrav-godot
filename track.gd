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
# Dschungel: stärker gewunden, eine krasse Abfahrt (470–512) und danach eine lange Steilkurve (530–700);
# die Höhe holt die Strecke vorher mit einem langen, sanften Anstieg (150–350) wieder herein
static var J := false
const SEG_J := [[80.0, 120.0, 44.0], [240.0, 140.0, -26.0], [420.0, 90.0, 22.0], [530.0, 170.0, -40.0]]
const DROP := [[150.0, 200.0, 12.0], [470.0, 42.0, -12.0]]


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
	var l := lz(z)
	var r := 0.0
	for s in seg():
		r += s[2] * s5((l - s[0]) / s[1])
	return r


static func dpx(z: float) -> float:
	var l := lz(z)
	var r := 0.0
	for s in seg():
		r += s[2] / s[1] * s1((l - s[0]) / s[1])
	return r


static func d2px(z: float) -> float:
	var l := lz(z)
	var r := 0.0
	for s in seg():
		r += s[2] / (s[1] * s[1]) * s2((l - s[0]) / s[1])
	return r


static func py(z: float) -> float:
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
	z = lz(z)
	var jn := ceilf((z - 60.0) / 350.0) * 350.0 + 60.0
	if jn < 300.0 or jn > 700.0:
		return 0.0
	var u := clampf((z - (jn - 10.0)) / 10.0, 0.0, 1.0)
	return 0.45 * u * u


static func gap(z: float) -> bool:
	z = lz(z)
	var j := floorf((z - 60.0) / 350.0) * 350.0 + 60.0
	if j < 300.0:
		return false
	return z > j and z < j + 7.0


static func in_tun(zl: float, m: float = 0.0) -> bool:
	for t in TUN:
		if zl >= t[0] - m and zl <= t[1] + m:
			return true
	return false


# Steilkurve: die Außenseite hebt sich
static func bank(z: float) -> float:
	if J:
		return clampf(d2px(z) * 70.0, -0.55, 0.55)   # Dschungel: steilere Kurven
	return clampf(d2px(z) * 45.0, -0.42, 0.42)


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
