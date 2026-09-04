class_name TestCase
extends RefCounted
## Base class for tests. Subclasses define methods starting with `test_`
## and call check() / check_eq() / check_near().

var passes := 0
var failures: Array[String] = []
var current := ""


func check(cond: bool, message: String) -> bool:
	if cond:
		passes += 1
	else:
		failures.append("%s: %s" % [current, message])
	return cond


func check_eq(a, b, message: String) -> bool:
	return check(a == b, "%s (got %s, expected %s)" % [message, str(a), str(b)])


func check_near(a: float, b: float, tol: float, message: String) -> bool:
	return check(absf(a - b) <= tol, "%s (got %s, expected %s +- %s)" % [message, str(a), str(b), str(tol)])


## Steps a world n times with the fixed tick.
static func run_ticks(world: World, n: int) -> void:
	for i in n:
		world.step(Balance.TICK)


static func run_seconds(world: World, s: float) -> void:
	run_ticks(world, int(round(s / Balance.TICK)))
