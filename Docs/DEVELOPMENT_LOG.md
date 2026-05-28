# 开发记录

## 2026-05-27

- 建立 Godot 4.6.2 GL Compatibility 项目骨架、Web export preset 与 GitHub Pages workflow。
- 复制测试版 SPEC 到 `Docs/`，并落地 `Data/*.json`：35 件五行武器、15 件法宝、敌人、刷怪、境界、心法、存档默认值。
- 实现 5 个 autoload：`SignalsBus`、`ConfigDB`、`AssetDB`、`GameState`、`SaveSystem`。
- 实现主菜单、灵根抉择、0-2 封印灵根、体质选择、Arena 玩法、四法器自动攻击、聚剑斩、dash 无敌、hitstop、屏震、机缘四选一、Boss 压力点与结算。
- 使用 Codex imagegen 生成并打包主菜单、战场、云栖、基础敌人、终局剑魔、法器/拾取物图标、HUD 图标和战斗 FX；通过 `assets/MANIFEST.json` 统一管理。
