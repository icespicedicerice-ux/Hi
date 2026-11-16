extends Node3D
# Hollow Blade: VR sword + sorcery. Right hand holds a sword (swing fast to cut,
# swing into enemy weapons to parry). Left trigger = fireball, left grip = force push.

class Enemy extends Node3D:
	var hp := 4
	var state := "walk"
	var t := 0.0
	var hit_cool := 0.0
	var flash := 0.0
	var fall := 0.0
	var mat: StandardMaterial3D
	var weapon: Node3D

const SPAWN_R := 9.0
const BG := Color(0.05, 0.04, 0.1)

var cam: XRCamera3D
var rc: XRController3D
var lc: XRController3D
var sword: Node3D
var label: Label3D
var env: Environment
var enemies: Array = []
var shots: Array = []
var state := "menu"
var hp := 100
var wave := 0
var score := 0
var to_spawn := 0
var spawn_t := 0.0
var wave_delay := 3.0
var flash := 0.0
var over_at := 0
var fire_cool := 0.0
var push_cool := 0.0
var tip_prev := Vector3.ZERO
var tip_vel := 0.0
var head := Vector3.ZERO
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()
	var xr := XRServer.find_interface("OpenXR")
	if xr and xr.is_initialized():
		get_viewport().use_xr = true
	_build()


func _mat(c: Color, glow := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = glow
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.material_override = m
	parent.add_child(mi)
	return mi


func _build() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BG
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.5, 0.75)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	add_child(sun)

	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	fl.mesh = pm
	fl.material_override = _mat(Color(0.14, 0.12, 0.2))
	add_child(fl)

	var origin := XROrigin3D.new()
	add_child(origin)
	cam = XRCamera3D.new()
	origin.add_child(cam)
	rc = XRController3D.new()
	rc.tracker = "right_hand"
	origin.add_child(rc)
	lc = XRController3D.new()
	lc.tracker = "left_hand"
	origin.add_child(lc)
	rc.button_pressed.connect(_on_button.bind(false))
	lc.button_pressed.connect(_on_button.bind(true))

	sword = Node3D.new()
	rc.add_child(sword)
	_box(sword, Vector3(0.05, 0.012, 0.9), Vector3(0, 0, -0.55), _mat(Color(0.75, 0.85, 0.95), 0.6))
	_box(sword, Vector3(0.2, 0.025, 0.03), Vector3(0, 0, -0.1), _mat(Color(0.5, 0.3, 0.9)))
	_box(sword, Vector3(0.03, 0.03, 0.14), Vector3(0, 0, 0.0), _mat(Color(0.3, 0.2, 0.15)))

	var orb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.06
	sm.height = 0.12
	orb.mesh = sm
	orb.material_override = _mat(Color(1, 0.5, 0.1), 2.0)
	lc.add_child(orb)

	label = Label3D.new()
	label.position = Vector3(0, 2.3, -3.5)
	label.pixel_size = 0.005
	label.font_size = 64
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)
	label.text = "Hollow Blade\nPress a trigger to begin"


func _buzz(c: XRController3D, amp: float, dur: float) -> void:
	c.trigger_haptic_pulse("haptic", 0.0, amp, dur, 0.0)


func _on_button(button_name: String, is_left: bool) -> void:
	if state == "menu":
		_start()
		return
	if state == "over":
		if Time.get_ticks_msec() - over_at > 1000:
			_start()
		return
	if is_left and button_name == "trigger_click":
		_fire()
	elif is_left and button_name == "grip_click":
		_push()


func _start() -> void:
	for e in enemies:
		e.queue_free()
	for s in shots:
		s["n"].queue_free()
	enemies.clear()
	shots.clear()
	hp = 100
	wave = 0
	score = 0
	state = "play"
	_next_wave()


func _next_wave() -> void:
	wave += 1
	to_spawn = 3 + wave * 2
	spawn_t = 0.0
	wave_delay = 3.0
	_hud()


