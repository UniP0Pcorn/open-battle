# 阶段一收尾：规则引擎、编成和数据导入基础

## 阶段结果

本阶段把项目从移动沙盒推进到可运行的本地数字对战原型：规则逻辑集中在 `rules/`，Godot 场景负责输入、显示和命令日志，JSON profile 与军表负责数据驱动。桌面流程已覆盖移动、射击、冲锋、近战、目标控制、战斗震慑、指挥点、存档和确定性回放。

最终回归命令：

```powershell
godot --headless --path . --script tests/run_tests.gd
```

最后一次验证结果：**264 项检查，0 失败**。

## 已交付能力

- 版本化规则集目录：注册 10E/11E，profile 和军表校验版本与阵营一致性。
- 军表编辑：单位条目、数量、分数上限、阵营设置、JSON 导入/导出和回滚式校验。
- 对战流程：移动额度与队形连续性、前进、地形阻挡、视线/曲射、射击、手枪接战限制、掩体、普通/无敌豁免、冲锋、近战、危险武器、爆炸、毁灭伤害、目标控制和战斗震慑。
- 状态一致性：`TurnState`、指挥点、模型独立移动/属性、损伤状态、命令日志和本机存档同步。
- 回放：移动、前进、冲锋、回合、战斗震慑、射击/近战伤害和危险武器事件可验证重放。
- 兵牌工具链：PDF 候选提取、草稿生成、复核表导出、严格晋升、批量晋升和 profile 目录重建。
- 数据索引：30 个来源记录、30 个待复核 profile、31 个目录索引条目；候选工作区当前有 643 个草稿，44 条结构字段完整候选，其中 22 条已通过当前可执行武器标签筛选，仍需人工确认底座、阵营与编成字段。

## 数据边界

仓库不包含用户提供的 PDF 原件，也不复制长篇官方规则文本、美术或徽记。待复核数据只保留结构化属性、来源文件名和页码；正式 profile 只有在阵营、底座尺寸、连结距离、武器选项和能力字段确认后才能进入可用目录。原型 profile 的数值仍应视为测试配置，不能宣称已核验为官方版本。

## 当前限制与下一阶段

- 当前仍是本地 Godot 原型，没有联机房间、账号权限、服务器权威状态或 3D 表现。
- 规则模块覆盖了主要流程，但完整版本规则、任务、阵营能力、编队限制和全部兵牌仍需按来源逐条复核并导入。
- 继续工作时优先顺序：复核并晋升首批 profile，补齐任务/阵营规则边界，建立服务器权威命令协议，再实现联机同步和发布构建。

## 复现入口

```powershell
python tools/extract_all_sources.py --source-root <pdf目录> --output-dir work/source_candidates
python tools/build_profile_drafts.py work/source_candidates --output-dir work/profile_drafts
python tools/export_profile_review_sheet.py
python tools/rebuild_profile_catalog.py
godot --headless --path . --script tests/run_tests.gd
```
