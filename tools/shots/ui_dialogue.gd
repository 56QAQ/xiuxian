extends RefCounted
## 界面截图：对话（头像、打字机、选项/禁用提示）

var ui: UIManager
var w: DialoguePanel


func frames() -> int:
	return 36


func build(root: Node) -> void:
	UIShotCommon.new_game()
	UIShotCommon.backdrop(root)
	ui = UIShotCommon.manager(root)


func step(_root: Node, frame: int) -> void:
	if frame == 1:
		w = ui.open("dialogue", {
			"name": "云清雪", "title": "天剑宗 · 二师姐 · 炼气七层",
			"text": "师弟，你来得正好。后山剑冢近日剑气翻涌，恐有异宝出世。掌门命我前去查探，你可愿与我同行？此行凶险，若是修为不济，还是留在宗门为好。",
			"portrait_appearance": {"gender": "female", "hair_style": "long", "hair_color": "#e8ecf4", "eye_color": "#3080f0", "ears": "human", "outfit": "robe", "outfit_colors": ["#e8ecf4", "#4a5a78", "#d8b050"], "mark": "lotus"},
			"options": [
				{"text": "愿随师姐同往。", "callback": Callable()},
				{"text": "（切磋）先让师弟领教师姐的剑法。", "callback": Callable(), "hint": "好感 +5"},
				{"text": "（赠礼）将【千年雪莲】赠予师姐。", "callback": Callable(), "disabled": true, "hint": "储物袋中没有"},
				{"text": "师弟修为尚浅，改日再说。", "callback": Callable()},
			],
		})
	if frame == 30 and w != null:
		w._finish()