func _hud() -> void:
	label.text = "Wave %d\nHealth %d   Score %d" % [wave, maxi(hp, 0), score]


func _hurt(n: int) -> void:
	hp -= n
	flash = 0.25
	_buzz(rc, 1.0, 0.2)
	_buzz(lc, 1.0, 0.2)
	if hp <= 0:
		state = "over"
		over_at = Time.get_ticks_msec()
		label.text = "You fell\nWave %d, score %d\nPress a trigger to retry" % [wave, score]
		return
	_hud()


func _spawn() -> void:
	var e := Enemy.new()
	e.mat = _mat(Color(0.28, 0.22, 0.34))
	e.hp = 3 + int(wave / 3)
	_box(e, Vector3(0.5, 0.8, 0.3), Vector3(0, 0.9, 0), e.mat)
	_box(e, Vector3(0.35, 0.5, 0.2), Vector3(0, 0.25, 0), e.mat)
	var hd := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.2
	sm.height = 0.4
	hd.mesh = sm
	hd.material_override = e.mat
	hd.position = Vector3(0, 1.55, 0)
	e.add_child(hd)
	for x in [-0.08, 0.08]:
		_box(e, Vector3(0.05, 0.03, 0.03), Vector3(x, 1.58, -0.18), _mat(Color(1, 0.2, 0.3), 2.0))
	e.weapon = Node3D.new()
	e.weapon.position = Vector3(0.35, 1.1, -0.2)
	e.add_child(e.weapon)
	_box(e.weapon, Vector3(0.05, 0.05, 0.8), Vector3(0, 0, -0.4), _mat(Color(0.7, 0.7, 0.75)))
	var a := rng.randf() * TAU
	add_child(e)
	e.global_position = Vector3(sin(a) * SPAWN_R, 0, cos(a) * SPAWN_R)
	enemies.append(e)


func _fire() -> void:
	if fire_cool > 0.0:
		return
	fire_cool = 0.5
	var n := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.12
	s.height = 0.24
	n.mesh = s
	n.material_override = _mat(Color(1, 0.5, 0.1), 3.0)
	var l := OmniLight3D.new()
	l.light_color = Color(1, 0.5, 0.1)
	l.omni_range = 4.0
	n.add_child(l)
	add_child(n)
	n.global_position = lc.global_position
	shots.append({"n": n, "v": -lc.global_transform.basis.z * 12.0, "life": 2.0})
	_buzz(lc, 0.5, 0.06)


func _push() -> void:
	if push_cool > 0.0:
		return
	push_cool = 4.0
	var d := -lc.global_transform.basis.z
	var o := lc.global_position
	for e in enemies:
		if e.state == "dead":
			continue
		var to: Vector3 = e.global_position + Vector3(0, 1, 0) - o
		if to.length() < 6.0 and to.normalized().dot(d) > 0.4:
			e.global_position += Vector3(to.x, 0, to.z).normalized() * 3.0
			e.state = "stagger"
			e.t = 0.0
			e.flash = 0.2
	_buzz(lc, 1.0, 0.2)


func _damage(e, n: int) -> void:
	e.hp -= n
	e.flash = 0.12
	e.hit_cool = 0.3
	var away: Vector3 = e.global_position - head
	away.y = 0
	e.global_position += away.normalized() * 0.4
	_buzz(rc, 0.8, 0.08)
	if e.hp <= 0 and e.state != "dead":
		e.state = "dead"
		e.t = 0.0
		score += 10
		_hud()


func _process(dt: float) -> void:
	head = cam.global_position
	var tip := sword.to_global(Vector3(0, 0, -1.0))
	tip_vel = tip.distance_to(tip_prev) / maxf(dt, 0.001)
	tip_prev = tip
	fire_cool -= dt
	push_cool -= dt
	if flash > 0.0:
		flash -= dt
	env.background_color = Color(0.25, 0.04, 0.08) if flash > 0.0 else BG
	if state == "play":
		_play(dt, tip)


