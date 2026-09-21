# SPDX-License-Identifier: AGPL-3.0-only
extends Node2D

const Rules = preload("res://rules/movement.gd")
const Combat = preload("res://rules/combat.gd")
const SCALE := 15.0
const OFFSET := Vector2(38, 112)
const GOLD := Color("e5ba6b")
const BLUE := Color("68b9db")
const RED := Color("ff6d79")
const WHITE := Color("dae5ed")
var fixture: Dictionary
var models: Array = []
var selected := -1
var dragging := false
var placing := false
var team := 0
var active_team := 0
var history: Array = []
var phase := "MOVEMENT"
var combat_rng := RandomNumberGenerator.new()
var preview := Vector2.ZERO
var drag_offset := Vector2.ZERO
var message := "选择底座以查看移动额度。"
var font: Font = ThemeDB.fallback_font

func _ready() -> void:
	fixture = JSON.parse_string(FileAccess.get_file_as_string("res://data/units/custodian_guard.json"))
	combat_rng.seed = 402000
	reset_table()
	add_button("＋ 放置底座  [P]", Vector2(976, 425), func(): placing = not placing; dragging = false; queue_redraw())
	add_button("切换阵营  [TAB]", Vector2(976, 477), func(): team = 1 - team; queue_redraw())
	add_button("新移动阶段  [N]", Vector2(976, 529), new_phase)
	add_button("重置棋盘  [R]", Vector2(976, 581), reset_table)
	add_button("结束回合  [T]", Vector2(976, 633), end_turn)
	add_button("撤销移动  [U]", Vector2(976, 685), undo_last)
	add_button("进入射击阶段  [SPACE]", Vector2(976, 737), enter_shooting)
	add_button("射击最近目标  [F]", Vector2(976, 789), fire_selected)

func add_button(title: String, position_px: Vector2, action: Callable) -> void:
	var button := Button.new()
	button.text = title
	button.position = position_px
	button.size = Vector2(265, 40)
	button.pressed.connect(action)
	add_child(button)

func reset_table() -> void:
	models.clear()
	selected = -1
	dragging = false
	placing = false
	active_team = 0
	history.clear()
	phase = "MOVEMENT"
	for side in range(2):
		for i in range(10):
			add_model(Vector2(6 + (i % 5) * 3, 6 + (i / 5) * 3 + side * 29), side)
	message = "20 个底座已就绪。当前为本地移动沙盒。"
	queue_redraw()

func add_model(point: Vector2, side: int) -> void:
	models.append({"position": point, "radius": Rules.radius_inches(float(fixture.base_diameter_mm)), "spent": 0.0, "team": side, "wounds": int(fixture.wounds)})

func new_phase() -> void:
	dragging = false
	for model in models:
		model.spent = 0.0
	message = "双方底座的移动额度已重置。"
	queue_redraw()

func end_turn() -> void:
	dragging = false
	placing = false
	selected = -1
	active_team = 1 - active_team
	phase = "MOVEMENT"
	message = "现在轮到%s方。" % ("金" if active_team == 0 else "蓝")
	queue_redraw()

func undo_last() -> void:
	if history.is_empty():
		message = "没有可撤销的移动。"
		queue_redraw()
		return
	var change: Dictionary = history.pop_back()
	models[change.index].position = change.position
	models[change.index].spent = change.spent
	selected = change.index
	message = "已撤销底座 %02d 的上一步移动。" % (selected + 1)
	queue_redraw()

func enter_shooting() -> void:
	if phase != "MOVEMENT":
		return
	dragging = false
	placing = false
	phase = "SHOOTING"
	message = "已进入射击阶段。选择底座后按 F 射击最近目标。"
	queue_redraw()

