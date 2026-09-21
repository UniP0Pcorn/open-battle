# SPDX-License-Identifier: AGPL-3.0-only
extends Node2D

const Rules = preload("res://rules/movement.gd")
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
var preview := Vector2.ZERO
var drag_offset := Vector2.ZERO
var message := "Select a base to inspect its move budget."
var font: Font = ThemeDB.fallback_font

func _ready() -> void:
	fixture = JSON.parse_string(FileAccess.get_file_as_string("res://data/units/custodian_guard.json"))
	reset_table()
	add_button("+ PLACE BASE  [P]", Vector2(976, 425), func(): placing = not placing; dragging = false; queue_redraw())
	add_button("SWITCH SIDE  [TAB]", Vector2(976, 477), func(): team = 1 - team; queue_redraw())
	add_button("NEW MOVE PHASE  [N]", Vector2(976, 529), new_phase)
	add_button("RESET TABLE  [R]", Vector2(976, 581), reset_table)

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
	for side in range(2):
		for i in range(10):
			add_model(Vector2(6 + (i % 5) * 3, 6 + (i / 5) * 3 + side * 29), side)
	message = "20 bases ready. Local movement sandbox."
	queue_redraw()

func add_model(point: Vector2, side: int) -> void:
	models.append({"position": point, "radius": Rules.radius_inches(float(fixture.base_diameter_mm)), "spent": 0.0, "team": side})

func new_phase() -> void:
	dragging = false
	for model in models:
		model.spent = 0.0
	message = "Movement budgets reset for both sides."
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
		models[selected].spent += distance
		models[selected].position = preview
		message = "Moved %.2f in. Budget is cumulative." % distance
	else:
		message = "ILLEGAL: %s. Move reverted." % reason
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
				message = "Cancelled."
			KEY_P:
				placing = not placing
				dragging = false
			KEY_TAB:
				team = 1 - team
			KEY_N:
				new_phase()
			KEY_R:
				reset_table()
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
				message = "Placed a 40 mm base."
			else:
				message = "ILLEGAL PLACEMENT: " + reason
		else:
			selected = pick(point)
			if selected >= 0:
				dragging = true
				drag_offset = models[selected].position - point
				preview = models[selected].position
		queue_redraw()

func label_at(point: Vector2, text: String, size_px: int = 16, color: Color = WHITE) -> void:
	draw_string(font, point, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)

func _draw() -> void:
	if fixture.is_empty():
		return
	label_at(Vector2(38, 44), "OPEN / BATTLE", 28)
	label_at(Vector2(38, 76), "MOVEMENT LAB     /     60 x 44 INCH TABLE     /     40 MM BASES", 15, BLUE)
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
		label_at(to_screen(preview) + Vector2(18, -16), "%.2f in | %s" % [models[selected].position.distance_to(preview), "LEGAL" if reason.is_empty() else reason], 16, color)
	if placing:
		var radius := Rules.radius_inches(float(fixture.base_diameter_mm))
		var color := GOLD if Rules.placement_reason(preview, radius, models).is_empty() else RED
		draw_arc(to_screen(preview), radius * SCALE, 0, TAU, 48, color, 2, true)
	label_at(Vector2(976, 135), "PROTOTYPE / 00", 19, GOLD)
	label_at(Vector2(976, 178), "Custodian Guard", 23)
	label_at(Vector2(976, 208), "40 mm / %.4f in diameter" % (40.0 / 25.4), 15)
	label_at(Vector2(976, 240), "Move: %.1f in (test fixture)" % float(fixture.movement_inches), 17, GOLD)
	label_at(Vector2(976, 281), "Side: " + ("GOLD" if team == 0 else "BLUE"), 17)
	label_at(Vector2(976, 313), "Mode: " + ("PLACE" if placing else "SELECT / DRAG"), 16)
	if selected >= 0:
		var spent := float(models[selected].spent)
		if dragging:
			spent += models[selected].position.distance_to(preview)
		label_at(Vector2(976, 353), "Base %02d: %.2f / %.1f in" % [selected + 1, spent, float(fixture.movement_inches)], 17, RED if spent > float(fixture.movement_inches) + Rules.EPSILON else GOLD)
	label_at(Vector2(976, 664), "Drag to move. Esc cancels.", 15)
	label_at(Vector2(976, 690), "Red = illegal; release reverts.", 15)
	label_at(Vector2(976, 716), "1 grid square = 1 inch.", 15)
	label_at(Vector2(976, 752), "Local sandbox / no turn rules", 14, BLUE)
	label_at(Vector2(38, 812), message, 17, RED if "ILLEGAL" in message else WHITE)
	label_at(Vector2(38, 841), "AGPL-3.0-only  |  Unofficial community prototype  |  No official artwork or rules text", 13, BLUE)
