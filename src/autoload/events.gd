extends Node
## 全局事件总线（autoload: Events）。系统之间通过信号解耦。

## 屏幕提示。kind: "info" | "good" | "warn" | "bad" | "loot" | "realm"
signal notify(text: String, kind: String)

## 玩家数据变化（属性、境界、装备等），UI 应刷新
signal player_changed
## 玩家背包/仓库变化
signal inventory_changed
## 境界或小境界变化
signal realm_changed(realm_idx: int, stage: int)
## 修为变化
signal exp_changed
## 游戏内时间推进（小时数）
signal time_advanced(hours: float)
## 新的一天
signal day_passed(day_index: int)

## 战斗
signal hit_landed(info: Dictionary)          ## 任意命中（UI 命中标记、跳字）
signal actor_died(actor: Node, killer: Node)
signal player_died
signal lock_target_changed(target: Node)

## 门派/任务/关系
signal sect_changed
signal missions_changed
signal relation_changed(npc_id: String)

## UI
signal open_panel(panel_name: String, args: Dictionary)
signal close_panels
signal dialogue_requested(npc_id: String, context: Dictionary)
signal interaction_prompt(text: String)      ## 空字符串表示隐藏
signal search_progress(progress: float)      ## <0 表示隐藏
signal hud_objective(text: String)           ## 屏幕上方的目标/计时文本（空字符串隐藏）
