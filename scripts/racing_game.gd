extends Node3D

const ROAD_LENGTH: float = 60.0
const ROAD_SEGMENTS: int = 5
const MAX_SPEED: float = 62.0
const NITRO_SPEED: float = 88.0
const STEER_SPEED: float = 10.0
const ROAD_LIMIT: float = 4.5

var player_car: Node3D
var camera: Camera3D
var selected_vehicle_index: int = 0
var garage_info_label: Label
const VEHICLE_MODEL_PATHS: Array[String] = [
    "res://assets/vehicles/rosso_v12_gt.glb",
    "res://assets/vehicles/toro_v10_r.glb",
    "res://assets/vehicles/supra_jdm.glb",
    "res://assets/vehicles/gtr_nismo.glb",
    "res://assets/vehicles/mclaren_aero.glb",
    "res://assets/vehicles/911_track.glb"
]
const VEHICLE_NAMES: Array[String] = [
    "ROSSO V12 GT  /  FERRARI-INSPIRED",
    "TORO V10 R  /  LAMBORGHINI-INSPIRED",
    "SUPRA JDM  /  TOYOTA-INSPIRED",
    "GTR NISMO  /  JAPANESE AWD STYLE",
    "MCLAREN AERO  /  MID-ENGINE STYLE",
    "911 TRACK  /  GERMAN SPORTS STYLE"
]
const VEHICLE_COLORS: Array[Color] = [
    Color(0.88, 0.035, 0.025),
    Color(0.95, 0.72, 0.015),
    Color(0.04, 0.42, 0.95),
    Color(0.07, 0.08, 0.10),
    Color(0.95, 0.95, 0.92),
    Color(0.10, 0.68, 0.38)
]
var road_segments: Array[Node3D] = []
var opponent_cars: Array[Node3D] = []

var speed: float = 28.0
var score: float = 0.0
var nitro: float = 100.0

var steering_left: bool = false
var steering_right: bool = false
var braking: bool = false
var nitro_active: bool = false

var paused: bool = false
var crashed: bool = false

var hud_label: Label
var speed_label: Label
var nitro_label: Label
var message_label: Label
var pause_button: Button
var restart_button: Button
var nitro_button: Button

var ui_layer: CanvasLayer
var cockpit_camera: Camera3D
var camera_mode: int = 0 # 0 = chase camera, 1 = cockpit
var camera_button: Button
var steering_wheel_control: Control
var steering_wheel_label: Label
var wheel_dragging: bool = false
var engine_audio: AudioStreamPlayer
var brake_audio: AudioStreamPlayer
var nitro_audio: AudioStreamPlayer
var crash_audio: AudioStreamPlayer
var tire_audio: AudioStreamPlayer
var menu_audio: AudioStreamPlayer
var last_braking: bool = false
var accelerating: bool = false
var game_started: bool = false
var drive_mode: String = "RACE MODE"
var hud_root: Control
var main_menu: Control
var settings_panel: Control
var garage_panel: Control
var menu_status_label: Label
var engine_volume: float = 0.75
var effects_volume: float = 0.85
var music_volume: float = 0.35
var sound_enabled: bool = true
var steering_angle: float = 0.0
var wheel_mode: bool = false
var settings_file := ConfigFile.new()
const SETTINGS_PATH: String = "user://velocity_settings.cfg"


func _ready() -> void:
    randomize()
    _load_settings()

    _create_environment()
    _create_road()
    _create_player()
    _create_opponents()
    _create_camera()
    _create_audio()
    _create_ui()
    _create_main_menu()
    _create_settings_panel()
    _create_garage_panel()
    _show_main_menu()

    _update_hud()


func _process(delta: float) -> void:
    _update_audio(delta)
    if not game_started or paused or crashed:
        return

    _update_speed(delta)
    _update_player(delta)
    _update_road(delta)
    _update_opponents(delta)
    _update_camera(delta)
    _update_score(delta)
    _update_hud()


# --------------------------------------------------
# ENVIRONMENT
# --------------------------------------------------

func _create_environment() -> void:
    var world_environment := WorldEnvironment.new()
    var environment := Environment.new()

    environment.background_mode = Environment.BG_SKY

    var sky := Sky.new()
    var sky_material := ProceduralSkyMaterial.new()

    sky_material.sky_top_color = Color(0.12, 0.30, 0.55)
    sky_material.sky_horizon_color = Color(0.70, 0.82, 0.94)
    sky_material.ground_bottom_color = Color(0.08, 0.10, 0.12)
    sky_material.ground_horizon_color = Color(0.45, 0.50, 0.55)

    sky.sky_material = sky_material
    environment.sky = sky
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color(0.65, 0.72, 0.85)
    environment.ambient_light_energy = 0.85
    environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    environment.tonemap_exposure = 1.05
    environment.ssr_enabled = false
    environment.glow_enabled = true
    environment.glow_intensity = 0.32

    world_environment.environment = environment
    add_child(world_environment)

    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-48.0, -28.0, 0.0)
    sun.light_energy = 1.35
    sun.shadow_enabled = true
    sun.directional_shadow_max_distance = 90.0
    add_child(sun)


# --------------------------------------------------
# MATERIALS AND GEOMETRY
# --------------------------------------------------

func _material(color: Color, metallic: float = 0.0) -> StandardMaterial3D:
    var result := StandardMaterial3D.new()
    result.albedo_color = color
    result.metallic = metallic
    result.roughness = 0.28 if metallic > 0.3 else 0.62
    return result


func _box(
    parent: Node3D,
    size: Vector3,
    position: Vector3,
    color: Color,
    metallic: float = 0.0
) -> MeshInstance3D:
    var instance := MeshInstance3D.new()
    var mesh := BoxMesh.new()

    mesh.size = size
    instance.mesh = mesh
    instance.position = position
    instance.material_override = _material(color, metallic)

    parent.add_child(instance)
    return instance


