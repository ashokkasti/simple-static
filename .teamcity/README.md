# InvisiRisk BAF in TeamCity

All eight jobs in `/.teamcity.yml` use `.teamcity/with-baf.sh` to start their own
BAF session, run their commands, and upload results during cleanup. There is no
separate InvisiRisk job. The frontend, API, and worker jobs each run `npm ci`
directly on their agent before their existing application commands.

Each job runs on a JetBrains-hosted `Ubuntu-24.04-Small` agent. Job result reuse
is disabled so BAF runs for every job execution. Application commands run on the
agent; the vendor BAF startup uses Docker internally to retrieve its binary.

## Configuration

In the pipeline's **Settings > Secrets**, create `IR_TOKEN` with your InvisiRisk
app token and save. TeamCity commits only its `credentialsJSON` reference.
The pipeline maps `IR_TOKEN` to `APP_TOKEN` for every job.
`API_URL` defaults to `https://app.invisirisk.com`.

Push changes to `/.teamcity.yml` on GitHub to update TeamCity automatically.

## Job lifecycle

1. Create a scan using the portal's `data.scan_id` response field and source the
   vendor startup script in the wrapper's Bash process. Retain `SCAN_ID`, proxy,
   and CA variables for the job and cleanup.
2. Run the job script under BAF. npm receives the proxy and CA through environment
   variables and uses a fresh cache. TLS verification remains enabled.
3. If the job installed `node_modules`, publish its dependency tree and enable
   dependency graph collection. Jobs without installed dependencies still record
   their own BAF session and skip dependency graph collection.
4. Run vendor cleanup on success, failure, or a handled cancellation. Publish
   `reports/baf` artifacts for each job and remove the temporary script and cache.

A cleanup failure fails an otherwise successful job. A command failure retains
its original exit code. A forced agent shutdown cannot execute shell traps.
BAF covers commands inside the wrapper; TeamCity checkout happens before startup.

Adapted from the [AWS CodeBuild Non Docker Build NPM example](https://github.com/ir-playground/invisirisk-baf-setup-examples/tree/77cd183283a17575ffc9c995fac21f6afa2bcdac/AWS%20CodeBuild%20Non%20Docker%20Build%20NPM).
