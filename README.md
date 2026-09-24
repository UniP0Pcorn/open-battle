# open-battle

Godot 4 原生 GDScript 数字桌面对战原型。当前实现本地二维俯视移动沙盒，项目许可证为 **AGPL-3.0-only**，仅第 3 版，不包含“或后续版本”授权。

## 启动

1. 安装 [Godot 4 标准版](https://godotengine.org/download/windows/)（无需 .NET）。基准版本为 **4.5.1**。
2. 在项目管理器点击“导入”，选择本目录 `project.godot`。
3. 打开项目，按 **F6** 运行当前场景，或 **F5** 运行项目。

命令行（将 `godot` 替换为本机 Godot 可执行文件路径）：

```sh
godot --path . --editor
godot --path .
godot --headless --path . --script tests/run_tests.gd
```

无需插件、外部素材、Node.js 或网络服务。工程打开后即可运行；本仓库不附带 Godot 引擎安装包或独立游戏可执行文件。

## 操作

| 操作 | 效果 |
| --- | --- |
| 左键选择并拖动底座 | 显示本次直线距离和累计移动额度；松开提交 |
| P / Place Base | 切换放置模式，点击桌面放置底座，可连续放置 |
| Tab / Switch Side | 切换新底座颜色，不限制控制现有棋子 |
| Esc | 取消拖动或退出放置模式 |
| N / New Move Phase | 指挥阶段进入移动阶段；本地沙盒在其他阶段仍可重置测试额度 |
| F7 / 战斗震慑检定 | 指挥阶段逐单位提交战斗震慑检定；联机由主机确定性生成 2D6 |
| Q / Advance | 当前单位在移动阶段掷 D6 增加移动额度；前进后只能用突击武器射击，不能冲锋 |
| Z / Fall Back | 接战单位宣布撤退后拖动离开接战范围；本回合不能射击或冲锋 |
| R / Reset Table | 清空修改并恢复初始 10 对 10 底座 |
| I / Cycle Profile | 从已复核 profile 目录切换当前可用兵牌并重建双方编成 |
| - / = | 减少或增加当前编成中的单位数量；超过分数上限的修改会被拒绝 |
| A / D | 添加当前 profile 的单位条目，或移除最后一个单位条目 |
| , / . | 以 100 点为步长降低或提高军表分数上限；低于当前编成分数会被拒绝 |
| B | 打开或关闭编成详情面板 |
| W | 循环选择当前 profile 的武器配置 |
| T / End Turn | 切换当前操作阵营，只能移动当前阵营的底座 |
| U / Undo Move | 撤销最近一次已提交的移动 |
| Space / 进入射击阶段 | 锁定移动，进入当前阵营的射击阶段 |
| F / 射击最近目标 | 对射程内最近的敌方底座进行一次原型武器攻击 |
| C / 进入冲锋阶段 | 从射击阶段进入冲锋阶段 |
| G / 执行冲锋 | 为选中的当前阵营底座掷 2D6，并尝试冲向最近敌方目标 |
| V / 进入战斗阶段 | 从冲锋阶段进入战斗阶段 |
| X / 近战攻击 | 对接战距离内最近敌方底座进行一次原型近战攻击 |
| Y / 指挥重掷 | 消耗 1 点指挥点，让下一次攻击重掷一次未命中的命中骰 |
| S / 保存 | 保存当前回合、分数、位置、移动额度、伤口、profile 和编成到本机存档 |
| L / 加载 | 读取本机最近一次存档 |
| K / 导出军表 | 将当前编成写入 `user://open_battle_roster.json` |
| O / 导入军表 | 读取并校验本机军表文件，失败时保留当前编成 |
| J / 单机 AI 回合 | 金方结束回合后，蓝方 AI 通过权威会话完成一整回合 |
| M / 联机大厅 | 打开本地账号、主机房间、加入房间和断线重连界面 |

桌面横向 60 英寸、纵向 44 英寸。每格 1 英寸，底座直径 40mm，即约 1.5748 英寸。窗口缩放只改变显示，不改变规则单位。权威会话快照会通过 `rules/model_state.gd` 检查稳定模型 ID、单位归属、阵营和坐标，网络传输可复用同一入口。

选中底座后，圆环显示剩余移动半径。拖动显示本次移动距离，右侧显示累计值。超过额度、整个底座不能留在桌面内、落点与其他底座重叠、或直线路径穿过其他底座时，预览标红并显示原因；松开后退回原位置，额度不变。合法移动累计消耗额度，多次拖动不能绕过限制。结束回合后，另一方才能操作自己的底座；撤销只影响最近一次已提交的移动。

射击阶段使用 `data/units/custodian_guard.json` 中的可配置测试武器，先由规则层验证攻击者属于当前阵营、目标属于敌方且处于射程内，再按攻击次数、命中值、力量、目标韧性、豁免、掩体和伤害计算结果。被减至 0 伤口的底座会从桌面移除；模型有 `feel_no_pain` 时，回放命令必须携带逐点 D6 结果，规则层会重新校验并应用忽略伤害。指挥点和策略资源由 `rules/command_points.gd` 校验；`rules/stratagems.gd` 提供可注册的策略定义、阶段/资源校验和回放效果记录，能力定义支持常驻修正与事件修正。回合交接时桌面会按记录的单位初始规模触发战斗震慑检定，结果写入命令日志和存档，震慑单位不能控制目标。所有这些数值均为原型配置，不代表任何已核验的官方规则版本。

桌面中央有一个 3 英寸控制半径的目标点。回合结束时，任务规则会计算每个目标的控制权和数据中的分值；达到任务目标分数后显示完成，并保留实际得分阵营。任务从 `data/missions/control_center.json` 加载，还可以声明矩形地形；底座不能穿过地形，地形会阻挡射击视线，并可通过 `cover_bonus` 修改目标豁免值；任务控制判定同时识别 `can_control=false` 和战斗震慑状态。单机 AI 通过 `client/battlefield/tabletop.gd` 的 `run_single_player_ai()` 调用 `rules/ai_player.gd`，不会绕过权威命令校验。军队示例和通用编成校验位于 `data/armies/` 与 `rules/army_validation.gd`；`rules/army_builder.gd` 会把版本化兵牌 profile 展开成可上桌的多模型单位，并拒绝版本不匹配的编成，棋盘初始化已通过该构建器读取原型 roster。保存文件写入 Godot 的 `user://` 目录，不进入仓库；加载前会验证 JSON 结构和命令日志序列，损坏或篡改的存档会被拒绝并保留当前对局。

## 测试单位与数据

任务数据进入桌面前由 `rules/mission_validation.gd` 校验目标位置、目标分值、部署纵深和地形边界，避免无效任务配置在运行时才暴露。

移动预览和提交逐个检查单位内每个模型的 `movement_inches` 和 `spent`；整队平移必须满足所有成员的剩余额度，选中单位的移动圆环显示其中的最小值。模型实例同时保存连结距离；新存档保留移动、底座尺寸、武器、能力、普通/无敌豁免和目标控制等模型属性。旧存档缺失的属性仍使用当前原型默认值，无法恢复旧文件从未记录的兵牌差异。

接战单位不能进行普通移动，必须先按 `Z` 宣布撤退；撤退必须结束在接战范围外，模型会记录 `fell_back`，随后本回合的射击和冲锋入口都会拒绝该单位。

`data/units/custodian_guard.json` 使用 Custodian Guard 名称、40mm 底座和 **6 英寸测试移动额度**。6 英寸是可编辑的原型假设，未按某个官方规则版本核验。本项目不包含官方长篇规则文字、美术、徽记、模型或军表数据库。

`rules/roster_editor.gd` 提供编成创建、添加、移除、阵营与版本检查、分数计算和 profile 就绪状态校验；界面层可以直接复用它，避免绕过编成规则修改 JSON。
桌面初始化和兵牌切换会自动把当前 profile 的 faction 写入军表，随后所有添加、数量和分数编辑都继续经过阵营校验。
编成校验还支持由 profile 声明的 `organization.unique`、`organization.max_copies`、`organization.role`，以及军表声明的 `organization.minimum_roles`；未声明这些字段的原型数据不会被额外限制。
`rules/army_builder.gd` 会在展开军表时校验版本、阵营一致性和 profile 的最小结构，发现未完成兵牌会拒绝上桌；展开后的模型会携带豁免、领导力、目标控制、能力、关键词和武器数据。
`rules/profile_catalog.gd` 同时支持单目录和递归目录索引；桌面运行时递归扫描 `data/units/`，因此放入 `imported/` 等子目录的正式 profile 会进入兵牌循环和目录统计。
目录的 ready/verified/prototype profile 会先经过 `rules/datasheet_validation.gd` 结构校验；状态标记本身不足以让缺字段或未知关键词的兵牌进入可用目录。
`rules/unit_abilities.gd` 提供可执行能力 ID 的注册、校验和数值修正；`datasheet_validation.gd` 会拒绝没有执行器的能力。
能力层同时提供中文/英文别名规范化，例如“隐匿”“斥候6英寸”“深入打击”会映射到稳定的内部 ID。
`rules/unit_keywords.gd` 规范化单位关键词；profile 校验会拒绝未知单位关键词，但允许来源自定义阵营关键词。
`rules/weapon_rules.gd` 负责武器关键词规范化和攻击上下文，例如喷射自动命中、忽略掩体和半程速射。
数值速射（如 `速射1`、`速射2`）在半程按数值增加攻击，`D3/D6` 攻击表达式也会保留；无数字的 `速射` 继续作为原型兼容简写。
数值热熔（如 `热熔2`、`热熔3`）在半程按数值增加每次攻击的伤害，固定伤害与 `D6` 伤害表达式都能进入同一解析路径。
针对关键词（如 `针对步兵4+`）在目标拥有匹配单位关键词时覆盖致伤阈值；双联会重掷失败致伤骰，致命一击会把未修正命中 6 转为自动致伤，持续命中 X 会增加命中事件。目标关键词不匹配时不会套用针对修正。
重型武器通过模型本回合的移动消耗判定：模型保持 `spent=0` 时命中值改善 1，发生移动后不保留该修正；界面和规则上下文使用同一移动状态。
手枪使用同一套底座接战几何：接战中的非手枪不能射击，手枪只能指定接战范围内的敌方目标。
曲射武器可以指定被矩形地形挡住的目标；规则层对该攻击加 1 命中阈值并给予目标掩体修正，普通武器仍需要清晰视线。一次性武器会在成功提交射击或近战事件后记录消耗状态，回放和权威校验都会拒绝第二次使用。
`lone_operator` 能力已接入远程目标筛选：距离超过 12 英寸时不能被远程指定，近距离仍可正常攻击。
`rules/datasheet_validation.gd` 会校验武器的攻击次数和伤害骰面是否能由 `rules/dice.gd` 执行；JSON 数字、`D3`、`D6`、`2D6+1` 等受支持表达式可直接进入 profile。
`rules/battle_shock.gd` 提供半数模型阈值判断、2D6 领导力检定以及按单位写入震慑和目标控制状态的辅助函数。
危险武器会记录失效次数，并将自伤作为独立命令写入命令日志；伤害值可由武器 profile 覆盖，默认值仅用于原型。
武器上下文还支持爆炸（按目标单位模型数增加攻击）和毁灭伤害（自然致伤 6 跳过普通豁免）。
`rules/replay.gd` 可以从初始棋盘和命令日志重建移动、前进、撤退、冲锋、回合、战斗震慑以及射击/近战/危险武器造成的伤口状态，并拒绝序列断裂、未知单位、非法伤害事件或越权命令。
`rules/command_schema.gd` 集中定义十一类命令的字段和阶段契约；存档、回放和未来服务器共享同一验证入口，避免不同入口接受不同的命令格式。
阶段推进会记录为 `PHASE_ADVANCE` 命令；回放会验证移动、射击、冲锋、战斗之间的顺序，不能通过日志跳过阶段。
回放入口还会确认攻击者属于活动阵营、目标属于敌方且引用的模型仍存在；客户端日志、存档和未来服务器因此共享同一组最小归属校验。
`rules/battle_session.gd` 提供版本化权威会话快照、阶段推进和命令提交入口，网络层可以直接复用它进行服务器端验证。
`rules/deployment.gd` 和任务 JSON 的 `deployment_depth_inches` 提供双方部署区校验；放置底座时会检查阵营、桌面边界和已有底座重叠。
`rules/engagement.gd` 统一按双方底座边缘距离判断接战；冲锋结束和近战目标选择会使用同一几何结果。
每个上桌模型还带有稳定 `model_id`；射击、近战、冲锋和危险武器命令会记录模型 ID，回放在模型被淘汰后仍能正确找到后续目标。
桌面阶段状态会同步到 `rules/turn_state.gd` 的版本化状态结构，阶段索引、活动阵营、回合数和指挥点会随对局存档恢复。
`rules/ruleset_catalog.gd` 注册当前可执行的 10E 和 11E 规则集；兵牌校验会拒绝未注册的 edition，避免把未知版本误当作可运行规则。

对用户提供的 PDF，可用 `tools/extract_profile_candidates.py` 生成只包含页码、属性、武器表和分数候选值的人工复核文件：

```powershell
$env:PYTHONIOENCODING='utf-8'
python tools/extract_profile_candidates.py <source.pdf> --edition 11 --output work/candidates.json
```

候选文件只用于复核和后续导入，不会把整段规则说明复制进项目；确认字段后再转换为 `data/units/*.json` 兵牌。
批量处理来源清单可运行 `tools/extract_all_sources.py --source-root <pdf目录> --output-dir work/source_candidates`，每条候选都保留来源文件名和页码。
提取器会跨越属性表与武器表之间的能力段落，支持没有英寸符号的射程、带空格的“个模型/分”价格，并把射击与近战武器技能列拆成结构化标签；无法确定的多模型价格仍留在待复核状态。
运行 `python tools/build_profile_drafts.py work/source_candidates --output-dir work/profile_drafts` 可生成逐条待复核草稿；草稿保留骰面表达式与来源页码，明确标记为不可上桌的 `pending_manual_review`。
确认底座、连结距离、阵营及所有字段后，可用 `tools/promote_profile_draft.py` 严格转换为正式 profile；候选草稿中的能力、单位关键词、阵营关键词和来源备注会保留，攻击次数和伤害允许规则层已支持的 `D3/D6/2D6` 等表达式，其余不受支持的骰面或缺失字段仍会失败，不会静默猜值。
`tools/index_promotable_candidates.py` 会生成 `work/promotable_candidates.json`，列出字段结构完整但仍需明确底座与阵营的候选，并统计被复杂骰面或缺失字段拦截的记录。
`tools/export_profile_review_sheet.py` 可将 `work/profile_drafts/` 导出为 `work/profile_review.csv`，并从 `data/sources/manifest.json` 自动填入 `source_id` 和默认阵营标识，供人工补录底座尺寸、编队信息并逐条标记审核决定；导出表只含结构化数值和来源页码，默认阵营仍可人工覆盖。`review_bucket` 与 `review_flags` 会列出缺失分数/武器/关键词、非数字属性、复杂武器骰面和未实现武器标签，帮助按问题类型分批处理，但所有行仍保持 `pending_manual_review`。`tools/promote_profile_draft.py` 会拒绝带未执行武器标签的草稿。
`tools/generate_profile_stubs.py --review-csv work/profile_review.csv` 会把每个来源的候选数量回写到 `data/units/pending/` 元数据；客户端显示来源数与候选数，但候选仍不能上桌。
`tools/rebuild_profile_catalog.py` 会递归重建 `data/units/catalog.json`，把正式和待复核 profile 的路径、版本、阵营与状态同步到索引。

## 目录

```text
client/battlefield/  主场景、绘制、输入和简易侧栏
rules/              独立的英寸制几何与移动判定
data/units/         版本化 JSON 兵牌 profile
data/sources/       外部规则与兵牌来源清单
tests/              无第三方依赖的 Godot 测试入口
docs/               架构、验证记录和下一步
third_party/        引擎许可证及其上游版权清单
LICENSE             GNU AGPL v3 完整正文
THIRD_PARTY_NOTICES.md  第三方与名称说明
```

核心规则章节到工程模块的映射见 `docs/CORE_RULE_MAP.md`。

## 当前限制

- 客户端仍是二维沙盒；大厅界面、P2P 包、ENet 传输、任务/比分权威快照和桌面快照载入已接入，桌面表现与更多操作还在继续完善，3D 表现也未加入。
- 规则层已有可测试的两人房间生命周期、断线重连状态、P2P 命令包/快照包、ENet 传输入口和挑战式账号身份模块（`rules/room.gd`、`rules/peer_protocol.gd`、`client/p2p_transport.gd`、`rules/account_identity.gd`）；大厅支持导出/导入配对凭据并持久化信任记录，公网打洞仍待接入。
- 客户端已按 `unit_id` 同步拖动多模型单位，规则层会检查连续性和外部阻挡。地形目前使用矩形阻挡和采样视线，复杂地形类别和完整任务规则仍待实现。
- 每次拖动按起点到终点的直线长度计算，不跟随鼠标轨迹；直线路径会按半个底座半径采样，阻挡检查不能被终点位移绕过。需要折线移动时分段拖动，各段累计。
- 已提交的移动、射击和结束回合会写入可序列化命令日志，并随本机存档保存，供回放和服务器校验复用。
- New Move Phase 是手动测试按钮，可随时重置双方额度，不代表正式阶段规则。
- 原型界面为英文，说明文档为中文。窗口逻辑尺寸 1280×860，采用等比例单位绘制；无缩放/平移镜头。

## 许可证与来源

本项目原创代码、说明及原创测试配置按 AGPL-3.0-only 提供，详见 `LICENSE`。第三方许可证文本及第三方名称保留原有权利。源码中的 SPDX 标识与此一致。

Warhammer 40,000、Custodian Guard 等相关名称属于各自权利人，包括 Games Workshop。本项目为非官方社区原型，与 Games Workshop 无隶属或授权关系。AGPL 授权不覆盖第三方商标或官方素材。参见 `THIRD_PARTY_NOTICES.md`。

交互方向参考了 [New Recruit](https://www.newrecruit.eu/) 公开介绍的编成校验、跨设备列表同步、分享与离线使用等能力；本项目的大厅和规则数据保持独立。

当前回归：Godot **385 项检查，0 失败**；下一阶段继续完善公网连接，再按来源逐条复核并导入正式兵牌目录。
