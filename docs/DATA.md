# 数据格式（data/*.json）

所有列表型文件是 JSON 数组，每项带唯一 `id`。颜色为 `"#rrggbb"` 字符串。五行 id：`metal wood water fire earth`，无属性用 `none`。品阶 `grade`：0 凡 · 1 灵 · 2 玄 · 3 地 · 4 天 · 5 仙。

属性修正字典（`stats` / `mods`）的键见 `src/core/stats.gd` 的 `DEFAULTS`；`xxx_pct` 表示百分比加成。

## realms.json（数组，按序号）
| 字段 | 说明 |
|---|---|
| name, stages[] | 大境界名与小境界名 |
| lifespan | 寿元（年） |
| base{} | 该大境界初始的 max_hp/max_shield/max_qi/attack/defense/poise |
| growth | 每个小境界的成长比例（线性） |
| exp[] | 每个小境界升到下一层所需修为；最后一项为圆满（瓶颈） |
| cult_rate | 每小时打坐基础修为 |
| breakthrough{base, pill} | 突破到下一大境界的基础成功率与推荐丹药 |
| perks[] / perk_stats{} / perk_text{} | 质变解锁 |

## items.json
| 字段 | 说明 |
|---|---|
| name, type, grade, size[w,h], stack, value, icon, icon_color?, element?, tags[]?, desc | 通用。type：weapon armor accessory pill material currency manual talisman treasure bag formation seed key misc |
| weapon{kind, attack, stats{}, visual{}} | 兵刃。kind：sword saber spear fist；visual 传给 WeaponBuilder |
| equip{stats{}, visual{}} | 法衣/佩饰。法衣 visual 可覆盖外貌中的 outfit / outfit_colors |
| use{effect, ..., text, combat?} | 使用效果。effect：heal(amount=比例) qi shield buff(status,duration) cast(spell) exp(amount,toxicity) breakthrough(realm,bonus) heal_injury detox attribute(attr,amount)。combat=true 可在战斗中用 Q 使用 |
| refine{exp, element?} | 可炼化获得修为 |
| teaches{technique?/spell?} | 玉简学习 |
| bag{w,h} | 储物袋容量 |
| grow{item, n[min,max], hours}? | 灵种（type seed）：种下后经过 hours 小时长出 n 株 item（灵田/灵植系统用；配方 herbalism 亦可直接培育） |
| formation{kind, mult, days}? | 可布置阵盘（type formation）：kind `gather` = 布于洞府后 days 日内打坐修炼倍率 ×mult。一次性阵盘则用 use（shield / cast） |

icon 可选：sword saber spear fist robe armor pendant ring pill herb flower fruit ore crystal core stone scroll talisman bag seed hide bone key disc。

tags 约定：
- 类别：herb ore core hide stone silk wood bone feather venom organ puppet talisman_mat formation_mat token。
- 产地（可采集物）：forest snow lake volcanic plateau ruins（大地图生物群系）与 ice water battlefield（秘境主题）。大地图采集点可按生物群系标签挑选物品。

weapon.visual：kind, length(体素), blade, guard, grip（颜色）, glow(五行，发光), flag(旗面颜色，旗枪)。拳套的 blade 为拳套主色。
玉简 id 约定：`manual_<功法或法诀 id>`（历史遗留：manual_gengjin、manual_fireball）。每门功法与法诀都有对应玉简。

## spells.json（法诀）
| 字段 | 说明 |
|---|---|
| name, element, grade, qi, cd, cast_time, power, anim, desc | power 为攻击力倍率；anim 为 AnimLib 剪辑名 |
| kind | projectile nova strike dash shield buff heal field summon beam |
| params{} | 见下表 |
| status{id, stacks, chance} | 命中附加状态 |

| kind | params |
|---|---|
| projectile | count, spread(度), speed, size, homing(0~1), pierce, range, explode(半径), crater(弹坑半径), shape(orb/blade/spike), knock |
| nova | radius, knock, crater, visual(ring/blade/frost/flame/quake) |
| strike | radius, delay, range, count, spread, interval, visual(pillar/meteor/lightning), crater |
| dash | distance, speed, width |
| shield | amount(护盾比例), status, duration |
| buff | status, stacks, duration |
| heal | amount(比例), over(秒) |
| field | radius, duration, tick, range, slow |
| summon | count, duration, orbit, fire_rate, speed |
| beam | length, width, duration, tick |

## techniques.json（功法）
name, element, grade, slot(main/aux), cult_mult(主修), max_realm, stats{}, req{root{e: 最低占比}, realm}, desc。熟练度 0~3（入门/小成/大成/圆满），每级效果 +25%。

## talents.json（天赋）
name, cost（负数为缺陷返还点数）, category, desc, stats{}, flags[]。

flags：`see_grades`（秘境远观容器品阶）、`hunted`（劫修/血煞宗遭遇大增）、`longevity`（寿元 +20%）、`heart_demon`（闭关时易生心魔）。

## backgrounds.json（出身）
name, desc, stones, bag, items[[id, n]], equip{slot: id}, techniques[], spells[], stats{}, sect_choice?。

## sects.json（宗门）
name, element, profession(alchemy/forging/talisman/formation/herbalism), region, color/color2/color3, motto, desc, join{root{e: 最低占比}}, ranks[{name, rep, realm?, stage?}], techniques[{id, rank, cost}], spells[{id, rank, cost}], shop[{item, rank, cost}], npcs[{role, title, realm}], rivals[], mission_pool[]。

