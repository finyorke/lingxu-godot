# Cloudflare Zero Trust / Access 配置指南

本项目的 Pages 发布由 `.github/workflows/cloudflare-pages.yml` 负责。Zero Trust / Access 是部署后的可选保护阶段，不属于每次游戏发布的上传流程。默认原则是：Pages deploy token 只负责 Cloudflare Pages，Access application、policy、service token 使用单独的权限和单独的 token。

## 快速入口

- Workers & Pages 项目列表：https://dash.cloudflare.com/?to=/:account/workers-and-pages
- Zero Trust Access 应用列表：https://dash.cloudflare.com/?to=/:account/access/apps
- 新建 Access 应用：https://dash.cloudflare.com/?to=/:account/access/apps/add
- Access policy 列表：https://dash.cloudflare.com/?to=/:account/access/policies
- Access service tokens：https://dash.cloudflare.com/?to=/:account/access/service-auth/service-tokens
- Access 自动化 token 模板：https://dash.cloudflare.com/profile/api-tokens?permissionGroupKeys=%5B%7B%22key%22%3A%22access%22%2C%22type%22%3A%22edit%22%7D%2C%7B%22key%22%3A%22access_acct%22%2C%22type%22%3A%22edit%22%7D%5D&accountId=%2A&zoneId=all&name=lingxu-godot-access-management

打开带 `:account` 的链接后，Cloudflare 会要求选择账号或跳到当前账号的对应页面。账号选错时，先切到放置 `lingxu-godot` Pages 项目的 Cloudflare account。

## 先问用户的问题

配置前必须明确这些输入：

- 要保护的范围：只保护 preview deployments、保护 production `lingxu-godot.pages.dev`、保护某个 custom domain，或者几个都保护。
- 要保护的 hostname：例如 `*.lingxu-godot.pages.dev`、`lingxu-godot.pages.dev`、`play.example.com`。
- 允许谁访问：具体邮箱、邮箱域名、Access group、IdP group、SAML/OIDC claim，或者其他 Access selector。
- 登录方式：使用 One-time PIN，还是使用已有身份源，例如 Google、GitHub、Okta、Microsoft Entra ID、SAML/OIDC。
- session duration：例如 24h、8h、1h。生产环境建议短一些，外部试玩可按需要拉长。
- 是否需要 service token：只有自动化探活、CI 抓取受保护 URL、截图机器人等非浏览器访问才需要。
- 是否允许 agent 自动创建或修改 Access app/policy/service token，以及允许使用哪个 Cloudflare account。

不要默认创建 `Everyone` allow policy，也不要默认使用 Bypass。除非用户明确要求公开访问，否则 Access policy 应该只允许具体邮箱、域名或 IdP/group 条件。

## 场景 1：只保护 Pages preview deployments

Cloudflare Pages 自带的 `Enable access policy` 足够保护 preview deployments。它只保护 hash preview URL 和 branch preview URL，例如 `<hash>.lingxu-godot.pages.dev` 或 `pr-123.lingxu-godot.pages.dev`，不保护 `lingxu-godot.pages.dev` production，也不保护 custom domain。

操作步骤：

1. 打开 Workers & Pages：https://dash.cloudflare.com/?to=/:account/workers-and-pages
2. 选择 `lingxu-godot` Pages 项目。
3. 进入 `Settings` -> `General`。
4. 点击或勾选 `Enable access policy`。
5. 如果默认只允许 Cloudflare account 成员访问已经足够，到这里结束。
6. 如果要允许额外邮箱或邮箱域名，打开 Access 应用列表：https://dash.cloudflare.com/?to=/:account/access/apps
7. 找到 Cloudflare 为这个 Pages preview 创建的 Access application。
8. 进入应用的 policy，按用户给出的邮箱、邮箱域名或 group 添加 `Allow` 规则。
9. 用无痕浏览器打开一个 PR preview 或 branch preview URL，确认先出现 Cloudflare Access 登录页。
10. 同时打开 `https://lingxu-godot.pages.dev/`，确认它没有因为 preview 开关而被误保护。

