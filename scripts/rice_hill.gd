# Procedural rice hills (khóm lúa) for every growth stage. field.gd builds a
# few variants per stage and level of detail and draws them with MultiMesh.
# s = 0 just transplanted (mạ 4-5 lá), 0.45 full tillering (đẻ nhánh),
# 0.62 heading (trổ bông), 1.0 ripe (chín, bông trĩu).
# Surface 0: leaves, sheaths and culms (and, at lod 1-2, solid panicles).
# Surface 1 (lod 0, heading on): panicle branches as crossed ribbons cut out
# by grain_texture() (alpha scissor, opaque pass).
# Vertex data read by shaders/rice_body.gdshaderinc:
#   UV      = (across 0..1, along the organ 0..1)
#   COLOR   = (organ: 0 leaf, 0.5 culm and sheath, 1 panicle; leaf rank 0 top
#              .. 1 lowest; per-organ random; height / plant height)
#   TANGENT = along the organ, for the waxy streak highlight
# Sizes follow field agronomy: leaves 8-12 mm wide (flag leaf 12-16 mm),
# 30-45 cm long at tillering, 10-16 tillers per hill, ripe panicles 20-25 cm
# whose rachis arcs over until the tip hangs below the neck.
extends RefCounted

const LEAF := 0.0
const STEM := 0.5
const PANICLE := 1.0


class Buf:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var t := PackedFloat32Array()
	var uv := PackedVector2Array()
	var c := PackedColorArray()
	var i := PackedInt32Array()
	var top := 0.01

	func vert(p: Vector3, nrm: Vector3, tng: Vector3, u: Vector2, col: Color) -> int:
		v.append(p)
		n.append(nrm)
		t.append_array([tng.x, tng.y, tng.z, 1.0])
		uv.append(u)
		c.append(col)
		top = maxf(top, p.y)
		return v.size() - 1

	func arrays(plant_top: float) -> Array:
		# COLOR.a = height over the plant height: AO and wind weight.
		for k in c.size():
			c[k].a = clampf(v[k].y / plant_top, 0.0, 1.0)
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = v
		a[Mesh.ARRAY_NORMAL] = n
		a[Mesh.ARRAY_TANGENT] = t
		a[Mesh.ARRAY_TEX_UV] = uv
		a[Mesh.ARRAY_COLOR] = c
		a[Mesh.ARRAY_INDEX] = i
		return a


# Normal bent toward the outside of the hill and the sky, so a hill shades
# like a soft tuft instead of a heap of flat ribbons.
static func _canopy(nrm: Vector3, p: Vector3, k: float) -> Vector3:
	var out := Vector3(p.x, 0.0, p.z)
	var dome := (Vector3.UP + out.normalized() * minf(out.length() * 6.0, 0.8)).normalized()
	return nrm.lerp(dome, k).normalized()


# Leaf blade from p0. Leaves at angle th0 from vertical and bends `droop`
# radians more by the tip, in the vertical plane through `dirh`. 3 vertices
# across (folded along the midrib, a shallow V) or 2.
static func _leaf(b: Buf, p0: Vector3, dirh: Vector3, length: float, width: float, th0: float, droop: float, twist: float, segs: int, across_n: int, rank: float, r: float, organ := LEAF) -> void:
	var side := Vector3.UP.cross(dirh).normalized()
	var p := p0
	var base := b.v.size()
	for s in segs + 1:
		var f := float(s) / segs
		var th := th0 + droop * f * f
		var tng := (Vector3.UP * cos(th) + dirh * sin(th)).normalized()
		var acr := side.rotated(tng, twist * f)
		var nrm := acr.cross(tng).normalized()
		if nrm.y < 0.0:
			nrm = -nrm
		nrm = _canopy(nrm, p, 0.35)
		# narrow at the collar, widest at about 40 %, long acuminate tip
		var w := width * (0.55 + 0.45 * sin(PI * minf(f * 1.25, 1.0) * 0.5 + 0.25)) * (1.0 - pow(f, 2.2))
		var col := Color(organ, rank, r, 0.0)
		if across_n == 3:
			var fold := 0.35
			b.vert(p - acr * w + nrm * w * fold, (nrm + acr * fold).normalized(), tng, Vector2(0.0, f), col)
			b.vert(p, nrm, tng, Vector2(0.5, f), col)
			b.vert(p + acr * w + nrm * w * fold, (nrm - acr * fold).normalized(), tng, Vector2(1.0, f), col)
		else:
			b.vert(p - acr * w, (nrm + acr * 0.3).normalized(), tng, Vector2(0.0, f), col)
			b.vert(p + acr * w, (nrm - acr * 0.3).normalized(), tng, Vector2(1.0, f), col)
		p += tng * (length / segs)
	for s in segs:
		var a := base + s * across_n
		var nx := a + across_n
		for k in across_n - 1:
			b.i.append_array([a + k, nx + k, a + k + 1, a + k + 1, nx + k, nx + k + 1])


