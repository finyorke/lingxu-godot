# Cloudflare Pages 自动部署工作流

这个项目的 Cloudflare Pages 发布使用 GitHub Actions 构建 Godot Web 产物，再通过 Wrangler Direct Upload 上传到已经存在的 Cloudflare Pages 项目。

当前工作流文件是 `.github/workflows/cloudflare-pages.yml`。GitHub Pages 的发布流程属于另一条线，不在这个 Cloudflare 工作流里混合处理。

## 触发规则

- `push` 到 `main`：自动部署 production，对应 `https://lingxu-godot.pages.dev/`。
- `pull_request`：同仓库 PR 自动部署 preview，Cloudflare branch 使用 `pr-<PR number>`。
- `workflow_dispatch`：可以在 GitHub Actions 页面手动运行。可选填写 `cloudflare_branch`，用于手动指定 Cloudflare Pages 分支名。

注意：GitHub 不会把 repository secrets 暴露给来自 fork 的 PR。fork PR 仍会构建和检查包体积，但不会自动部署 preview；需要维护者在可信分支上重跑或用手动 workflow dispatch 发布。

如果仓库还没有配置 Cloudflare secrets，同仓库 PR 会给出 warning 并跳过 preview deploy，避免引入 workflow 的 PR 被配置缺失挡住。`push main` 和手动部署仍会在缺配置时失败，并在 Actions summary 里提示需要补哪些值。

## 使用前需要的权限和配置

你需要同时具备这些权限：

- GitHub 仓库管理员或有权限配置 Actions secrets / variables 的成员。
- Cloudflare 账号里可以管理目标 Pages 项目的权限。
- 可以创建 Cloudflare Account API Token 的权限。

Cloudflare 侧需要已经存在 Pages 项目：

- Project name：`lingxu-godot`
- Production branch：`main`
- 如果要保护 preview，需要继续使用 Cloudflare Zero Trust / Access 配置。Access application 和 policy 不在每次游戏发布时重建。

## GitHub 配置项

在 GitHub 仓库页面进入：

`Settings` -> `Secrets and variables` -> `Actions`

新增这些 repository secret：

| Name | 类型 | 用途 |
| --- | --- | --- |
| `CLOUDFLARE_API_TOKEN` | Secret | Wrangler 用它登录 Cloudflare 并上传 Pages 部署 |
| `CLOUDFLARE_ACCOUNT_ID` | Secret | 指定部署到哪个 Cloudflare account |

新增这个 repository variable：

| Name | 类型 | 用途 |
| --- | --- | --- |
| `CLOUDFLARE_PROJECT_NAME` | Variable | Pages 项目名，当前值是 `lingxu-godot` |

`CLOUDFLARE_PROJECT_NAME` 不是敏感信息；如果不配置，workflow 会默认使用 `lingxu-godot`。

## 如何获取 Cloudflare API Token

不要使用 Cloudflare Global API Key，也不要把 token 发到 issue、聊天或代码里。

推荐步骤：

1. 打开 Cloudflare Dashboard。
2. 进入右上角头像菜单 -> `My Profile` -> `API Tokens`。
3. 点击 `Create Token`。
4. 选择 `Custom token` -> `Get started`。
5. Token name 填 `github-actions-lingxu-godot-pages`。
6. Permissions 选择：
   - Account -> Cloudflare Pages -> Edit
7. Account Resources 选择 `Include`，并只选择这个项目所在的 Cloudflare account。
8. 生成 token 后立即复制一次，保存到 GitHub secret `CLOUDFLARE_API_TOKEN`。

这个 token 只负责 Pages 上传部署。Zero Trust / Access 的 application 和 policy 建议作为基础设施单独管理，不要放到每次游戏发布 workflow 里。

## 如何获取 Cloudflare Account ID

常见获取方式：

1. 打开 Cloudflare Dashboard。
2. 进入目标账号或任意该账号下的站点 / Workers & Pages 页面。
3. 在 Dashboard 右侧或 Overview 区域找到 `Account ID`。
4. 复制后保存到 GitHub secret `CLOUDFLARE_ACCOUNT_ID`。

也可以在本机已登录 Wrangler 时运行：

```powershell
npx wrangler whoami
```

从输出里确认目标账号，再复制对应 account ID。

## 文件大小提醒

Cloudflare Pages 单个站点文件限制是 25 MiB。工作流在上传前会扫描 `build/web`：

- Actions summary 会列出最大的 10 个导出文件。
- 如果任意文件大于 25 MiB，workflow 会失败并标出具体文件。
- 处理方式通常是压缩资源、拆分大文件、减少 Godot Web 导出体积，或者把特别大的静态资源移到 Cloudflare R2。

当前项目的 Web 包会先做两步处理：

- 在 CI 临时 subset `NotoSansCJKsc-Regular.otf` 和 `MaShanZheng-Regular.ttf`，只保留项目文本会用到的字形，降低 `index.pck` 体积。
- 把 `index.wasm` gzip 后仍以 `index.wasm` 文件名上传，并生成 `_worker.js` 设置 `Content-Encoding: gzip` 和正确 MIME。

这些处理只发生在 GitHub Actions runner 的临时 checkout 中，不会改动仓库里的原始字体文件。

字体 subset 的字形来源是项目源码、场景、数据和 import 配置里的文本，再加上一组常用 UI 字符。新增运行时拼接出来的生僻字或不在这些文件里的动态文本时，需要在 preview 上抽检相关界面；如果出现缺字形，需要把对应文字加入数据/场景文本，或扩大 workflow 里的 subset 文本范围。

## 手动部署

如果需要手动重跑：

1. 打开 GitHub 仓库。
2. 进入 `Actions`。
3. 选择 `Cloudflare Pages`。
4. 点击 `Run workflow`。
5. 留空 `cloudflare_branch` 时，使用当前分支名；填写 `main` 会部署 production，填写 `pr-123` 这样的名字会部署对应 preview branch。

## 参考文档

- Cloudflare Pages Direct Upload: https://developers.cloudflare.com/pages/get-started/direct-upload/
- Direct Upload with continuous integration: https://developers.cloudflare.com/pages/how-to/use-direct-upload-with-continuous-integration/
- Cloudflare Pages limits: https://developers.cloudflare.com/pages/platform/limits/
- GitHub Actions secrets: https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets
