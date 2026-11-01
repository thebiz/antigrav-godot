// VoxDSP – Stimmen-Bearbeitung für den AntiGrav-Stimmen-Baukasten.
// Reines JavaScript ohne Web-Audio-Knoten: liefert im Browser und in Node exakt dasselbe Ergebnis.
(function (G) {
	"use strict";
	var TAU = Math.PI * 2;
	var SR = 44100;

	function rng(seed) {
		return function () {
			seed |= 0; seed = seed + 0x6D2B79F5 | 0;
			var t = Math.imul(seed ^ seed >>> 15, 1 | seed);
			t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
			return ((t ^ t >>> 14) >>> 0) / 4294967296;
		};
	}

	// Lesen mit Schrittweite ratio (ratio > 1: kürzer und höher)
	function resample(x, ratio) {
		var n = Math.max(1, Math.floor(x.length / ratio));
		var y = new Float32Array(n);
		for (var i = 0; i < n; i++) {
			var p = i * ratio, j = Math.floor(p), f = p - j;
			var a = x[j] || 0, b = x[j + 1] || 0;
			y[i] = a + (b - a) * f;
		}
		return y;
	}

	// Körnige Zeit- und Tonhöhenänderung (Overlap-Add mit Hann-Fenstern)
	function granular(x, timeRatio, pitchRatio, grainMs) {
		var N = Math.max(64, Math.round(SR * grainMs / 1000));
		var hop = N >> 2;
		var outLen = Math.max(1, Math.round(x.length * timeRatio));
		var y = new Float32Array(outLen + N), w = new Float32Array(outLen + N);
		var win = new Float32Array(N);
		for (var i = 0; i < N; i++) win[i] = 0.5 - 0.5 * Math.cos(TAU * i / (N - 1));
		var L = x.length;
		for (var o = 0; o < outLen; o += hop) {
			var s = (o + N / 2) / timeRatio - pitchRatio * N / 2;
			for (var k = 0; k < N; k++) {
				var p = s + k * pitchRatio;
				if (p < 0 || p >= L - 1) { w[o + k] += win[k]; continue; }
				var j = Math.floor(p), f = p - j;
				y[o + k] += (x[j] + (x[j + 1] - x[j]) * f) * win[k];
				w[o + k] += win[k];
			}
		}
		var out = new Float32Array(outLen);
		for (var n = 0; n < outLen; n++) out[n] = w[n] > 1e-3 ? y[n] / w[n] : 0;
		return out;
	}

	// RBJ-Biquad
	function biquad(x, type, f, q, gainDb) {
		var A = Math.pow(10, (gainDb || 0) / 40);
		var w0 = TAU * Math.min(f, SR * 0.49) / SR, cs = Math.cos(w0), sn = Math.sin(w0);
		var al = sn / (2 * (q || 0.707));
		var b0, b1, b2, a0, a1, a2;
		if (type === "lp") { b0 = (1 - cs) / 2; b1 = 1 - cs; b2 = b0; a0 = 1 + al; a1 = -2 * cs; a2 = 1 - al; }
		else if (type === "hp") { b0 = (1 + cs) / 2; b1 = -(1 + cs); b2 = b0; a0 = 1 + al; a1 = -2 * cs; a2 = 1 - al; }
		else if (type === "bp") { b0 = al; b1 = 0; b2 = -al; a0 = 1 + al; a1 = -2 * cs; a2 = 1 - al; }
		else if (type === "peak") { b0 = 1 + al * A; b1 = -2 * cs; b2 = 1 - al * A; a0 = 1 + al / A; a1 = -2 * cs; a2 = 1 - al / A; }
		else if (type === "ls") {
			var sa = 2 * Math.sqrt(A) * al;
			b0 = A * ((A + 1) - (A - 1) * cs + sa); b1 = 2 * A * ((A - 1) - (A + 1) * cs); b2 = A * ((A + 1) - (A - 1) * cs - sa);
			a0 = (A + 1) + (A - 1) * cs + sa; a1 = -2 * ((A - 1) + (A + 1) * cs); a2 = (A + 1) + (A - 1) * cs - sa;
		} else { // hs
			var sb = 2 * Math.sqrt(A) * al;
			b0 = A * ((A + 1) + (A - 1) * cs + sb); b1 = -2 * A * ((A - 1) + (A + 1) * cs); b2 = A * ((A + 1) + (A - 1) * cs - sb);
			a0 = (A + 1) - (A - 1) * cs + sb; a1 = 2 * ((A - 1) - (A + 1) * cs); a2 = (A + 1) - (A - 1) * cs - sb;
		}
		b0 /= a0; b1 /= a0; b2 /= a0; a1 /= a0; a2 /= a0;
		var y = new Float32Array(x.length), x1 = 0, x2 = 0, y1 = 0, y2 = 0;
		for (var i = 0; i < x.length; i++) {
			var v = b0 * x[i] + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
			x2 = x1; x1 = x[i]; y2 = y1; y1 = v; y[i] = v;
		}
		return y;
	}

	function envelope(x, hz) {
		var a = 1 - Math.exp(-TAU * hz / SR), e = 0, y = new Float32Array(x.length);
		for (var i = 0; i < x.length; i++) { e += (Math.abs(x[i]) - e) * a; y[i] = e; }
		return y;
	}

	function mixInto(y, src, g, offset) {
		offset = offset || 0;
		for (var i = 0; i < src.length && i + offset < y.length; i++) y[i + offset] += src[i] * g;
	}

	// Freeverb-artiger Hall: parallele Kammfilter + Allpässe
	function reverb(x, size, damp) {
		var combs = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617];
		var aps = [556, 441, 341, 225];
		var fb = 0.7 + 0.28 * size, out = new Float32Array(x.length);
		for (var c = 0; c < combs.length; c++) {
			var d = Math.round(combs[c] * (0.6 + 0.8 * size)), buf = new Float32Array(d), idx = 0, lp = 0;
			for (var i = 0; i < x.length; i++) {
				var o = buf[idx];
				lp = o * (1 - damp) + lp * damp;
				buf[idx] = x[i] * 0.015 + lp * fb;
				out[i] += o;
				idx = (idx + 1) % d;
			}
		}
		for (var a = 0; a < aps.length; a++) {
			var da = aps[a], ba = new Float32Array(da), ia = 0;
			for (var n = 0; n < out.length; n++) {
				var bo = ba[ia], v = -out[n] + bo;
				ba[ia] = out[n] + bo * 0.5;
				out[n] = v;
				ia = (ia + 1) % da;
			}
		}
		return out;
	}

	function peak(x) { var m = 0; for (var i = 0; i < x.length; i++) { var v = Math.abs(x[i]); if (v > m) m = v; } return m || 1; }

	var DEFAULTS = {
		pitch: 0, formant: 0, speed: 1, sub: 0, octup: 0, chorus: 0, whisper: 0,
		ring: 0, ringf: 60, growl: 0, growlf: 30, metal: 0, metald: 3, metalfb: 0.5,
		drive: 0, bits: 16, crush: 1,
		bass: 0, mud: 0, presence: 0, air: 0, lowcut: 40, highcut: 16000, radio: 0,
		echo: 0, echot: 120, echofb: 0.3, verb: 0, verbsize: 0.5, comp: 0.4, gain: 0
	};

	// src: Float32Array (Mono), srcRate: Abtastrate der Quelle, p: Einstellungen → Float32Array bei 44,1 kHz
	function render(src, srcRate, p) {
		var q = {};
		for (var k in DEFAULTS) q[k] = (p && p[k] !== undefined) ? +p[k] : DEFAULTS[k];
		var rand = rng(12345);
		var x = resample(src, srcRate / SR);
		// Stimmgröße (Formant): erst alles verschieben, dann Tonhöhe und Länge zurückholen
		var rf = Math.pow(2, q.formant / 12), rp = Math.pow(2, q.pitch / 12), sp = Math.max(0.3, q.speed);
		var xr = rf === 1 ? x : resample(x, rf);
		var T = rf / sp;
		var main = granular(xr, T, rp / rf, 42);
		var tail = Math.round(SR * Math.min(3, 0.15 + q.echo * q.echot / 1000 * 4 + q.verb * (0.6 + 1.6 * q.verbsize)));
		var y = new Float32Array(main.length + tail);
		mixInto(y, main, 1);
		if (q.sub > 0) mixInto(y, biquad(granular(xr, T, rp / rf / 2, 60), "lp", 380, 0.7), q.sub * 1.2);
		if (q.octup > 0) mixInto(y, granular(xr, T, rp / rf * 2, 30), q.octup * 0.8);
		if (q.chorus > 0) {
			mixInto(y, granular(xr, T, rp / rf * Math.pow(2, 0.18 / 12), 42), q.chorus * 0.5, Math.round(SR * 0.013));
			mixInto(y, granular(xr, T, rp / rf * Math.pow(2, -0.22 / 12), 42), q.chorus * 0.5, Math.round(SR * 0.021));
		}
		var n = y.length, i;
		// Hauchen/Flüstern: Atemgeräusch, das den Klang der Stimme trägt (Vocoder: Rauschen in 20 Bändern,
		// jedes Band so laut wie die Stimme in diesem Band) – so bleibt die Stimme verständlich und wird nur hauchig
		if (q.whisper > 0) {
			var nz = new Float32Array(n), br = new Float32Array(n), NB = 20, wf0 = 160, wf1 = 8000;
			for (i = 0; i < n; i++) nz[i] = rand() * 2 - 1;
			for (var b = 0; b < NB; b++) {
				var fc = wf0 * Math.pow(wf1 / wf0, (b + 0.5) / NB);
				var bs = biquad(biquad(y, "bp", fc, 2.6), "bp", fc, 2.6);
				var be = envelope(bs, 28);
				var bn = biquad(biquad(nz, "bp", fc, 2.6), "bp", fc, 2.6);
				var tilt = Math.pow(fc / 1000, 0.3);   // Atem ist heller als die Stimme
				for (i = 0; i < n; i++) br[i] += bn[i] * be[i] * tilt;
			}
			br = biquad(biquad(br, "hp", 300, 0.7), "lp", 8500, 0.7);
			var pbw = peak(br), pyw = peak(y), ww = q.whisper;
			var wet = Math.min(1, ww * 1.2) * 0.95, dry = 1 - Math.min(0.9, ww * 0.9);
			for (i = 0; i < n; i++) y[i] = y[i] * dry + br[i] / pbw * pyw * wet;
		}
		// Roboter: Ringmodulation
		if (q.ring > 0) for (i = 0; i < n; i++) y[i] = y[i] * (1 - q.ring) + y[i] * Math.sin(TAU * q.ringf * i / SR) * q.ring;
		// Knurren: schnelles Pumpen der Lautstärke
		if (q.growl > 0) for (i = 0; i < n; i++) y[i] *= 1 + q.growl * Math.sin(TAU * q.growlf * i / SR);
		// Metall: kurzer Kammfilter mit Rückkopplung
		if (q.metal > 0) {
			var d = Math.max(1, Math.round(SR * q.metald / 1000)), z = new Float32Array(n), fbk = Math.min(0.92, q.metalfb);
			for (i = 0; i < n; i++) z[i] = y[i] + (i >= d ? z[i - d] * fbk : 0);
			var pz = peak(z), py = peak(y);
			for (i = 0; i < n; i++) y[i] = y[i] * (1 - q.metal) + z[i] / pz * py * q.metal;
		}
		// Verzerrung
		if (q.drive > 0) {
			var dr = 1 + q.drive * 9, nd = Math.tanh(dr), py2 = peak(y);
			for (i = 0; i < n; i++) y[i] = Math.tanh(y[i] / py2 * dr) / nd * py2;
		}
		// Digital: weniger Bits, grobere Abtastung
		if (q.bits < 16 || q.crush > 1) {
			var lv = Math.pow(2, Math.max(2, q.bits) - 1), step = Math.max(1, Math.round(q.crush)), hold = 0, py3 = peak(y);
			for (i = 0; i < n; i++) {
				if (i % step === 0) hold = Math.round(y[i] / py3 * lv) / lv * py3;
				y[i] = hold;
			}
		}
		// Klangfarbe
		if (q.bass) y = biquad(y, "ls", 140, 0.7, q.bass);
		if (q.mud) y = biquad(y, "peak", 380, 1.0, q.mud);
		if (q.presence) y = biquad(y, "peak", 3300, 0.9, q.presence);
		if (q.air) y = biquad(y, "hs", 8500, 0.7, q.air);
		if (q.lowcut > 25) y = biquad(y, "hp", q.lowcut, 0.7);
		if (q.highcut < 15500) y = biquad(y, "lp", q.highcut, 0.7);
		// Funk: Telefon-Band, etwas Rauschen und Biss
		if (q.radio > 0) {
			var r = biquad(biquad(biquad(y, "hp", 420, 0.9), "lp", 2900, 0.9), "peak", 1700, 1.1, 5), pr = peak(r);
			var py5 = peak(y), er = envelope(y, 14), per = peak(er);
			for (i = 0; i < n; i++) {
				// Rauschen nur, solange gesprochen wird (wie ein offener Funkkanal), keine dauerhafte Störung
				var v = Math.tanh(r[i] / pr * 2.2) * 0.8 + (rand() * 2 - 1) * 0.035 * Math.min(1, er[i] / per * 3);
				y[i] = y[i] * (1 - q.radio) + v * py5 * q.radio;
			}
		}
		// Echo
		if (q.echo > 0) {
			var de = Math.max(1, Math.round(SR * q.echot / 1000)), eb = new Float32Array(n), efb = Math.min(0.85, q.echofb);
			for (i = de; i < n; i++) eb[i] = y[i - de] + eb[i - de] * efb;
			for (i = 0; i < n; i++) y[i] += eb[i] * q.echo * 0.7;
		}
		// Hall
		if (q.verb > 0) {
			var rv = reverb(y, q.verbsize, 0.25), pv = peak(rv), pyv = peak(y);
			for (i = 0; i < n; i++) y[i] = y[i] * (1 - q.verb * 0.35) + rv[i] / pv * pyv * q.verb * 0.7;
		}
		// Kompressor: leise Stellen anheben, Spitzen zähmen
		if (q.comp > 0) {
			var e2 = envelope(y, 18), pe = peak(e2), ratio = 1 + q.comp * 7, thr = 0.25;
			for (i = 0; i < n; i++) {
				var lev = e2[i] / pe;
				var g = lev > thr ? Math.pow(thr / lev, 1 - 1 / ratio) : 1;
				y[i] *= g;
			}
		}
		// Ende kürzen, Ein- und Ausblenden, normalisieren
		var last = n - 1, pk = peak(y);
		while (last > 0 && Math.abs(y[last]) < pk * 0.002) last--;
		y = y.subarray(0, Math.min(n, last + Math.round(SR * 0.03)));
		var fi = Math.round(SR * 0.003), fo = Math.round(SR * 0.04);
		for (i = 0; i < fi && i < y.length; i++) y[i] *= i / fi;
		for (i = 0; i < fo && i < y.length; i++) y[y.length - 1 - i] *= i / fo;
		var gfin = 0.95 / peak(y) * Math.pow(10, Math.min(0, q.gain) / 20);
		var res = new Float32Array(y.length);
		for (i = 0; i < y.length; i++) res[i] = y[i] * gfin;
		return res;
	}

	function wav(x) {
		var buf = new ArrayBuffer(44 + x.length * 2), v = new DataView(buf);
		function s(o, t) { for (var i = 0; i < t.length; i++) v.setUint8(o + i, t.charCodeAt(i)); }
		s(0, "RIFF"); v.setUint32(4, 36 + x.length * 2, true); s(8, "WAVE"); s(12, "fmt ");
		v.setUint32(16, 16, true); v.setUint16(20, 1, true); v.setUint16(22, 1, true);
		v.setUint32(24, SR, true); v.setUint32(28, SR * 2, true); v.setUint16(32, 2, true); v.setUint16(34, 16, true);
		s(36, "data"); v.setUint32(40, x.length * 2, true);
		for (var i = 0; i < x.length; i++) v.setInt16(44 + i * 2, Math.max(-1, Math.min(1, x[i])) * 32767, true);
		return buf;
	}

	G.VoxDSP = { render: render, wav: wav, SR: SR, DEFAULTS: DEFAULTS };
})(typeof window !== "undefined" ? window : globalThis);