# Culm wrapped in its leaf sheaths: a thin 3-sided prism, pale at the base.
static func _culm(b: Buf, p0: Vector3, axis: Vector3, length: float, r0: float, r1: float, r: float, sides := 3, rank := 1.0) -> void:
	var side := axis.cross(Vector3.FORWARD if absf(axis.z) < 0.9 else Vector3.RIGHT).normalized()
	var up2 := side.cross(axis)
	var base := b.v.size()
	var segs := 2
	for s in segs + 1:
		var f := float(s) / segs
		var c := p0 + axis * length * f
		var rr := lerpf(r0, r1, f)
		for k in sides:
			var a := TAU * k / sides
			var d := side * cos(a) + up2 * sin(a)
			b.vert(c + d * rr, d, axis, Vector2(float(k) / sides, f), Color(STEM, rank, r, 0.0))
	for s in segs:
		for k in sides:
			var a := base + s * sides + k
			var a2 := base + s * sides + (k + 1) % sides
			b.i.append_array([a, a + sides, a2, a2, a + sides, a2 + sides])


# A flat strip along a polyline (panicle branch or a whole far panicle).
static func _ribbon(b: Buf, pts: Array, acr: Vector3, w0: float, w1: float, col: Color) -> void:
	var base := b.v.size()
	var n := pts.size()
	for s in n:
		var g := float(s) / (n - 1)
		var p: Vector3 = pts[s]
		var fwd: Vector3 = (pts[mini(s + 1, n - 1)] - pts[maxi(s - 1, 0)]).normalized()
		var nrm := acr.cross(fwd).normalized()
		if nrm.y < 0.0:
			nrm = -nrm
		var w := lerpf(w0, w1, g)
		b.vert(p - acr * w, nrm, fwd, Vector2(0.0, g), col)
		b.vert(p + acr * w, nrm, fwd, Vector2(1.0, g), col)
	for s in n - 1:
		var a := base + s * 2
		b.i.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])


# Panicle (bông lúa) from the neck p0, leaning toward `out`. The rachis arcs
# over as the grains fill; primary branches leave it at the golden angle,
# open at flowering and close up and hang when ripe. lod 0: each branch is
# two crossed grain ribbons; lod 1: one solid ribbon per branch; lod 2: the
# whole panicle is one solid ribbon.
static func _panicle(b: Buf, p0: Vector3, out: Vector3, ripe: float, rng: RandomNumberGenerator, lod: int) -> void:
	var length := rng.randf_range(0.19, 0.25)
	var bend := lerpf(0.2, 2.8, ripe) * rng.randf_range(0.8, 1.1)
	var segs := 6 if lod == 0 else 4
	var pts := []
	var p := p0
	for s in segs + 1:
		var f := float(s) / segs
		var th := 0.06 + bend * pow(f, 1.3)
		var tng := (Vector3.UP * cos(th) + out * sin(th)).normalized()
		pts.append([p, tng])
		p += tng * (length / segs)
	var r := rng.randf()
	if lod > 0:
		# solid panicle: one ribbon (lod 2) or two crossed ribbons (lod 1)
		var line := []
		for q in pts:
			line.append(q[0])
		var acr := Vector3.UP.cross(out).normalized()
		_ribbon(b, line, acr, 0.02, 0.01, Color(PANICLE, 0.0, r, 0.0))
		if lod == 1:
			var mid: Vector3 = pts[segs / 2][1]
			_ribbon(b, line, mid.cross(acr).normalized(), 0.017, 0.008, Color(PANICLE, 0.5, r, 0.0))
		return
	var nb := 8
	var ga := rng.randf() * TAU
	for j in nb:
		var f := 0.12 + 0.86 * float(j) / nb
		var k := mini(int(f * segs), segs - 1)
		var q: float = f * segs - k
		var bp: Vector3 = (pts[k][0] as Vector3).lerp(pts[k + 1][0], q)
		var bt: Vector3 = (pts[k][1] as Vector3).lerp(pts[k + 1][1], q).normalized()
		ga += deg_to_rad(137.5)
		var radial := bt.cross(Vector3.UP if absf(bt.y) < 0.95 else Vector3.RIGHT).normalized().rotated(bt, ga)
		var open := deg_to_rad(lerpf(36.0, 12.0, ripe))
		var bdir := (bt * cos(open) + radial * sin(open)).normalized()
		var bl := 0.12 * (1.0 - 0.5 * f) * rng.randf_range(0.85, 1.15)
		var hang := Vector3.DOWN * bl * 0.9 * ripe
		var line := [bp, bp + bdir * bl * 0.5 + hang * 0.25, bp + bdir * bl + hang]
		var col := Color(PANICLE, f, r, 0.0)
		_ribbon(b, line, bdir.cross(radial).normalized(), 0.011, 0.009, col)
		_ribbon(b, line, radial, 0.011, 0.009, col)