func _create_car(
    parent: Node3D,
    body_color: Color,
    player: bool,
    vehicle_style: int = -1
) -> Node3D:
    if vehicle_style < 0:
        vehicle_style = selected_vehicle_index if player else randi_range(0, VEHICLE_NAMES.size() - 1)
    if player and vehicle_style >= 0 and vehicle_style < VEHICLE_COLORS.size():
        body_color = VEHICLE_COLORS[vehicle_style]

    var car := Node3D.new()
    parent.add_child(car)

    # Prefer the bundled, offline glTF 2.0 vehicle model. Keep the original
    # procedural car as a fallback so a missing/import-failed asset never
    # makes the game disappear.
    if vehicle_style >= 0 and vehicle_style < VEHICLE_MODEL_PATHS.size():
        var vehicle_resource: Resource = load(VEHICLE_MODEL_PATHS[vehicle_style])
        if vehicle_resource is PackedScene:
            var vehicle_model: Node3D = (vehicle_resource as PackedScene).instantiate() as Node3D
            if vehicle_model != null:
                vehicle_model.name = "VehicleGLBModel"
                vehicle_model.scale = Vector3.ONE
                car.add_child(vehicle_model)
                return car

    # Main body (fallback model)

    _box(
        car,
        Vector3(1.8, 0.55, 3.5),
        Vector3(0.0, 0.75, 0.0),
        body_color,
        0.55
    )

    # Front hood
    _box(
        car,
        Vector3(1.72, 0.20, 1.05),
        Vector3(0.0, 0.99, -1.05),
        body_color,
        0.45
    )

    # Cabin
    _box(
        car,
        Vector3(1.25, 0.55, 1.55),
        Vector3(0.0, 1.24, 0.10),
        Color(0.08, 0.16, 0.23),
        0.3
    )

    # Windshield
    _box(
        car,
        Vector3(1.12, 0.34, 0.08),
        Vector3(0.0, 1.29, -0.68),
        Color(0.25, 0.55, 0.72),
        0.2
    )

    # Rear window
    _box(
        car,
        Vector3(1.10, 0.30, 0.08),
        Vector3(0.0, 1.29, 0.85),
        Color(0.16, 0.30, 0.42),
        0.2
    )

    # Wheels
    var wheel_positions: Array[Vector3] = [
        Vector3(-0.94, 0.40, -1.08),
        Vector3(0.94, 0.40, -1.08),
        Vector3(-0.94, 0.40, 1.08),
        Vector3(0.94, 0.40, 1.08)
    ]

    for wheel_position in wheel_positions:
        var wheel := MeshInstance3D.new()
        var wheel_mesh := CylinderMesh.new()

        wheel_mesh.top_radius = 0.34
        wheel_mesh.bottom_radius = 0.34
        wheel_mesh.height = 0.22

        wheel.mesh = wheel_mesh
        wheel.position = wheel_position
        wheel.rotation_degrees.z = 90.0
        wheel.material_override = _material(
            Color(0.035, 0.04, 0.05)
        )

        car.add_child(wheel)

    # Headlights
    _box(
        car,
        Vector3(0.38, 0.12, 0.07),
        Vector3(-0.52, 0.88, -1.77),
        Color(0.75, 0.92, 1.0)
    )

    _box(
        car,
        Vector3(0.38, 0.12, 0.07),
        Vector3(0.52, 0.88, -1.77),
        Color(0.75, 0.92, 1.0)
    )

    # Rear lights
    _box(
        car,
        Vector3(0.40, 0.12, 0.07),
        Vector3(-0.52, 0.88, 1.77),
        Color(1.0, 0.04, 0.025)
    )

    _box(
        car,
        Vector3(0.40, 0.12, 0.07),
        Vector3(0.52, 0.88, 1.77),
        Color(1.0, 0.04, 0.025)
    )

    # More sculpted sports-car details: lower splitter, side skirts, mirrors,
    # grille, metallic wheels and brake discs. These are procedural meshes so
    # the game remains self-contained and works offline.
    _box(car, Vector3(1.72, 0.12, 0.30), Vector3(0.0, 0.49, -1.73), Color(0.035, 0.04, 0.05), 0.25)
    _box(car, Vector3(0.48, 0.12, 0.12), Vector3(0.0, 0.70, -1.79), Color(0.04, 0.05, 0.06), 0.35)
    _box(car, Vector3(0.12, 0.18, 1.85), Vector3(-0.87, 0.53, 0.05), body_color, 0.4)
    _box(car, Vector3(0.12, 0.18, 1.85), Vector3(0.87, 0.53, 0.05), body_color, 0.4)
    _box(car, Vector3(0.20, 0.10, 0.34), Vector3(-0.91, 1.12, -0.40), body_color, 0.45)
    _box(car, Vector3(0.20, 0.10, 0.34), Vector3(0.91, 1.12, -0.40), body_color, 0.45)
    # Wheel hubs and brake details
    for wheel_position in wheel_positions:
        var hub := MeshInstance3D.new()
        var hub_mesh := CylinderMesh.new()
        hub_mesh.top_radius = 0.16
        hub_mesh.bottom_radius = 0.16
        hub_mesh.height = 0.235
        hub.mesh = hub_mesh
        hub.position = wheel_position
        hub.rotation_degrees.z = 90.0
        hub.material_override = _material(Color(0.58, 0.62, 0.68), 0.8)
        car.add_child(hub)
        for spoke_index in range(5):
            var spoke := _box(car, Vector3(0.045, 0.035, 0.23), wheel_position + Vector3(0.0, 0.0, 0.0), Color(0.78, 0.82, 0.88), 0.85)
            spoke.rotation.z = float(spoke_index) * TAU / 5.0
            spoke.position += Vector3(0.0, cos(float(spoke_index) * TAU / 5.0) * 0.10, sin(float(spoke_index) * TAU / 5.0) * 0.10)
    # Hood vents add visual detail
    for vent_index in range(3):
        _box(car, Vector3(0.09, 0.025, 0.48), Vector3(-0.30 + float(vent_index) * 0.30, 1.105, -1.00), Color(0.045, 0.055, 0.065), 0.2)

    if player:
        # Vehicle-specific aero styling. These are procedural 3D parts, not flat images.
        match vehicle_style:
            0: # Italian V12 GT: low nose and wide rear wing
                _box(car, Vector3(1.72, 0.10, 0.48), Vector3(0.0, 0.55, -1.72), body_color, 0.55)
                _box(car, Vector3(1.78, 0.09, 0.22), Vector3(0.0, 1.30, 1.47), Color(0.08, 0.08, 0.09), 0.65)
                _box(car, Vector3(0.08, 0.20, 0.20), Vector3(-0.68, 1.21, 1.44), Color(0.08, 0.08, 0.09), 0.5)
                _box(car, Vector3(0.08, 0.20, 0.20), Vector3(0.68, 1.21, 1.44), Color(0.08, 0.08, 0.09), 0.5)
            1: # Angular supercar: sharp splitter and high rear aero
                _box(car, Vector3(1.95, 0.10, 0.36), Vector3(0.0, 0.47, -1.76), Color(0.035, 0.04, 0.045), 0.35)
                _box(car, Vector3(1.70, 0.08, 0.28), Vector3(0.0, 1.45, 1.40), body_color, 0.55)
                _box(car, Vector3(0.12, 0.25, 0.18), Vector3(-0.70, 1.31, 1.40), Color(0.06, 0.06, 0.07), 0.45)
                _box(car, Vector3(0.12, 0.25, 0.18), Vector3(0.70, 1.31, 1.40), Color(0.06, 0.06, 0.07), 0.45)
            2: # Japanese coupe: long hood and compact rear spoiler
                _box(car, Vector3(1.54, 0.12, 0.68), Vector3(0.0, 1.04, -1.20), body_color, 0.5)
                _box(car, Vector3(1.48, 0.12, 0.18), Vector3(0.0, 1.36, 1.42), body_color, 0.45)
                _box(car, Vector3(0.52, 0.09, 0.06), Vector3(-0.50, 1.12, -1.16), Color(0.035, 0.04, 0.05), 0.2)
                _box(car, Vector3(0.52, 0.09, 0.06), Vector3(0.50, 1.12, -1.16), Color(0.035, 0.04, 0.05), 0.2)
            3: # Wide-body AWD performance coupe
                _box(car, Vector3(1.98, 0.20, 2.65), Vector3(0.0, 0.68, 0.0), body_color, 0.5)
                _box(car, Vector3(1.65, 0.12, 0.24), Vector3(0.0, 1.32, 1.45), Color(0.045, 0.05, 0.06), 0.5)
                _box(car, Vector3(0.22, 0.18, 0.45), Vector3(-0.86, 0.88, -1.35), Color(0.04, 0.045, 0.05), 0.3)
                _box(car, Vector3(0.22, 0.18, 0.45), Vector3(0.86, 0.88, -1.35), Color(0.04, 0.045, 0.05), 0.3)
            4: # Mid-engine aero coupe
                _box(car, Vector3(1.48, 0.16, 0.85), Vector3(0.0, 0.93, 0.70), body_color, 0.55)
                _box(car, Vector3(1.82, 0.08, 0.28), Vector3(0.0, 1.30, 1.48), Color(0.06, 0.07, 0.08), 0.6)
                _box(car, Vector3(0.22, 0.22, 0.75), Vector3(-0.72, 0.80, 0.15), Color(0.035, 0.045, 0.055), 0.25)
                _box(car, Vector3(0.22, 0.22, 0.75), Vector3(0.72, 0.80, 0.15), Color(0.035, 0.045, 0.055), 0.25)
            5: # Compact track coupe
                _box(car, Vector3(1.76, 0.10, 0.34), Vector3(0.0, 0.50, -1.75), Color(0.05, 0.055, 0.06), 0.35)
                _box(car, Vector3(1.58, 0.10, 0.22), Vector3(0.0, 1.27, 1.46), body_color, 0.5)
                _box(car, Vector3(0.15, 0.16, 0.25), Vector3(-0.70, 1.17, 1.42), Color(0.04, 0.045, 0.05), 0.45)
                _box(car, Vector3(0.15, 0.16, 0.25), Vector3(0.70, 1.17, 1.42), Color(0.04, 0.045, 0.05), 0.45)

    return car


