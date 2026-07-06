# Security — secrets handling

*Last updated: 2026-07-05 12:12*

**No secrets are committed to this repo, and tooling is in place to keep it that way.**

## What is never committed
- `.env` / `.env.*` (AWS profile config) — only `.env.example` is tracked
- `backend.hcl`, `*.tfvars` — only the `*.example` templates are tracked
- `*.tfstate*` (Terraform state can contain secrets)
- Key material: `*.pem`, `*.key`, `*.p12`, `*.pfx`, `id_rsa`, `credentials`

All of the above are in [`.gitignore`](.gitignore). Credentials the tooling generates
(e.g. the `cicd-demo` IAM user from `scripts/demo-user.sh`) are printed to the terminal
**once** and never written to disk.

## Pre-commit secret scanner
[`.githooks/pre-commit`](.githooks/pre-commit) blocks any commit that adds a sensitive
file or content matching an AWS access key (`AKIA…`/`ASIA…`), a private-key block, or a
secret-key assignment. **Enable it once per clone:**

```sh
git config core.hooksPath .githooks
```

Bypass only for a verified false positive: `git commit --no-verify`.

> For stronger coverage you can also run a dedicated scanner (e.g. `gitleaks`) in CI;
> the local hook is the first line of defense.

## If a secret is ever exposed
1. **Rotate/revoke it immediately** at the source (e.g. delete the IAM access key:
   `scripts/demo-user.sh delete`, or rotate in the IAM console).
2. If it was committed, purge it from history (`git filter-repo`) and force-push.
3. Prefer short-lived **SSO** credentials over long-lived IAM keys (the project default).
