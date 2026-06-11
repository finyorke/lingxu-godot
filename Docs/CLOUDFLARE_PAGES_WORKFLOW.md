# Cloudflare Pages 自动部署工作流

这个项目的 Cloudflare Pages 发布使用 GitHub Actions 构建 Godot Web 产物，再通过 Wrangler Direct Upload 上传到 Cloudflare Pages。workflow 会用 `CLOUDFLARE_API_TOKEN` 解析 Cloudflare account，并在 Pages 项目不存在时自动创建项目。

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
- 推荐路径需要可以创建 Cloudflare Account API Token；如果没有这个权限，可以使用下面的 User API Token 兜底链接。

Cloudflare 侧 Pages 项目不需要提前手动创建。workflow 会在部署前检查项目是否存在，不存在时自动创建：

- Project name：`lingxu-godot`
- Production branch：`main`
- 如果要保护 preview、production `*.pages.dev` 或 custom domain，需要继续使用 Cloudflare Zero Trust / Access 配置，具体步骤见 `Docs/CLOUDFLARE_ZERO_TRUST_ACCESS_GUIDE.md`。Access application 和 policy 不在每次游戏发布时重建。

如果 API token 可以看到多个 Cloudflare account，workflow 不会猜测使用哪一个；这种情况下需要显式配置 `CLOUDFLARE_ACCOUNT_ID`。

## 最少步骤配置入口

先在 Cloudflare 创建 token，再回到 GitHub 保存配置。Cloudflare 的 template URL 只能预填创建表单，不能替你完成创建；仍然需要你登录 Cloudflare、选择账号范围、点击创建并复制 token。

Cloudflare token 链接：

