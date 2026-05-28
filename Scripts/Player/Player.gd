extends Node2D
class_name YunxiPlayer

signal died

const WEAPON_ATTACK_FRAME_COUNT := 12
const WEAPON_IDLE_POSITIONS := [
	Vector2(-70, -45),
	Vector2(-28, -90),
	Vector2(28, -90),
	Vector2(70, -45)
]
const WEAPON_IDLE_ROTATIONS := [-0.48, -0.16, 0.16, 0.48]

var hp := 110.0
var shield := 60.0
var velocity := Vector2.ZERO
var facing := Vector2.DOWN
var dash_time := 0.0
var dash_cd := 0.0
var iframe_time := 0.0
var shield_delay := 0.0
var sprite: Sprite2D
var shadow: ColorRect
var weapon_root: Node2D
var weapon_visuals: Array = []
var weapon_visual_signature := ""

func _ready() -> void:
	sprite = Sprite2D.new()
	sprite.texture = AssetDB.tex("char_yunxi")
	sprite.scale = Vector2(0.11, 0.11)
	sprite.position = Vector2(0, -26)
	sprite.z_index = 1
	add_child(sprite)
	shadow = ColorRect.new()
	shadow.color = Color(0, 0, 0, 0.22)
	shadow.size = Vector2(50, 18)
	shadow.position = Vector2(-25, 16)
	shadow.z_index = -1
	add_child(shadow)
	weapon_root = Node2D.new()
	weapon_root.name = "EquippedWeapons"
	weapon_root.z_index = 4
	add_child(weapon_root)
	hp = float(GameState.stats.get("max_hp", 110))
	shield = float(GameState.stats.get("max_qi_shield", 60))
	if not SignalsBus.weapon_changed.is_connected(_on_weapon_changed):
		SignalsBus.weapon_changed.connect(_on_weapon_changed)
	_sync_weapon_visuals(true)

func tick(delta: float, arena_radius: Vector2) -> void:
	dash_cd = max(0.0, dash_cd - delta)
	iframe_time = max(0.0, iframe_time - delta)
	shield_delay = max(0.0, shield_delay - delta)
	var input := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	)
	if input.length() > 1.0:
		input = input.normalized()
	if input.length_squared() > 0.01:
		facing = input.normalized()
	var speed := float(GameState.stats.get("move_speed", 160)) * (1.0 + float(GameState.stats.get("speed_pct", 0.0)))
	if Input.is_action_just_pressed("dash") and dash_cd <= 0.0:
		dash_time = float(GameState.stats.get("dash_duration", 0.18))
		dash_cd = float(GameState.stats.get("dash_cooldown", 2.2))
		iframe_time = float(GameState.stats.get("dash_iframes", 0.30))
		SignalsBus.hud_request_shake.emit(4.0, 0.12)
	if dash_time > 0.0:
		dash_time -= delta
		velocity = (facing if input.length_squared() <= 0.01 else input.normalized()) * float(GameState.stats.get("dash_speed", 640))
	else:
		velocity = input * speed
	position += velocity * delta
	_clamp_to_ellipse(arena_radius)
	_regen(delta)
	_update_visual(delta)
	_update_weapon_visuals(delta)

func trigger_weapon_attack(weapon: Dictionary, slot_index: int, target_pos := Vector2.ZERO) -> void:
	_sync_weapon_visuals()
	if slot_index < 0 or slot_index >= weapon_visuals.size():
		slot_index = _find_weapon_visual_index(weapon)
	if slot_index < 0 or slot_index >= weapon_visuals.size():
		return
	var dir := target_pos - global_position
	if dir.length_squared() < 9.0:
		dir = facing
	if dir.length_squared() < 0.01:
		dir = Vector2.RIGHT
	var visual: Dictionary = weapon_visuals[slot_index]
	visual["attack_time"] = 0.0
	visual["attack_duration"] = _weapon_attack_duration(weapon)
	visual["attack_dir"] = dir.normalized()
	visual["attack_style"] = _weapon_attack_style(weapon)
	visual["attack_element"] = str(weapon.get("element", "metal"))
	visual["attack_frame"] = 0
	weapon_visuals[slot_index] = visual

func weapon_muzzle_global_position(slot_index: int) -> Vector2:
	_sync_weapon_visuals()
	if slot_index >= 0 and slot_index < weapon_visuals.size():
		var visual: Dictionary = weapon_visuals[slot_index]
		var slot: Node2D = visual.get("slot", null)
		if slot != null and slot.visible:
			return slot.global_position
	return global_position + Vector2(0, -58)

