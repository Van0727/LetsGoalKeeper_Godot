extends Control

const PLAYER_MAX_HEALTH := 100
const ENEMY_MAX_HEALTH := 30

@onready var player_display := %PlayerDisplay
@onready var enemy_display := %EnemyDisplay

var _player_health := PLAYER_MAX_HEALTH
var _player_shield := 0
var _enemy_health := ENEMY_MAX_HEALTH


func _ready() -> void:
	player_display.configure("玩家", PLAYER_MAX_HEALTH, Color(0.55, 0.82, 1.0))
	enemy_display.configure("企鹅占位", ENEMY_MAX_HEALTH, Color(1.0, 0.58, 0.5))


func _on_damage_enemy_pressed() -> void:
	var damage := mini(6, _enemy_health)
	_enemy_health -= damage
	enemy_display.set_health(_enemy_health)
	enemy_display.show_damage(damage)


func _on_damage_player_pressed() -> void:
	var incoming_damage := 5
	var absorbed := mini(_player_shield, incoming_damage)
	_player_shield -= absorbed
	var health_damage := mini(incoming_damage - absorbed, _player_health)
	_player_health -= health_damage
	player_display.set_shield(_player_shield)
	player_display.set_health(_player_health)
	if health_damage > 0:
		player_display.show_damage(health_damage)
	else:
		player_display.show_shield_loss(absorbed)


func _on_heal_player_pressed() -> void:
	var previous_health := _player_health
	_player_health = mini(_player_health + 6, PLAYER_MAX_HEALTH)
	var healed := _player_health - previous_health
	player_display.set_health(_player_health)
	player_display.show_heal(healed)


func _on_shield_player_pressed() -> void:
	_player_shield += 6
	player_display.set_shield(_player_shield)
	player_display.show_shield_gain(6)


func _on_reset_pressed() -> void:
	_player_health = PLAYER_MAX_HEALTH
	_player_shield = 0
	_enemy_health = ENEMY_MAX_HEALTH
	player_display.set_health(_player_health)
	player_display.set_shield(_player_shield)
	enemy_display.set_health(_enemy_health)
	enemy_display.set_shield(0)


func _on_back_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
