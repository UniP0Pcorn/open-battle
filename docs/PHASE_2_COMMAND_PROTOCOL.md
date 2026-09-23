# 阶段二：命令协议收口

本阶段把本地对局日志整理成可供存档、回放和未来联机服务器共用的命令边界。

## 已完成

- 新增 `rules/command_schema.gd`，统一定义 MOVE、SHOOT、CHARGE、FIGHT、END_TURN、BATTLE_SHOCK、HAZARDOUS 和 STRATAGEM 八类命令。
- 统一检查序号、操作阵营、命令类型、载荷字段和阶段要求；只对需要字段的命令执行校验，避免各模块重复实现同一套规则。
- `rules/command_log.gd` 使用统一契约验证存档日志。
- `rules/replay.gd` 使用统一契约验证回放命令，并保留未知单位、越权阵营、错误阶段和非法目标的语义错误。
- `rules/battle_session.gd` 提供版本化权威会话：创建快照、推进阶段、提交命令，并把合法命令交给同一个回放入口执行。
- `rules/deployment.gd` 增加任务驱动的双方部署区检查；界面放置入口会拒绝越界或放入中场的底座，并绘制部署边界。
- 新增回归覆盖：活动阵营可执行命令、错误阶段拒绝、缺字段载荷拒绝。

## 验证

```powershell
godot --headless --path . --script tests/run_tests.gd
```

当前结果：**220 项检查，0 失败**。

## 下一步

在命令契约上增加规则集版本和状态快照字段，随后把服务器端权威提交接入同一验证入口；同时继续从用户提供的本地来源逐条复核 profile，只有审核通过的兵牌进入可用目录。
