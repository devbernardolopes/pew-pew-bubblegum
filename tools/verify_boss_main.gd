extends Node

var ok: bool = true
var arena: FormationData = null
var boss_scene: PackedScene = null
var boss: Entity = null
var hero_scene: PackedScene = null
var regular: PackedScene = null
var formation: Formation = null
var anchor: Marker2D = null
var entities_root: Node2D = null
var formations_root: Node2D = null
var director: StageDirector = null

func _ready() -> void:
	# Autoloads are ready by now; SceneTree scripts miss them.
	await _run()
	get_tree().quit(0 if ok else 1)

func _run() -> void:
	print("=== BOSS VERIFY START ===")
	arena = load("res://resources/formations/formation_boss_arena.tres") as FormationData
	if arena == null:
		print("FAIL arena null"); return
	print("arena cols=", arena.get_column_count(), " rows=", arena.get_row_count(),
		" half=", arena.get_half_width(), " peak=", arena.get_peak_slot_speed(), " spacing=", arena.spacing)
	if arena.get_column_count() != 12 or arena.get_row_count() != 6:
		print("FAIL arena size"); ok = false
	if arena.has_cell(0, 4) or arena.has_cell(1, 5) or arena.has_cell(2, 7):
		print("FAIL arena hole"); ok = false
	if not arena.has_cell(0, 0) or not arena.has_cell(3, 4) or not arena.has_cell(5, 11):
		print("FAIL arena occupied"); ok = false
	if arena.get_cell_count() != 60:
		print("FAIL arena cell count=", arena.get_cell_count()); ok = false
	formation = Formation.new()
	formation.data = arena
	add_child(formation)
	await get_tree().process_frame
	print("formation cols=", formation.columns, " rows=", formation.rows)
	anchor = formation.create_anchor(0, 4, 3, 4)
	if anchor == null:
		print("FAIL anchor null"); ok = false
	else:
		print("anchor local=", anchor.position)
		if not anchor.position.is_equal_approx(Vector2(0.0, 44.0)):
			print("FAIL anchor pos expected (0,44) got ", anchor.position); ok = false
		var f0: Vector2 = anchor.global_position
		formation._physics_process(1.0)
		var f1: Vector2 = anchor.global_position
		print("anchor sway: ", f0, " -> ", f1, " formation pos=", formation.position)
		# anchor is a child of formation; its global is formation*anchor.position
		if not f1.is_equal_approx(formation.global_position + anchor.position):
			print("FAIL anchor not following"); ok = false
	if formation.create_anchor(0, 0, 0, 3) != null:
		print("FAIL anchor span 0 should be null"); ok = false
	# Boss data
	var bdata: BossData = load("res://resources/entities/boss_01.tres") as BossData
	if bdata == null:
		print("FAIL bdata null"); ok = false
	else:
		print("bdata visual=", bdata.visual, " hp=", bdata.max_health, " speed=", bdata.base_speed,
			" die=", bdata.dies_on_contact, " center=", bdata.center_on_bounds, " phases=", bdata.phases.size())
		if bdata.visual != Helpers.VISUAL.BOSS_01 or bdata.max_health != 60:
			print("FAIL bdata core"); ok = false
		if bdata.dies_on_contact or not bdata.center_on_bounds:
			print("FAIL bdata flags"); ok = false
		if bdata.phases.size() != 3:
			print("FAIL phases count"); ok = false
		else:
			var p0: BossPhaseData = bdata.phases[0]
			var p1: BossPhaseData = bdata.phases[1]
			var p2: BossPhaseData = bdata.phases[2]
			print("phases: ", p0.health_below, " ", p1.health_below, " ", p2.health_below)
			if not (p0.health_below == 1.0 and p1.health_below == 0.66 and p2.health_below == 0.33):
				print("FAIL thresholds"); ok = false
			if p0.fire_pattern != BossPhaseData.FirePattern.STRAIGHT or p1.fire_pattern != BossPhaseData.FirePattern.AIMED or p2.fire_pattern != BossPhaseData.FirePattern.SPREAD:
				print("FAIL patterns"); ok = false
			if p1.muzzle_indices != PackedInt32Array([1]) or not p0.muzzle_indices.is_empty() or not p2.muzzle_indices.is_empty():
				print("FAIL muzzle indices"); ok = false
			if p2.spread_count != 3 or not is_equal_approx(p2.spread_angle_deg, 40.0):
				print("FAIL spread"); ok = false
			if not p1.offset.is_equal_approx(Vector2(0, 44)) or not p2.offset.is_equal_approx(Vector2(0, 88)):
				print("FAIL offsets"); ok = false
		var vis: PackedStringArray = bdata.validate("test", 3)
		print("bdata validate issues=", vis)
		for s in vis:
			if s.begins_with("[error]"):
				print("FAIL bdata validate error: ", s); ok = false
	# Boss scene
	boss_scene = load("res://scenes/entities/boss_01.tscn") as PackedScene
	if boss_scene == null:
		print("FAIL boss scene null"); ok = false
	else:
		boss = boss_scene.instantiate() as Entity
		add_child(boss)
		await get_tree().process_frame
		await get_tree().process_frame
		if boss.visual == null or boss.collision == null:
			print("FAIL boss visual/collision null"); ok = false
		else:
			var pts: PackedVector2Array = Helpers.get_polygon(Helpers.VISUAL.BOSS_01)
			var center: Vector2 = Helpers.get_points_center(pts)
			var expected: Vector2 = -center * boss.scale_aux
			print("boss visual pos=", boss.visual.position, " expected=", expected, " center=", center, " scale=", boss.scale_aux)
			if not boss.visual.position.is_equal_approx(expected):
				print("FAIL boss visual pos"); ok = false
			if not boss.collision.position.is_equal_approx(expected):
				print("FAIL boss collision pos"); ok = false
			if not is_equal_approx(boss.scale_aux, 0.4):
				print("FAIL scale"); ok = false
		var weapon: Weapon = boss.get_node_or_null("Weapon") as Weapon
		print("weapon max_in_flight=", weapon.max_in_flight if weapon != null else -1)
		if weapon == null or weapon.max_in_flight != 16 or weapon.projectile_data == null:
			print("FAIL weapon"); ok = false
		var muzzles: Node = boss.get_node_or_null("Muzzles")
		var mc: int = 0
		if muzzles != null:
			for c in muzzles.get_children():
				if c is Marker2D: mc += 1
		print("muzzle count=", mc)
		if mc != 3:
			print("FAIL muzzles"); ok = false
		if boss.get_node_or_null("FoeShooter") != null:
			print("FAIL boss should have no FoeShooter"); ok = false
		if boss.get_node_or_null("FoeBrain") == null or boss.get_node_or_null("BossPattern") == null:
			print("FAIL boss children"); ok = false
	# Regular shape
	regular = load("res://scenes/entities/foe_turret.tscn") as PackedScene
	if regular != null:
		var foe: Entity = regular.instantiate() as Entity
		add_child(foe)
		await get_tree().process_frame
		await get_tree().process_frame
		var old: Vector2 = Vector2.ONE * Helpers.ENTITY_HALF_WIDTH * foe.scale_aux * -1.0
		print("regular visual pos=", foe.visual.position if foe != null else Vector2.ZERO, " old=", old)
		if foe != null and foe.visual != null and not foe.visual.position.is_equal_approx(old):
			print("FAIL regular shape moved"); ok = false
	# Ramming (boss)
	hero_scene = load("res://scenes/entities/hero.tscn") as PackedScene
	if hero_scene != null and boss_scene != null and boss != null:
		var hero: Entity = hero_scene.instantiate() as Entity
		add_child(hero)
		await get_tree().process_frame
		await get_tree().process_frame
		var hdata: EntityData = (hero.data as EntityData).duplicate() as EntityData
		hdata.god_mode = false
		hero.data = hdata
		hero.reset_health()
		var hero_hp_before: int = hero.health
		boss.health = 60
		boss.is_dead = false
		boss._on_area_entered(hero)
		print("boss ram: boss hp=", boss.health, " boss dead=", boss.is_dead, " hero hp=", hero.health, " was ", hero_hp_before)
		if boss.is_dead or boss.health != 60:
			print("FAIL boss died on ram"); ok = false
		if hero.health != hero_hp_before - boss.data.contact_damage:
			print("FAIL hero damage"); ok = false
	# Regular foe dies on contact
	if regular != null and hero_scene != null:
		var foe2: Entity = regular.instantiate() as Entity
		add_child(foe2)
		var hero2: Entity = hero_scene.instantiate() as Entity
		add_child(hero2)
		await get_tree().process_frame
		await get_tree().process_frame
		var h2d: EntityData = (hero2.data as EntityData).duplicate() as EntityData
		h2d.god_mode = false
		hero2.data = h2d
		hero2.reset_health()
		foe2.reset_health()
		print("foe2 dies_on_contact=", foe2.data.dies_on_contact)
		foe2._on_area_entered(hero2)
		print("foe2 ram dead=", foe2.is_dead)
		if not foe2.is_dead:
			print("FAIL regular foe should die on contact"); ok = false
	# _spawn_boss
	entities_root = Node2D.new()
	add_child(entities_root)
	formations_root = Node2D.new()
	add_child(formations_root)
	director = StageDirector.new()
	add_child(director)
	# _ready of StageDirector will error since stages empty; override after
	director.entities = entities_root
	director.formations_root = formations_root
	var curve: Curve2D = load("res://resources/curves/entries/entry_left_01.tres") as Curve2D
	var bw: BossWaveData = BossWaveData.new()
	bw.foe_scene = boss_scene
	bw.formation = arena
	bw.entry_curve = curve
	bw.row = 0
	bw.col = 4
	bw.row_span = 3
	bw.col_span = 4
	var form: Formation = director._get_formation(arena)
	print("director formation=", form != null)
	director._spawn_boss(bw, form)
	var spawned: Entity = null
	for child in entities_root.get_children():
		if child is Entity:
			spawned = child as Entity
	print("spawned boss=", spawned != null, " total=", director._total_foes_spawned)
	if spawned == null:
		print("FAIL _spawn_boss spawned nothing"); ok = false
	else:
		var brain_on: FoeBrain = spawned.get_node_or_null("FoeBrain") as FoeBrain
		var pat_on: BossPattern = spawned.get_node_or_null("BossPattern") as BossPattern
		print("spawned brain=", brain_on != null, " pattern=", pat_on != null, " state=", brain_on.state if brain_on != null else -1)
		if brain_on == null or pat_on == null:
			print("FAIL _spawn_boss missing brain/pattern"); ok = false
		# count live foes
		var live: int = director._count_live_foes()
		print("live foes=", live)
		if live != 1:
			print("FAIL live count should be 1"); ok = false
		# phases: simulate health fractions via BossPattern
		# put boss in FORMATION at anchor
		spawned.rotation = PI
		brain_on.setup(null, false, form.get_slot(0, 0), 0.0, [])
		# force to slot & FORMATION
		spawned.global_position = form.get_slot(0, 0).global_position
		await get_tree().process_frame
		brain_on._physics_process(0.05)
		await get_tree().process_frame
		print("after settle state=", brain_on.state, " boss pos=", spawned.global_position, " slot=", form.get_slot(0, 0).global_position)
		# now test phase advancement: set health so fraction hits 0.5 -> phase 1
		spawned.health = 30
		brain_on.state = FoeBrain.State.FORMATION
		pat_on._physics_process(0.1)
		print("phase after 0.5 health: ", pat_on._phase_index, " anchor=", (pat_on._anchor.position if pat_on._anchor != null else Vector2.ZERO))
		if pat_on._phase_index != 1:
			print("FAIL phase 1"); ok = false
		# heal should not go back
		spawned.health = 60
		pat_on._physics_process(0.1)
		if pat_on._phase_index != 1:
			print("FAIL phase went back"); ok = false
		spawned.health = 12
		pat_on._physics_process(0.1)
		print("phase after 0.2 health: ", pat_on._phase_index)
		if pat_on._phase_index != 2:
			print("FAIL phase 2"); ok = false
		# anchor tween target
		pat_on._enter_phase((spawned.data as BossData).phases[2])
		# with move_duration 1.0, tween runs async; wait a bit
		await get_tree().create_timer(1.2).timeout
		print("anchor final=", pat_on._anchor.position if pat_on._anchor != null else Vector2.ZERO, " home=", pat_on._home, " expected=", pat_on._home + Vector2(0, 88))
		# fire direction check: STRAIGHT base should be down when boss rotated PI
		var muzzle: Marker2D = (spawned.get_node("Muzzles").get_children()[0]) as Marker2D
		var base: Vector2 = Vector2.UP.rotated(muzzle.global_rotation)
		print("straight base dir=", base, " boss rot=", spawned.rotation)
		if not base.is_equal_approx(Vector2(0, 1)):
			print("FAIL straight dir"); ok = false
	# Demo stage validation
	var demo: StageData = load("res://resources/stages/stage_boss_demo.tres") as StageData
	if demo == null:
		print("FAIL demo null"); ok = false
	else:
		var issues: PackedStringArray = demo.validate()
		print("demo waves=", demo.waves.size(), " issues=", issues)
		for s in issues:
			print("demo issue: ", s)
			if s.begins_with("[error]"):
				print("FAIL demo error"); ok = false
		if demo.waves.size() != 4 or not (demo.waves[0] is BossWaveData):
			print("FAIL demo first wave not boss"); ok = false
		else:
			var bw2: BossWaveData = demo.waves[0] as BossWaveData
			print("boss wave row=", bw2.row, " col=", bw2.col, " row_span=", bw2.row_span, " col_span=", bw2.col_span, " delay=", bw2.delay)
			if bw2.row != 0 or bw2.col != 4 or bw2.row_span != 3 or bw2.col_span != 4:
				print("FAIL boss footprint"); ok = false
			for i in range(1, 4):
				if (demo.waves[i] as WaveData).delay != 3.0:
					print("FAIL delay wave ", i); ok = false
	# Existing stages
	var stage_paths: Array[String] = [
		"res://resources/stages/stage_000.tres",
		"res://resources/stages/stage_001.tres",
		"res://resources/stages/stage_002.tres",
		"res://resources/stages/stage_003.tres",
		"res://resources/stages/stage_004.tres",
		"res://resources/stages/stage_alpha.tres",
		"res://resources/stages/stage_beta.tres",
	]
	for p in stage_paths:
		var st: StageData = load(p) as StageData
		if st == null:
			print("FAIL stage null ", p); ok = false; continue
		var iss: PackedStringArray = st.validate()
		var errs: int = 0
		for s in iss:
			if s.begins_with("[error]"):
				errs += 1
		print(p, " issues=", iss.size(), " errors=", errs)
		if errs > 0:
			for s in iss: print("  ", s)
			print("FAIL existing stage errors ", p); ok = false
	# Validation negative cases
	var bad: BossWaveData = BossWaveData.new()
	bad.foe_scene = boss_scene
	bad.formation = arena
	bad.entry_curve = load("res://resources/curves/entries/entry_left_01.tres") as Curve2D
	bad.row = 4
	bad.row_span = 3
	var badissues: PackedStringArray = bad.validate("bad", 0, {})
	var found: bool = false
	for s in badissues:
		print("bad footprint issue: ", s)
		if s.begins_with("[error]") and s.contains("does not fit"):
			found = true
	if not found:
		print("FAIL bad footprint not flagged"); ok = false
	var overlap: BossWaveData = BossWaveData.new()
	overlap.foe_scene = boss_scene
	overlap.formation = arena
	overlap.entry_curve = load("res://resources/curves/entries/entry_left_01.tres") as Curve2D
	overlap.row = 0
	overlap.col = 0
	overlap.row_span = 1
	overlap.col_span = 1
	var oissues: PackedStringArray = overlap.validate("ov", 0, {})
	found = false
	for s in oissues:
		print("overlap issue: ", s)
		if s.contains("inside the boss footprint"):
			found = true
	if not found:
		print("FAIL overlap not flagged"); ok = false
	# bounds center
	var boss_pts: PackedVector2Array = Helpers.get_polygon(Helpers.VISUAL.BOSS_01)
	var bc: Vector2 = Helpers.get_points_center(boss_pts)
	print("bounds center=", bc)
	if not bc.is_equal_approx(Vector2(192, 160)):
		print("FAIL bounds center"); ok = false
	print("=== VERIFY ", "PASS" if ok else "FAIL", " ===")
