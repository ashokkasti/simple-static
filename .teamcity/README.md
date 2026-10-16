# InvisiRisk BAF in TeamCity

Every job in `.teamcity.yml` runs bootstrap, sources `/tmp/ir_envs`, runs its
application commands, and calls `pse-data-collector cleanup`.

TeamCity supplies the `IR_TOKEN` secret as an environment variable. `API_URL` is
`https://app.invisirisk.com`. Bootstrap and cleanup use `sudo -E` because native
setup writes to root-owned paths on the TeamCity agent.
