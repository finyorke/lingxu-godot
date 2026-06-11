# 御剑灵墟

Godot 4.6.2 web preview for a 2D top-down xianxia survivor roguelite.

## Local Commands

```powershell
C:\Users\fengbo\Developer\godot\Godot_v4.6.2-stable_win64_console.exe --headless --path . --script tests/smoke.gd
C:\Users\fengbo\Developer\godot\Godot_v4.6.2-stable_win64_console.exe --headless --path . --export-release Web build/web/index.html
```

## Deployment

- Cloudflare Pages GitHub Actions workflow: `Docs/CLOUDFLARE_PAGES_WORKFLOW.md`
- Cloudflare Zero Trust / Access setup guide: `Docs/CLOUDFLARE_ZERO_TRUST_ACCESS_GUIDE.md`
- Reusable Codex Cloudflare Pages deployment skill: `skills/cloudflare-pages-deploy/`
- Existing GitHub Pages preview workflow remains separate in `.github/workflows/web-preview.yml`.

## Current Slice

- Main menu, root selection, root sealing from 0 to 2 roots, and arena entry.
- WASD movement, dash invulnerability, burst slash, pause, hitstop, screen shake, and result flow.
- Four automatic weapon slots, 35 weapon records, 15 item records, market filtering by active roots, and elemental/root damage math.
- 12-minute run structure with 3/6/9/12 boss pressure points and final sword demon.
- Generated bitmap assets for menu, arena, player, enemies, weapons, pickups, HUD icons, and combat FX.
