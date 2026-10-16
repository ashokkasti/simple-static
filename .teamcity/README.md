# InvisiRisk BAF in TeamCity

The `SecurityScan` job performs a real Docker build and installs the dependencies
in `package-lock.json` through InvisiRisk BAF. The frontend, API, and worker jobs
wait for it. Their existing mock application behavior is unchanged.

The canonical pipeline file is `/.teamcity.yml`. TeamCity loads updates from
GitHub and starts the pipeline on new changes.

## Configuration

In the pipeline's **Settings > Secrets**, create `IR_TOKEN` with your InvisiRisk
app token and save the pipeline settings. TeamCity stores the value securely and
commits only its `credentialsJSON` reference. The security job maps this secret
to the `APP_TOKEN` environment variable expected by BAF.

`API_URL` defaults to `https://app.invisirisk.com`. The BuildKit frontend is
`public.ecr.aws/w3c0c0n7/invisirisk/baf-buildkit:latest`.

The job runs directly on a JetBrains-hosted `Ubuntu-24.04-Small` agent with Docker and
passwordless sudo. BAF startup modifies the agent's proxy and trust settings, so
it must run on an isolated agent, outside the Node step containers.

## Build lifecycle

1. Create a scan using the portal's `data.scan_id` response field, then download
   the vendor startup script and source it in the job's Bash process.
   This retains `SCAN_ID` and proxy variables for cleanup.
   Passing `SCAN_ID` also avoids the vendor script's outdated scan-response parser.
2. Use the BAF BuildKit frontend, proxy build argument, and CA secret to run
   `npm ci --omit=dev` in the Docker build. npm keeps TLS verification enabled.
   `--no-cache` ensures this installation runs on every security job execution.
3. Run the vendor cleanup script on success, failure, or a handled cancellation.
   It receives the same scan ID and the build's success or failure status.
4. Remove the temporary image and downloaded script. Publish the image ID and
   exit status from `reports/baf` as TeamCity artifacts.

If the build succeeds but cleanup fails, the job fails. If both fail, the build's
original exit code is preserved. A forced agent shutdown cannot run shell traps.

This protects the dependency installation in the security job's Docker build.
It does not establish a shared firewall for other jobs running on other agents.

Adapted from the [AWS CodeBuild Docker Build NPM example](https://github.com/ir-playground/invisirisk-baf-setup-examples/tree/77cd183283a17575ffc9c995fac21f6afa2bcdac/AWS%20CodeBuild%20Docker%20Build%20NPM).
