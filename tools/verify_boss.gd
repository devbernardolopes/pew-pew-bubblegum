extends SceneTree

func _init() -> void:
	print("=== BOSS VERIFY START ===")
	var ok: bool = true
	# 1. Arena formation + anchor
	var arena: FormationData = load("res://resources/formations/formation_boss_arena.tres") as FormationData
	if arena == null:
		print("FAIL arena null"); quit(); return
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
	# Formation node + anchor
	var formation: Formation = Formation.new()
	formation.data = arena
	root.add_child(formation)
	# _ready ran already since added to tree? ensure slots built
	print("formation cols=", formation.columns, " rows=", formation.rows)
	var anchor: Marker2D = formation.create_anchor(0, 4, 3, 4)
	if anchor == null:
		print("FAIL anchor null"); ok = false
	else:
		print("anchor local=", anchor.position)
		if not anchor.position.is_equal_approx(Vector2(0.0, 44.0)):
			print("FAIL anchor pos expected (0,44) got ", anchor.position); ok = false
		# sway: step physics, anchor global should follow formation
		var f0: Vector2 = anchor.global_position
		formation._physics_process(1.0)
		var f1: Vector2 = anchor.global_position
		print("anchor global before/after sway: ", f0, " -> ", f1, " formation pos=", formation.position)
		if not f1.is_equal_approx(formation.position + anchor.position):
			print("FAIL anchor not following"); ok = false
	# null anchor cases
	if formation.create_anchor(0, 0, 0, 3) != null:
		print("FAIL anchor span 0 should be null"); ok = false
	# 2. Boss data
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
	# 3. Boss scene shape
	var boss_scene: PackedScene = load("res://scenes/entities/boss_01.tscn") as PackedScene
	var boss: Entity = null
	if boss_scene == null:
		print("FAIL boss scene null"); ok = false
	else:
		var holder: Node = Node.new()
		root.add_child(holder)
		boss = boss_scene.instantiate() as Entity
		holder.add_child(boss)
		await process_frame
		await process_frame
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
			print("boss scale_aux=", boss.scale_aux)
			if not is_equal_approx(boss.scale_aux, 0.4):
				print("FAIL scale"); ok = false
		# weapon + muzzles
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
	# 4. Regular shape unchanged
	var regular: PackedScene = load("res://scenes/entities/foe_turret.tscn") as PackedScene
	if regular != null:
		var foe: Entity = regular.instantiate() as Entity
		root.add_child(foe)
		await process_frame
		await process_frame
		var old: Vector2 = Vector2.ONE * Helpers.ENTITY_HALF_WIDTH * foe.scale_aux * -1.0
		print("regular visual pos=", foe.visual.position if foe != null else Vector2.ZERO, " old=", old)
		if foe != null and foe.visual != null:
			if not foe.visual.position.is_equal_approx(old):
				print("FAIL regular shape moved"); ok = false
	# 5. Ramming
	var hero_scene: PackedScene = load("res://scenes/entities/hero.tscn") as PackedScene
	if hero_scene != null and boss_scene != null and boss != null:
		var hero: Entity = hero_scene.instantiate() as Entity
		root.add_child(hero)
		await process_frame
		await process_frame
		# hero god_mode true -> take_damage returns early; set god off via dupe data
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
	# regular foe still dies on contact
	if regular != null and hero_scene != null:
		var foe2: Entity = regular.instantiate() as Entity
		root.add_child(foe2)
		var hero2: Entity = hero_scene.instantiate() as Entity
		root.add_child(hero2)
		await process_frame
		await process_frame
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
	# 6. Boss spawn via StageDirector._spawn_boss
	if arena != null and boss_scene != null:
		var entities_root: Node2D = Node2D.new()
		root.add_child(entities_root)
		var formations_root: Node2D = Node2D.new()
		root.add_child(formations_root)
		var director: StageDirector = StageDirector.new()
		root.add_child(director)
		# bypass _ready stages check: set fields directly
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
		print("director formation=", form != null, " anchor check via _spawn_boss")
		director._spawn_boss(bw, form)
		# find boss in entities_root
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
			# drive the brain to formation: settle directly (curve null logic equivalent)
			spawned.global_position = Vector2(100, 100)
			if brain_on != null:
				brain_on.setup(null, false, form.get_slot(0, 0), 0.0, [])
				# _process_settling will move to slot; step it
				brain_on._physics_process(1.0)
				brain_on._physics_process(1.0)
				print("after settle state=", brain_on.state, " boss pos=", spawned.global_position, " slot=", form.get_slot(0, 0).global_position if form.get_slot(0, 0) != null else Vector2.ZERO)
	# 7. Demo stage validation
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
		# check wave types
		if demo.waves.size() != 4 or not (demo.waves[0] is BossWaveData):
			print("FAIL demo first wave not boss"); ok = false
		else:
			var bw: BossWaveData = demo.waves[0] as BossWaveData
			print("boss wave row=", bw.row, " col=", bw.col, " row_span=", bw.row_span, " col_span=", bw.col_span, " delay=", bw.delay)
			if bw.row != 0 or bw.col != 4 or bw.row_span != 3 or bw.col_span != 4:
				print("FAIL boss footprint"); ok = false
			for i in range(1, 4):
				if (demo.waves[i] as WaveData).delay != 3.0:
					print("FAIL delay wave ", i); ok = false
	# 7. Existing stages no errors
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
	# 8. Validation negative cases
	# boss wave footprint outside
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
	# overlap footprint warning: boss over occupied cells
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
	# explode centering math
	var boss_pts: PackedVector2Array = Helpers.get_polygon(Helpers.VISUAL.BOSS_01)
	var bc: Vector2 = Helpers.get_points_center(boss_pts)
	var off_boss: Vector2 = bc * 0.4
	var off_norm: Vector2 = Vector2.ONE * Helpers.ENTITY_HALF_WIDTH * 0.4
	print("bounds center=", bc, " off_boss=", off_boss, " off_norm=", off_norm)
	if not bc.is_equal_approx(Vector2(192, 160)):
		print("FAIL bounds center"); ok = false
	print("=== VERIFY ", "PASS" if ok else "FAIL", " ===")
	quit(0 if ok else 1)