适合第一版 Skill 的默认引导：Pages 部署成功后提示“是否只保护 PR/branch preview”，给出上面的 Workers & Pages 直达链接。除非用户提供单独 Access token 并确认允许自动化，否则第一版只做引导，不自动改 Access。

## 场景 2：保护 production `*.pages.dev`

`Enable access policy` 默认不保护 production `lingxu-godot.pages.dev`。如果要同时保护 production 和 previews，需要让 Cloudflare 为 production `*.pages.dev` 建一个独立 Access application，同时保留 preview 的 wildcard application。

Cloudflare 当前文档给的 dashboard 路径是先利用 Pages 生成的 preview Access app，再把它的 public hostname 从 wildcard 改为 production，之后回到 Pages 重新启用 preview protection，让 Cloudflare 生成第二个 preview app。

操作步骤：

1. 先按“场景 1”启用 preview access policy。
2. 在 Pages 项目设置里，点击刚创建的 Access policy 的 `Manage`。
3. 在 Zero Trust Access 应用里选择这个 Pages 项目对应的 application。
4. 进入 `Configure`。
5. 在 `Public hostname` 里删除 `Subdomain` 的 wildcard `*`，保存。必要时同步改 application name，避免名称冲突。
6. 这时 production `lingxu-godot.pages.dev` 应该已经进入 Access 保护。
7. 回到 Workers & Pages -> `lingxu-godot` -> `Settings` -> `General`。
8. 再次选择 `Enable access policy`，让 Cloudflare 为 preview deployments 重新创建一个 wildcard Access app。
9. 在 Access 应用列表里检查应有两个 app：一个保护 `lingxu-godot.pages.dev`，一个保护 `*.lingxu-godot.pages.dev` preview。
10. 分别用无痕浏览器打开 production URL 和 preview URL，确认二者都要求 Access 登录。

自动化边界：

- 可以自动化：两个 Access apps 已经按 Cloudflare dashboard 流程建好后，在用户确认 policy 和 token 后更新 policy。
- 谨慎自动化：production `*.pages.dev` app 的创建。`pages.dev` 不是用户自己的 zone，第一版应优先走 Cloudflare 文档里的 dashboard 流程；只有在已经识别到 Pages 生成的 Access app 后，才允许自动化修改。
- 不建议自动化：未经确认就修改 Cloudflare 为 Pages 生成的 Access app，因为 production 和 preview wildcard 很容易被改反。
- 必须人工确认：最终 hostname 列表、允许访问的人群、session duration，以及是否要影响 production。

## 场景 3：保护 custom domain

custom domain 不会因为 preview 或 `*.pages.dev` 的 Access 设置自动受保护。Access app 和 hostname 是显式绑定关系：要保护 `play.example.com`，就必须有一个 Access application 的 public hostname 包含 `play.example.com`，或者用户明确选择把它和其他 hostname 放进同一个 Access app。

前置条件：

- custom domain 已经在 Pages 项目里完成 `Custom domains` 配置。
- apex domain 例如 `example.com` 必须是这个 Cloudflare account 里的 zone，并且 nameserver 指向 Cloudflare。
- Pages custom domain 本身允许某些 subdomain 通过外部 DNS CNAME 指向 `<YOUR_SITE>.pages.dev`，但标准 Access public hostname 需要 hostname 属于当前 Cloudflare account 里的 active zone，或者走 Cloudflare for SaaS custom hostname 路径。要保护 `play.example.com`，实践上应先把 `example.com` 接入 Cloudflare，或让用户确认已有可用的 Cloudflare zone/custom hostname。
- subdomain 例如 `play.example.com` 仍必须先在 Pages 的 `Custom domains` 页面完成绑定。只手写 CNAME 而不在 Pages 里绑定会导致解析或 522 问题。
- 如果 custom domain 已经有 Access policy，Cloudflare 可能无法完成 Pages custom domain 绑定。优先顺序应是先绑定 Pages custom domain，再创建或恢复 Access app。
- 如果证书校验失败，要确认 Access 或 Worker 没有拦截 `http://<domain>/.well-known/acme-challenge/*`。

