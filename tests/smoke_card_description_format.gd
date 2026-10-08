# 验证卡牌数值格式：混合效果独立着色、小数及未知单位、空描述与字面括号。
extends SceneTree

const FORMAT := preload("res://scripts/cards/card_description_format.gd")


func _initialize() -> void:
	var result := FORMAT.format_description("造成6点伤害，获得5点护盾，恢复3点生命，消耗1点能量")
	assert(result.plain == "造成 6 点伤害，获得 5 点护盾，恢复 3 点生命，消耗 1 点能量")
	for pair in [["6", FORMAT.ATTACK], ["5", FORMAT.DEFENSE], ["3", FORMAT.HEAL], ["1", FORMAT.ENERGY]]:
		assert(result.rich.contains("[color=%s]%s[/color]" % [pair[1], pair[0]]))
	assert(FORMAT.format_description("以0.25拍攻击4次").rich == "以 0.25 拍攻击 4 次")
	assert(FORMAT.format_description("伤害+2").rich.contains("[color=%s]+2[/color]" % FORMAT.ATTACK))
	assert(FORMAT.format_description("伤害变为1.5倍").rich.contains("[color=%s]1.5[/color]" % FORMAT.ATTACK))
	assert(FORMAT.format_description("").rich == "")
	assert(FORMAT.format_description("[测试]").rich == "[lb]测试]")
	assert(FORMAT.format_description("造成 6 点伤害").plain == "造成 6 点伤害")
	print("smoke_card_description_format: PASS")
	quit()
