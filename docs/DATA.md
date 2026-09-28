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

icon 可选：sword saber spear fist robe armor pendant ring pill herb flower fruit ore crystal core stone scroll talisman bag seed hide bone key disc。

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
| nova | radius, knock, crater, visual |
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

## backgrounds.json（出身）
name, desc, stones, bag, items[[id, n]], equip{slot: id}, techniques[], spells[], stats{}, sect_choice?。

## sects.json（宗门）
name, element, profession(alchemy/forging/talisman/formation/herbalism), region, color/color2/color3, motto, desc, join{root{e: 最低占比}}, ranks[{name, rep, realm?, stage?}], techniques[{id, rank, cost}], spells[{id, rank, cost}], shop[{item, rank, cost}], npcs[{role, title, realm}], rivals[], mission_pool[]。

## statuses.json（状态）
name, type(debuff/buff/gauge/instant/control), element?, max_stacks, duration, dot(施加者攻击倍率/层/秒), hot(最大生命比例/秒), moving_mult, mods_per_stack{}, slow, root_status, root_duration, immune, color, desc。

## movesets.json（近战招式）
每种武器：lunge_range, lunge_speed, combo[{clip, dmg, range, arc(度), poise, knock, cancel(可衔接的剪辑进度 0~1), lunge?, launch?, heavy?}]。命中时机由剪辑中的 `"hit"` 事件决定。

## enemies.json（敌人）
- 妖兽 `kind: "beast"`：model(wolf/fox/boar/golem/...), element, realm, stage, mult{属性倍率}, speed, attacks[{name, dmg, range, cd, leap?, charge?, aoe?, projectile{element,speed,size}?, status?}], aggro, pack[min,max], colors[], size, drops[{item, chance, n?}]。
- 修士 `kind: "cultivator"`：faction, realm, stage[min,max], weapons[], spells[], roots("random" 或字典), ai(aggressive/balanced/cautious), outfit_colors?。

## secret_realms.json（秘境）
name, min_realm, theme(forest/ruins/volcano/ice/...), size(米), time_limit(秒), entry_cost, desc, enemies[{id, w}], enemy_groups[min,max], rivals[min,max], rival_ids[], containers{count[min,max], types[{type, w, table, time}]}, extracts。

## loot_tables.json
rolls[min,max], entries[{item, w(权重), n[min,max]?, grade?}]。

## recipes.json（配方）
name, profession, level, inputs[[id, n]], output[id, n], time(小时), success, desc?。

## missions.json（任务模板）
name, type(kill/deliver/spar/realm_item), targets[]/items[], count[min,max], min_rank, reward{contribution, stones, rep: [min,max]}, text（{target}{item}{count} 占位）。

## encounters.json（遭遇）
name, w(权重), desc。

## names.json / dialogue.json / appearance.json
- names：surnames, given_female, given_male, daoist, evil_titles。
- dialogue：按情境分组的台词数组；greet 按立场 righteous/neutral/evil 分组。
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
