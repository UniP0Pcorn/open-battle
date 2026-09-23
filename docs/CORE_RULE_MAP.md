# 11 版核心规则模块映射

来源：用户提供的 `11版核心规则简中 (2).pdf`。本文只记录章节结构和工程规划，不复制规则正文。

| 核心章节 | 工程模块 | 当前状态 |
| --- | --- | --- |
| 核心概念：军队、单位、模型、距离、骰子 | `rules/model_state.gd`、`rules/dice.gd` | 待实现 |
| 数据卡：属性、武器、关键词、能力 | `data/units/*.json`、`rules/datasheet_validation.gd`、`rules/army_builder.gd` | 已有版本化数据契约、结构校验和编成展开 |
| 移动、部署、连续性、交战状态 | `rules/movement.gd`、`rules/unit_validation.gd`、`rules/unit_movement.gd`、`rules/deployment.gd`、`rules/engagement.gd` | 已加入多模型连续性、部署区和底座边缘接战校验 |
| 选择武器、选择目标、解析攻击 | `rules/combat.gd` | 有原型射击，待补完整攻击流程 |
| 命中、致伤、豁免、造成伤害 | `rules/combat.gd`、`rules/dice.gd` | 命中/致伤/伤害有原型，豁免待实现 |
| 战斗轮和玩家回合 | `rules/turn_state.gd` | 当前只有本地移动/射击阶段 |
| 指挥阶段、指挥点和战斗震慑 | `rules/turn_state.gd`、`rules/command_points.gd`、`rules/battle_shock.gd` | 已有阶段、指挥点和震慑检定，完整指挥能力待实现 |
| 移动阶段 | `rules/movement.gd` | 已有基础移动、边界、重叠和路径阻挡 |
| 射击阶段 | `rules/combat.gd` | 已有敌我和射程验证，待补单位/武器选择 |
| 冲锋阶段 | `rules/charge.gd` | 待实现 |
| 战斗阶段、贴靠、合并和近战攻击 | `rules/melee.gd`、`rules/engagement.gd` | 已有接战距离和近战攻击原型，完整单位合并/分配仍待扩展 |
| 地形、视线、掩体、遮蔽 | `rules/terrain.gd`、`rules/visibility.gd`、`rules/combat.gd` | 已有矩形阻挡、采样视线和 `cover_bonus` 豁免修正，复杂掩体类别待实现 |
| 目标点和任务胜负 | `rules/mission.gd` | 已抽出目标控制、目标分值和胜负判定，任务条件仍待扩展 |
| 战略点、核心策略和行动 | `rules/stratagems.gd`、`rules/actions.gd` | 待实现 |
| 运输工具、附属单位、预备队、飞行单位 | `rules/advanced_rules.gd` | 待实现 |

## 实施顺序

1. 把当前单模型结构提升为“单位包含模型”的状态模型。
2. 增加单位连续性、交战状态和部署合法性。
3. 完成攻击流程中的豁免、伤害、分配和移除。
4. 把本地阶段改为可校验的战斗轮状态机。
5. 增加地形与视线，再接入冲锋和近战。
6. 最后导入派系数据，并让每份数据声明版本、来源和更新时间。
