# SPDX-License-Identifier: AGPL-3.0-only
extends Node
## Opt-in UDP mapping. All blocking router calls stay on one worker thread.
signal status_changed(result: Dictionary)
var status: Dictionary = {"state": "IDLE"}
var worker: Thread
var stop_signal: Semaphore
var closing := false
var generation := 0
var _renew_interval_ms := 300000

func start_mapping(port: int, backend: Object = null) -> String:
	if port < 1024 or port > 65535:
		return "UPNP PORT MUST BE 1024..65535"
	if worker != null:
		return "UPNP BUSY"
	generation += 1
	closing = false
	stop_signal = Semaphore.new()
	worker = Thread.new()
	var error := worker.start(_run.bind(port, backend, stop_signal, generation, _renew_interval_ms))
	if error != OK:
		worker = null
		return "UPNP THREAD FAILED"
	_publish(generation, {"state": "DISCOVERING", "port": port})
	return ""

func stop_mapping() -> void:
	if worker != null and not closing:
		closing = true
		stop_signal.post()
		status = {"state": "CLOSING"}
		status_changed.emit(status.duplicate(true))

func _process(_delta: float) -> void:
	if worker != null and not worker.is_alive():
		var result: Dictionary = worker.wait_to_finish()
		worker = null
		closing = false
		generation += 1
		_publish(generation, result)

func _exit_tree() -> void:
	stop_mapping()
	if worker != null:
		worker.wait_to_finish()
		worker = null

func _publish(token: int, result: Dictionary) -> void:
	if token != generation or closing:
		return
	status = result.duplicate(true)
	status_changed.emit(status.duplicate(true))

func _run(port: int, supplied_backend: Object, stop: Semaphore, token: int, renew_interval_ms: int) -> Dictionary:
	var backend: Object = supplied_backend if supplied_backend != null else UPNP.new()
	var error: int = backend.discover(2000, 2, "InternetGatewayDevice")
	if error != OK:
		return {"state": "ERROR", "step": "discover", "code": error}
	if stop.try_wait():
		return {"state": "CLOSED"}
	var gateway: Object = backend.get_gateway()
	if gateway == null or not gateway.is_valid_gateway():
		return {"state": "ERROR", "step": "gateway"}
	# Finite lease only: no fallback to a permanent router configuration.
	error = gateway.add_port_mapping(port, port, "open-battle", "UDP", 600)
	if error != OK:
		return {"state": "ERROR", "step": "mapping", "code": error}
	var address: String = gateway.query_external_address()
	call_deferred("_publish", token, {"state": "MAPPED", "address": address, "port": port, "lease_seconds": 600})
	var refreshed := Time.get_ticks_msec()
	var renewal_error := 0
	while not stop.try_wait():
		if Time.get_ticks_msec() - refreshed >= renew_interval_ms:
			renewal_error = gateway.add_port_mapping(port, port, "open-battle", "UDP", 600)
			if renewal_error != OK:
				break
			refreshed = Time.get_ticks_msec()
		OS.delay_msec(50)
	var cleanup_error: int = gateway.delete_port_mapping(port, "UDP")
	if cleanup_error != OK:
		return {"state": "ERROR", "step": "cleanup", "code": cleanup_error, "lease_seconds": 600}
	if renewal_error != OK:
		return {"state": "ERROR", "step": "renewal", "code": renewal_error}
	return {"state": "CLOSED"}
