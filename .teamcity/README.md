# InvisiRisk BAF in TeamCity

All eight jobs in `/.teamcity.yml` run the same bootstrap flow before their
application commands. `WORKSPACE` is set to the writable checkout directory
and `CI_BUILDER` is set to `teamcity` before bootstrap:

```sh
curl -sSf -H "x-api-key: ${IR_TOKEN}" "${API_URL%/}/ingestionapi/v1/pse/bootstrap" | sudo -E bash
. /tmp/ir_envs
```

An exit trap invokes `sudo -E pse-data-collector cleanup` when the commands succeed,
fail, or receive a handled cancellation. Cleanup failures fail successful jobs;
command failures retain their original exit code. Forced agent shutdowns cannot
run shell traps.

The bootstrap and cleanup are inline in each job. There is no separate BAF job,
local wrapper script, manual scan API call, or application Docker build.

## Configuration

The pipeline maps the TeamCity secret `IR_TOKEN` to the environment variable of
the same name. `API_URL` defaults to `https://app.invisirisk.com`. Secret values
remain in TeamCity; GitHub stores only their `credentialsJSON` references.

Every job runs directly on an Ubuntu 24.04 agent with curl, Bash, and passwordless
sudo. Bootstrap and cleanup run with sudo because native setup writes to root-owned
paths. Application commands run as the agent user. The proxy and CA must be
configured before application commands start. Result reuse is disabled so every job execution runs bootstrap and cleanup.
The frontend, API, and worker jobs each run `npm ci` under BAF before their
existing application commands. The remaining application checks are mocked.

TeamCity loads GitHub changes to `/.teamcity.yml` automatically. BAF starts after
TeamCity checks out the repository and protects the commands that follow startup.
