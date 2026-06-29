# module: pipeline

The CI/CD orchestrator — **CodePipeline V2** + CodeBuild + the GitHub connection.

**Provisions (planned):**
- **CodeConnections** connection to GitHub (`scriptbuzz/aws-msp-mb`) — comes up `PENDING`, authorized manually once
- **CodePipeline V2** with a **path-filtered trigger** (`branch: main`, `filePaths: app/**`)
- Stages: Source → Build → Deploy dev → Deploy test → Deploy stage → **Manual approval** → Deploy prod (blue/green)
- **CodeBuild** projects (smallest compute) running `buildspec.yml`:
  - build image → push ECR; run unit/integration tests
  - reserved no-op **security-scan** phase (scanners deferred — design §8a)
  - scale-to-zero up/down for lower envs
  - GitHub-issue **change record** step before prod (decision #19)
- CloudWatch Logs for build/deploy execution trail (evidence)

`msp-control`: OPS06 + GAP (staged promotion, approval gate, change record).

*Placeholder — `.tf` to be added.*