func _regen(delta: float) -> void:
	hp = min(float(GameState.stats.get("max_hp", 110)), hp + float(GameState.stats.get("hp_regen", 0.0)) * delta)
	if shield_delay <= 0.0:
		shield = min(float(GameState.stats.get("max_qi_shield", 60)), shield + float(GameState.stats.get("qi_shield_regen", 8.0)) * delta)

func receive_damage(amount: float) -> void:
	if iframe_time > 0.0:
		return
	if randf() < clamp(float(GameState.stats.get("dodge", 0.0)), 0.0, 0.60):
		SignalsBus.hud_request_shake.emit(2.0, 0.08)
		return
	var armor := float(GameState.stats.get("armor", 0.0))
	var mitigated := amount * (1.0 - armor / (armor + 60.0)) if armor > 0.0 else amount
	shield_delay = float(GameState.stats.get("qi_shield_delay", 3.5))
	if shield > 0.0:
		var absorbed: float = min(shield, mitigated)
		shield -= absorbed
		mitigated -= absorbed
	hp -= mitigated
	iframe_time = 0.24
	sprite.modulate = Color("#f25050")
	SignalsBus.player_damaged.emit(mitigated)
	SignalsBus.hud_request_shake.emit(8.0, 0.16)
	if hp <= 0.0:
		died.emit()

func heal_from_lifesteal(amount: float) -> void:
	var heal := amount * float(GameState.stats.get("lifesteal", 0.0))
	if heal > 0.0:
		hp = min(float(GameState.stats.get("max_hp", 110)), hp + heal)

func _clamp_to_ellipse(radius: Vector2) -> void:
	var v := position
	var metric := (v.x * v.x) / (radius.x * radius.x) + (v.y * v.y) / (radius.y * radius.y)
	if metric > 1.0:
		position = v / sqrt(metric)

func _update_visual(delta: float) -> void:
	var moving := velocity.length_squared() > 20.0
	sprite.rotation = sin(Time.get_ticks_msec() * 0.006) * (0.045 if moving else 0.018)
	sprite.position.y = -28 + sin(Time.get_ticks_msec() * 0.005) * (5 if moving else 2)
	sprite.flip_h = facing.x < -0.1
	if iframe_time <= 0.0:
		sprite.modulate = sprite.modulate.lerp(Color.WHITE, delta * 12.0)

func _on_weapon_changed(_slot: int, _weapon: Dictionary) -> void:
	_sync_weapon_visuals(true)

func _sync_weapon_visuals(force := false) -> void:
	var signature := _active_weapon_signature()
	if not force and signature == weapon_visual_signature:
		return
	weapon_visual_signature = signature
	while weapon_visuals.size() < GameState.active_weapons.size():
		weapon_visuals.append(_make_weapon_visual(weapon_visuals.size()))
	for i in range(weapon_visuals.size()):
		var visual: Dictionary = weapon_visuals[i]
		var slot: Node2D = visual["slot"]
		var has_weapon := i < GameState.active_weapons.size()
		slot.visible = has_weapon
		if has_weapon:
			var weapon: Dictionary = GameState.active_weapons[i]
			var sprite_node: Sprite2D = visual["sprite"]
			var trail_a: Sprite2D = visual["trail_a"]
			var trail_b: Sprite2D = visual["trail_b"]
			var aura: Sprite2D = visual["aura"]
			var texture := AssetDB.tex(str(weapon.get("art_id", "icon_metal")))
			sprite_node.texture = texture
			trail_a.texture = texture
			trail_b.texture = texture
			aura.texture = AssetDB.tex("fx_%s" % str(weapon.get("element", "metal")))
			visual["weapon_id"] = str(weapon.get("id", ""))
			visual["tier"] = int(weapon.get("tier", 1))
			visual["element"] = str(weapon.get("element", "metal"))
			visual["base_scale"] = 0.052 + float(clampi(int(weapon.get("tier", 1)), 1, 4) - 1) * 0.004
			weapon_visuals[i] = visual

func _make_weapon_visual(index: int) -> Dictionary:
	var slot := Node2D.new()
	slot.name = "EquippedWeapon%d" % (index + 1)
	slot.z_index = index + 1
	weapon_root.add_child(slot)
	var aura := Sprite2D.new()
	aura.name = "ReleaseAura"
	aura.z_index = 0
	aura.centered = true
	aura.visible = false
	slot.add_child(aura)
	var trail_b := Sprite2D.new()
	trail_b.name = "TrailBack"
	trail_b.z_index = 1
	trail_b.centered = true
	trail_b.visible = false
	slot.add_child(trail_b)
	var trail_a := Sprite2D.new()
	trail_a.name = "TrailFront"
	trail_a.z_index = 2
	trail_a.centered = true
	trail_a.visible = false
	slot.add_child(trail_a)
	var sprite_node := Sprite2D.new()
	sprite_node.name = "WeaponSprite"
	sprite_node.z_index = 3
	sprite_node.centered = true
	slot.add_child(sprite_node)
	return {
		"slot": slot,
		"sprite": sprite_node,
		"aura": aura,
		"trail_a": trail_a,
		"trail_b": trail_b,
		"weapon_id": "",
		"tier": 1,
		"element": "metal",
		"base_scale": 0.052,
		"attack_time": 999.0,
		"attack_duration": 0.28,
		"attack_dir": Vector2.RIGHT,
		"attack_style": "thrust",
		"attack_element": "metal",
		"attack_frame": 0
	}

