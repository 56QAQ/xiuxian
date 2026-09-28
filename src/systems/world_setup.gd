class_name WorldSetup
## 新世界初始化与时间推进时的世界模拟。具体逻辑分别在 NpcSystem / SectSystem 中。


static func init_world(world: Dictionary, player: PlayerData, seed_value: int) -> void:
	var sects := {}
	for sid in DB.sects:
		sects[sid] = {"missions": [], "last_refresh": -999}
	world["sects"] = sects
	if player.sect != "":
		player.contribution[player.sect] = 0
		player.reputation[player.sect] = 0
	NpcSystem.generate_world_npcs(world, seed_value)


## 时间跨天（闭关等）时推进世界
static func simulate_days(world: Dictionary, player: PlayerData, days: int) -> void:
	NpcSystem.simulate_days(world, days)
	SectSystem.simulate_days(world, player, days)
