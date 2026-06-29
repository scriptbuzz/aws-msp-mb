# app/ — sample static website

The **application code** the Release Management pipeline builds and deploys.
A deliberately simple static site (the whole point is to exercise the pipeline,
not to be a complex app).

- `index.html` — the site
- `VERSION` — the release marker. Bump it to cut a release (see [branch & release strategy](../docs/BRANCH_AND_RELEASE_STRATEGY.md) §5).

## How it's packaged

At build time CodeBuild builds a tiny container image (nginx serving these
static files), tags it by **immutable digest**, and pushes it to ECR. The same
digest is promoted dev → test → stage → prod.

> A change to anything under `app/**` triggers the pipeline (path filter).
> Changes to `docs/`, `web/`, or `infra/` do not.

*Placeholder — the `Dockerfile` and any build tooling land here when scaffolding fills in.*
