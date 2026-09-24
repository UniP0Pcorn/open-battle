# SPDX-License-Identifier: AGPL-3.0-only
extends Control
## Minimal usable lobby UI around P2PLobby.

const AccountIdentity = preload("res://rules/account_identity.gd")
const AccountStore = preload("res://rules/account_store.gd")
const P2PLobby = preload("res://client/p2p_lobby.gd")

var lobby: Node
var account_id: LineEdit
var password: LineEdit
var room_id: LineEdit
var address: LineEdit
var port: SpinBox
var status: Label
var ready_button: Button

func _ready() -> void:
	_build_ui()
	lobby = P2PLobby.new()
	add_child(lobby)
	lobby.lobby_changed.connect(_on_lobby_changed)
	lobby.error_occurred.connect(_on_error)
	var saved := AccountStore.load_identity()
	if not saved.is_empty():
		account_id.text = str(saved.account_id)
		status.text = "已加载本机账号：" + str(saved.account_id)

func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("101b25")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var panel := VBoxContainer.new()
	panel.position = Vector2(90, 60)
	panel.size = Vector2(560, 650)
	add_child(panel)
	var title := Label.new()
	title.text = "OPEN BATTLE / P2P 联机大厅"
	title.add_theme_font_size_override("font_size", 28)
	panel.add_child(title)
	panel.add_child(_label("账号 ID"))
	account_id = _line("player@example.com")
	panel.add_child(account_id)
	panel.add_child(_label("密码（只用于本机派生凭据，不会保存明文）"))
	password = _line("")
	password.secret = true
	panel.add_child(password)
	var account_row := HBoxContainer.new()
	var create_account := Button.new()
	create_account.text = "创建/保存本机账号"
	create_account.pressed.connect(_create_account)
	account_row.add_child(create_account)
	panel.add_child(account_row)
	panel.add_child(_label("房间 ID"))
	room_id = _line("room-001")
	panel.add_child(room_id)
	panel.add_child(_label("对端地址（加入房间时使用）"))
	address = _line("127.0.0.1")
	panel.add_child(address)
	panel.add_child(_label("端口"))
	port = SpinBox.new()
	port.min_value = 1
	port.max_value = 65535
	port.value = 24567
	panel.add_child(port)
	var room_row := HBoxContainer.new()
	var host_button := Button.new()
	host_button.text = "创建主机房间"
	host_button.pressed.connect(_host_room)
	room_row.add_child(host_button)
	var join_button := Button.new()
	join_button.text = "加入房间"
	join_button.pressed.connect(_join_room)
	room_row.add_child(join_button)
	ready_button = Button.new()
	ready_button.text = "准备"
	ready_button.disabled = true
	ready_button.pressed.connect(_ready_room)
	room_row.add_child(ready_button)
	panel.add_child(room_row)
	status = Label.new()
	status.text = "先创建或加载账号。P2P 主机需要把对端身份加入信任目录。"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(status)
	var back := Button.new()
	back.text = "返回桌面"
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://client/battlefield/tabletop.tscn"))
	panel.add_child(back)

func _create_account() -> void:
	var identity := AccountIdentity.create(account_id.text, password.text, account_id.text)
	if identity.is_empty():
		status.text = "账号 ID 和密码不能为空。"
		return
	var error := AccountStore.save_identity(identity)
	if not error.is_empty():
		status.text = error
		return
	var set_error: String = lobby.set_identity(identity)
	status.text = "账号已保存。" if set_error.is_empty() else set_error

func _ensure_identity() -> bool:
	var identity := AccountStore.load_identity()
	if identity.is_empty():
		var created := AccountIdentity.create(account_id.text, password.text, account_id.text)
		if created.is_empty():
			status.text = "请先创建账号或填写账号与密码。"
			return false
		identity = created
	return lobby.set_identity(identity).is_empty()

func _host_room() -> void:
	if not _ensure_identity():
		return
	var error: String = lobby.host_room(room_id.text, int(port.value))
	status.text = "主机已启动：" + room_id.text if error.is_empty() else error
	ready_button.disabled = error != ""

func _join_room() -> void:
	if not _ensure_identity():
		return
	var error: String = lobby.connect_to_room(room_id.text, address.text, int(port.value))
	status.text = "正在连接……" if error.is_empty() else error

func _ready_room() -> void:
	var error: String = lobby.set_ready(true)
	status.text = "已准备。" if error.is_empty() else error

func _on_lobby_changed(room: Dictionary) -> void:
	ready_button.disabled = false
	status.text = "房间 %s：%d/2 名玩家。" % [str(room.get("id", "")), room.get("players", []).size()]

func _on_error(reason: String) -> void:
	status.text = "网络错误：" + reason

func _label(value: String) -> Label:
	var label := Label.new()
	label.text = value
	return label

func _line(placeholder: String) -> LineEdit:
	var line := LineEdit.new()
	line.placeholder_text = placeholder
	return line