# One hill. lod 0 near (< ~5 m), 1 middle, 2 far.
static func hill(s: float, seed: int, lod := 0) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var leaves := Buf.new()
	var pan := Buf.new()
	var young := 1.0 - smoothstep(0.0, 0.2, s) # transplant seedlings
	var tiller_n := int(round(lerpf(3.0, 15.0, smoothstep(0.02, 0.45, s))))
	if lod == 1:
		tiller_n = maxi(3, int(round(tiller_n * 0.6)))
	elif lod == 2:
		tiller_n = maxi(3 if young > 0.5 else 2, int(round(tiller_n * 0.4)))
	var collar := 0.045 + 0.59 * pow(smoothstep(0.0, 0.68, s), 2.2) # flag-leaf collar height
	var heading := s >= 0.58
	var ripe := clampf((s - 0.62) / 0.38, 0.0, 1.0)
	var leaf_len := lerpf(0.19, 0.42, smoothstep(0.0, 0.48, s))
	# half width: 5 mm seedling leaves to 10-11 mm; the far lods widen to keep
	# cover, seedlings most of all (a 5 mm leaf is sub-pixel past ~8 m)
	var leaf_w: float = lerpf(0.0026, 0.0052, smoothstep(0.0, 0.42, s)) * [1.0, 1.35, lerpf(3.5, 2.0, smoothstep(0.0, 0.4, s))][lod]
	var segs: int = [5, 3, 2][lod]
	var across: int = [3, 2, 2][lod]
	var nleaf: int = [4, 3, 2][lod]
	if young > 0.5:
		nleaf = [5, 3, 2][lod]
	var spread := 0.012 + 0.035 * smoothstep(0.0, 0.45, s)
	var plant_top := 0.0
	for ti in tiller_n:
		var az := rng.randf() * TAU
		var out := Vector3(cos(az), 0.0, sin(az))
		# seedlings flop a little after transplanting; tillers fan out with age
		var lean := deg_to_rad(rng.randf_range(2.0, 7.0) + 14.0 * smoothstep(0.12, 0.6, s) + young * rng.randf_range(0.0, 14.0))
		var axis := (Vector3.UP + out * tan(lean)).normalized()
		var base := out * rng.randf_range(0.0, spread)
		var hc := collar * rng.randf_range(0.8, 1.05)
		if lod == 0:
			_culm(leaves, base, axis, hc + (0.06 if heading else 0.0), 0.0035, 0.0022, rng.randf())
		elif lod == 1 and s > 0.3:
			_culm(leaves, base, axis, hc, 0.004, 0.003, rng.randf(), 2)
		var phi := az + rng.randf_range(-0.6, 0.6)
		for k in nleaf: # k = 0: youngest (flag) leaf at the top
			var rank := float(k) / maxf(nleaf - 1, 1)
			var hp := base + axis * hc * (1.0 - 0.22 * k)
			var a := phi + PI * k + rng.randf_range(-0.5, 0.5) # distichous: alternate sides
			var dirh := (Vector3(cos(a), 0.0, sin(a)) + out * 0.7).normalized()
			var flag := heading and k == 0
			var ln := leaf_len * (0.62 if flag else 1.0) * rng.randf_range(0.82, 1.15) * (1.0 - 0.18 * rank)
			if young > 0.5:
				ln *= lerpf(1.0, 0.55, rank) # seedling: older leaves are the short lower ones
			var wd: float = leaf_w * (1.4 if flag else 1.0)
			var th0 := deg_to_rad(6.0 + 18.0 * rank + rng.randf_range(-4.0, 6.0) + young * 8.0)
			if lod == 2 and young > 0.5:
				th0 *= 0.5 # far seedlings stand up to show their length above the water
			var droop := deg_to_rad(lerpf(14.0, 75.0, rank) * clampf(ln / 0.42, 0.35, 1.2)) * rng.randf_range(0.7, 1.3)
			if flag:
				droop *= 0.4 # the flag leaf stands erect
			_leaf(leaves, hp, dirh, ln, wd, th0, droop, rng.randf_range(-1.2, 1.2), segs, across, rank, rng.randf())
			plant_top = maxf(plant_top, hp.y + ln * cos(th0 + droop * 0.5) * 0.95)
		if heading and ti < int(ceil(tiller_n * 0.85)):
			var neck := base + axis * (hc + 0.06 + 0.05 * rng.randf())
			if lod == 0:
				_panicle(pan, neck, out, ripe, rng, 0)
			else:
				_panicle(leaves, neck, out, ripe, rng, lod)
			plant_top = maxf(plant_top, neck.y + 0.08)
	plant_top = maxf(plant_top, 0.05)
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, leaves.arrays(plant_top))
	if pan.v.size() > 0:
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, pan.arrays(plant_top))
	return m


