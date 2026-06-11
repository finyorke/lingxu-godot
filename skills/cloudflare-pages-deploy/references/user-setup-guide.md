# Cloudflare Pages 用户配置指导

把下面内容按当前仓库替换后发给用户。不要要求用户把 Cloudflare 密码、Global API Key 或 API Token 发到 issue 评论、聊天、代码或日志里。

## 需要先告诉用户的默认值

在给链接前先明确这些值：

- GitHub repo: `<owner>/<repo>`
- 默认 Pages project name: `<repo>`
- Production branch: `main`，除非仓库默认分支或用户要求不同
- Direct Upload workflow 会在 Pages project 不存在时自动创建它

示例：

```text
默认 Cloudflare Pages project name 会使用 `<repo>`。如果你不配置 `CLOUDFLARE_PROJECT_NAME`，workflow 会使用这个默认值，并在首次部署时自动创建 Pages project。只有想换别的 Pages 项目名时才需要配置 `CLOUDFLARE_PROJECT_NAME`。
```

## Cloudflare API Token 链接

优先给 Account token 链接：

```text
https://dash.cloudflare.com/?to=/:account/api-tokens&permissionGroupKeys=%5B%7B%22key%22%3A%22page%22%2C%22type%22%3A%22edit%22%7D%2C%7B%22key%22%3A%22account_settings%22%2C%22type%22%3A%22read%22%7D%5D&name=Cloudflare%20Pages%20Deploy
```

如果用户没有权限创建 Account token，再给 User token 兜底链接：

```text
https://dash.cloudflare.com/profile/api-tokens?permissionGroupKeys=%5B%7B%22key%22%3A%22page%22%2C%22type%22%3A%22edit%22%7D%2C%7B%22key%22%3A%22account_settings%22%2C%22type%22%3A%22read%22%7D%5D&accountId=*&zoneId=all&name=Cloudflare%20Pages%20Deploy
```

这类链接只能预填权限和名称，用户仍然需要在 Cloudflare Dashboard 里确认 account/resource scope 并点击创建。

## 用户点开 Cloudflare 链接后的步骤

1. 如果 Cloudflare 要求选择 account，选择要部署 Pages 的目标 account。
2. 确认 Token name 是 `Cloudflare Pages Deploy`，可以改成 `github-actions-<repo>-pages-deploy`。
3. 确认 Permissions 至少有：
   - `Account` -> `Cloudflare Pages` -> `Edit`
   - `Account` -> `Account Settings` -> `Read`
4. 在 Account Resources / Resources 里选择：
   - `Include` -> `Specific account` -> 目标 Cloudflare account
   - 不要默认选 `All accounts`，除非用户明确需要同一个 token 管多个 account。
5. Zone Resources 不需要新增 Zone 权限。只部署 Pages 或 `*.pages.dev` 时不需要 DNS 权限。
6. 点击 `Continue to summary`，检查权限和 account scope。
7. 点击 `Create Token`。
8. token 只显示一次。复制后立刻打开 GitHub Secret 链接，把它保存成 `CLOUDFLARE_API_TOKEN`。不要发到 issue 评论里。

如果用户不愿意给 `Account Settings Read`，也可以只给 `Cloudflare Pages Edit`，但这样 workflow 可能无法自动调用 `/accounts` 解析 account id。此时需要手动配置 `CLOUDFLARE_ACCOUNT_ID`。

## GitHub 链接生成规则

把 `<owner>` 和 `<repo>` 替换成当前仓库：

- Actions secrets 页面：`https://github.com/<owner>/<repo>/settings/secrets/actions`
- 新建 Actions secret：`https://github.com/<owner>/<repo>/settings/secrets/actions/new`
- Actions variables 页面：`https://github.com/<owner>/<repo>/settings/variables/actions`
- 新建 Actions variable：`https://github.com/<owner>/<repo>/settings/variables/actions/new`

给用户时优先用直接新建链接：

```text
GitHub Secret:
https://github.com/<owner>/<repo>/settings/secrets/actions/new

GitHub Variables:
https://github.com/<owner>/<repo>/settings/variables/actions
```

## 用户配置 GitHub Secret 的步骤

