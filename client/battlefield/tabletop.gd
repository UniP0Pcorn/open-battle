# SPDX-License-Identifier: AGPL-3.0-only
extends Node2D

const Rules = preload("res://rules/movement.gd")
const Combat = preload("res://rules/combat.gd")
const Charge = preload("res://rules/charge.gd")
const Melee = preload("res://rules/melee.gd")
const Terrain = preload("res://rules/terrain.gd")
const Visibility = preload("res://rules/visibility.gd")
const Damage = preload("res://rules/damage.gd")
const MissionRules = preload("res://rules/mission.gd")
const ArmyBuilder = preload("res://rules/army_builder.gd")
const UnitMovement = preload("res://rules/unit_movement.gd")
const CommandPoints = preload("res://rules/command_points.gd")
const Stratagems = preload("res://rules/stratagems.gd")
const ArmyValidation = preload("res://rules/army_validation.gd")
const CommandLog = preload("res://rules/command_log.gd")
const ProfileCatalog = preload("res://rules/profile_catalog.gd")
const RosterEditor = preload("res://rules/roster_editor.gd")
const UnitAbilities = preload("res://rules/unit_abilities.gd")
const WeaponRules = preload("res://rules/weapon_rules.gd")
const BattleShock = preload("res://rules/battle_shock.gd")
const TurnState = preload("res://rules/turn_state.gd")
const Deployment = preload("res://rules/deployment.gd")
const MissionValidation = preload("res://rules/mission_validation.gd")
const Dice = preload("res://rules/dice.gd")
const BattleSession = preload("res://rules/battle_session.gd")
const AIPlayer = preload("res://rules/ai_player.gd")
const SCALE := 15.0
const OFFSET := Vector2(38, 112)
const GOLD := Color("e5ba6b")
const BLUE := Color("68b9db")
const RED := Color("ff6d79")
const WHITE := Color("dae5ed")
var fixture: Dictionary
var unit_profile: Dictionary = {}
var roster: Dictionary = {}
var models: Array = []
var selected := -1
var dragging := false
var falling_back := false
var placing := false
var team := 0
var active_team := 0
var history: Array = []
var command_log: Array = []
var phase := "MOVEMENT"
var combat_rng := RandomNumberGenerator.new()
var mission: Dictionary = {}
var objectives: Array = []
var objective_values: Array = []
var terrain: Array = []
var control_radius := 3.0
var score_to_win := 5
var deployment_depth := 12.0
var score: Array = [0, 0]
var command_points: Array = [0, 0]
var reroll_next_attack := false
var preview := Vector2.ZERO
var drag_offset := Vector2.ZERO
var message := "选择底座以查看移动额度。"
var font: Font = ThemeDB.fallback_font
var ready_profile_count := 0
var pending_profile_count := 0
var pending_candidate_count := 0
var ready_profiles: Array = []
var selected_profile_index := 0
var show_roster_panel := false
var selected_weapon_index := 0
var starting_unit_sizes: Dictionary = {}
var turn_state: Dictionary = {}

func _ready() -> void:
	fixture = JSON.parse_string(FileAccess.get_file_as_string("res://data/units/custodian_guard.json"))
	unit_profile = JSON.parse_string(FileAccess.get_file_as_string("res://data/units/custodian_guard_profile.json"))
	ready_profiles = ProfileCatalog.filter(ProfileCatalog.ready_only(ProfileCatalog.load_tree("res://data/units", true)), 11)
	for i in range(ready_profiles.size()):
		if str(ready_profiles[i].get("id", "")) == str(unit_profile.get("id", "")):
			selected_profile_index = i
			break
	sync_profile_weapon()
	roster = JSON.parse_string(FileAccess.get_file_as_string("res://data/armies/prototype_gold.json"))
	var parsed_mission = JSON.parse_string(FileAccess.get_file_as_string("res://data/missions/control_center.json"))
	mission = parsed_mission if parsed_mission is Dictionary else {}
	var mission_errors := MissionValidation.validate(mission)
	if not mission_errors.is_empty():
		message = "任务数据无效：" + str(mission_errors[0])
	if not roster.has("faction") and not str(unit_profile.get("faction", "")).is_empty():
		roster.faction = str(unit_profile.get("faction", ""))
	ready_profile_count = ProfileCatalog.ready_only(ProfileCatalog.load_tree("res://data/units", true)).size()
	var pending_catalog := ProfileCatalog.load_tree("res://data/units/pending", true)
	pending_profile_count = pending_catalog.size()
	for pending_profile in pending_catalog.values():
		pending_candidate_count += int(pending_profile.get("candidate_count", 0))
	control_radius = float(mission.get("control_radius_inches", 3.0))
	score_to_win = int(mission.get("score_to_win", 5))
	deployment_depth = float(mission.get("deployment_depth_inches", 12.0))
	for objective in mission.get("objectives", []):
		objectives.append(Vector2(float(objective.position_inches[0]), float(objective.position_inches[1])))
		objective_values.append(int(objective.get("points", 1)))
	terrain = mission.get("terrain", [])
	combat_rng.seed = 402000
	reset_table()
	add_button("＋ 放置底座  [P]", Vector2(976, 445), func(): placing = not placing; dragging = false; queue_redraw())
	add_button("切换阵营  [TAB]", Vector2(976, 485), func(): team = 1 - team; queue_redraw())
	add_button("新移动阶段  [N]", Vector2(976, 525), new_phase)
	add_button("重置棋盘  [R]", Vector2(976, 565), reset_table)
	add_button("结束回合  [T]", Vector2(976, 605), end_turn)
	add_button("单机 AI 回合  [J]", Vector2(976, 325), run_single_player_ai)
	add_button("联机大厅  [M]", Vector2(976, 365), func(): get_tree().change_scene_to_file("res://client/lobby/lobby_screen.tscn"))
	add_button("撤销移动  [U]", Vector2(976, 645), undo_last)
	add_button("进入射击阶段  [SPACE]", Vector2(976, 685), enter_shooting)
	add_button("射击最近目标  [F]", Vector2(976, 725), fire_selected)
	add_button("进入冲锋阶段  [C]", Vector2(976, 765), enter_charge)
	add_button("进入战斗阶段  [V]", Vector2(976, 805), enter_fight)
	add_button("近战攻击  [X]", Vector2(976, 845), fight_selected)
	add_button("宣布撤退  [Z]", Vector2(976, 885), fall_back_selected)

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
	falling_back = false
	placing = false
	active_team = 0
	history.clear()
	command_log.clear()
	phase = "MOVEMENT"
	score = [0, 0]
	command_points = CommandPoints.new_state()
	reroll_next_attack = false
	starting_unit_sizes.clear()
	turn_state = TurnState.advance(TurnState.new_state(0))
	for side in range(2):
		var profiles: Dictionary = {str(unit_profile.get("id", fixture.get("id", "fixture"))): unit_profile}
		var build := ArmyBuilder.build(roster, profiles, side)
		var model_index := 0
		if build.valid:
			for unit in build.units:
				for unit_model in unit.models:
					var row := model_index / 5
					var column := model_index % 5
					add_model(Vector2(6 + column * 3, 6 + row * 3 + side * 29), side, str(unit.unit_id), unit_model)
					model_index += 1
		else:
			for i in range(10):
				add_model(Vector2(6 + (i % 5) * 3, 6 + (i / 5) * 3 + side * 29), side)
	for model in models:
		var unit_id := str(model.get("unit_id", ""))
		starting_unit_sizes[unit_id] = int(starting_unit_sizes.get(unit_id, 0)) + 1
	message = "20 个底座已就绪。当前为本地移动沙盒。"
	queue_redraw()