# --------------------------------------------------
# ROAD
# --------------------------------------------------

func _create_road() -> void:
    for index in range(ROAD_SEGMENTS):
        var segment := Node3D.new()
        segment.position.z = -float(index) * ROAD_LENGTH
        add_child(segment)

        _box(
            segment,
            Vector3(14.0, 0.25, ROAD_LENGTH),
            Vector3(0.0, -0.18, -ROAD_LENGTH / 2.0),
            Color(0.12, 0.13, 0.15)
        )

        # Road shoulders
        _box(
            segment,
            Vector3(1.2, 0.27, ROAD_LENGTH),
            Vector3(-7.5, -0.15, -ROAD_LENGTH / 2.0),
            Color(0.75, 0.18, 0.10)
        )

        _box(
            segment,
            Vector3(1.2, 0.27, ROAD_LENGTH),
            Vector3(7.5, -0.15, -ROAD_LENGTH / 2.0),
            Color(0.75, 0.18, 0.10)
        )

        # Lane markings
        for line_index in range(6):
            var line_z := -5.0 - float(line_index) * 9.0

            _box(
                segment,
                Vector3(0.12, 0.025, 3.6),
                Vector3(-2.3, -0.035, line_z),
                Color(0.95, 0.95, 0.86)
            )

            _box(
                segment,
                Vector3(0.12, 0.025, 3.6),
                Vector3(2.3, -0.035, line_z),
                Color(0.95, 0.95, 0.86)
            )

        _create_buildings(segment)
        _create_street_furniture(segment, index)
        if index == 0:
            _create_start_finish_line(segment)

        road_segments.append(segment)


func _create_start_finish_line(segment: Node3D) -> void:
    # A visible checker start/finish stripe across the road, repeated as the
    # modular track loops. The player still gets a real playable 3D road.
    var tile_width: float = 0.58
    for tile_index in range(24):
        var tile_color: Color = Color(0.92, 0.94, 0.98) if tile_index % 2 == 0 else Color(0.025, 0.035, 0.05)
        var tile_x: float = -6.7 + float(tile_index) * tile_width
        _box(segment, Vector3(tile_width, 0.035, 0.75), Vector3(tile_x, -0.025, -8.0), tile_color, 0.1)
    _box(segment, Vector3(14.0, 0.10, 0.12), Vector3(0.0, 0.03, -8.45), Color(0.02, 0.72, 1.0), 0.35)


func _create_street_furniture(segment: Node3D, segment_index: int) -> void:
    # Trees, planters, street lamps and a small decorative fountain create a
    # richer city boulevard without downloading any runtime resources.
    for side_index in range(2):
        var side: float = -1.0 if side_index == 0 else 1.0
        for tree_index in range(3):
            var z: float = -11.0 - float(tree_index) * 18.0
            var x: float = side * randf_range(9.2, 10.8)
            _box(segment, Vector3(0.42, 1.55, 0.42), Vector3(x, 0.65, z), Color(0.30, 0.17, 0.09), 0.0)
            var crown := MeshInstance3D.new()
            var crown_mesh := SphereMesh.new()
            crown_mesh.radius = randf_range(0.9, 1.25)
            crown_mesh.height = crown_mesh.radius * 2.0
            crown.mesh = crown_mesh
            crown.position = Vector3(x, 1.95, z)
            crown.material_override = _material([Color(0.08, 0.35, 0.16), Color(0.12, 0.43, 0.20), Color(0.20, 0.48, 0.22)][randi_range(0, 2)], 0.0)
            segment.add_child(crown)
            # Compact modern lamp posts placed safely outside the shoulder.
            if tree_index == 1:
                _box(segment, Vector3(0.12, 3.2, 0.12), Vector3(side * 8.8, 1.45, z - 4.0), Color(0.12, 0.15, 0.19), 0.6)
                _box(segment, Vector3(0.62, 0.10, 0.22), Vector3(side * 8.55, 3.05, z - 4.0), Color(0.76, 0.91, 1.0), 0.15)
    if segment_index % 2 == 0:
        # Fountain island in the far plaza beside the boulevard.
        var fountain_x: float = -10.7 if segment_index % 4 == 0 else 10.7
        var basin := MeshInstance3D.new()
        var basin_mesh := CylinderMesh.new()
        basin_mesh.top_radius = 1.15
        basin_mesh.bottom_radius = 1.28
        basin_mesh.height = 0.42
        basin.mesh = basin_mesh
        basin.position = Vector3(fountain_x, 0.18, -30.0)
        basin.material_override = _material(Color(0.40, 0.47, 0.54), 0.55)
        segment.add_child(basin)
        var water := MeshInstance3D.new()
        var water_mesh := CylinderMesh.new()
        water_mesh.top_radius = 0.88
        water_mesh.bottom_radius = 0.88
        water_mesh.height = 0.045
        water.mesh = water_mesh
        water.position = Vector3(fountain_x, 0.41, -30.0)
        water.material_override = _material(Color(0.05, 0.45, 0.78), 0.65)
        segment.add_child(water)
        _box(segment, Vector3(0.22, 1.0, 0.22), Vector3(fountain_x, 0.85, -30.0), Color(0.65, 0.78, 0.88), 0.65)


func _create_buildings(segment: Node3D) -> void:
    var building_colors: Array[Color] = [
        Color(0.28, 0.34, 0.42),
        Color(0.38, 0.40, 0.43),
        Color(0.26, 0.30, 0.36),
        Color(0.48, 0.43, 0.38)
    ]

    for side_index in range(2):
        var side: float = -1.0 if side_index == 0 else 1.0
        for index in range(3):
            var building_height: float = randf_range(7.0, 17.0)
            var building_width: float = randf_range(4.0, 7.0)

            var building_z: float = -8.0 - float(index) * 19.0
            var random_offset: float = randf_range(12.0, 17.0)
            var building_x: float = side * random_offset

            _box(
                segment,
                Vector3(
                    building_width,
                    building_height,
                    randf_range(5.0, 9.0)
                ),
                Vector3(
                    building_x,
                    building_height / 2.0 - 0.25,
                    building_z
                ),
                building_colors[
                    randi_range(0, building_colors.size() - 1)
                ]
            )
            # Repeating glass strips catch the sunlight and make the skyline
            # read as modern city blocks rather than plain cubes.
            var facade_z: float = building_z - 0.2
            for floor_index in range(1, int(building_height / 2.5)):
                var window_y: float = float(floor_index) * 2.2
                _box(segment, Vector3(building_width * 0.72, 0.10, 0.035), Vector3(building_x, window_y, facade_z), Color(0.22, 0.42, 0.60), 0.35)