func _active_weapon_signature() -> String:
	var parts: Array = []
	for weapon in GameState.active_weapons:
		parts.append("%s:%d:%s" % [str(weapon.get("id", "")), int(weapon.get("tier", 1)), str(weapon.get("art_id", ""))])
	return "|".join(parts)

func _find_weapon_visual_index(weapon: Dictionary) -> int:
	var weapon_id := str(weapon.get("id", ""))
	for i in range(weapon_visuals.size()):
		var visual: Dictionary = weapon_visuals[i]
		if str(visual.get("weapon_id", "")) == weapon_id:
			return i
	return -1

func _update_weapon_visuals(delta: float) -> void:
	_sync_weapon_visuals()
	var now := Time.get_ticks_msec() * 0.001
	for i in range(weapon_visuals.size()):
		var visual: Dictionary = weapon_visuals[i]
		var slot: Node2D = visual["slot"]
		if not slot.visible:
			continue
		var base := _weapon_idle_position(i, GameState.active_weapons.size(), now)
		var base_rot := _weapon_idle_rotation(i, now)
		var base_scale := float(visual.get("base_scale", 0.052))
		var attack_time := float(visual.get("attack_time", 999.0))
		var attack_duration: float = max(0.05, float(visual.get("attack_duration", 0.28)))
		var attacking: bool = attack_time < attack_duration
		var pose: Dictionary = {"position": base, "rotation": base_rot, "scale_mult": 1.0, "glow": 0.0}
		if attacking:
			var progress: float = clamp(attack_time / attack_duration, 0.0, 0.999)
			var frame: int = clampi(int(floor(progress * WEAPON_ATTACK_FRAME_COUNT)), 0, WEAPON_ATTACK_FRAME_COUNT - 1)
			visual["attack_frame"] = frame
			pose = _weapon_attack_pose(str(visual.get("attack_style", "thrust")), frame, visual.get("attack_dir", Vector2.RIGHT), base, base_rot, i)
			visual["attack_time"] = attack_time + delta
			if float(visual["attack_time"]) >= attack_duration:
				visual["attack_time"] = 999.0
				attacking = false
		_apply_weapon_pose(visual, pose, base_scale, attacking)
		weapon_visuals[i] = visual

func _weapon_idle_position(index: int, count: int, now: float) -> Vector2:
	var base: Vector2 = WEAPON_IDLE_POSITIONS[index % WEAPON_IDLE_POSITIONS.size()]
	if count <= 1:
		base = Vector2(0, -94)
	elif count == 2:
		base = Vector2(-38, -82) if index % 2 == 0 else Vector2(38, -82)
	elif count == 3:
		if index % 3 == 0:
			base = Vector2(-66, -48)
		elif index % 3 == 1:
			base = Vector2(0, -96)
		else:
			base = Vector2(66, -48)
	elif count > WEAPON_IDLE_POSITIONS.size():
		var angle: float = -PI * 0.9 + float(index) / max(1.0, float(count - 1)) * PI * 0.8
		base = Vector2(cos(angle) * 74.0, -56.0 + sin(angle) * 38.0)
	return base + Vector2(0, sin(now * 2.3 + float(index) * 0.8) * 3.0)

func _weapon_idle_rotation(index: int, now: float) -> float:
	return float(WEAPON_IDLE_ROTATIONS[index % WEAPON_IDLE_ROTATIONS.size()]) + sin(now * 1.8 + float(index)) * 0.045

