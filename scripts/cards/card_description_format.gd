@tool
# 卡牌描述展示格式：只标记数值，不回写配表或改变战斗结算。
extends RefCounted

const ATTACK := "#df352f"
const DEFENSE := "#247bd1"
const HEAL := "#23994d"
const ENERGY := "#d49a00"


# 同时返回纯文本及富文本；纯文本供提示使用，避免 BBCode 泄露到玩家界面。
static func format_description(source: String) -> Dictionary:
	var regex := RegEx.new()
	regex.compile("[+-]?[0-9]+(?:\\.[0-9]+)?%?")
	var plain := ""
	var rich := ""
	var cursor := 0
	for found in regex.search_all(source):
		var start := found.get_start()
		var end := found.get_end()
		var before := source.substr(cursor, start - cursor).strip_edges(false, true)
		var value := found.get_string()
		var color := _value_color(source.substr(0, start), source.substr(end))
		plain += before + " " + value + " "
		rich += escape_bbcode(before) + " "
		rich += ("[color=%s]%s[/color]" % [color, value]) if not color.is_empty() else value
		rich += " "
		cursor = end
		while cursor < source.length() and source[cursor] == " ":
			cursor += 1
	var tail := source.substr(cursor)
	return {"plain": plain + tail, "rich": rich + escape_bbcode(tail)}


# 对每个数值就近识别单位；次数、拍数、概率保持原色，不按整张卡类别染色。
static func _value_color(before: String, after: String) -> String:
	var suffix := RegEx.new()
	suffix.compile("^\\s*(?:点)?(香蕉球伤害|伤害|护盾|生命|能量)")
	var found := suffix.search(after)
	var effect := found.get_string(1) if found != null else ""
	if effect.is_empty():
		var prefix := RegEx.new()
		prefix.compile("(伤害|护盾|生命|能量)(?:变为|值)?\\s*$")
		found = prefix.search(before)
		if found != null:
			effect = found.get_string(1)
	match effect:
		"伤害", "香蕉球伤害": return ATTACK
		"护盾": return DEFENSE
		"生命": return HEAL
		"能量": return ENERGY
	return ""


# 将源文中的方括号转成字面量，防止自定义描述意外被解析为富文本指令。
static func escape_bbcode(source: String) -> String:
	return source.replace("[", "[lb]")