func _update_road(delta: float) -> void:
    var loop_length: float = ROAD_LENGTH * float(ROAD_SEGMENTS)
    var curve_frequency: float = TAU / loop_length
    for segment in road_segments:
        segment.position.z += speed * delta
        if segment.position.z > ROAD_LENGTH:
            segment.position.z -= loop_length
        # Gentle alternating left/right bends. Every scenery object is attached
        # to the road segment, so the road, buildings and trees follow together.
        var distance_ahead: float = -segment.position.z
        segment.position.x = sin(distance_ahead * curve_frequency) * 3.4
        segment.rotation.y = -atan(cos(distance_ahead * curve_frequency) * 3.4 * curve_frequency)


# --------------------------------------------------
# PLAYER
# --------------------------------------------------

func _create_player() -> void:
    player_car = _create_car(
        self,
        VEHICLE_COLORS[selected_vehicle_index],
        true,
        selected_vehicle_index
    )

    player_car.position = Vector3(0.0, 0.0, 0.0)


func _update_speed(delta: float) -> void:
    if braking:
        speed = maxf(0.0, speed - 42.0 * delta)
    elif accelerating:
        speed = minf(MAX_SPEED, speed + 18.0 * delta)
    else:
        speed = maxf(0.0, speed - 2.0 * delta)

    if nitro_active and nitro > 0.0:
        speed = minf(NITRO_SPEED, speed + 35.0 * delta)
        nitro = maxf(0.0, nitro - 32.0 * delta)
    else:
        nitro = minf(100.0, nitro + 7.0 * delta)


func _update_player(delta: float) -> void:
    var direction := 0.0

    if steering_left:
        direction -= 1.0

    if steering_right:
        direction += 1.0

    if wheel_mode:
        direction = steering_angle
    var speed_factor: float = clampf(1.0 - (speed / NITRO_SPEED) * 0.32, 0.55, 1.0)
    player_car.position.x += direction * STEER_SPEED * speed_factor * delta
    player_car.position.x = clampf(player_car.position.x, -ROAD_LIMIT, ROAD_LIMIT)

    # Smooth body lean and self-centering steering wheel.
    player_car.rotation.z = lerpf(player_car.rotation.z, -direction * 0.10, minf(1.0, delta * 7.0))
    if not wheel_dragging:
        steering_angle = move_toward(steering_angle, 0.0, delta * 1.7)
    if steering_wheel_label:
        steering_wheel_label.rotation = steering_angle * 0.72


# --------------------------------------------------
# OPPONENTS
# --------------------------------------------------

func _create_opponents() -> void:
    var colors: Array[Color] = [
        Color(0.04, 0.36, 0.95),
        Color(0.95, 0.65, 0.04),
        Color(0.12, 0.78, 0.38),
        Color(0.60, 0.15, 0.85),
        Color(0.85, 0.85, 0.88)
    ]

    for index in range(5):
        var opponent := _create_car(
            self,
            colors[index],
            false
        )

        opponent.position = Vector3(
            _random_lane(),
            0.0,
            -45.0 - float(index) * 32.0
        )

        opponent_cars.append(opponent)


func _random_lane() -> float:
    var lanes: Array[float] = [-4.0, 0.0, 4.0]
    return lanes[randi_range(0, lanes.size() - 1)]


func _update_opponents(delta: float) -> void:
    for opponent in opponent_cars:
        opponent.position.z += speed * 0.78 * delta

        # Recycle cars after they pass the player.
        if opponent.position.z > 12.0:
            opponent.position.z = -randf_range(90.0, 190.0)
            opponent.position.x = _random_lane()

        # Basic arcade collision detection.
        var distance_z := absf(
            opponent.position.z - player_car.position.z
        )

        var distance_x := absf(
            opponent.position.x - player_car.position.x
        )

        if drive_mode != "FREE DRIVE" and distance_z < 2.4 and distance_x < 1.65:
            _handle_collision()
            return


func _handle_collision() -> void:
    if crashed:
        return

    crashed = true
    if crash_audio and sound_enabled and effects_volume > 0.0:
        crash_audio.volume_db = linear_to_db(effects_volume)
        crash_audio.play()
    speed = 0.0
    steering_left = false
    steering_right = false
    braking = false
    nitro_active = false

    message_label.text = "CRASH!\nScore: %d" % int(score)
    message_label.visible = true
    restart_button.visible = true


# --------------------------------------------------
# CAMERA
# --------------------------------------------------

func _create_camera() -> void:
    camera = Camera3D.new()
    camera.position = Vector3(0.0, 5.5, 9.0)
    camera.current = true
    camera.fov = 72.0
    add_child(camera)
    camera.look_at(Vector3(0.0, 1.0, -12.0), Vector3.UP)

    cockpit_camera = Camera3D.new()
    cockpit_camera.position = Vector3(0.0, 1.42, -0.46)
    cockpit_camera.fov = 78.0
    player_car.add_child(cockpit_camera)
    cockpit_camera.look_at(Vector3(0.0, 1.40, -35.0), Vector3.UP)

    # Dashboard, instrument hood and steering wheel are visible from the cockpit.
    _box(player_car, Vector3(1.24, 0.16, 0.42), Vector3(0.0, 1.03, -0.02), Color(0.025, 0.035, 0.045), 0.1)
    _box(player_car, Vector3(0.42, 0.08, 0.05), Vector3(0.0, 1.13, -0.12), Color(0.04, 0.72, 0.95), 0.3)
    var cockpit_wheel := MeshInstance3D.new()
    var wheel_mesh := TorusMesh.new()
    wheel_mesh.inner_radius = 0.19
    wheel_mesh.outer_radius = 0.24
    cockpit_wheel.mesh = wheel_mesh
    cockpit_wheel.position = Vector3(0.0, 1.05, -0.48)
    cockpit_wheel.rotation.x = deg_to_rad(68.0)
    cockpit_wheel.material_override = _material(Color(0.025, 0.03, 0.035), 0.15)
    player_car.add_child(cockpit_wheel)


func _update_camera(delta: float) -> void:
    if camera_mode == 1:
        cockpit_camera.current = true
        camera.current = false
        cockpit_camera.position.x = lerpf(cockpit_camera.position.x, player_car.rotation.z * 0.4, minf(1.0, delta * 5.0))
        cockpit_camera.fov = lerpf(cockpit_camera.fov, 82.0 if nitro_active and nitro > 0.0 else 76.0, minf(1.0, delta * 3.0))
        return

    camera.current = true
    cockpit_camera.current = false
    var target_position := Vector3(player_car.position.x * 0.55, 5.5, 9.0)
    camera.position = camera.position.lerp(target_position, minf(1.0, delta * 4.0))
    camera.look_at(Vector3(player_car.position.x * 0.35, 1.0, -12.0), Vector3.UP)
    var target_fov := 82.0 if nitro_active and nitro > 0.0 else 72.0
    camera.fov = lerpf(camera.fov, target_fov, minf(1.0, delta * 3.0))