func cycle_ready_profile() -> void:
	if ready_profiles.is_empty():
		message = "没有可用的已复核兵牌。"
		queue_redraw()
		return
	selected_profile_index = (selected_profile_index + 1) % ready_profiles.size()
	unit_profile = ready_profiles[selected_profile_index].duplicate(true)
	selected_weapon_index = 0
	sync_profile_weapon()
	fixture = fixture.duplicate(true)
	fixture.id = unit_profile.id
	fixture.display_name = unit_profile.display_name
	fixture.movement_inches = float(unit_profile.models[0].get("movement_inches", fixture.get("movement_inches", 6.0)))
	fixture.wounds = int(unit_profile.models[0].get("wounds", fixture.get("wounds", 3)))
	var built_roster := RosterEditor.create(str(unit_profile.display_name) + " Prototype", int(unit_profile.edition), int(roster.get("points_limit", 1000)))
	built_roster.faction = str(unit_profile.get("faction", ""))
	var add_result := RosterEditor.add_unit(built_roster, {unit_profile.id: unit_profile}, unit_profile.id, 10)
	if add_result.ok:
		roster = add_result.roster
		reset_table()
		message = "已切换可用兵牌：" + str(unit_profile.display_name)
	else:
		message = "兵牌无法加入编成：" + str(add_result.reason)
	queue_redraw()

func sync_profile_weapon() -> void:
	if not unit_profile.get("models", []).is_empty():
		var profile_model: Dictionary = unit_profile.models[0]
		fixture.movement_inches = float(profile_model.get("movement_inches", fixture.get("movement_inches", 6.0)))
		fixture.toughness = int(profile_model.get("toughness", fixture.get("toughness", 5)))
		fixture.wounds = int(profile_model.get("wounds", fixture.get("wounds", 3)))
		fixture.save_on = int(profile_model.get("save_on", fixture.get("save_on", 7)))
		fixture.base_diameter_mm = float(profile_model.get("base_diameter_mm", fixture.get("base_diameter_mm", 40.0)))
		fixture.abilities = unit_profile.get("abilities", [])
	var weapons: Array = unit_profile.get("weapons", [])
	if weapons.is_empty():
		return
	selected_weapon_index = clampi(selected_weapon_index, 0, weapons.size() - 1)
	fixture.weapon = weapons[selected_weapon_index].duplicate(true)

func cycle_profile_weapon() -> void:
	var weapons: Array = unit_profile.get("weapons", [])
	if weapons.is_empty():
		message = "当前 profile 没有可用武器。"
		queue_redraw()
		return
	selected_weapon_index = (selected_weapon_index + 1) % weapons.size()
	sync_profile_weapon()
	message = "已选择武器：" + str(fixture.weapon.get("name", "未命名"))
	queue_redraw()

func weapon_for_model(model: Dictionary) -> Dictionary:
	var weapons: Array = model.get("weapons", [])
	if weapons.is_empty():
		return fixture.weapon.duplicate(true)
	var index := clampi(selected_weapon_index, 0, weapons.size() - 1)
	return weapons[index].duplicate(true)

func adjust_roster_count(delta: int) -> void:
	var units: Array = roster.get("units", [])
	if units.is_empty():
		message = "当前编成没有单位。"
		queue_redraw()
		return
	var current := int(units[0].get("count", 1))
	var profiles := {str(unit_profile.get("id", "")): unit_profile}
	var result := RosterEditor.set_unit_count(roster, profiles, 0, current + delta)
	if not result.ok:
		message = "编成修改失败：" + str(result.reason)
		queue_redraw()
		return
	roster = result.roster
	reset_table()
	message = "当前单位数量：%d，编成 %d 点。" % [current + delta, RosterEditor.total_points(roster)]
	queue_redraw()

func add_roster_entry() -> void:
	var profiles := {str(unit_profile.get("id", "")): unit_profile}
	var result := RosterEditor.add_unit(roster, profiles, str(unit_profile.get("id", "")), 1)
	if not result.ok:
		message = "无法添加单位：" + str(result.reason)
		queue_redraw()
		return
	roster = result.roster
	reset_table()
	message = "已添加 %s，当前军表 %d 点。" % [str(unit_profile.get("display_name", "单位")), RosterEditor.total_points(roster)]
	queue_redraw()

func remove_roster_entry() -> void:
	if roster.get("units", []).size() <= 1:
		message = "军表至少保留一个单位条目。"
		queue_redraw()
		return
	var result := RosterEditor.remove_unit(roster, roster.units.size() - 1)
	if result.ok:
		roster = result.roster
		reset_table()
		message = "已移除最后一个单位条目，当前军表 %d 点。" % RosterEditor.total_points(roster)
	queue_redraw()

func adjust_points_limit(delta: int) -> void:
	var result := RosterEditor.set_points_limit(roster, {str(unit_profile.get("id", "")): unit_profile}, int(roster.get("points_limit", 0)) + delta)
	if not result.ok:
		message = "分数上限修改失败：" + str(result.reason)
		queue_redraw()
		return
	roster = result.roster
	message = "分数上限已调整为 %d 点。" % int(roster.points_limit)
	queue_redraw()

func toggle_roster_panel() -> void:
	show_roster_panel = not show_roster_panel
	queue_redraw()