操作步骤：

1. 打开 Workers & Pages：https://dash.cloudflare.com/?to=/:account/workers-and-pages
2. 选择 `lingxu-godot` Pages 项目。
3. 进入 `Custom domains`，点击 `Set up a domain`。
4. 输入要服务的域名，例如 `play.example.com`，按 Cloudflare 提示完成 DNS 或 CNAME。
5. 等 custom domain 状态正常后，打开新建 Access 应用：https://dash.cloudflare.com/?to=/:account/access/apps/add
6. 选择 `Self-hosted and private`。
7. 选择 `Add public hostname`。
8. 在 `Domain` 下拉中选择 custom domain 所在 zone，填入 subdomain，最终 hostname 应等于 `play.example.com`。
9. 在 `Access policies` 里添加或新建 `Allow` policy，规则来自用户确认的邮箱、邮箱域名、group 或 IdP 条件。
10. 选择登录方式。外部试玩通常可以用 One-time PIN；组织内部建议使用已有 IdP。
11. 设置 `Session Duration`。
12. 创建应用后，用无痕浏览器访问 custom domain，确认出现 Access 登录页，且允许名单外邮箱无法进入。

如果同一个 custom domain 和 production `lingxu-godot.pages.dev` 要共享登录体验，可以考虑放在同一个 Access app 的多个 public hostnames 下。否则为了降低误改风险，建议分成独立 app。

## 自动化边界

可以由 agent 自动化的内容：

- 读取用户提供的 hostname、允许名单、IdP/group 条件、session duration。
- 在用户明确授权后，创建或更新 Access application。
- 在用户明确授权后，创建或更新 Access policy。
- 在用户明确授权后，创建 service token，并把 `client_id`、`client_secret` 只交给用户指定的安全存储位置。
- 生成可点击链接、检查清单和验证步骤。

必须用户确认或手动完成的内容：

- Cloudflare account 选择。
- API token 创建和权限授予。
- 是否影响 production hostname。
- custom domain 的 zone、nameserver、DNS、CNAME 和 Pages custom domain 绑定。
- 允许哪些人访问，尤其是邮箱域名、IdP group、`Everyone`、Bypass。
- service token 的有效期、存放位置和使用方。
- 是否允许自动化修改已有 Access app/policy。

不应该自动化的内容：

- 把 Zero Trust 权限加入 `CLOUDFLARE_API_TOKEN` Pages deploy token。
- 在没有用户确认的情况下创建 `Everyone` allow 或 Bypass policy。
- 覆盖名称相似但来源不明的 Access app。
- 默认保护或解除保护 production hostname。
- 在 issue、日志、代码或 PR 描述里泄露 API token、service token secret。

## API token 方案

保留现有 Pages deploy token：

- GitHub secret：`CLOUDFLARE_API_TOKEN`
- 用途：解析 account、创建 Pages project、上传 Pages deployment。
- 权限：`Account` -> `Cloudflare Pages` -> `Edit`，只选目标 Cloudflare account。
- 不加入 Access 权限。

如果需要 agent 自动化 Access app/policy，另建 token：

- 建议名称：`lingxu-godot-access-management`
- 建议存放：不要提交到仓库；只放在用户认可的 secret store 或本次 agent 可读取的临时环境中。
- 最小权限：`Account` -> `Access: Apps and Policies` -> `Edit` 或 `Write`，Account Resources 只包含目标 account。
- 如果还要自动配置 One-time PIN、IdP 或 Access rule groups，额外需要 `Account` -> `Access: Organizations, Identity Providers, and Groups` -> `Edit` 或 `Write`。
- 如果还要自动创建 service token，额外需要 `Account` -> `Access: Service Tokens` -> `Write`。

