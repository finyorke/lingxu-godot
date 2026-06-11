---
name: cloudflare-pages-deploy
description: Set up and document Cloudflare Pages deployment for repositories. Use when Codex needs to choose between Cloudflare Pages Git integration and GitHub Actions plus Wrangler Direct Upload, add or update Pages deployment workflows, generate user setup links for Cloudflare API tokens and GitHub Actions secrets/variables, configure Cloudflare account/project defaults, or explain Pages migration limits for Direct Upload and Git-integrated projects.
---

# Cloudflare Pages Deploy

Use this skill to make Cloudflare Pages deployment repeatable with the least possible user setup. Prefer explicit, auditable defaults over interactive CI behavior, and never ask users to paste Cloudflare tokens into issues, chat, code, or logs.

## Decision Tree

Inspect the repository and the user's deployment goal before choosing a path.

- Use **GitHub Actions build + Wrangler Direct Upload** for Godot, Unity, large asset projects, custom build toolchains, native/export templates, caching needs, artifacts, smoke tests, Playwright checks, or projects that need pre-upload file-size validation.
- Use **Cloudflare Pages Git integration** for lightweight static sites, docs, and ordinary frontend projects where Cloudflare can run the build directly with simple build/output settings.
- For existing repositories, respect the current deployment path unless the user explicitly asks to migrate. Treat migration as a separate PoC.
- If an existing Pages project was created by Direct Upload, do not try to switch it to Git integration. Create a new Git-integrated Pages project for PoC or migration.
- If an existing Pages project is Git-integrated, do not assume it can become a Direct Upload project. Disable automatic builds only when the user intentionally wants manual Wrangler deployments into that project.

## Direct Upload Workflow

Use `assets/github-actions-direct-upload.yml` as the starting template when implementing GitHub Actions + Wrangler Direct Upload.

When copying the template into `.github/workflows/cloudflare-pages.yml`:

1. Replace the `Build static output` step with the project's real build, test, and export steps.
2. Set `BUILD_OUTPUT_DIR` to the directory Wrangler should upload.
3. Keep the configuration resolution, account parsing, project auto-create, file limit check, and summary output unless the repo already has equivalent logic.
4. For Godot or Unity, keep build artifacts between build and deploy jobs so deploy credentials are not exposed to untrusted build steps.
5. Keep fork PR behavior conservative: build/check artifacts, but do not deploy with repository secrets from forks.

The Direct Upload workflow must preserve these behaviors:

- Automatically create the Pages project when it does not exist.
- Resolve `CLOUDFLARE_PROJECT_NAME` in this order: `workflow_dispatch` input, then GitHub Actions variable, then sanitized repo name.
- Resolve `CLOUDFLARE_ACCOUNT_ID` in this order: `workflow_dispatch` input, then GitHub Actions variable/secret, then Cloudflare `/accounts` using `CLOUDFLARE_API_TOKEN`.
- Skip the `/accounts` call entirely when the user explicitly configured `CLOUDFLARE_ACCOUNT_ID`.
- If `/accounts` returns multiple visible accounts, list account name/id in logs and `$GITHUB_STEP_SUMMARY`, then fail. Never guess.
- If `/accounts` returns no usable account or the token cannot list accounts, fail and tell the user to configure `CLOUDFLARE_ACCOUNT_ID`.
- Write the final account ID source, project name source, deploy branch, production branch, and whether the project was found or created to `$GITHUB_STEP_SUMMARY`.

## User Setup

Read `references/user-setup-guide.md` whenever the user needs to configure Cloudflare or GitHub. Generate concrete links from the current repository:

- GitHub secrets page: `https://github.com/<owner>/<repo>/settings/secrets/actions`
- New GitHub secret page: `https://github.com/<owner>/<repo>/settings/secrets/actions/new`
- GitHub variables page: `https://github.com/<owner>/<repo>/settings/variables/actions`
- New GitHub variable page: `https://github.com/<owner>/<repo>/settings/variables/actions/new`

Tell the user the default Pages project name before asking them to configure anything. Example: "Default Pages project name: `repo-name`. If you do not configure `CLOUDFLARE_PROJECT_NAME`, the workflow will use this value and create the project automatically."

Recommend:

- `CLOUDFLARE_API_TOKEN` as a GitHub Actions secret.
- `CLOUDFLARE_ACCOUNT_ID` as an optional GitHub Actions variable; secret is acceptable but unnecessary.
- `CLOUDFLARE_PROJECT_NAME` as an optional GitHub Actions variable only when overriding the repo-name default.
- `CLOUDFLARE_PRODUCTION_BRANCH` as an optional variable only when the production branch is not `main`.

## Token Scope

For Pages Direct Upload, prefer an account-owned Cloudflare API token when the user has permission to create one. Required permission:

- `Account` -> `Cloudflare Pages` -> `Edit`

Recommended extra permission when the user wants automatic account ID resolution:

- `Account` -> `Account Settings` -> `Read`

Scope resources to the specific target account. Do not add Zone permissions for basic Pages deployments. Add DNS or custom-domain permissions only when the user explicitly asks to automate those tasks.

## Git Integration

For Cloudflare Pages Git integration:

- Tell the user an API token does not replace the Cloudflare Workers and Pages GitHub App authorization.
- Use `https://github.com/apps/cloudflare-workers-and-pages/installations/new` for GitHub App installation.
- Ask the user to authorize only the target repository when possible.
- Use `https://dash.cloudflare.com/?to=/:account/workers-and-pages` for the Cloudflare Workers & Pages entry point.
- Configure production branch, build command, output directory, and environment variables in Cloudflare Dashboard.
- Do not use Git integration as a shortcut migration for an existing Direct Upload Pages project.

## Zero Trust Boundary

Do not bundle Zero Trust / Access automation into the default Pages deploy token.

- Preview-only Access can be configured from Pages settings when that matches the user's goal.
- Production `*.pages.dev` or custom-domain protection requires a separate Access application/policy design.
- Before automating Access, get explicit user decisions for hostname, allowed emails/domains/groups, identity provider, and session duration.
- If Access automation is required, use a separate token and a separate implementation step.

## Verification

After editing skill or workflow files:

1. Run the skill validator on this skill directory.
2. Run YAML or syntax validation when tools are available.
3. Run `git diff --check`.
4. For repository workflows, verify the build step is project-specific and `BUILD_OUTPUT_DIR` exists before Wrangler deploy.
5. For Godot/Unity/web builds, keep smoke tests and file-size checks before upload.

## Official References

- Cloudflare API token template URLs: https://developers.cloudflare.com/fundamentals/api/how-to/account-owned-token-template/
- Cloudflare Pages Direct Upload: https://developers.cloudflare.com/pages/get-started/direct-upload/
- Cloudflare Pages Direct Upload with CI: https://developers.cloudflare.com/pages/how-to/use-direct-upload-with-continuous-integration/
- Cloudflare Pages Git integration: https://developers.cloudflare.com/pages/get-started/git-integration/
- Cloudflare Pages GitHub integration: https://developers.cloudflare.com/pages/configuration/git-integration/github-integration/
- Cloudflare token permissions: https://developers.cloudflare.com/fundamentals/api/reference/permissions/
