# Changelog

## 0.3.2 — 2026-11-03

- 新增独立负重带物品图标、供 Neat Crafting 使用的制作分类图标，以及延续蘇清龙族角色设定的模组封面。
- 整理中英文说明、创意工坊介绍和上传交接材料；封面不写游戏版本号。
- 保留0.3.1训练、制作、穿戴、经验叠加和进度数据机制，不调整训练速率或原版负重规则。
- 用户已确认0.3.1机制测试未发现问题；0.3.2新美术仍待游戏内显示核对。发布材料准备与本机部署、Git推送、工坊上传分别记录。

- Added a belt inventory icon, an optional Neat Crafting category icon and cover artwork retaining SuQing's dragon-character design.
- Prepared Chinese/English release and Workshop materials. The cover does not display the game version.
- Preserved the tested 0.3.1 gameplay behavior. New artwork requires a separate in-game visual check; prepared materials do not establish deployment or publication.

## 0.3.1 — 2026-11-03

- 状态面板每次进入存档默认隐藏，只通过右键真实负重带的选项打开/关闭。
- 显隐使用本次会话状态，忽略旧版自动显示偏好；训练经验、倍率和余数保持。


## 0.3.0 — 2026-11-03

- 合成分类改为“负重带”，物品描述缩短为“穿戴后移动可练习体能技能。”
- 默认倍率改为1，基准每游戏分钟每项5基础经验；范围0.1–20，支持小数。
- 新1=旧5、新4=旧20、新20=旧100；个人档保留20数值，产量为上一版的5倍。
- 沙盒说明增加默认1/10/60游戏分钟的产量及公式。沿用用户已验收的0.2.0计时、穿戴、负重与经验叠加机制。


## 0.2.0 — 2026-11-03

- 改为纯Lua与原版脚本，撤去本模组的Java运行包、依赖声明及启动门禁。
- 修复初版因Java接口不可用而永久跳过训练经验的问题；训练直接按穿戴、实际位移与游戏时间结算。
- 本体重量改为10，穿戴和移速按原版负重规则计算；取消固定0.5倍速度。
- 保留物品/槽位ID、schema1余数及个人档倍率20，针对旧负重带迁移重量。
- 新增可开关文字状态和实际XP增量，满级与原版限制分别显示；UI不参与发奖。


## 0.1.0 — 2026-11-03

- 新增独立负重带、制作配方和穿戴槽；复用原版腰带资源。
- 新增正常地面移动0.5倍速度及按有效游戏移动时间产生的六项体能经验。
- 新增训练经验倍率沙盒选项，默认5、范围1–20；正常叠加原版经验规则与可选蛋白饮料增益。
- 新增部分分钟持久化、重新采样及失败后停止发放保护。
- 完成隔离Lua双VM、原生元数据与ZombieBuddy/原版/AOT字节码验证。实际游戏内验收待完成。