npc role：master（掌门）、teacher（传功长老，学功法/法诀）、steward（任务堂执事，领任务）、artisan（技艺长老，本门生产技艺）、elder（其他长老）、senior（师兄师姐）、junior（师弟师妹）。

## statuses.json（状态）
name, type(debuff/buff/gauge/instant/control), element?, max_stacks, duration, dot(施加者攻击倍率/层/秒), hot(最大生命比例/秒), moving_mult, mods_per_stack{}, slow, root_status, root_duration, immune, color, desc。

## movesets.json（近战招式）
每种武器：lunge_range, lunge_speed, combo[{clip, dmg, range, arc(度), poise, knock, cancel(可衔接的剪辑进度 0~1), lunge?, launch?, heavy?}]。命中时机由剪辑中的 `"hit"` 事件决定。

## enemies.json（敌人）
- 妖兽 `kind: "beast"`：model(wolf/fox/boar/bear/golem/snake/crane/spider，仅此八种), element, realm, stage, mult{属性倍率}, speed, attacks[{name, dmg, range, cd, leap?, charge?, aoe?, projectile{element,speed,size}?, status{id,stacks}?, buff?}], aggro, pack[min,max], colors[主色, 副色, 眼/点缀], size, biomes[], boss?, drops[{item, chance, n?}]。
  - attacks.name 仅限：bite（撕咬）、pounce（扑击，leap）、charge（冲撞，charge）、slam（重砸，aoe 半径）、spit（喷吐，projectile）、howl（嚎叫，buff）。
  - howl 的 `buff{status, stacks, duration, radius}`：给自身与 radius 内同伴施加增益（dmg 为 0）。
  - `biomes[]`：大地图刷新的生物群系（forest snow lake volcanic plateau ruins）。
  - `boss: true`：妖王/首领，体型 1.8~2.5，秘境 `boss` 字段引用。
  - drops.n：整数或 [min,max]。
- 修士 `kind: "cultivator"`：faction(宗门 id / xuesha / robber / none), alignment(righteous/neutral/evil，决定台词 greet 分组), realm, stage[min,max], weapons[], spells[], roots("random" 或字典), ai(aggressive/balanced/cautious), technique?(主修功法), armor?(法衣物品 id), outfit_colors?, loot?(死亡时储物袋按此掉落表生成)。

## secret_realms.json（秘境）
name, min_realm, theme(forest/ruins/volcano/ice/water/battlefield), size(米), time_limit(秒), entry_cost(灵石), token?(进入时消耗一枚的信物物品 id), desc, enemies[{id, w}], enemy_groups[min,max], boss?(首领妖兽 id，守在最深处的祭坛旁), rivals[min,max], rival_ids[], containers{count[min,max], types[{type, w, table, time}]}, extracts。

容器 type：herb_patch（药圃）、chest（宝箱）、ore_vein（矿脉）、corpse（修士遗骸）、altar（祭坛）、cauldron（丹炉）、bookshelf（书架）。

## loot_tables.json
rolls[min,max], entries[{item, w(权重), n[min,max]?, grade?}]。grade 覆盖物品实例品阶（如高品阶的精铁剑）。

命名：`<容器>_t<档位>`，t0 炼气 / t1 筑基 / t2 金丹；主题变体如 herb_patch_fire_t0、ore_vein_ice_t1、herb_patch_water_t1。低权重条目为“大奖”。

## recipes.json（配方）
name, profession, level, inputs[[id, n]], output[id, n], time(小时), success, desc?。

## missions.json（任务模板）
name, type(kill/deliver/spar/realm_item), targets[]/items[], count[min,max], min_rank, reward{contribution, stones, rep: [min,max]}, text（{target}{item}{count} 占位）。

realm_item：任务物品会出现在秘境容器中（宗门古籍记载的遗物），带出秘境后上交。

## encounters.json（遭遇）
name, w(权重), desc, lines[]?（desc 的随机变体）。w 为 0 的遭遇为规划中（merchant / elder_guidance / demon_ambush），代码支持后再调高权重。

## names.json / dialogue.json / appearance.json
- names：surnames, given_female, given_male, daoist, evil_titles。
- dialogue：按情境分组的台词数组（每组 ≥ 8 句）；greet 按立场 righteous/neutral/evil 分组；friend_tiers 按关系 acquaintance/friend/confidant 分组。
  其余分组：friend lover confess confess_accept confess_reject master（师尊对弟子） disciple（弟子对师尊） apprentice（收徒） rival（仇敌）
  spar_invite spar_win（NPC 落败） spar_lose（NPC 获胜） robber_demand robber_paid robber_refuse robber_flee（玩家逃脱）
  gift_thanks gift_meh gift_love gift_dislike teach trade attacked flee rescued rescue_plea farewell breakthrough death
  treasure_contest witness（目击袭杀） sect_greet steward rumors（世界传闻）。
- appearance：捏人可选项（hair_styles, eye_styles, marks, ears, tails, horns, outfits 的 {id,name}）与调色板（hair_colors, eye_colors, skin_colors, outfit_palettes）。

## 外貌字典（appearance，存于 PlayerData.appearance 与 NPC）
```
gender: "female"|"male"      height: 0.9~1.1      build: 0~1      head_scale: 0.9~1.15   chest: 0~1
skin, hair_color, hair_color2(挑染), eye_color, mark_color, ear_color: "#rrggbb"
hair_style: twin_tails|ponytail|long|short|bun|flowing
eye_style: almond|round|sharp      brow_style: 0~2      mark: none|lotus|flame|dot
ears: human|fox|cat|elf      tail: none|fox      horns: none|dragon
outfit: robe|martial|armor   outfit_colors: [主色, 副色, 饰边]
```
