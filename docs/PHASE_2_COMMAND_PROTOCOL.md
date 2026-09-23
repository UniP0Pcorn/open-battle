# 阶段二：命令协议收口

本阶段把本地对局日志整理成可供存档、回放和未来联机服务器共用的命令边界。

## 已完成

- 新增 `rules/command_schema.gd`，统一定义 MOVE、SHOOT、CHARGE、FIGHT、PHASE_ADVANCE、END_TURN、BATTLE_SHOCK、HAZARDOUS 和 STRATAGEM 九类命令。
- 统一检查序号、操作阵营、命令类型、载荷字段和阶段要求；只对需要字段的命令执行校验，避免各模块重复实现同一套规则。
- `rules/command_log.gd` 使用统一契约验证存档日志。
- `rules/replay.gd` 使用统一契约验证回放命令，并保留未知单位、越权阵营、错误阶段和非法目标的语义错误。
- `rules/battle_session.gd` 提供版本化权威会话：创建快照、推进阶段、提交命令，并把合法命令交给同一个回放入口执行。
- `rules/deployment.gd` 增加任务驱动的双方部署区检查；界面放置入口会拒绝越界或放入中场的底座，并绘制部署边界。
- 任务目标保留 JSON 中的 `points`，回合结算按目标分值计分，胜利提示显示真正达到分数的阵营。
- 复核表导出器会按来源清单预填 `source_id` 和默认阵营标识，候选仍保持 `pending_manual_review`，不会绕过底座与字段确认。
- 待复核 profile 元数据记录每个来源的候选数量，客户端同时显示待复核来源和候选记录总数。
- `rules/engagement.gd` 统一冲锋结束与近战目标的底座边缘距离，避免不同底座尺寸产生不同接战结果。
- 模型获得稳定 `model_id`，攻击命令按 ID 记录目标；回放会同步移除被淘汰模型，避免数组下标变化破坏重放。
- 阶段切换也写入 `PHASE_ADVANCE` 命令；界面、权威会话和回放现在能重建移动→射击→冲锋→战斗的完整阶段顺序，并拒绝跳过阶段。
- 射击、近战、冲锋、危险武器和战斗震慑命令会在回放入口确认模型 ID/索引、活动阵营和敌我关系，不能只伪造一个伤害值。
- 编成校验支持 profile 的 `organization.unique`、`organization.max_copies`、`organization.role`，以及军表的 `organization.minimum_roles`；未声明组织字段的原型 profile 行为保持不变。
- 新增回归覆盖：活动阵营可执行命令、错误阶段拒绝、缺字段载荷拒绝。

## 验证

```powershell
godot --headless --path . --script tests/run_tests.gd
```

当前结果：**236 项检查，0 失败**。

## 下一步

下一阶段继续从用户提供的本地来源逐条复核并晋升 profile，补齐任务/阵营边界，再把权威会话接入网络传输和房间生命周期；只有审核通过的兵牌进入可用目录。