func _toggle_camera() -> void:
    camera_mode = 1 - camera_mode
    camera.current = camera_mode == 0
    cockpit_camera.current = camera_mode == 1
    if camera_button:
        camera_button.text = "COCKPIT" if camera_mode == 0 else "CHASE CAM"


# --------------------------------------------------
# AUDIO (offline, bundled WAV files)
# --------------------------------------------------
func _create_audio() -> void:
    engine_audio = AudioStreamPlayer.new()
    var engine_stream: AudioStreamWAV = preload("res://assets/audio/engine.wav")
    engine_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
    engine_audio.stream = engine_stream
    engine_audio.volume_db = -9.0
    add_child(engine_audio)

    brake_audio = AudioStreamPlayer.new()
    brake_audio.stream = preload("res://assets/audio/brake.wav")
    brake_audio.volume_db = -3.0
    add_child(brake_audio)

    nitro_audio = AudioStreamPlayer.new()
    var nitro_stream: AudioStreamWAV = preload("res://assets/audio/nitro.wav")
    nitro_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
    nitro_audio.stream = nitro_stream
    nitro_audio.volume_db = -7.0
    add_child(nitro_audio)

    crash_audio = AudioStreamPlayer.new()
    crash_audio.stream = preload("res://assets/audio/crash.wav")
    crash_audio.volume_db = -2.0
    add_child(crash_audio)

    tire_audio = AudioStreamPlayer.new()
    var tire_stream: AudioStreamWAV = preload("res://assets/audio/tire_squeal.wav")
    tire_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
    tire_audio.stream = tire_stream
    tire_audio.volume_db = -12.0
    add_child(tire_audio)

    menu_audio = AudioStreamPlayer.new()
    var music_stream: AudioStreamWAV = preload("res://assets/audio/menu_music.wav")
    music_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
    menu_audio.stream = music_stream
    menu_audio.volume_db = linear_to_db(maxf(0.001, music_volume))
    add_child(menu_audio)


func _update_audio(_delta: float) -> void:
    if engine_audio:
        if not sound_enabled or not game_started or paused or crashed:
            if engine_audio.playing:
                engine_audio.stop()
        else:
            if not engine_audio.playing:
                engine_audio.play()
            engine_audio.pitch_scale = clampf(0.68 + speed / MAX_SPEED * 0.95, 0.65, 1.85)
            engine_audio.volume_db = linear_to_db(maxf(0.001, engine_volume * (0.22 + clampf(speed / MAX_SPEED, 0.0, 1.0) * 0.78)))
    if menu_audio:
        menu_audio.volume_db = linear_to_db(maxf(0.001, music_volume))
        if sound_enabled and not game_started and music_volume > 0.0:
            if not menu_audio.playing:
                menu_audio.play()
        elif menu_audio.playing:
            menu_audio.stop()
    if tire_audio:
        var drifting: bool = game_started and not paused and not crashed and speed > 24.0 and (steering_left or steering_right or absf(steering_angle) > 0.48)
        if sound_enabled and effects_volume > 0.0 and drifting:
            tire_audio.volume_db = linear_to_db(maxf(0.001, effects_volume)) - 12.0
            if not tire_audio.playing:
                tire_audio.play()
        elif tire_audio.playing:
            tire_audio.stop()
    if braking and not last_braking and brake_audio and sound_enabled and effects_volume > 0.0:
        brake_audio.volume_db = linear_to_db(effects_volume) - 2.0
        brake_audio.play()
    last_braking = braking
    if (paused or crashed or not game_started or not sound_enabled):
        if nitro_audio and nitro_audio.playing:
            nitro_audio.stop()
        return
    if nitro_active and nitro > 0.0:
        if nitro_audio:
            nitro_audio.volume_db = linear_to_db(maxf(0.001, effects_volume)) - 3.0
        if nitro_audio and not nitro_audio.playing:
            nitro_audio.play()
    elif nitro_audio and nitro_audio.playing:
        nitro_audio.stop()


# --------------------------------------------------
# USER INTERFACE
# --------------------------------------------------

func _create_ui() -> void:
    ui_layer = CanvasLayer.new()
    add_child(ui_layer)

    var root := Control.new()
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    ui_layer.add_child(root)
    hud_root = root

    hud_label = _make_label(
        root,
        "VELOCITY RUSH",
        Vector2(25.0, 18.0),
        25
    )

    speed_label = _make_label(
        root,
        "SPEED 000",
        Vector2(25.0, 57.0),
        23
    )

    nitro_label = _make_label(
        root,
        "NITRO 100%",
        Vector2(25.0, 94.0),
        19
    )

    message_label = _make_label(
        root,
        "",
        Vector2(0.0, 0.0),
        34
    )

    message_label.set_anchors_and_offsets_preset(
        Control.PRESET_CENTER
    )

    message_label.position = Vector2(-230.0, -85.0)
    message_label.size = Vector2(460.0, 170.0)
    message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    message_label.visible = false

    # Left steering
    var left_button := _make_button(
        root,
        "◀",
        Vector4(0.0, 1.0, 0.0, 1.0),
        Vector4(25.0, -125.0, 125.0, -30.0)
    )

    left_button.button_down.connect(_on_left_down)
    left_button.button_up.connect(_on_left_up)

    # Right steering
    var right_button := _make_button(
        root,
        "▶",
        Vector4(0.0, 1.0, 0.0, 1.0),
        Vector4(140.0, -125.0, 240.0, -30.0)
    )

    right_button.button_down.connect(_on_right_down)
    right_button.button_up.connect(_on_right_up)

    # Brake
    var brake_button := _make_button(
        root,
        "BRAKE",
        Vector4(1.0, 1.0, 1.0, 1.0),
        Vector4(-290.0, -120.0, -160.0, -30.0)
    )

    brake_button.button_down.connect(_on_brake_down)
    brake_button.button_up.connect(_on_brake_up)

    # Accelerator pedal (hold to accelerate)
    var throttle_button := _make_button(
        root,
        "ACCEL",
        Vector4(1.0, 1.0, 1.0, 1.0),
        Vector4(-420.0, -120.0, -295.0, -30.0)
    )
    throttle_button.add_theme_font_size_override("font_size", 16)
    throttle_button.button_down.connect(_on_throttle_down)
    throttle_button.button_up.connect(_on_throttle_up)

    # Nitro
    nitro_button = _make_button(
        root,
        "NITRO",
        Vector4(1.0, 1.0, 1.0, 1.0),
        Vector4(-150.0, -130.0, -25.0, -30.0)
    )

    nitro_button.button_down.connect(_on_nitro_down)
    nitro_button.button_up.connect(_on_nitro_up)

    # Pause
    pause_button = _make_button(
        root,
        "Ⅱ",
        Vector4(1.0, 0.0, 1.0, 0.0),
        Vector4(-100.0, 20.0, -20.0, 85.0)
    )

    pause_button.pressed.connect(_toggle_pause)

    camera_button = _make_button(
        root,
        "COCKPIT",
        Vector4(1.0, 0.0, 1.0, 0.0),
        Vector4(-245.0, 20.0, -115.0, 78.0)
    )
    camera_button.add_theme_font_size_override("font_size", 14)
    camera_button.pressed.connect(_toggle_camera)

    var wheel_mode_button := _make_button(
        root,
        "WHEEL",
        Vector4(1.0, 0.0, 1.0, 0.0),
        Vector4(-390.0, 20.0, -260.0, 78.0)
    )
    wheel_mode_button.add_theme_font_size_override("font_size", 15)
    wheel_mode_button.pressed.connect(_toggle_steering_mode)

    steering_wheel_control = Control.new()
    steering_wheel_control.anchor_left = 0.0
    steering_wheel_control.anchor_top = 1.0
    steering_wheel_control.anchor_right = 0.0
    steering_wheel_control.anchor_bottom = 1.0
    steering_wheel_control.offset_left = 24.0
    steering_wheel_control.offset_top = -210.0
    steering_wheel_control.offset_right = 205.0
    steering_wheel_control.offset_bottom = -20.0
    steering_wheel_control.mouse_filter = Control.MOUSE_FILTER_STOP
    steering_wheel_control.visible = wheel_mode
    steering_wheel_control.gui_input.connect(_on_wheel_gui_input)
    root.add_child(steering_wheel_control)

    steering_wheel_label = Label.new()
    steering_wheel_label.text = "◉"
    steering_wheel_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    steering_wheel_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    steering_wheel_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    steering_wheel_label.add_theme_font_size_override("font_size", 105)
    steering_wheel_label.add_theme_color_override("font_color", Color(0.78, 0.88, 0.98, 0.95))
    steering_wheel_control.add_child(steering_wheel_label)
    if wheel_mode:
        for control_item in root.get_children():
            if control_item is Button and (control_item.text == "◀" or control_item.text == "▶"):
                control_item.visible = false

    # Restart
    restart_button = _make_button(
        root,
        "RACE AGAIN",
        Vector4(0.5, 0.5, 0.5, 0.5),
        Vector4(-100.0, 95.0, 100.0, 155.0)
    )

    restart_button.pressed.connect(_restart_race)
    restart_button.visible = false