1. 打开 `https://github.com/<owner>/<repo>/settings/secrets/actions/new`。
2. `Name` 填：`CLOUDFLARE_API_TOKEN`。
3. `Secret` 粘贴刚才 Cloudflare 生成的 token。
4. 点击 `Add secret`。

不要让用户把 token 粘贴到 issue、聊天或 PR 描述里。

## 用户配置 GitHub Variables 的步骤

多数项目只需要先配置 `CLOUDFLARE_API_TOKEN`。下面的变量都不是敏感信息，建议放在 Variables，不建议放进 issue 评论。

如果 workflow 因为看到了多个 Cloudflare account 而失败：

1. 打开 `https://github.com/<owner>/<repo>/settings/variables/actions/new`。
2. `Name` 填：`CLOUDFLARE_ACCOUNT_ID`。
3. `Value` 填 workflow summary 里列出的目标 account id。
4. 点击 `Add variable`。
5. 重新运行 workflow。

如果用户要覆盖默认 Pages project name：

1. 打开 `https://github.com/<owner>/<repo>/settings/variables/actions/new`。
2. `Name` 填：`CLOUDFLARE_PROJECT_NAME`。
3. `Value` 填目标 Pages project name。
4. 点击 `Add variable`。

如果 production branch 不是 `main`：

1. 打开 `https://github.com/<owner>/<repo>/settings/variables/actions/new`。
2. `Name` 填：`CLOUDFLARE_PRODUCTION_BRANCH`。
3. `Value` 填 production branch 名称，例如 `master` 或 `release`。

## Direct Upload 运行后的解释

workflow summary 应该告诉用户：

- `CLOUDFLARE_ACCOUNT_ID` 来源：手动输入、GitHub variable/secret，或 Cloudflare `/accounts` 自动解析
- `CLOUDFLARE_PROJECT_NAME` 来源：手动输入、GitHub variable，或 repo name 默认值
- Cloudflare deploy branch
- Production branch
- Pages project 是已存在还是本次自动创建
- 部署 URL

如果 summary 列出多个 account，让用户从表格里选目标 account id，然后配置 `CLOUDFLARE_ACCOUNT_ID`。不要在 CI 里隐式猜测。

## Git Integration 用户步骤

只在选择 Cloudflare Pages Git integration 时使用。API token 不能替代 GitHub App 授权。

GitHub App 安装链接：

```text
https://github.com/apps/cloudflare-workers-and-pages/installations/new
```

Cloudflare Workers & Pages 入口：

```text
https://dash.cloudflare.com/?to=/:account/workers-and-pages
```

用户步骤：

1. 打开 GitHub App 安装链接。
2. 选择自己的账号或组织。
3. Repository access 选择 `Only select repositories`。
4. 只选择当前目标 repo。
5. 点击 Install / Save。
6. 打开 Cloudflare Workers & Pages 入口。
7. 进入目标 account。
8. 选择 `Create application` -> `Pages` -> `Connect to Git`。
9. 选择刚授权的 GitHub repo。
10. Production branch 选择 `main` 或用户指定分支。
11. Framework preset 按项目选择；简单静态站可选 None。
12. 填 build command 和 output directory。
13. 点击 `Save and Deploy`。

如果现有 Pages project 是 Direct Upload，不要让用户在原项目上找“切换 Git integration”的按钮。应新建一个 Git-integrated Pages project 做 PoC。

## Zero Trust / Access 边界

Pages deploy token 不要默认混入 Zero Trust 权限。

只有用户明确要求自动配置 Access 时，再单独收集：

- 要保护的 hostname
- 允许访问的邮箱、邮箱域名或 group
- 使用的 IdP
- session duration
- 是否保护 preview、production `*.pages.dev`、custom domain

需要自动创建 Access app/policy 时再创建单独 token，不要复用 Pages deploy token。

可选 Access token 模板链接：

```text
https://dash.cloudflare.com/?to=/:account/api-tokens&permissionGroupKeys=%5B%7B%22key%22%3A%22access%22%2C%22type%22%3A%22edit%22%7D%2C%7B%22key%22%3A%22access_acct%22%2C%22type%22%3A%22read%22%7D%5D&name=Cloudflare%20Access%20Setup
```