| 用途 | 链接 | 什么时候用 |
| --- | --- | --- |
| 推荐：Account API Token | [创建 `github-actions-lingxu-godot-pages` account token](https://dash.cloudflare.com/?to=/:account/api-tokens&permissionGroupKeys=%5B%7B%22key%22%3A%22page%22%2C%22type%22%3A%22edit%22%7D%2C%7B%22key%22%3A%22account_settings%22%2C%22type%22%3A%22read%22%7D%5D&name=github-actions-lingxu-godot-pages) | 你是 Cloudflare Super Administrator / Administrator，或有权限创建 Account API Token |
| 兜底：User API Token | [创建 `github-actions-lingxu-godot-pages` user token](https://dash.cloudflare.com/profile/api-tokens?permissionGroupKeys=%5B%7B%22key%22%3A%22page%22%2C%22type%22%3A%22edit%22%7D%2C%7B%22key%22%3A%22account_settings%22%2C%22type%22%3A%22read%22%7D%5D&accountId=*&zoneId=all&name=github-actions-lingxu-godot-pages) | 你没有权限创建 Account API Token，但可以在自己的 Profile 下创建 User API Token |

GitHub 配置链接：

| GitHub 值 | 类型 | 链接 | 填什么 |
| --- | --- | --- | --- |
| `CLOUDFLARE_API_TOKEN` | Secret | [新建 repository secret](https://github.com/finyorke/lingxu-godot/settings/secrets/actions/new) | 粘贴 Cloudflare 刚显示的 token |
| `CLOUDFLARE_ACCOUNT_ID` | Variable 或 Secret | [新建 repository variable](https://github.com/finyorke/lingxu-godot/settings/variables/actions/new) | 可选；只有 workflow 无法自动解析唯一 account 时才填 |
| `CLOUDFLARE_PROJECT_NAME` | Variable | [新建 repository variable](https://github.com/finyorke/lingxu-godot/settings/variables/actions/new) | 可选；不填时默认 `lingxu-godot` |

不要把 Cloudflare token、Global API Key、Cloudflare 密码发到 issue 评论、聊天、代码或日志里。`CLOUDFLARE_API_TOKEN` 是 Secret；`CLOUDFLARE_PROJECT_NAME` 不是敏感信息，应放 Variable；`CLOUDFLARE_ACCOUNT_ID` 通常也不是 credential，可以放 Variable，如果你希望隐藏账号 ID，也可以放 Secret。

## GitHub 配置项

在 GitHub 仓库页面进入：

`Settings` -> `Secrets and variables` -> `Actions`

新增这些 repository secret：

| Name | 类型 | 用途 |
| --- | --- | --- |
| `CLOUDFLARE_API_TOKEN` | Secret | Wrangler 用它登录 Cloudflare 并上传 Pages 部署 |

新增这些 repository variable：

| Name | 类型 | 用途 |
| --- | --- | --- |
| `CLOUDFLARE_PROJECT_NAME` | Variable | Pages 项目名，当前值是 `lingxu-godot` |
| `CLOUDFLARE_PRODUCTION_BRANCH` | Variable | 自动创建 Pages 项目时使用的 production branch，默认 `main` |

`CLOUDFLARE_PROJECT_NAME` 和 `CLOUDFLARE_PRODUCTION_BRANCH` 不是敏感信息；如果不配置，workflow 会默认使用 `lingxu-godot` 和 `main`。

`CLOUDFLARE_ACCOUNT_ID` 现在是可选项，可以配成 repository secret，也可以配成 repository variable。workflow 会先读取它；如果没配置，就调用 Cloudflare `/accounts` API：

- 只返回 1 个 account：自动使用这个 account id。
- 返回 0 个 account、多个 account，或 token 无法列出 account：workflow 失败并要求配置 `CLOUDFLARE_ACCOUNT_ID`。

## 如何获取 Cloudflare API Token

不要使用 Cloudflare Global API Key，也不要把 token 发到 issue、聊天或代码里。

推荐使用上面的 Account API Token 链接：

1. 打开推荐链接后，如果 Cloudflare 要求登录，先登录。
2. 如果 Cloudflare 让你选择 account，选择承载 `lingxu-godot` Pages 项目的目标账号。
3. 你应该看到 token 名称预填为 `github-actions-lingxu-godot-pages`。
4. 权限页面核对这些字段：
   - Account -> Cloudflare Pages -> Edit
   - Account -> Account Settings -> Read
5. Resources / Scope 页面选择 `Include`，并只选择这个项目所在的 Cloudflare account。这个 token 不需要任何 Zone 权限；如果页面显示 Zone Resources，不用额外添加站点范围。
6. Client IP Address Filtering 和 TTL 可以保持默认，除非你的团队有额外安全策略。
7. 进入 summary 后再次确认只有上面的权限和目标 account，然后点击 `Create Token`。
8. 创建成功后立即复制 token；Cloudflare 只显示这一次。
9. 打开 GitHub [新建 repository secret](https://github.com/finyorke/lingxu-godot/settings/secrets/actions/new)，Name 填 `CLOUDFLARE_API_TOKEN`，Secret 粘贴 token，保存。

如果推荐链接提示你没有权限创建 Account API Token，使用兜底 User API Token 链接。Cloudflare 当前 template URL 格式要求 user token 链接带 `accountId=*` 和 `zoneId=all`；打开后仍然要在表单里核对权限，并在可选的 Resources / Scope 区域把 Account Resources 收窄到目标 account。User token 链接同样只负责预填表单，创建后也要把复制到的值保存为 GitHub secret `CLOUDFLARE_API_TOKEN`。

这个 token 只负责解析 account、自动创建 Pages 项目、上传 Pages 部署。Zero Trust / Access 的 application 和 policy 建议作为基础设施单独管理，不要放到每次游戏发布 workflow 里。

如果需要 agent 自动创建或更新 Access application / policy，不要给这个 Pages deploy token 追加 Zero Trust 权限。请按 `Docs/CLOUDFLARE_ZERO_TRUST_ACCESS_GUIDE.md` 创建单独的 Access 管理 token。

## 如何获取 Cloudflare Account ID

常见获取方式：

1. 打开 Cloudflare Dashboard。
2. 进入目标账号或任意该账号下的站点 / Workers & Pages 页面。
3. 在 Dashboard 右侧或 Overview 区域找到 `Account ID`。
4. 复制后按需保存到 GitHub secret 或 variable `CLOUDFLARE_ACCOUNT_ID`。

如果只配置了 `CLOUDFLARE_API_TOKEN`，workflow 会自动尝试获取 account ID。你也可以用 API token 手动查询：

```powershell
curl.exe https://api.cloudflare.com/client/v4/accounts `
  -H "Authorization: Bearer <你的 Cloudflare API Token>"
```

返回的 `result[].id` 就是 account id。也可以在本机已登录 Wrangler 时运行：

```powershell
npx wrangler whoami
```

从输出里确认目标账号，再复制对应 account ID。

只有在 API token 对多个 account 都有权限，或者 token 无法调用 `/accounts` 时，才需要把这个值配置为 `CLOUDFLARE_ACCOUNT_ID`。

## 自动创建 Pages 项目

部署前 workflow 会调用 Cloudflare API 检查：

```text
GET /client/v4/accounts/<account_id>/pages/projects/<project_name>
```

如果返回 404，workflow 会自动创建 Direct Upload Pages 项目：

```text
POST /client/v4/accounts/<account_id>/pages/projects
```

请求里会使用当前的 project name 和 production branch：

```json
{
  "name": "lingxu-godot",
  "production_branch": "main"
}
```

创建成功后，同一次 workflow 会继续执行 `wrangler pages deploy build/web --project-name <project_name> --branch <branch>`。所以首次部署只需要提前配置 `CLOUDFLARE_API_TOKEN`；account 无法唯一解析时再补 `CLOUDFLARE_ACCOUNT_ID`。

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

- Cloudflare API token template URLs: https://developers.cloudflare.com/fundamentals/api/how-to/account-owned-token-template/
- Cloudflare Create API token: https://developers.cloudflare.com/fundamentals/api/get-started/create-token/
- Cloudflare API token permissions: https://developers.cloudflare.com/fundamentals/api/reference/permissions/
- Cloudflare Find account and zone IDs: https://developers.cloudflare.com/fundamentals/account/find-account-and-zone-ids/
- Cloudflare Pages Direct Upload: https://developers.cloudflare.com/pages/get-started/direct-upload/
- Direct Upload with continuous integration: https://developers.cloudflare.com/pages/how-to/use-direct-upload-with-continuous-integration/
- Cloudflare Accounts API: https://developers.cloudflare.com/api/resources/accounts/methods/list/
- Cloudflare Pages Create Project API: https://developers.cloudflare.com/api/resources/pages/subresources/projects/methods/create/
- Cloudflare Pages limits: https://developers.cloudflare.com/pages/platform/limits/
- Cloudflare Zero Trust / Access 配置指南: `Docs/CLOUDFLARE_ZERO_TRUST_ACCESS_GUIDE.md`
- GitHub Actions secrets: https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets
