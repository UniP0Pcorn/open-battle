# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## In-memory index for versioned unit profiles.

const DatasheetValidation = preload("res://rules/datasheet_validation.gd")

static func build(profiles: Array) -> Dictionary:
	var by_id := {}
	for profile in profiles:
		var profile_id := str(profile.get("id", ""))
		if not profile_id.is_empty():
			by_id[profile_id] = profile
	return by_id

static func filter(profiles: Dictionary, edition: int = 0, faction: String = "") -> Array:
	var result: Array = []
	for profile in profiles.values():
		if edition > 0 and int(profile.get("edition", 0)) != edition:
			continue
		if not faction.is_empty() and str(profile.get("faction", "")) != faction:
			continue
		result.append(profile)
	result.sort_custom(func(a, b): return str(a.get("display_name", "")) < str(b.get("display_name", "")))
	return result

static func is_ready(profile: Dictionary) -> bool:
	var status := str(profile.get("import_status", "ready"))
	return status in ["ready", "verified", "prototype"] and DatasheetValidation.validate_profile(profile).is_empty()

static func ready_only(profiles: Dictionary) -> Dictionary:
	var result := {}
	for profile_id in profiles:
		if is_ready(profiles[profile_id]):
			result[profile_id] = profiles[profile_id]
	return result

static func load_directory(path: String, include_pending: bool = true) -> Dictionary:
	var loaded: Array = []
	var directory := DirAccess.open(path)
	if directory == null:
		return {}
	for filename in directory.get_files():
		if not filename.ends_with(".json"):
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path.path_join(filename)))
		if parsed is Dictionary and parsed.has("edition") and parsed.has("models"):
			if not include_pending and not is_ready(parsed):
				continue
			loaded.append(parsed)
	return build(loaded)

static func load_tree(path: String, include_pending: bool = true) -> Dictionary:
	var loaded := load_directory(path, include_pending)
	var directory := DirAccess.open(path)
	if directory == null:
		return loaded
	for child in directory.get_directories():
		var nested := load_tree(path.path_join(child), include_pending)
		for profile_id in nested:
			loaded[profile_id] = nested[profile_id]
	return loaded