Cloudflare 支持 API token template URL 预填权限。上方“快速入口”的 Access 自动化 token 模板会预填常见 Access 管理权限。用户打开后仍必须在 summary 页面确认权限、account scope 和 token name。如果只自动创建或更新 app/policy，不需要 IdP 或 rule group 管理，可以删除 `Access: Organizations, Identity Providers, and Groups`。service token 权限不要默认加入；只有用户明确需要非浏览器访问时，再手动添加 `Access: Service Tokens Write` 或使用单独 token。

## service token 使用边界

service token 只给非浏览器调用方使用，例如 CI 探活、自动截图、内部监控。普通试玩人员不要使用 service token，应该通过 One-time PIN 或 IdP 登录。

配置步骤：

1. 打开 service tokens：https://dash.cloudflare.com/?to=/:account/access/service-auth/service-tokens
2. 点击 `Create Service Token`。
3. 填写可追踪的名称，例如 `lingxu-godot-preview-smoke`。
4. 选择有效期。
5. 生成后立即复制 `Client ID` 和 `Client Secret`，secret 只显示一次。
6. 在目标 Access app 的 policy 里添加 `Service Auth` policy，并选择这个 service token。
7. 调用方请求受保护 URL 时加 headers：

```text
CF-Access-Client-Id: <CLIENT_ID>
CF-Access-Client-Secret: <CLIENT_SECRET>
```

## 第一版 Skill 应如何引用

第一版 `godot-pages-preview` 或后续插件应把 Zero Trust 当作 Pages 部署后的可选阶段：

1. Pages 部署和 preview URL 输出完成后，提示是否进入“Zero Trust 保护”。
2. 默认推荐“只保护 preview deployments”，因为风险和权限最小。
3. 如果用户选择 production `*.pages.dev` 或 custom domain，先展示本指南对应场景的确认问题，不直接改 Cloudflare。
4. 如果没有单独 Access token，只输出直达链接和“点开后怎么做”的步骤。
5. 如果用户提供单独 Access token 且明确授权，才执行自动创建或更新 Access app/policy。
6. 跳过 Zero Trust 不应让 Pages 部署失败；结果里写明当前访问保护状态和下一步链接。

## 验证清单

- preview only：preview URL 出现 Access 登录页，`https://lingxu-godot.pages.dev/` 不受影响。
- production `*.pages.dev`：`https://lingxu-godot.pages.dev/` 和 preview URL 都出现 Access 登录页，并对应两个 Access apps 或明确的多 hostname app。
- custom domain：custom domain 已在 Pages 里绑定成功，DNS 正常，访问 custom domain 出现 Access 登录页。
- policy：允许名单内邮箱能进入，允许名单外邮箱不能进入。
- session：关闭无痕窗口或等待 session duration 后，Access 会重新要求登录。
- service token：无 headers 的请求被 Access 拦截，带正确 service token headers 的请求成功。

## 参考文档

- Cloudflare Pages preview deployments：https://developers.cloudflare.com/pages/configuration/preview-deployments/
- Cloudflare Pages known issues for `*.pages.dev` Access：https://developers.cloudflare.com/pages/platform/known-issues/#enable-access-on-your-pagesdev-domain
- Cloudflare Pages custom domains：https://developers.cloudflare.com/pages/configuration/custom-domains/
- Access self-hosted public application：https://developers.cloudflare.com/cloudflare-one/access-controls/applications/http-apps/self-hosted-public-app/
- Access policies：https://developers.cloudflare.com/cloudflare-one/access-controls/policies/
- One-time PIN login：https://developers.cloudflare.com/cloudflare-one/integrations/identity-providers/one-time-pin/
- Service tokens：https://developers.cloudflare.com/cloudflare-one/access-controls/service-credentials/service-tokens/
- API token template URLs：https://developers.cloudflare.com/fundamentals/api/how-to/account-owned-token-template/
- API token permissions：https://developers.cloudflare.com/fundamentals/api/reference/permissions/
