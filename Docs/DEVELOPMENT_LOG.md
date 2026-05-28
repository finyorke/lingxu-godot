# 开发记录

## 2026-05-27

- 建立 Godot 4.6.2 GL Compatibility 项目骨架、Web export preset 与 GitHub Pages workflow。
- 复制测试版 SPEC 到 `Docs/`，并落地 `Data/*.json`：35 件五行武器、15 件法宝、敌人、刷怪、境界、心法、存档默认值。
- 实现 5 个 autoload：`SignalsBus`、`ConfigDB`、`AssetDB`、`GameState`、`SaveSystem`。
- 实现主菜单、灵根抉择、0-2 封印灵根、体质选择、Arena 玩法、四法器自动攻击、聚剑斩、dash 无敌、hitstop、屏震、机缘四选一、Boss 压力点与结算。
- 使用 Codex imagegen 生成并打包主菜单、战场、云栖、基础敌人、终局剑魔、法器/拾取物图标、HUD 图标和战斗 FX；通过 `assets/MANIFEST.json` 统一管理。

## 2026-05-28

- 接通武器 `on_hit`：毒/流血/灼烧 DoT、减速/寒意叠层/冻结、击退/拉拽、爆炸、震荡、易伤、石化、定身、护盾获取、分裂、传奇武器 nova/burst 等效果都从 `weapons.json` 读取。
- `execute_jade` 的 `fire_execute`、`execute_threshold`、`execute_mult` 已进入伤害计算；阈值/倍率类字段按 set/max 语义处理，避免重复拿同一道具时无限叠加。
- 新增赤睛妖蟒 `serpent_boss.png` 正式资产并写入 `assets/MANIFEST.json`，`serpent_boss` 不再复用玄甲傀贴图。
- 移除未加载的空壳 `Scenes/MainMenu.tscn` 与 `Scenes/RootChoice.tscn`，入口 UI 继续由 `Scripts/Main.gd` 程序化生成。
- 修正 `market_offered` 信号参数为四选一卡牌数据数组；投射物速度读取 `proj_speed`，未配置时默认 560。
- GitHub Pages 首次部署提醒：仓库 Pages 若未自动创建，需要在 Settings -> Pages 中把 Source 设为 GitHub Actions 后重跑 main 的 deploy job。
- 精修主菜单、灵根抉择、结算与机缘 UI：新增随 Web 打包的书法标题字体，灵根卡牌显示五行图标、封印状态、元素边框/光晕，确认入墟按钮与各类面板改为符箓感描边、阴影和高对比排版。
- 法器获得改为“同名同品先合成，其次入空槽，再入 2 格备炼栏，最后拒绝”，不再在槽满时自动替换；市集法器带四档品阶颜色与 1.7x/品的伤害成长。