func _make_label(
    parent: Control,
    text_value: String,
    position_value: Vector2,
    font_size: int
) -> Label:
    var label := Label.new()

    label.text = text_value
    label.position = position_value
    label.size = Vector2(360.0, 38.0)

    label.add_theme_font_size_override(
        "font_size",
        font_size
    )

    label.add_theme_color_override(
        "font_color",
        Color(1.0, 1.0, 1.0)
    )

    label.add_theme_color_override(
        "font_shadow_color",
        Color(0.0, 0.0, 0.0, 0.8)
    )

    label.add_theme_constant_override("shadow_offset_x", 2)
    label.add_theme_constant_override("shadow_offset_y", 2)

    parent.add_child(label)
    return label


func _make_button(
    parent: Control,
    text_value: String,
    anchors: Vector4,
    offsets: Vector4
) -> Button:
    var button := Button.new()

    button.text = text_value

    button.anchor_left = anchors.x
    button.anchor_top = anchors.y
    button.anchor_right = anchors.z
    button.anchor_bottom = anchors.w

    button.offset_left = offsets.x
    button.offset_top = offsets.y
    button.offset_right = offsets.z
    button.offset_bottom = offsets.w

    button.focus_mode = Control.FOCUS_NONE

    button.add_theme_font_size_override(
        "font_size",
        20
    )

    button.add_theme_color_override(
        "font_color",
        Color.WHITE
    )

    var normal_style := StyleBoxFlat.new()
    normal_style.bg_color = Color(0.04, 0.10, 0.18, 0.88)
    normal_style.corner_radius_top_left = 15
    normal_style.corner_radius_top_right = 15
    normal_style.corner_radius_bottom_left = 15
    normal_style.corner_radius_bottom_right = 15
    normal_style.border_width_left = 2
    normal_style.border_width_right = 2
    normal_style.border_width_top = 2
    normal_style.border_width_bottom = 2
    normal_style.border_color = Color(0.12, 0.65, 1.0)

    var hover_style := normal_style.duplicate() as StyleBoxFlat
    hover_style.bg_color = Color(0.08, 0.22, 0.36, 0.96)

    var pressed_style := normal_style.duplicate() as StyleBoxFlat
    pressed_style.bg_color = Color(0.05, 0.50, 0.90, 0.98)

    button.add_theme_stylebox_override("normal", normal_style)
    button.add_theme_stylebox_override("hover", hover_style)
    button.add_theme_stylebox_override("pressed", pressed_style)
    button.add_theme_stylebox_override("focus", normal_style)

    parent.add_child(button)
    return button


# --------------------------------------------------
# BUTTON CALLBACKS
# --------------------------------------------------
func _toggle_steering_mode() -> void:
    var use_wheel: bool = not steering_wheel_control.visible
    steering_wheel_control.visible = use_wheel
    wheel_mode = use_wheel
    _save_settings()
    if hud_root:
        for item in hud_root.get_children():
            if item is Button and (item.text == "◀" or item.text == "▶"):
                item.visible = not use_wheel


func _on_wheel_gui_input(event: InputEvent) -> void:
    if event is InputEventScreenTouch:
        wheel_dragging = event.pressed
        if not event.pressed:
            steering_left = false
            steering_right = false
    elif event is InputEventScreenDrag and wheel_dragging:
        var local_x: float = event.position.x
        var center_x: float = steering_wheel_control.size.x * 0.5
        steering_angle = clampf((local_x - center_x) / maxf(1.0, center_x), -1.0, 1.0)
        steering_left = steering_angle < -0.12
        steering_right = steering_angle > 0.12


func _on_throttle_down() -> void:
    accelerating = true


func _on_throttle_up() -> void:
    accelerating = false


func _on_left_down() -> void:
    steering_left = true


func _on_left_up() -> void:
    steering_left = false


func _on_right_down() -> void:
    steering_right = true


func _on_right_up() -> void:
    steering_right = false


func _on_brake_down() -> void:
    braking = true


func _on_brake_up() -> void:
    braking = false


func _on_nitro_down() -> void:
    nitro_active = true


func _on_nitro_up() -> void:
    nitro_active = false


func _toggle_pause() -> void:
    if crashed or not game_started:
        return

    paused = not paused

    if paused:
        message_label.text = "PAUSED"
        message_label.visible = true
        pause_button.text = "▶"
    else:
        message_label.visible = false
        pause_button.text = "Ⅱ"


func _restart_race() -> void:
    crashed = false
    paused = false
    game_started = true
    if hud_root:
        hud_root.visible = true
    if main_menu:
        main_menu.visible = false
    if settings_panel:
        settings_panel.visible = false
    if garage_panel:
        garage_panel.visible = false

    speed = 0.0
    score = 0.0
    nitro = 100.0
    accelerating = false
    steering_angle = 0.0

    steering_left = false
    steering_right = false
    braking = false
    nitro_active = false

    player_car.position = Vector3.ZERO
    player_car.rotation = Vector3.ZERO
    camera_mode = 0
    camera.current = true
    cockpit_camera.current = false
    camera_button.text = "COCKPIT"

    for index in range(opponent_cars.size()):
        opponent_cars[index].position = Vector3(
            _random_lane(),
            0.0,
            -55.0 - float(index) * 35.0
        )

    message_label.visible = false
    restart_button.visible = false
    pause_button.text = "Ⅱ"

    _update_hud()


# --------------------------------------------------
# HUD AND SCORE
# --------------------------------------------------

func _update_score(delta: float) -> void:
    score += speed * delta * 0.12