func save_roster() -> void:
	var file := FileAccess.open("user://open_battle_roster.json", FileAccess.WRITE)
	file.store_string(RosterEditor.encode(roster))
	message = "军表已导出到本机存档。"
	queue_redraw()

func load_roster() -> void:
	if not FileAccess.file_exists("user://open_battle_roster.json"):
		message = "没有找到军表文件。"
		queue_redraw()
		return
	var file := FileAccess.open("user://open_battle_roster.json", FileAccess.READ)
	var imported := RosterEditor.decode(file.get_as_text())
	var validation := RosterEditor.validate(imported, _ready_profile_map())
	if not validation.is_empty():
		message = "军表导入失败：" + str(validation[0])
		queue_redraw()
		return
	roster = imported
	reset_table()
	message = "军表已导入并通过校验。"
	queue_redraw()

func _ready_profile_map() -> Dictionary:
	var profiles: Dictionary = {}
	for profile in ready_profiles:
		profiles[str(profile.get("id", ""))] = profile
	profiles[str(unit_profile.get("id", ""))] = unit_profile
	return profiles

func add_model(point: Vector2, side: int, unit_id: String = "", model_data: Dictionary = {}) -> void:
	if unit_id.is_empty():
		unit_id = "%s_model_%02d" % [str(fixture.get("id", "fixture")), models.size() + 1]
	var model_id := str(model_data.get("model_id", "%s_m%03d" % [unit_id, models.size() + 1]))
	var ability_ids: Array = model_data.get("ability_ids", UnitAbilities.ids_from_profile(unit_profile))
	var ability_mods := UnitAbilities.modifiers(ability_ids)
	var base_mm := float(model_data.get("base_diameter_mm", fixture.get("base_diameter_mm", 40.0)))
	var objective_control := int(model_data.get("objective_control", 1)) + int(ability_mods.objective_control_bonus)
	# Retain movement per model; the current catalogue selection is only a default.
	var movement_inches := float(model_data.get("movement_inches", fixture.get("movement_inches", 6.0)))
	models.append({"model_id": model_id, "position": point, "radius": Rules.radius_inches(base_mm), "spent": 0.0, "advanced": bool(model_data.get("advanced", false)), "advance_bonus": int(model_data.get("advance_bonus", 0)), "fell_back": bool(model_data.get("fell_back", false)), "used_weapon_names": model_data.get("used_weapon_names", []).duplicate(true), "team": side, "wounds": int(model_data.get("wounds", fixture.get("wounds", 3))), "toughness": int(model_data.get("toughness", fixture.get("toughness", 4))), "save_on": int(model_data.get("save_on", fixture.get("save_on", 7))), "invulnerable_save": int(model_data.get("invulnerable_save", fixture.get("invulnerable_save", 0))), "leadership": int(model_data.get("leadership", fixture.get("leadership", 7))), "objective_control": objective_control, "ability_ids": ability_ids, "keywords": model_data.get("keywords", unit_profile.get("keywords", [])).duplicate(true), "faction_keywords": model_data.get("faction_keywords", unit_profile.get("faction_keywords", [])).duplicate(true), "weapons": model_data.get("weapons", unit_profile.get("weapons", [])).duplicate(true), "unit_id": unit_id, "battle_shocked": false, "can_control": true})

	models[-1].movement_inches = movement_inches
	models[-1].coherency_inches = float(model_data.get("coherency_inches", 2.0))

func movement_for_model(model: Dictionary) -> float:
	return float(model.get("movement_inches", fixture.get("movement_inches", 6.0))) + float(model.get("advance_bonus", 0)) if bool(model.get("advanced", false)) else float(model.get("movement_inches", fixture.get("movement_inches", 6.0)))

func selected_unit_remaining_movement() -> float:
	var remaining := INF
	for model in selected_unit_models():
		remaining = minf(remaining, maxf(0.0, movement_for_model(model) - float(model.get("spent", 0.0))))
	return 0.0 if remaining == INF else remaining

func new_phase() -> void:
	dragging = false
	falling_back = false
	for model in models:
		model.spent = 0.0
		model.advanced = false
		model.advance_bonus = 0
		model.fell_back = false
	message = "双方底座的移动额度已重置。"
	queue_redraw()

func advance_selected() -> void:
	if phase != "MOVEMENT":
		message = "请在移动阶段宣布前进。"
		queue_redraw()
		return
	if selected < 0 or selected >= models.size() or models[selected].team != active_team:
		message = "请选择当前阵营的底座。"
		queue_redraw()
		return
	var unit_models := selected_unit_models()
	if unit_models.is_empty():
		message = "没有找到所选单位。"
		queue_redraw()
		return
	if unit_is_engaged(unit_models):
		message = "接战单位不能前进，必须先撤退。"
		queue_redraw()
		return
	for model in unit_models:
		if float(model.get("spent", 0.0)) > Rules.EPSILON or bool(model.get("advanced", false)) or bool(model.get("fell_back", false)):
			message = "该单位已经开始移动，不能再宣布前进。"
			queue_redraw()
			return
	var roll := Dice.roll_d6(combat_rng, 1, 0)
	var unit_id := str(models[selected].get("unit_id", ""))
	for model in unit_models:
		model.advanced = true
		model.advance_bonus = int(roll.total)
	command_log = CommandLog.append(command_log, active_team, "ADVANCE", {"unit_id": unit_id, "roll": int(roll.total), "rolls": roll.rolls})
	message = "单位宣布前进：D6=%d，移动额度增加 %d 英寸；只能使用突击武器射击且不能冲锋。" % [roll.total, roll.total]
	queue_redraw()

func fall_back_selected() -> void:
	if phase != "MOVEMENT":
		message = "请在移动阶段宣布撤退。"
		queue_redraw()
		return
	if selected < 0 or selected >= models.size() or models[selected].team != active_team:
		message = "请选择当前阵营的底座。"
		queue_redraw()
		return
	var unit_models := selected_unit_models()
	if unit_models.is_empty() or not unit_is_engaged(unit_models):
		message = "只有处于接战范围的单位可以撤退。"
		queue_redraw()
		return
	for model in unit_models:
		if float(model.get("spent", 0.0)) > Rules.EPSILON or bool(model.get("advanced", false)) or bool(model.get("fell_back", false)):
			message = "该单位已经开始移动，不能再宣布撤退。"
			queue_redraw()
			return
	falling_back = true
	message = "已宣布撤退：拖动单位离开接战范围；完成后本回合不能射击或冲锋。"
	queue_redraw()

