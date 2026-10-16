# InvisiRisk BAF in TeamCity

The `SecurityScan` job runs `npm ci` directly on the agent and installs the dependencies
in `package-lock.json` through InvisiRisk BAF. The frontend, API, and worker jobs
wait for it. Their existing mock application behavior is unchanged.

The canonical pipeline file is `/.teamcity.yml`. TeamCity loads updates from
GitHub and starts the pipeline on new changes.

## Configuration

In the pipeline's **Settings > Secrets**, create `IR_TOKEN` with your InvisiRisk
app token and save the pipeline settings. TeamCity stores the value securely and
commits only its `credentialsJSON` reference. The security job maps this secret
to the `APP_TOKEN` environment variable expected by BAF.

`API_URL` defaults to `https://app.invisirisk.com`.

The job runs directly on a JetBrains-hosted `Ubuntu-24.04-Small` agent with Node,
npm, and passwordless sudo. The vendor BAF startup still uses Docker to retrieve
the BAF binary. The application does not have a Docker build.
BAF startup modifies the agent's proxy and trust settings, so
it must run on an isolated agent, outside the Node step containers.

## Build lifecycle

1. Create a scan using the portal's `data.scan_id` response field, then download
   the vendor startup script and source it in the job's Bash process.
   This retains `SCAN_ID` and proxy variables for cleanup.
   Passing `SCAN_ID` also avoids the vendor script's outdated scan-response parser.
2. Run `npm ci --omit=dev` directly on the agent with the BAF proxy and CA environment
   variables. TLS verification remains enabled. Each run uses a fresh npm cache.
   The dependency graph collector reads the installed `node_modules` in the checkout.
3. Run the vendor cleanup script on success, failure, or a handled cancellation.
   It receives the same scan ID and the build's success or failure status.
4. Remove the temporary cache and downloaded script. Publish the installed dependency
   tree and exit status from `reports/baf` as TeamCity artifacts.

If the build succeeds but cleanup fails, the job fails. If both fail, the build's
original exit code is preserved. A forced agent shutdown cannot run shell traps.

This protects the dependency installation in the security job.
It does not establish a shared firewall for other jobs running on other agents.

Adapted from the [AWS CodeBuild Non Docker Build NPM example](https://github.com/ir-playground/invisirisk-baf-setup-examples/tree/77cd183283a17575ffc9c995fac21f6afa2bcdac/AWS%20CodeBuild%20Non%20Docker%20Build%20NPM).
