# InvisiRisk BAF in TeamCity

## Before and after

This comparison uses [the pipeline before BAF integration, commit `6d34791`](https://github.com/ashokkasti/simple-static/blob/6d34791/.teamcity.yml),
and [the simplified BAF integration, commit `f1a7375`](https://github.com/ashokkasti/simple-static/blob/f1a7375/.teamcity.yml).

| Area | Before BAF | After BAF |
| --- | --- | --- |
| Jobs | Nine jobs, including a mock `SecurityScan` | Eight jobs; BAF runs inside every job |
| Execution | Scripts ran in `node:22-bookworm-slim` containers | Scripts run directly on `Ubuntu-24.04-Small` agents |
| BAF startup | None | Bootstrap runs at the start of each job |
| Environment | No BAF environment loaded | Each job sources `/tmp/ir_envs` |
| Dependency installation | Manifest existed, but build jobs did not install dependencies | Frontend, API, and worker jobs run `npm ci` after BAF setup |
| Token | `IR_TOKEN` secret reference existed but scripts did not use it | TeamCity maps the secret to `env.IR_TOKEN`; bootstrap sends it in the `x-api-key` header |
| Cleanup | None | Each job ends with `sudo -E pse-data-collector cleanup` |
| Result reuse | No explicit setting | `allow-reuse: false` on every job |

The frontend packaging, mock API/worker outputs, artifact checks, release archive,
and mock staging deployment remain. Explicit artifact transfers between jobs remain.
The integration also added `package-lock.json` for `npm ci`.

## Current job flow

```text
ValidateManifest
  -> QualityChecks
  -> BuildFrontend / BuildApi / BuildWorker
  -> IntegrationChecks
  -> PackageRelease
  -> DeployStaging
```

The three build jobs can run in parallel. Each job follows the same BAF lifecycle.

| Job | Commands between BAF setup and cleanup |
| --- | --- |
| `ValidateManifest` | Read and print dependencies from `package.json` |
| `QualityChecks` | Write a mock lint/unit-test report |
| `BuildFrontend` | Install npm dependencies and copy `index.html` |
| `BuildApi` | Install npm dependencies and write mock API metadata |
| `BuildWorker` | Install npm dependencies and write mock worker metadata |
| `IntegrationChecks` | Check that the three build artifacts exist and write a mock integration report |
| `PackageRelease` | Create `release/application.tar.gz` from the build artifacts and manifest |
| `DeployStaging` | Check and list the release archive, then print mock deployment messages |

## Script before integration

Example from `BuildFrontend`:

```bash
set -eu
mkdir -p dist/frontend
cp index.html dist/frontend/index.html
echo "Packaged the existing static frontend"
```

## Script after integration

Current `BuildFrontend` script:

```bash
#!/usr/bin/env bash
set -e
curl -sSf -H "x-api-key: ${IR_TOKEN}" "${API_URL}/ingestionapi/v1/pse/bootstrap" | sudo -E bash
. /tmp/ir_envs

npm ci --omit=dev --no-audit --no-fund
mkdir -p dist/frontend
cp index.html dist/frontend/index.html
echo "Packaged the existing static frontend"

sudo -E pse-data-collector cleanup
```

Bootstrap initializes BAF. Sourcing `/tmp/ir_envs` loads the environment it creates
into the job shell before application commands run. Cleanup invokes the vendor
collector at the end of the script.

Bootstrap and cleanup use `sudo -E` because native setup writes to root-owned paths
on this agent. An earlier attempt without sudo failed creating `/pse-bin`.
`-E` preserves the environment for those commands. Application commands run as
the agent user.

There is no application Docker build, separate BAF job, or `with-baf.sh` wrapper.

## TeamCity configuration

The canonical pipeline file is [`.teamcity.yml`](../.teamcity.yml).
TeamCity is configured to load this file from GitHub. Push changes to `main`
to update the pipeline through its existing VCS configuration.

The pipeline defines:

```yaml
parameters:
  env.API_URL: https://app.invisirisk.com
  env.IR_TOKEN: "%IR_TOKEN%"
```

Store the token in the TeamCity pipeline's Secrets settings under `IR_TOKEN`.
The existing `secrets.IR_TOKEN` entry in YAML is a TeamCity credential reference,
not the token value. GitHub repository secrets are not used by this pipeline.

Agents need Bash, curl, Node.js/npm, tar, and passwordless sudo. They also need
network access to the BAF API and dependency sources used by the build.

## Scope and failure behavior

- BAF setup starts after TeamCity checks out the repository.
- Every job runs bootstrap and loads its environment, including jobs with no dependency downloads.
- The dependency manifest includes React, Express, PostgreSQL client `pg`, BullMQ, and Zod. Only the three build jobs run `npm ci`.
- Lint, unit tests, API/worker builds, application integration tests, and staging deployment remain mocked. BAF integration does not implement those application tasks.
- With `set -e`, an application command failure stops the script before the final cleanup command. There is no exit trap in this simplified version.
- The bootstrap command uses a shell pipe without `pipefail`. A curl failure is not independently propagated through the pipe; sourcing `/tmp/ir_envs` is the next command.
- A nonzero cleanup exit code fails the job when execution reaches cleanup.

## Observed result

On October 16, 2026, GitHub commit statuses reported success for all eight jobs
and the aggregate pipeline at commit `f1a7375`.
See [TeamCity build 146](https://ashokkastitv.teamcity.com/buildConfiguration/SimpleStatic_SimpleStatic/146).
This confirms pipeline execution. It does not establish a malicious-package
blocking test or validate a particular BAF policy.