func end_turn() -> void:
	dragging = false
	falling_back = false
	placing = false
	selected = -1
	var scoring_team := active_team
	var gained := score_objectives(scoring_team)
	score[scoring_team] += gained
	active_team = 1 - active_team
	for model in models:
		if int(model.get("team", -1)) == active_team:
			model.spent = 0.0
			model.advanced = false
			model.advance_bonus = 0
			model.fell_back = false
	command_points = CommandPoints.gain(command_points, active_team)
	phase = "MOVEMENT"
	if active_team == 0:
		turn_state.round = int(turn_state.get("round", 1)) + 1
	turn_state.active_team = active_team
	turn_state.phase = "MOVEMENT"
	turn_state.phase_index = TurnState.phase_index("MOVEMENT")
	turn_state.command_points = command_points.duplicate(true)
	command_log = CommandLog.append(command_log, 1 - active_team, "END_TURN", {"score_gained": gained})
	var shock_summary := resolve_battle_shock(active_team)
	message = "得分 +%d。现在轮到%s方。%s" % [gained, "金" if active_team == 0 else "蓝", shock_summary]
	var winning_team := MissionRules.winner(score, score_to_win)
	if winning_team >= 0:
		message = "%s方达到 %d 分，任务完成！" % ["金" if winning_team == 0 else "蓝", score_to_win]
	queue_redraw()

func run_single_player_ai() -> Dictionary:
	if active_team != 1:
		message = "单机模式中，先结束金方回合再让蓝方 AI 行动。"
		queue_redraw()
		return {"ok": false, "reason": "NOT AI TEAM", "state": {}}
	var state := BattleSession.create(models, 11, active_team, terrain)
	if state.is_empty():
		message = "无法创建单机权威会话。"
		queue_redraw()
		return {"ok": false, "reason": "SESSION CREATE FAILED", "state": {}}
	state.round = int(turn_state.get("round", 1))
	state.command_points = command_points.duplicate(true)
	state.command_log = command_log.duplicate(true)
	state.phase = "COMMAND"
	state.phase_index = TurnState.phase_index("COMMAND")
	var ai_result := AIPlayer.play_turn(state, 1, 402000 + int(state.round), 64)
	if not bool(ai_result.get("ok", false)):
		message = "蓝方 AI 回合失败：" + str(ai_result.get("reason", "UNKNOWN"))
		queue_redraw()
		return ai_result
	var next: Dictionary = ai_result.state
	models = next.models.duplicate(true)
	command_log = next.command_log.duplicate(true)
	active_team = int(next.active_team)
	phase = str(next.phase)
	command_points = next.command_points.duplicate(true)
	turn_state = {"round": int(next.round), "active_team": active_team, "phase": phase, "phase_index": int(next.phase_index), "command_points": command_points.duplicate(true)}
	selected = -1
	history.clear()
	message = "蓝方 AI 已完成回合，命令 %d 条。现在轮到金方。" % ai_result.commands.size()
	queue_redraw()
	return ai_result

func resolve_battle_shock(team_id: int) -> String:
	var grouped: Dictionary = {}
	for model in models:
		if int(model.get("team", -1)) != team_id:
			continue
		var unit_id := str(model.get("unit_id", ""))
		if not grouped.has(unit_id):
			grouped[unit_id] = []
		grouped[unit_id].append(model)
	var failed := 0
	for unit_id in grouped:
		var unit_models: Array = grouped[unit_id]
		var starting := int(starting_unit_sizes.get(unit_id, unit_models.size()))
		var result := {"passed": true, "rolls": [], "total": 0}
		if BattleShock.required(unit_models.size(), starting):
			result = BattleShock.test(int(unit_models[0].get("leadership", 7)), combat_rng)
		models = BattleShock.apply_to_models(models, unit_id, result)
		command_log = CommandLog.append(command_log, team_id, "BATTLE_SHOCK", {"unit_id": unit_id, "rolls": result.rolls, "total": result.total, "passed": result.passed})
		if not result.passed:
			failed += 1
	if failed > 0:
		return " %d 个单位战斗震慑。" % failed
	return ""

func score_objectives(team_id: int) -> int:
	var objective_data: Array = []
	for index in range(objectives.size()):
		objective_data.append({"position": objectives[index], "points": int(objective_values[index]) if index < objective_values.size() else 1})
	var scored := MissionRules.score_objectives(objective_data, models, control_radius)
	return int(scored.score[team_id])

func undo_last() -> void:
	if history.is_empty():
		message = "没有可撤销的移动。"
		queue_redraw()
		return
	var change: Dictionary = history.pop_back()
	if change.has("changes"):
		for item in change.changes:
			models[item.index].position = item.position
			models[item.index].spent = item.spent
		selected = int(change.get("selected", -1))
	else:
		models[change.index].position = change.position
		models[change.index].spent = change.spent
		selected = change.index
	message = "已撤销底座 %02d 的上一步移动。" % (selected + 1)
	queue_redraw()