func fire_selected() -> void:
	if phase != "SHOOTING":
		message = "请先进入射击阶段。"
		queue_redraw()
		return
	if selected < 0 or selected >= models.size() or models[selected].team != active_team:
		message = "请选择当前阵营的底座。"
		queue_redraw()
		return
	var attacker: Dictionary = models[selected]
	var target_index := -1
	var nearest := INF
	for i in range(models.size()):
		if models[i].team != active_team:
			var distance: float = attacker.position.distance_to(models[i].position)
			if distance <= float(fixture.weapon.range_inches) and distance < nearest:
				nearest = distance
				target_index = i
	if target_index < 0:
		message = "射程 %.1f 英寸内没有目标。" % float(fixture.weapon.range_inches)
		queue_redraw()
		return
	var result := Combat.resolve_ranged_attack(fixture.weapon, models[target_index], combat_rng)
	models[target_index].wounds -= int(result.damage)
	var target_name := "底座 %02d" % (target_index + 1)
	if models[target_index].wounds <= 0:
		models.remove_at(target_index)
		selected = -1 if selected == target_index else selected
		message = "%s：命中 %d，造成 %d 点伤害，目标被淘汰。" % [target_name, result.hits, result.damage]
	else:
		message = "%s：命中 %d，造成 %d 点伤害，剩余 %d 伤口。" % [target_name, result.hits, result.damage, models[target_index].wounds]
	queue_redraw()

func to_inches(point: Vector2) -> Vector2:
	return (point - OFFSET) / SCALE

func to_screen(point: Vector2) -> Vector2:
	return OFFSET + point * SCALE

func pick(point: Vector2) -> int:
	for i in range(models.size() - 1, -1, -1):
		if point.distance_to(models[i].position) <= float(models[i].radius):
			return i
	return -1

func preview_reason() -> String:
	var model: Dictionary = models[selected]
	return Rules.movement_reason(model.position, preview, model.spent, float(fixture.movement_inches), model.radius, models, selected)

func finish_drag() -> void:
	if not dragging:
		return
	var reason := preview_reason()
	if reason.is_empty():
		var distance: float = models[selected].position.distance_to(preview)
		var old_position: Vector2 = models[selected].position
		var old_spent: float = models[selected].spent
		models[selected].spent += distance
		models[selected].position = preview
		history.append({"index": selected, "position": old_position, "spent": old_spent})
		message = "本次移动 %.2f 英寸。移动额度按累计值计算。" % distance
	else:
		message = "非法移动：%s。已还原位置。" % display_reason(reason)
	dragging = false
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		dragging = false
		queue_redraw()

func _input(event: InputEvent) -> void:
	# Capture releases even when the mouse is over the sidebar.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and dragging:
		preview = to_inches(get_global_mouse_position()) + drag_offset
		finish_drag()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				dragging = false
				placing = false
				message = "已取消。"
			KEY_P:
				placing = not placing
				dragging = false
			KEY_TAB:
				team = 1 - team
			KEY_N:
				new_phase()
			KEY_R:
				reset_table()
			KEY_T:
				end_turn()
			KEY_U:
				undo_last()
			KEY_SPACE:
				enter_shooting()
			KEY_F:
				fire_selected()
		queue_redraw()
	if event is InputEventMouseMotion:
		preview = to_inches(get_global_mouse_position()) + (drag_offset if dragging else Vector2.ZERO)
		queue_redraw()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var point := to_inches(get_global_mouse_position())
		if placing:
			var reason := Rules.placement_reason(point, Rules.radius_inches(float(fixture.base_diameter_mm)), models)
			if reason.is_empty():
				add_model(point, team)
				selected = models.size() - 1
				message = "已放置 40mm 底座。"
			else:
				message = "非法放置：" + display_reason(reason)
		else:
			selected = pick(point)
			if selected >= 0:
				if models[selected].team != active_team:
					message = "现在轮到%s方，不能操作另一方的底座。" % ("金" if active_team == 0 else "蓝")
					selected = -1
				elif phase != "MOVEMENT":
					message = "已选中底座；射击阶段不能移动。按 F 射击最近目标。"
				else:
					dragging = true
					drag_offset = models[selected].position - point
					preview = models[selected].position
		queue_redraw()

func label_at(point: Vector2, text: String, size_px: int = 16, color: Color = WHITE) -> void:
	draw_string(font, point, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)

func display_reason(reason: String) -> String:
	match reason:
		"MOVE LIMIT EXCEEDED": return "超过移动额度"
		"OUTSIDE TABLE": return "底座超出桌面"
		"BASE OVERLAP": return "底座与其他底座重叠"
	return reason

