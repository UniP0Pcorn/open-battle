# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Validation for external PDF/data source manifests.

static func validate(manifest: Dictionary) -> String:
	if int(manifest.get("schema_version", 0)) < 1:
		return "INVALID SCHEMA VERSION"
	var ids := {}
	for source in manifest.get("sources", []):
		var source_id := str(source.get("id", ""))
		if source_id.is_empty() or ids.has(source_id):
			return "DUPLICATE OR EMPTY SOURCE ID"
		ids[source_id] = true
		if not source.has("filename") or not source.has("edition") or not source.has("status"):
			return "INCOMPLETE SOURCE " + source_id
	return ""