func save_state() -> void:
	var serialized_models: Array = []
	for model in models:
		var saved: Dictionary = model.duplicate(true)
		saved.x = model.position.x
		saved.y = model.position.y
		saved.erase("position")
		serialized_models.append(saved)
	var state := {"active_team": active_team, "phase": phase, "turn_state": turn_state, "score": score, "command_points": command_points, "reroll_next_attack": reroll_next_attack, "roster": roster, "profile_id": str(unit_profile.get("id", "")), "starting_unit_sizes": starting_unit_sizes, "models": serialized_models, "command_log": command_log}
	var file := FileAccess.open("user://open_battle_save.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(state))
	message = "对局已保存。"
	queue_redraw()

func load_state() -> void:
	if not FileAccess.file_exists("user://open_battle_save.json"):
		message = "没有找到保存的对局。"
		queue_redraw()
		return
	var file := FileAccess.open("user://open_battle_save.json", FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		message = "对局加载失败：存档格式无效。"
		queue_redraw()
		return
	var state: Dictionary = parsed
	var saved_log: Array = state.get("command_log", []) if state.get("command_log", []) is Array else []
	var log_error := CommandLog.validate(saved_log)
	if not log_error.is_empty():
		message = "对局加载失败：命令日志%s。" % log_error
		queue_redraw()
		return
	active_team = int(state.get("active_team", 0))
	phase = str(state.get("phase", "MOVEMENT"))
	if active_team not in [0, 1] or TurnState.phase_index(phase) < 0:
		message = "对局加载失败：回合状态无效。"
		queue_redraw()
		return
	turn_state = state.get("turn_state", {}).duplicate(true) if state.get("turn_state", {}) is Dictionary else {}
	if state.has("turn_state") and not TurnState.is_valid(turn_state):
		message = "对局加载失败：版本化回合状态无效。"
		queue_redraw()
		return
	if not TurnState.is_valid(turn_state):
		turn_state = TurnState.advance(TurnState.new_state(active_team))
		turn_state.phase = phase
		turn_state.phase_index = TurnState.phase_index(phase)
	score = state.get("score", [0, 0])
	command_points = state.get("command_points", [0, 0])
	turn_state.command_points = command_points.duplicate(true)
	reroll_next_attack = bool(state.get("reroll_next_attack", false))
	starting_unit_sizes = state.get("starting_unit_sizes", {}).duplicate(true)
	if state.get("roster", {}) is Dictionary and not state.roster.is_empty():
		roster = state.roster
	var saved_profile_id := str(state.get("profile_id", ""))
	for candidate in ready_profiles:
		if str(candidate.get("id", "")) == saved_profile_id:
			unit_profile = candidate.duplicate(true)
			fixture = fixture.duplicate(true)
			fixture.id = unit_profile.id
			fixture.display_name = unit_profile.display_name
			sync_profile_weapon()
			break
	var encoded_log = state.get("command_log_json", "")
	command_log = CommandLog.decode(encoded_log) if encoded_log is String and not encoded_log.is_empty() else []
	if command_log.is_empty() and state.get("command_log", []) is Array:
		command_log = state.get("command_log", [])
	models.clear()
	for saved in state.get("models", []):
		# Old saves lacked model attributes. Build defaults, then restore all saved fields.
		add_model(Vector2(float(saved.x), float(saved.y)), int(saved.team), str(saved.get("unit_id", "unassigned")))
		var restored: Dictionary = saved.duplicate(true)
		restored.erase("x")
		restored.erase("y")
		restored.erase("position")
		models[-1].merge(restored, true)
	selected = -1
	dragging = false
	message = "对局已加载。"
	queue_redraw()

func enter_shooting() -> void:
	if phase != "MOVEMENT":
		return
	dragging = false
	falling_back = false
	placing = false
	var previous_phase := phase
	phase = "SHOOTING"
	turn_state.phase = phase
	turn_state.phase_index = TurnState.phase_index(phase)
	command_log = CommandLog.append(command_log, active_team, "PHASE_ADVANCE", {"from": previous_phase, "to": phase})
	message = "已进入射击阶段。选择底座后按 F 射击最近目标。"
	queue_redraw()

func enter_charge() -> void:
	if phase != "SHOOTING":
		message = "请先完成射击阶段。"
		queue_redraw()
		return
	dragging = false
	placing = false
	var previous_phase := phase
	phase = "CHARGE"
	turn_state.phase = phase
	turn_state.phase_index = TurnState.phase_index(phase)
	command_log = CommandLog.append(command_log, active_team, "PHASE_ADVANCE", {"from": previous_phase, "to": phase})
	message = "已进入冲锋阶段。选择当前阵营底座后按 G 执行冲锋。"
	queue_redraw()

func enter_fight() -> void:
	if phase != "CHARGE":
		message = "请先完成冲锋阶段。"
		queue_redraw()
		return
	dragging = false
	placing = false
	var previous_phase := phase
	phase = "FIGHT"
	turn_state.phase = phase
	turn_state.phase_index = TurnState.phase_index(phase)
	command_log = CommandLog.append(command_log, active_team, "PHASE_ADVANCE", {"from": previous_phase, "to": phase})
	message = "已进入战斗阶段。选择接战底座后按 X 执行近战攻击。"
	queue_redraw()

func use_command_reroll() -> void:
	var result := Stratagems.use(Stratagems.command_reroll(), phase, active_team, command_points)
	if not result.ok:
		message = "指挥重掷失败：" + str(result.reason)
		queue_redraw()
		return
	command_points = result.points
	turn_state.command_points = command_points.duplicate(true)
	reroll_next_attack = true
	command_log = CommandLog.append(command_log, active_team, "STRATAGEM", {"id": "command_reroll", "phase": phase})
	message = "已消耗 1 指挥点：下一次攻击可重掷一次未命中。"
	queue_redraw()

func charge_selected() -> void:
	if phase != "CHARGE":
		message = "请先进入冲锋阶段。"
		queue_redraw()
		return
	if selected < 0 or selected >= models.size() or models[selected].team != active_team:
		message = "请选择当前阵营的底座。"
		queue_redraw()
		return
	var attacker: Dictionary = models[selected]
	var attacker_abilities := UnitAbilities.modifiers(attacker.get("ability_ids", []))
	if bool(attacker.get("advanced", false)) and not bool(attacker_abilities.advance_and_charge):
		message = "前进后的单位不能冲锋。"
		queue_redraw()
		return
	var target_index := -1
	var nearest := INF
	for i in range(models.size()):
		if models[i].team != active_team:
			var distance: float = attacker.position.distance_to(models[i].position)
			if distance < nearest:
				nearest = distance
				target_index = i
	if target_index < 0:
		message = "没有可冲锋的敌方目标。"
		queue_redraw()
		return
	var roll := Charge.charge_distance(combat_rng)
	var target: Dictionary = models[target_index]
	var reason := Charge.target_reason(attacker, target, active_team, nearest, int(roll.distance), 1.0, bool(attacker_abilities.advance_and_charge))
	if not reason.is_empty():
		message = "冲锋失败：%s（2D6=%d）。" % [reason, roll.distance]
		queue_redraw()
		return
	var direction: Vector2 = (target.position - attacker.position).normalized()
	var destination: Vector2 = target.position - direction * (attacker.radius + target.radius + 1.0)
	var move_reason := Rules.movement_reason(attacker.position, destination, 0.0, float(roll.distance), attacker.radius, models, selected)
	if not move_reason.is_empty():
		message = "冲锋落点非法：%s。" % display_reason(move_reason)
		queue_redraw()
		return
	var old_position: Vector2 = attacker.position
	attacker.position = destination
	command_log = CommandLog.append(command_log, active_team, "CHARGE", {"model": selected, "model_id": attacker.get("model_id", ""), "target": target_index, "target_id": target.get("model_id", ""), "roll": roll.rolls, "from": [old_position.x, old_position.y], "to": [destination.x, destination.y]})
	message = "冲锋成功：2D6=%d，已进入接战距离。" % roll.distance
	queue_redraw()

func fight_selected() -> void:
	if phase != "FIGHT":
		message = "请先进入战斗阶段。"
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
			if Melee.target_reason(attacker, models[i], active_team).is_empty() and distance < nearest:
				nearest = distance
				target_index = i
	if target_index < 0:
		message = "接战距离内没有敌方目标。"
		queue_redraw()
		return
	var attacker_abilities := UnitAbilities.modifiers(attacker.get("ability_ids", []))
	var weapon := weapon_for_model(attacker)
	var weapon_ids := WeaponRules.ids_from_weapon(weapon)
	var weapon_name := str(weapon.get("name", ""))
	if weapon_ids.has("one_shot") and attacker.get("used_weapon_names", []).has(weapon_name):
		message = "一次性武器已经使用过。"
		queue_redraw()
		return
	var result := Melee.resolve_attack(weapon, models[target_index], combat_rng, (1 if reroll_next_attack else 0) + int(attacker_abilities.hit_rerolls), models[target_index].get("keywords", []), attacker_abilities)
	reroll_next_attack = false
	if weapon_ids.has("one_shot") and not attacker.get("used_weapon_names", []).has(weapon_name):
		attacker.used_weapon_names.append(weapon_name)
	var damage_result := Damage.allocate_to_unit(models, int(result.damage), target_index, combat_rng)
	var fight_payload := {"attacker": selected, "attacker_id": attacker.get("model_id", ""), "target": target_index, "target_id": models[target_index].get("model_id", ""), "weapon": weapon_name, "one_shot": weapon_ids.has("one_shot"), "hits": result.hits, "damage": result.damage}
	if not damage_result.feel_no_pain_rolls.is_empty():
		fight_payload.feel_no_pain_rolls = damage_result.feel_no_pain_rolls
	command_log = CommandLog.append(command_log, active_team, "FIGHT", fight_payload)
	if int(damage_result.destroyed) > 0:
		selected = -1 if selected == target_index else selected
		message = "近战命中 %d，造成 %d 点伤害，目标被淘汰。" % [result.hits, result.damage]
	else:
		message = "近战命中 %d，造成 %d 点伤害，目标剩余 %d 伤口。" % [result.hits, result.damage, damage_result.wounds_after]
	queue_redraw()

func model_is_engaged_with_enemy(model: Dictionary) -> bool:
	for other in models:
		if int(other.get("team", -1)) == int(model.get("team", -1)):
			continue
		if Melee.target_reason(model, other, int(model.get("team", -1))).is_empty():
			return true
	return false

func unit_is_engaged(unit_models: Array) -> bool:
	for model in unit_models:
		if model_is_engaged_with_enemy(model):
			return true
	return false

func engagement_reason_for_delta(unit_models: Array, delta: Vector2, reason: String) -> String:
	for model in unit_models:
		var moved_model: Dictionary = model.duplicate(true)
		moved_model.position = model.position + delta
		for enemy in models:
			if int(enemy.get("team", -1)) == int(model.get("team", -1)):
				continue
			if Melee.target_reason(moved_model, enemy, int(model.get("team", -1))).is_empty():
				return reason
	return ""

func fall_back_reason(unit_models: Array, delta: Vector2) -> String:
	if not unit_is_engaged(unit_models):
		return "UNIT NOT ENGAGED"
	var movement_error := UnitMovement.movement_reason(unit_models, delta, float(unit_models[0].get("spent", 0.0)), movement_for_model(unit_models[0]), models, terrain)
	if not movement_error.is_empty():
		return movement_error
	return engagement_reason_for_delta(unit_models, delta, "FALL BACK MUST END OUT OF ENGAGEMENT")

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
	var weapon := weapon_for_model(attacker)
	var attacker_engaged := model_is_engaged_with_enemy(attacker)
	var weapon_ids := WeaponRules.ids_from_weapon(weapon)
	var weapon_name := str(weapon.get("name", ""))
	if weapon_ids.has("one_shot") and attacker.get("used_weapon_names", []).has(weapon_name):
		message = "一次性武器已经使用过。"
		queue_redraw()
		return
	var target_index := -1
	var nearest := INF
	var target_has_line_of_sight := true
	for i in range(models.size()):
		if models[i].team != active_team:
			var distance: float = attacker.position.distance_to(models[i].position)
			var has_line_of_sight := not Visibility.blocked(attacker.position, models[i].position, terrain)
			if not has_line_of_sight and not WeaponRules.ids_from_weapon(weapon).has("indirect"):
				continue
			var target_engaged := model_is_engaged_with_enemy(models[i])
			if Combat.target_reason(attacker, models[i], distance, weapon, active_team, attacker_engaged, target_engaged).is_empty() and distance < nearest:
				nearest = distance
				target_index = i
				target_has_line_of_sight = has_line_of_sight
	if target_index < 0:
		message = "射程 %.1f 英寸内没有目标。" % float(weapon.range_inches)
		queue_redraw()
		return
	var target_for_attack: Dictionary = models[target_index].duplicate(true)
	var target_abilities := UnitAbilities.modifiers(target_for_attack.get("ability_ids", []))
	var cover_bonus := Visibility.cover_bonus(attacker.position, target_for_attack.position, terrain) + int(target_abilities.cover_bonus)
	var target_unit_id := str(target_for_attack.get("unit_id", ""))
	var target_models := 0
	for model in models:
		if str(model.get("unit_id", "")) == target_unit_id:
			target_models += 1
	var weapon_context := WeaponRules.context(weapon, nearest, cover_bonus, target_models, target_for_attack.get("keywords", []), is_zero_approx(float(attacker.get("spent", 0.0))), target_has_line_of_sight)
	target_for_attack.cover_save_bonus = int(weapon_context.cover_bonus)
	var attacker_abilities := UnitAbilities.modifiers(attacker.get("ability_ids", []))
	var result := Combat.resolve_ranged_attack(weapon_context.weapon, target_for_attack, combat_rng, (1 if reroll_next_attack else 0) + int(attacker_abilities.hit_rerolls), attacker_abilities)
	reroll_next_attack = false
	if weapon_ids.has("one_shot") and not attacker.get("used_weapon_names", []).has(weapon_name):
		attacker.used_weapon_names.append(weapon_name)
	var damage_result := Damage.allocate_to_unit(models, int(result.damage), target_index, combat_rng)
	var shoot_payload := {"attacker": selected, "attacker_id": attacker.get("model_id", ""), "target": target_index, "target_id": models[target_index].get("model_id", ""), "weapon": weapon_name, "one_shot": weapon_ids.has("one_shot"), "hits": result.hits, "damage": result.damage}
	if not damage_result.feel_no_pain_rolls.is_empty():
		shoot_payload.feel_no_pain_rolls = damage_result.feel_no_pain_rolls
	command_log = CommandLog.append(command_log, active_team, "SHOOT", shoot_payload)
	var hazardous_damage := int(result.hazardous_failures) * int(weapon_context.weapon.get("hazardous_damage", 3))
	var hazardous_result := {"destroyed": 0, "damage": 0}
	if hazardous_damage > 0 and selected >= 0 and selected < models.size():
		hazardous_result = Damage.allocate_to_unit(models, hazardous_damage, selected, combat_rng)
		var hazardous_payload := {"attacker": selected, "attacker_id": attacker.get("model_id", ""), "damage": hazardous_damage}
		if not hazardous_result.feel_no_pain_rolls.is_empty():
			hazardous_payload.feel_no_pain_rolls = hazardous_result.feel_no_pain_rolls
		command_log = CommandLog.append(command_log, active_team, "HAZARDOUS", hazardous_payload)
	var target_name := "底座 %02d" % (target_index + 1)
	if int(hazardous_result.destroyed) > 0:
		selected = -1
		message = "%s：危险武器失效，自身受到 %d 点伤害并被淘汰。" % [target_name, hazardous_damage]
	elif int(damage_result.destroyed) > 0:
		selected = -1 if selected == target_index else selected
		message = "%s：命中 %d，造成 %d 点伤害，目标被淘汰。" % [target_name, result.hits, result.damage]
	else:
		message = "%s：命中 %d，造成 %d 点伤害，剩余 %d 伤口。" % [target_name, result.hits, result.damage, damage_result.wounds_after]
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
	var unit_models := selected_unit_models()
	if falling_back:
		return fall_back_reason(unit_models, preview - model.position)
	for unit_model in unit_models:
		if bool(unit_model.get("fell_back", false)):
			return "FELL BACK"
	if unit_models.size() > 1:
		var unit_move_error := UnitMovement.movement_reason(unit_models, preview - model.position, model.spent, movement_for_model(model), models, terrain)
		if not unit_move_error.is_empty():
			return unit_move_error
		return engagement_reason_for_delta(unit_models, preview - model.position, "CANNOT END IN ENGAGEMENT")
	if unit_is_engaged(unit_models):
		return "ENGAGED UNIT MUST FALL BACK"
	var move_error := Rules.movement_reason(model.position, preview, model.spent, movement_for_model(model), model.radius, models, selected, terrain)
	if not move_error.is_empty():
		return move_error
	return engagement_reason_for_delta(unit_models, preview - model.position, "CANNOT END IN ENGAGEMENT")

func selected_unit_models() -> Array:
	if selected < 0 or selected >= models.size():
		return []
	var unit_id := str(models[selected].get("unit_id", ""))
	var unit_models: Array = []
	for model in models:
		if str(model.get("unit_id", "")) == unit_id:
			unit_models.append(model)
	return unit_models

func finish_drag() -> void:
	if not dragging:
		return
	var reason := preview_reason()
	if reason.is_empty():
		var unit_models := selected_unit_models()
		var distance: float = models[selected].position.distance_to(preview)
		var delta: Vector2 = preview - models[selected].position
		var changes: Array = []
		for index in range(models.size()):
			if unit_models.has(models[index]):
				changes.append({"index": index, "position": models[index].position, "spent": models[index].spent})
				models[index].spent += distance
				models[index].position += delta
		history.append({"changes": changes, "selected": selected})
		var move_kind := "FALL_BACK" if falling_back else "MOVE"
		if falling_back:
			for moved_model in unit_models:
				moved_model.fell_back = true
		command_log = CommandLog.append(command_log, active_team, move_kind, {"unit_id": models[selected].unit_id, "model": selected, "model_id": models[selected].get("model_id", ""), "delta": [delta.x, delta.y], "distance": distance})
		message = ("撤退 %.2f 英寸，单位本回合不能射击或冲锋。" if falling_back else "本次移动 %.2f 英寸。移动额度按累计值计算。") % distance
		falling_back = false
	else:
		message = "非法移动：%s。已还原位置。" % display_reason(reason)
		falling_back = false
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
			KEY_I:
				cycle_ready_profile()
			KEY_MINUS:
				adjust_roster_count(-1)
			KEY_EQUAL:
				adjust_roster_count(1)
			KEY_A:
				add_roster_entry()
			KEY_D:
				remove_roster_entry()
			KEY_COMMA:
				adjust_points_limit(-100)
			KEY_PERIOD:
				adjust_points_limit(100)
			KEY_B:
				toggle_roster_panel()
			KEY_W:
				cycle_profile_weapon()
			KEY_K:
				save_roster()
			KEY_O:
				load_roster()
			KEY_ESCAPE:
				dragging = false
				falling_back = false
				placing = false
				message = "已取消。"
			KEY_P:
				placing = not placing
				dragging = false
			KEY_TAB:
				team = 1 - team
			KEY_N:
				new_phase()
			KEY_Q:
				advance_selected()
			KEY_Z:
				fall_back_selected()
			KEY_R:
				reset_table()
			KEY_T:
				end_turn()
			KEY_J:
				run_single_player_ai()
			KEY_M:
				get_tree().change_scene_to_file("res://client/lobby/lobby_screen.tscn")
			KEY_U:
				undo_last()
			KEY_SPACE:
				enter_shooting()
			KEY_C:
				enter_charge()
			KEY_G:
				charge_selected()
			KEY_V:
				enter_fight()
			KEY_X:
				fight_selected()
			KEY_Y:
				use_command_reroll()
			KEY_F:
				fire_selected()
			KEY_S:
				save_state()
			KEY_L:
				load_state()
		queue_redraw()
	if event is InputEventMouseMotion:
		preview = to_inches(get_global_mouse_position()) + (drag_offset if dragging else Vector2.ZERO)
		queue_redraw()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var point := to_inches(get_global_mouse_position())
		if placing:
			var reason := Deployment.placement_reason(point, Rules.radius_inches(float(fixture.base_diameter_mm)), team, models, -1, deployment_depth)
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
		"PATH BLOCKED": return "移动路径被其他底座阻挡"
		"OUTSIDE DEPLOYMENT ZONE": return "超出当前阵营部署区"
		"INVALID DEPLOYMENT ZONE": return "任务部署区配置无效"
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
	draw_line(to_screen(Vector2(0, deployment_depth)), to_screen(Vector2(Rules.BOARD_SIZE.x, deployment_depth)), Color(0.9, 0.72, 0.35, 0.55), 2)
	draw_line(to_screen(Vector2(0, Rules.BOARD_SIZE.y - deployment_depth)), to_screen(Vector2(Rules.BOARD_SIZE.x, Rules.BOARD_SIZE.y - deployment_depth)), Color(0.4, 0.72, 0.9, 0.55), 2)
	label_at(to_screen(Vector2(1, deployment_depth)) + Vector2(0, -6), "金方部署区", 12, GOLD)
	label_at(to_screen(Vector2(1, Rules.BOARD_SIZE.y - deployment_depth)) + Vector2(0, 16), "蓝方部署区", 12, BLUE)
	for x in range(0, 61, 6):
		label_at(to_screen(Vector2(x, 0)) + Vector2(-5, -10), str(x), 12, BLUE)
	for y in range(6, 45, 6):
		label_at(to_screen(Vector2(0, y)) + Vector2(-26, 4), str(y), 12, BLUE)
	for i in range(objectives.size()):
		var objective_screen := to_screen(objectives[i])
		draw_circle(objective_screen, control_radius * SCALE, Color(0.95, 0.78, 0.28, 0.12), true)
		draw_arc(objective_screen, control_radius * SCALE, 0, TAU, 64, GOLD, 2, true)
		label_at(objective_screen + Vector2(-14, 5), "目标 %d" % (i + 1), 12, GOLD)
	for obstacle in terrain:
		var terrain_rect := Terrain.rect(obstacle)
		draw_rect(Rect2(to_screen(terrain_rect.position), terrain_rect.size * SCALE), Color("4f5963"), true)
		draw_rect(Rect2(to_screen(terrain_rect.position), terrain_rect.size * SCALE), Color("9ca9b5"), false, 2)
	if selected >= 0:
		var model: Dictionary = models[selected]
		var remaining := selected_unit_remaining_movement()
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
		var color := GOLD if Deployment.placement_reason(preview, radius, team, models, -1, deployment_depth).is_empty() else RED
		draw_arc(to_screen(preview), radius * SCALE, 0, TAU, 48, color, 2, true)
	label_at(Vector2(976, 135), "原型版本 / 00", 19, GOLD)
	label_at(Vector2(976, 160), "任务：" + str(mission.get("display_name", "未命名")), 15)
	label_at(Vector2(976, 178), str(unit_profile.get("display_name", "未选择兵牌")), 23)
	label_at(Vector2(976, 202), "编成：%d / %d 点" % [ArmyValidation.total_points(roster), int(roster.get("points_limit", 0))], 14)
	label_at(Vector2(976, 220), "兵牌：%d 可用 / %d 来源待复核" % [ready_profile_count, pending_profile_count], 14, BLUE)
	label_at(Vector2(976, 240), "候选记录：%d 条（均需人工审核）" % pending_candidate_count, 13, BLUE)
	label_at(Vector2(976, 236), "单位条目：%d（A 添加 / D 移除）" % roster.get("units", []).size(), 13, BLUE)
	label_at(Vector2(976, 248), "40mm / %.4f 英寸直径" % (40.0 / 25.4), 15)
	label_at(Vector2(976, 264), "武器：" + str(fixture.get("weapon", {}).get("name", "未选择")), 14, GOLD)
	var displayed_movement := movement_for_model(models[selected]) if selected >= 0 else float(fixture.movement_inches)
	label_at(Vector2(976, 280), "移动：%.1f 英寸" % displayed_movement, 17, GOLD)
	label_at(Vector2(976, 313), "阵营：" + ("金色" if team == 0 else "蓝色"), 17)
	label_at(Vector2(976, 345), "比分：金 %d  :  %d 蓝" % [score[0], score[1]], 16, GOLD)
	label_at(Vector2(976, 377), "当前回合：" + ("金色" if active_team == 0 else "蓝色"), 16, GOLD if active_team == 0 else BLUE)
	var phase_name: String = str({"MOVEMENT": "移动", "SHOOTING": "射击", "CHARGE": "冲锋", "FIGHT": "战斗"}.get(phase, phase))
	label_at(Vector2(976, 409), "阶段：" + phase_name, 16, GOLD if phase == "MOVEMENT" else RED)
	label_at(Vector2(976, 441), "模式：" + ("放置" if placing else "选择 / 拖动"), 16)
	if selected >= 0:
		var spent := float(models[selected].spent)
		if dragging:
			spent += models[selected].position.distance_to(preview)
		label_at(Vector2(976, 473), "底座 %02d：%.2f / %.1f 英寸" % [selected + 1, spent, displayed_movement], 17, RED if spent > displayed_movement + Rules.EPSILON else GOLD)
	label_at(Vector2(976, 824), "I 兵牌；- / = 数量；, / . 上限。", 14)
	label_at(Vector2(38, 812), "本地沙盒 / 尚无完整任务规则", 14, BLUE)
	label_at(Vector2(38, 812), message, 17, RED if "非法" in message else WHITE)
	label_at(Vector2(38, 841), "AGPL-3.0-only  |  非官方社区原型  |  不含官方美术或规则正文", 13, BLUE)
	if show_roster_panel:
		draw_rect(Rect2(760, 108, 500, 330), Color("101b25e8"), true)
		draw_rect(Rect2(760, 108, 500, 330), BLUE, false, 2)
		label_at(Vector2(780, 140), "编成详情 / ROSTER", 22, GOLD)
		label_at(Vector2(780, 166), "版本 %s   总分 %d / %d" % [str(roster.get("edition", "?")), RosterEditor.total_points(roster), int(roster.get("points_limit", 0))], 15)
		var roster_errors := RosterEditor.validate(roster, {str(unit_profile.get("id", "")): unit_profile})
		label_at(Vector2(780, 190), "校验：" + ("通过" if roster_errors.is_empty() else str(roster_errors[0])), 15, GOLD if roster_errors.is_empty() else RED)
		var row := 220
		for index in range(roster.get("units", []).size()):
			var entry: Dictionary = roster.units[index]
			label_at(Vector2(780, row), "%02d  %s  ×%d  (%d点)" % [index + 1, str(entry.get("unit_id", "未知")), int(entry.get("count", 0)), int(entry.get("points_each", 0))], 14)
			row += 24
		label_at(Vector2(780, 416), "B 关闭面板", 13, BLUE)