# Stubble (gốc rạ) left after the sickle: 10-16 straw culms cut 12-25 cm
# above the mud and a few dry leaves bent over.
static func stubble(seed: int, lod := 0) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var b := Buf.new()
	var n := rng.randi_range(10, 16) if lod == 0 else 7
	for k in n:
		var az := rng.randf() * TAU
		var out := Vector3(cos(az), 0.0, sin(az))
		var axis := (Vector3.UP + out * tan(deg_to_rad(rng.randf_range(3.0, 16.0)))).normalized()
		var base := out * rng.randf_range(0.0, 0.04)
		var h := rng.randf_range(0.12, 0.24)
		_culm(b, base, axis, h, 0.0035, 0.003, rng.randf(), 4 if lod == 0 else 3, 1.0)
		if k % 3 == 0:
			var a := az + rng.randf_range(-1.0, 1.0)
			var dirh := (Vector3(cos(a), 0.0, sin(a)) + out).normalized()
			_leaf(b, base + axis * h * 0.5, dirh, rng.randf_range(0.12, 0.25), 0.004, deg_to_rad(30.0), deg_to_rad(80.0), rng.randf_range(-1.0, 1.0), 3 if lod == 0 else 2, 2, 1.0, rng.randf())
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, b.arrays(0.3))
	return m


# Grain texture for the lod-0 panicle ribbons: two staggered rows of husked
# grains (thóc) on a thin pedicel. R = shading, A = coverage. 64 x 256.
static func grain_texture() -> ImageTexture:
	var W := 64
	var H := 256
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.5, 0.5, 0.5, 0.0))
	var n := 8
	for py in H:
		for px in W:
			var u := (px + 0.5) / W - 0.5
			var v := (py + 0.5) / H
			var best := 0.0
			var shade := 0.0
			for g in n:
				var side := -1.0 if g % 2 == 0 else 1.0
				var cy := (g + 0.5) / n
				var dy := (v - cy) / 0.048
				var dx := (u - side * 0.26) / 0.19
				var d := dx * dx + dy * dy
				if d < 1.0:
					best = 1.0
					# lit centre, darker husk ridge and awn end
					shade = 0.65 + 0.35 * sqrt(1.0 - d) - 0.12 * float(absf(dx) < 0.08)
				# thin pedicel from the rachis out to the grain: loose, open
				# branches rather than a packed wheat-like spike
				var su := u * side
				if su > 0.0 and su < 0.12 and absf(v - (cy + 0.05 - su * 0.4)) < 0.007 and best == 0.0:
					best = 1.0
					shade = 0.5
			if absf(u) < 0.025:
				best = 1.0
				shade = maxf(shade, 0.55)
			if best > 0.0:
				img.set_pixel(px, py, Color(shade, shade, shade, 1.0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