func _update_hud() -> void:
    speed_label.text = "SPEED  %03d KM/H" % int(speed * 4.0)
    nitro_label.text = "NITRO  %d%%" % int(nitro)

    hud_label.text = "%s  |  SCORE %06d" % [drive_mode, int(score)]

    if nitro <= 0.0:
        nitro_button.modulate = Color(0.6, 0.6, 0.6)
    else:
        nitro_button.modulate = Color.WHITE


# --------------------------------------------------
# MAIN MENU, GARAGE, SETTINGS AND PERSISTENCE
# --------------------------------------------------
func _load_settings() -> void:
    settings_file.load(SETTINGS_PATH)
    engine_volume = float(settings_file.get_value("audio", "engine", 0.75))
    effects_volume = float(settings_file.get_value("audio", "effects", 0.85))
    music_volume = float(settings_file.get_value("audio", "music", 0.35))
    sound_enabled = bool(settings_file.get_value("audio", "enabled", true))
    wheel_mode = bool(settings_file.get_value("controls", "wheel", false))
    selected_vehicle_index = clampi(int(settings_file.get_value("garage", "vehicle", 0)), 0, VEHICLE_NAMES.size() - 1)


func _save_settings() -> void:
    settings_file.set_value("audio", "engine", engine_volume)
    settings_file.set_value("audio", "effects", effects_volume)
    settings_file.set_value("audio", "music", music_volume)
    settings_file.set_value("audio", "enabled", sound_enabled)
    settings_file.set_value("controls", "wheel", wheel_mode)
    settings_file.set_value("garage", "vehicle", selected_vehicle_index)
    settings_file.save(SETTINGS_PATH)


func _create_main_menu() -> void:
    main_menu = Control.new()
    main_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    main_menu.mouse_filter = Control.MOUSE_FILTER_STOP
    ui_layer.add_child(main_menu)

    var backdrop := ColorRect.new()
    backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    backdrop.color = Color(0.015, 0.035, 0.075, 0.91)
    main_menu.add_child(backdrop)

    var accent := ColorRect.new()
    accent.anchor_left = 0.0
    accent.anchor_top = 0.0
    accent.anchor_right = 0.43
    accent.anchor_bottom = 1.0
    accent.color = Color(0.02, 0.12, 0.22, 0.72)
    main_menu.add_child(accent)

    var title := _make_label(main_menu, "VELOCITY", Vector2(42, 48), 44)
    title.size = Vector2(470, 62)
    title.add_theme_color_override("font_color", Color(0.28, 0.78, 1.0))
    var subtitle := _make_label(main_menu, "RUSH 3D  /  SUPER STAR RACING", Vector2(45, 110), 17)
    subtitle.size = Vector2(470, 34)
    var tagline := _make_label(main_menu, "OWN THE ROAD.\nCHASE THE LIMIT.", Vector2(45, 205), 28)
    tagline.size = Vector2(440, 100)

    var status_panel := Panel.new()
    status_panel.position = Vector2(44, 330)
    status_panel.size = Vector2(370, 88)
    var panel_style := StyleBoxFlat.new()
    panel_style.bg_color = Color(0.02, 0.07, 0.13, 0.92)
    panel_style.border_color = Color(0.1, 0.55, 0.9, 0.8)
    panel_style.set_border_width_all(1)
    panel_style.set_corner_radius_all(12)
    status_panel.add_theme_stylebox_override("panel", panel_style)
    main_menu.add_child(status_panel)
    menu_status_label = _make_label(status_panel, "ARCADE STREET SERIES\nTouch controls  •  Offline play", Vector2(18, 16), 16)
    menu_status_label.size = Vector2(340, 58)

    var button_x: float = 0.62
    var button_w: float = 0.30
    var buttons: Array[Dictionary] = [
        {"text": "RACE MODE", "y": 0.15, "call": "race"},
        {"text": "DUEL RACE  /  VS AI", "y": 0.265, "call": "duel"},
        {"text": "FREE DRIVE", "y": 0.38, "call": "free"},
        {"text": "GARAGE", "y": 0.495, "call": "garage"},
        {"text": "SETTINGS", "y": 0.61, "call": "settings"},
        {"text": "SOUND: ON" if sound_enabled else "SOUND: OFF", "y": 0.725, "call": "sound"}
    ]
    for item in buttons:
        var b := Button.new()
        b.text = str(item["text"])
        b.anchor_left = button_x
        b.anchor_right = button_x + button_w
        b.anchor_top = float(item["y"])
        b.anchor_bottom = float(item["y"]) + 0.105
        b.offset_left = 0
        b.offset_right = 0
        b.offset_top = 0
        b.offset_bottom = 0
        _style_menu_button(b)
        main_menu.add_child(b)
        match str(item["call"]):
            "race": b.pressed.connect(_start_mode.bind("RACE MODE"))
            "duel": b.pressed.connect(_start_mode.bind("DUEL RACE"))
            "free": b.pressed.connect(_start_mode.bind("FREE DRIVE"))
            "garage": b.pressed.connect(_show_garage)
            "settings": b.pressed.connect(_show_settings)
            "sound": b.pressed.connect(_toggle_sound)


func _style_menu_button(button: Button) -> void:
    button.focus_mode = Control.FOCUS_NONE
    button.add_theme_font_size_override("font_size", 21)
    button.add_theme_color_override("font_color", Color(0.92, 0.97, 1.0))
    var normal := StyleBoxFlat.new()
    normal.bg_color = Color(0.035, 0.12, 0.21, 0.96)
    normal.border_color = Color(0.10, 0.62, 0.96, 0.95)
    normal.set_border_width_all(2)
    normal.set_corner_radius_all(13)
    normal.content_margin_left = 18
    normal.content_margin_right = 18
    var hover := normal.duplicate() as StyleBoxFlat
    hover.bg_color = Color(0.04, 0.28, 0.43, 1.0)
    var pressed_style := normal.duplicate() as StyleBoxFlat
    pressed_style.bg_color = Color(0.02, 0.46, 0.68, 1.0)
    button.add_theme_stylebox_override("normal", normal)
    button.add_theme_stylebox_override("hover", hover)
    button.add_theme_stylebox_override("pressed", pressed_style)
    button.add_theme_stylebox_override("focus", normal)


func _create_settings_panel() -> void:
    settings_panel = _make_overlay_panel("SETTINGS  /  AUDIO & CONTROL")
    _make_label(settings_panel, "ENGINE VOLUME", Vector2(460, 190), 16)
    var engine_slider := HSlider.new()
    engine_slider.position = Vector2(460, 222)
    engine_slider.size = Vector2(360, 34)
    engine_slider.min_value = 0.0
    engine_slider.max_value = 1.0
    engine_slider.step = 0.05
    engine_slider.value = engine_volume
    settings_panel.add_child(engine_slider)
    engine_slider.value_changed.connect(_on_engine_volume_changed)

    _make_label(settings_panel, "EFFECTS VOLUME", Vector2(460, 270), 16)
    var effects_slider := HSlider.new()
    effects_slider.position = Vector2(460, 302)
    effects_slider.size = Vector2(360, 34)
    effects_slider.min_value = 0.0
    effects_slider.max_value = 1.0
    effects_slider.step = 0.05
    effects_slider.value = effects_volume
    settings_panel.add_child(effects_slider)
    effects_slider.value_changed.connect(_on_effects_volume_changed)

    _make_label(settings_panel, "MENU MUSIC VOLUME", Vector2(460, 350), 14)
    var music_slider := HSlider.new()
    music_slider.position = Vector2(460, 382)
    music_slider.size = Vector2(360, 34)
    music_slider.min_value = 0.0
    music_slider.max_value = 1.0
    music_slider.step = 0.05
    music_slider.value = music_volume
    settings_panel.add_child(music_slider)
    music_slider.value_changed.connect(_on_music_volume_changed)

    var steering_button := _make_button(settings_panel, "STEERING: WHEEL / BUTTONS", Vector4(0, 0, 0, 0), Vector4(460, 432, 820, 486))
    steering_button.add_theme_font_size_override("font_size", 15)
    steering_button.pressed.connect(_toggle_steering_mode)
    var back := _make_button(settings_panel, "BACK", Vector4(0, 0, 0, 0), Vector4(460, 510, 600, 566))
    back.pressed.connect(_show_main_menu)
    settings_panel.visible = false


