extends SceneTree
## Plain test runner. Loads every res://tests/test_*.gd, instantiates it and
## calls each method whose name starts with "test_". Exit code 1 on failure.
## Run:  godot --headless --script res://tests/run_tests.gd
## (run `godot --headless --import` once first so class_name lookups resolve)


func _init() -> void:
	var filter := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--filter="):
			filter = a.trim_prefix("--filter=")
	var total_pass := 0
	var total_tests := 0
	var all_failures: Array[String] = []
	var files: Array[String] = []
	var dir := DirAccess.open("res://tests")
	if dir != null:
		dir.list_dir_begin()
		var f := dir.get_next()
		while f != "":
			if f.begins_with("test_") and f.ends_with(".gd") and f != "test_case.gd":
				files.append(f)
			f = dir.get_next()
		dir.list_dir_end()
	files.sort()
	var t0 := Time.get_ticks_msec()
	for f in files:
		var script: GDScript = load("res://tests/" + f)
		if script == null:
			all_failures.append("%s: failed to load" % f)
			continue
		var inst = script.new()
		for m in inst.get_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			if filter != "" and filter not in name and filter not in f:
				continue
			inst.current = "%s::%s" % [f, name]
			var before_fail: int = inst.failures.size()
			var tm := Time.get_ticks_msec()
			inst.call(name)
			total_tests += 1
			var status := "ok" if inst.failures.size() == before_fail else "FAIL"
			print("  [%s] %s (%d ms)" % [status, inst.current, Time.get_ticks_msec() - tm])
		total_pass += inst.passes
		all_failures.append_array(inst.failures)
	print("")
	print("%d test methods, %d checks passed, %d checks failed (%.1f s)" % [total_tests, total_pass, all_failures.size(), (Time.get_ticks_msec() - t0) / 1000.0])
	for fl in all_failures:
		print("  FAIL: " + fl)
	quit(1 if not all_failures.is_empty() else 0)