func _weapon_attack_pose(style: String, frame: int, dir: Vector2, base: Vector2, base_rot: float, index: int) -> Dictionary:
	var t := float(frame) / float(WEAPON_ATTACK_FRAME_COUNT - 1)
	var wave := sin(t * PI)
	var side := Vector2(-dir.y, dir.x)
	var pos := base
	var rot := base_rot
	var scale_mult := 1.0 + wave * 0.12
	var glow := wave
	match style:
		"dash":
			pos = base + dir * lerpf(-10.0, 64.0, t) + side * sin(t * PI * 2.0) * 10.0
			rot = dir.angle() + 0.85 * wave
			scale_mult = 1.05 + wave * 0.18
		"fan":
			pos = base + dir * (18.0 + 34.0 * wave) + side * sin(t * TAU + float(index)) * 15.0
			rot = dir.angle() + sin(t * TAU) * 0.34
		"sigil":
			pos = base + Vector2(0, -22.0 * wave) + dir * 12.0 * wave
			rot = base_rot + t * TAU
			scale_mult = 1.0 + wave * 0.34
			glow = min(1.0, 0.25 + wave)
		"ring":
			var angle := atan2(base.y + 52.0, base.x) + t * TAU * 1.18
			pos = Vector2(cos(angle) * 76.0, -55.0 + sin(angle) * 36.0)
			rot = angle + PI * 0.5
			scale_mult = 0.95 + wave * 0.16
		"pulse":
			pos = base + Vector2(0, -8.0 * wave)
			rot = base_rot + sin(t * TAU) * 0.22
			scale_mult = 1.0 + wave * 0.28
			glow = min(1.0, 0.35 + wave)
		"summon":
			pos = base + side * sin(t * TAU) * 22.0 + dir * 26.0 * wave
			rot = base_rot + t * TAU * 1.4
			scale_mult = 0.96 + wave * 0.22
		"guard":
			pos = Vector2(0, -76.0) + side * (float(index) - 1.5) * 7.0 + Vector2(0, -10.0 * wave)
			rot = base_rot + sin(t * TAU) * 0.18
			scale_mult = 1.0 + wave * 0.38
			glow = min(1.0, 0.55 + wave)
		"slam":
			pos = base + dir * (58.0 * wave) + Vector2(0, 10.0 * wave)
			rot = dir.angle() + lerpf(-0.75, 0.45, t)
			scale_mult = 1.0 + wave * 0.2
		_:
			pos = base + dir * (42.0 * wave) + side * sin(t * TAU) * 6.0
			rot = dir.angle() + sin(t * PI) * 0.22
	return {"position": pos, "rotation": rot, "scale_mult": scale_mult, "glow": glow}

func _apply_weapon_pose(visual: Dictionary, pose: Dictionary, base_scale: float, attacking: bool) -> void:
	var slot: Node2D = visual["slot"]
	var sprite_node: Sprite2D = visual["sprite"]
	var aura: Sprite2D = visual["aura"]
	var trail_a: Sprite2D = visual["trail_a"]
	var trail_b: Sprite2D = visual["trail_b"]
	var element_color := AssetDB.color_for_element(str(visual.get("attack_element", visual.get("element", "metal"))))
	var pose_scale := base_scale * float(pose.get("scale_mult", 1.0))
	slot.position = pose.get("position", Vector2.ZERO)
	slot.rotation = float(pose.get("rotation", 0.0))
	sprite_node.scale = Vector2.ONE * pose_scale
	sprite_node.modulate = Color.WHITE.lerp(element_color, 0.14)
	var glow := float(pose.get("glow", 0.0)) if attacking else 0.0
	aura.visible = glow > 0.02
	aura.rotation = -slot.rotation
	aura.scale = Vector2.ONE * pose_scale * (2.4 + glow * 0.8)
	aura.modulate = Color(element_color.r, element_color.g, element_color.b, 0.18 * glow)
	trail_a.visible = attacking
	trail_b.visible = attacking
	if attacking:
		var dir: Vector2 = visual.get("attack_dir", Vector2.RIGHT)
		trail_a.position = -dir * 8.0
		trail_b.position = -dir * 17.0
		trail_a.rotation = -0.08
		trail_b.rotation = -0.16
		trail_a.scale = Vector2.ONE * pose_scale * 0.92
		trail_b.scale = Vector2.ONE * pose_scale * 0.82
		trail_a.modulate = Color(element_color.r, element_color.g, element_color.b, 0.28)
		trail_b.modulate = Color(element_color.r, element_color.g, element_color.b, 0.14)

func _weapon_attack_style(weapon: Dictionary) -> String:
	match str(weapon.get("class", "flying_sword")):
		"dash_blade":
			return "dash"
		"needle", "thorn":
			return "fan"
		"area", "talisman":
			return "sigil"
		"orbit":
			return "ring"
		"aura":
			return "pulse"
		"summon":
			return "summon"
		"shield":
			return "guard"
		"hammer", "spike":
			return "slam"
		_:
			return "thrust"

func _weapon_attack_duration(weapon: Dictionary) -> float:
	match str(weapon.get("class", "flying_sword")):
		"needle", "orbit":
			return 0.24
		"shield", "area", "summon":
			return 0.36
		"hammer", "spike":
			return 0.32
		_:
			return 0.28

func hp_ratio() -> float:
	return hp / max(1.0, float(GameState.stats.get("max_hp", 110)))