func _make_overlay_panel(title_text: String) -> Control:
    var panel := Control.new()
    panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    panel.mouse_filter = Control.MOUSE_FILTER_STOP
    ui_layer.add_child(panel)
    var dim := ColorRect.new()
    dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    dim.color = Color(0.005, 0.015, 0.035, 0.94)
    panel.add_child(dim)
    var card := Panel.new()
    card.anchor_left = 0.5
    card.anchor_top = 0.5
    card.anchor_right = 0.5
    card.anchor_bottom = 0.5
    card.offset_left = -250
    card.offset_top = -250
    card.offset_right = 250
    card.offset_bottom = 250
    var style := StyleBoxFlat.new()
    style.bg_color = Color(0.025, 0.07, 0.12, 0.99)
    style.border_color = Color(0.12, 0.62, 0.98, 0.95)
    style.set_border_width_all(2)
    style.set_corner_radius_all(18)
    card.add_theme_stylebox_override("panel", style)
    panel.add_child(card)
    var title := _make_label(card, title_text, Vector2(28, 22), 22)
    title.size = Vector2(430, 48)
    return panel


func _create_garage_panel() -> void:
    garage_panel = _make_overlay_panel("GARAGE  /  CHOOSE YOUR RIDE")
    var intro := _make_label(garage_panel, "SELECT A 3D CAR STYLE", Vector2(0, 0), 16)
    intro.anchor_left = 0.0
    intro.anchor_right = 1.0
    intro.anchor_top = 0.15
    intro.anchor_bottom = 0.21
    intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    intro.add_theme_color_override("font_color", Color(0.35, 0.80, 1.0))

    for index in range(VEHICLE_NAMES.size()):
        var column: int = index % 2
        var row: int = int(index / 2)
        var b := Button.new()
        b.text = VEHICLE_NAMES[index]
        b.anchor_left = 0.07 + float(column) * 0.46
        b.anchor_right = 0.49 + float(column) * 0.46
        b.anchor_top = 0.23 + float(row) * 0.105
        b.anchor_bottom = 0.23 + float(row) * 0.105 + 0.085
        b.offset_left = 0
        b.offset_right = 0
        b.offset_top = 0
        b.offset_bottom = 0
        b.add_theme_font_size_override("font_size", 13)
        _style_menu_button(b)
        garage_panel.add_child(b)
        b.pressed.connect(_select_vehicle.bind(index))

    garage_info_label = _make_label(garage_panel, "", Vector2(0, 0), 15)
    garage_info_label.anchor_left = 0.08
    garage_info_label.anchor_right = 0.92
    garage_info_label.anchor_top = 0.56
    garage_info_label.anchor_bottom = 0.70
    garage_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    garage_info_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _refresh_garage_info()

    var back := Button.new()
    back.text = "BACK TO MENU"
    back.anchor_left = 0.35
    back.anchor_right = 0.65
    back.anchor_top = 0.78
    back.anchor_bottom = 0.88
    _style_menu_button(back)
    garage_panel.add_child(back)
    back.pressed.connect(_show_main_menu)
    garage_panel.visible = false


func _refresh_garage_info() -> void:
    if garage_info_label:
        garage_info_label.text = "%s\n\nTOP SPEED: %d KM/H  |  NITRO: READY\nProcedural 3D concept model — no official brand logos/assets." % [VEHICLE_NAMES[selected_vehicle_index], int(MAX_SPEED * 4.0)]


func _select_vehicle(index: int) -> void:
    if index < 0 or index >= VEHICLE_NAMES.size():
        return
    selected_vehicle_index = index
    _rebuild_player_vehicle()
    _refresh_garage_info()
    _save_settings()


func _rebuild_player_vehicle() -> void:
    var old_position := Vector3.ZERO
    if is_instance_valid(player_car):
        old_position = player_car.position
        player_car.queue_free()
    if is_instance_valid(camera):
        camera.queue_free()
    player_car = null
    camera = null
    cockpit_camera = null
    _create_player()
    player_car.position = old_position
    _create_camera()
    camera_mode = 0
    camera.current = true
    cockpit_camera.current = false


func _on_engine_volume_changed(value: float) -> void:
    engine_volume = value
    _save_settings()


func _on_effects_volume_changed(value: float) -> void:
    effects_volume = value
    _save_settings()


func _on_music_volume_changed(value: float) -> void:
    music_volume = value
    if menu_audio:
        menu_audio.volume_db = linear_to_db(maxf(0.001, music_volume))
    _save_settings()


func _toggle_sound() -> void:
    sound_enabled = not sound_enabled
    if not sound_enabled:
        for audio_player in [engine_audio, brake_audio, nitro_audio, crash_audio, tire_audio, menu_audio]:
            if audio_player and audio_player.playing:
                audio_player.stop()
    _save_settings()
    # Rebuild only the menu label/button state by updating the existing sound button.
    for child in main_menu.get_children():
        if child is Button and (child.text.begins_with("SOUND:") or child.text == "SOUND"):
            child.text = "SOUND: ON" if sound_enabled else "SOUND: OFF"


func _start_mode(mode_name: String) -> void:
    drive_mode = mode_name
    game_started = true
    paused = false
    crashed = false
    speed = 0.0
    score = 0.0
    nitro = 100.0
    accelerating = false
    braking = false
    nitro_active = false
    steering_left = false
    steering_right = false
    steering_angle = 0.0
    if hud_root:
        hud_root.visible = true
    main_menu.visible = false
    settings_panel.visible = false
    garage_panel.visible = false
    message_label.visible = false
    restart_button.visible = false
    pause_button.text = "Ⅱ"
    _restart_race()
    # Restart preserves the selected mode and starts with a safe zero-speed state.
    speed = 0.0
    if menu_status_label:
        menu_status_label.text = "MODE: %s" % mode_name


func _show_main_menu() -> void:
    game_started = false
    paused = false
    crashed = false
    accelerating = false
    braking = false
    nitro_active = false
    steering_left = false
    steering_right = false
    if hud_root:
        hud_root.visible = false
    if main_menu:
        main_menu.visible = true
    if settings_panel:
        settings_panel.visible = false
    if garage_panel:
        garage_panel.visible = false
    if engine_audio and engine_audio.playing:
        engine_audio.stop()
    if nitro_audio and nitro_audio.playing:
        nitro_audio.stop()


func _show_settings() -> void:
    main_menu.visible = false
    settings_panel.visible = true
    garage_panel.visible = false


func _show_garage() -> void:
    main_menu.visible = false
    settings_panel.visible = false
    garage_panel.visible = true


func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_CLOSE_REQUEST:
        _save_settings()
        get_tree().quit()