func _play(dt: float, tip: Vector3) -> void:
	if to_spawn > 0:
		spawn_t -= dt
		if spawn_t <= 0.0:
			_spawn()
			to_spawn -= 1
			spawn_t = maxf(0.8, 2.8 - wave * 0.15)
	elif enemies.is_empty():
		wave_delay -= dt
		if wave_delay <= 0.0:
			_next_wave()
	var mid := sword.to_global(Vector3(0, 0, -0.55))
	for e in enemies.duplicate():
		_enemy(e, dt, tip, mid)
		if state != "play":
			return
	for i in range(shots.size() - 1, -1, -1):
		var s: Dictionary = shots[i]
		s["n"].global_position += s["v"] * dt
		s["life"] -= dt
		var gone: bool = s["life"] <= 0.0
		for e in enemies:
			if e.state != "dead" and s["n"].global_position.distance_to(e.global_position + Vector3(0, 1.1, 0)) < 0.6:
				_damage(e, 3)
				gone = true
				break
		if gone:
			s["n"].queue_free()
			shots.remove_at(i)
	for i in range(enemies.size() - 1, -1, -1):
		if enemies[i].state == "gone":
			enemies.remove_at(i)


func _enemy(e, dt: float, tip: Vector3, mid: Vector3) -> void:
	e.hit_cool -= dt
	e.flash -= dt
	e.mat.emission_enabled = e.flash > 0.0
	e.mat.emission = Color(1, 1, 1)
	if e.state == "dead":
		e.t += dt
		if e.fall < 1.5:
			var a := dt * 2.5
			e.fall += a
			e.rotate_object_local(Vector3.RIGHT, a)
		if e.t > 1.5:
			e.queue_free()
			e.state = "gone"
		return
	var pos: Vector3 = e.global_position
	var flat := Vector3(head.x - pos.x, 0, head.z - pos.z)
	var dist := flat.length()
	if dist > 0.01:
		e.look_at(Vector3(head.x, pos.y, head.z), Vector3.UP)
	match e.state:
		"walk":
			e.weapon.rotation.x = 0.2
			if dist > 1.7:
				e.global_position += flat / dist * (1.2 + wave * 0.1) * dt
			else:
				e.state = "windup"
				e.t = 0.0
		"windup":
			e.t += dt
			e.weapon.rotation.x = lerpf(0.2, 1.4, minf(e.t / 0.7, 1.0))
			var wt: Vector3 = e.weapon.to_global(Vector3(0, 0, -0.7))
			if tip_vel > 1.5 and (tip.distance_to(wt) < 0.6 or mid.distance_to(wt) < 0.6):
				e.state = "stagger"
				e.t = 0.0
				e.flash = 0.2
				_buzz(rc, 1.0, 0.15)
			elif e.t >= 0.7:
				e.weapon.rotation.x = -0.9
				if dist < 2.1:
					_hurt(10)
				e.state = "recover"
				e.t = 0.0
		"recover":
			e.t += dt
			if e.t > 0.9:
				e.state = "walk"
		"stagger":
			e.t += dt
			e.weapon.rotation.x = 0.2
			if e.t > 1.0:
				e.state = "walk"
	if e.state != "dead" and tip_vel > 2.0 and e.hit_cool <= 0.0:
		var base := 2 if tip_vel > 4.0 else 1
		var bp: Vector3 = pos + Vector3(0, 1.0, 0)
		var hp_: Vector3 = pos + Vector3(0, 1.62, 0)
		if tip.distance_to(hp_) < 0.3 or mid.distance_to(hp_) < 0.3:
			_damage(e, base * 2)
		elif tip.distance_to(bp) < 0.45 or mid.distance_to(bp) < 0.45:
			_damage(e, base)