func _draw() -> void:
	if fixture.is_empty():
		return
	label_at(Vector2(38, 44), "开放战场 / OPEN BATTLE", 28)
	label_at(Vector2(38, 76), "移动实验室     /     60 × 44 英寸桌面     /     40mm 底座", 15, BLUE)
	draw_rect(Rect2(OFFSET, Rules.BOARD_SIZE * SCALE), Color("142832"))
	for x in range(61):
		draw_line(to_screen(Vector2(x, 0)), to_screen(Vector2(x, 44)), Color("36505c") if x % 6 == 0 else Color("1e3540"))
	for y in range(45):
		draw_line(to_screen(Vector2(0, y)), to_screen(Vector2(60, y)), Color("36505c") if y % 6 == 0 else Color("1e3540"))
	draw_rect(Rect2(OFFSET, Rules.BOARD_SIZE * SCALE), BLUE, false, 2)
	for x in range(0, 61, 6):
		label_at(to_screen(Vector2(x, 0)) + Vector2(-5, -10), str(x), 12, BLUE)
	for y in range(6, 45, 6):
		label_at(to_screen(Vector2(0, y)) + Vector2(-26, 4), str(y), 12, BLUE)
	if selected >= 0:
		var model: Dictionary = models[selected]
		var remaining := maxf(0, float(fixture.movement_inches) - float(model.spent))
		draw_arc(to_screen(model.position), remaining * SCALE, 0, TAU, 128, Color(0.9, 0.73, 0.42, 0.4), 1.5, true)
	for i in range(models.size()):
		var model: Dictionary = models[i]
		var center := to_screen(model.position)
		var color := GOLD if model.team == 0 else BLUE
		draw_circle(center, model.radius * SCALE, color.darkened(0.65), true, -1, true)
		draw_arc(center, model.radius * SCALE, 0, TAU, 48, WHITE if i == selected else color, 2, true)
		label_at(center + Vector2(-7, 4), "%02d" % (i + 1), 11, color)
	if dragging:
		var reason := preview_reason()
		var color := BLUE if reason.is_empty() else RED
		draw_line(to_screen(models[selected].position), to_screen(preview), color, 2, true)
		draw_circle(to_screen(preview), models[selected].radius * SCALE, Color(color, 0.4), true, -1, true)
		label_at(to_screen(preview) + Vector2(18, -16), "%.2f 英寸 | %s" % [models[selected].position.distance_to(preview), "合法" if reason.is_empty() else display_reason(reason)], 16, color)
	if placing:
		var radius := Rules.radius_inches(float(fixture.base_diameter_mm))
		var color := GOLD if Rules.placement_reason(preview, radius, models).is_empty() else RED
		draw_arc(to_screen(preview), radius * SCALE, 0, TAU, 48, color, 2, true)
	label_at(Vector2(976, 135), "原型版本 / 00", 19, GOLD)
	label_at(Vector2(976, 178), "Custodian Guard", 23)
	label_at(Vector2(976, 208), "40mm / %.4f 英寸直径" % (40.0 / 25.4), 15)
	label_at(Vector2(976, 240), "移动：%.1f 英寸（测试配置）" % float(fixture.movement_inches), 17, GOLD)
	label_at(Vector2(976, 281), "阵营：" + ("金色" if team == 0 else "蓝色"), 17)
	label_at(Vector2(976, 313), "当前回合：" + ("金色" if active_team == 0 else "蓝色"), 16, GOLD if active_team == 0 else BLUE)
	label_at(Vector2(976, 345), "阶段：" + ("移动" if phase == "MOVEMENT" else "射击"), 16, GOLD if phase == "MOVEMENT" else RED)
	label_at(Vector2(976, 377), "模式：" + ("放置" if placing else "选择 / 拖动"), 16)
	if selected >= 0:
		var spent := float(models[selected].spent)
		if dragging:
			spent += models[selected].position.distance_to(preview)
		label_at(Vector2(976, 417), "底座 %02d：%.2f / %.1f 英寸" % [selected + 1, spent, float(fixture.movement_inches)], 17, RED if spent > float(fixture.movement_inches) + Rules.EPSILON else GOLD)
	label_at(Vector2(976, 824), "移动阶段拖动；射击阶段按 F。", 14)
	label_at(Vector2(38, 812), "本地沙盒 / 尚无完整任务规则", 14, BLUE)
	label_at(Vector2(38, 812), message, 17, RED if "非法" in message else WHITE)
	label_at(Vector2(38, 841), "AGPL-3.0-only  |  非官方社区原型  |  不含官方美术或规则正文", 13, BLUE)

