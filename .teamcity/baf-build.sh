#!/usr/bin/env bash
# Run on an isolated Ubuntu agent, outside TeamCity's step container.
set +x
set -eo pipefail

: "${API_URL:?Set API_URL to the InvisiRisk portal URL}"
: "${APP_TOKEN:?Set the TeamCity pipeline secret IR_TOKEN}"
: "${BUILD_ID:?TeamCity build ID is required}"

command -v curl >/dev/null
command -v python3 >/dev/null
command -v node >/dev/null
command -v npm >/dev/null
if [ "$(id -u)" -ne 0 ]; then
  sudo -n true
fi

export DEBUG=false DEBUG_FORCE=false
export CI_BUILDER=teamcity WORKSPACE="$PWD"

mkdir -p reports/baf
baf_workdir=$(mktemp -d "${TMPDIR:-/tmp}/simple-static-baf.XXXXXX")
baf_cleanup_script=/tmp/pse_cleanup/cleanup.sh
baf_started=false

baf_finish() {
  baf_status=$?
  trap - EXIT ERR INT TERM
  set +e
  export BUILD_STATUS=failed
  if [ "$baf_status" -eq 0 ]; then
    export BUILD_STATUS=success
  fi

  if [ "$baf_started" = true ]; then
    if [ -f "$baf_cleanup_script" ]; then
      echo "Uploading BAF build data and cleaning up"
      bash "$baf_cleanup_script"
      baf_cleanup_status=$?
      if [ "$baf_status" -eq 0 ] && [ "$baf_cleanup_status" -ne 0 ]; then
        baf_status=$baf_cleanup_status
      fi
    else
      echo "BAF startup did not finish; its cleanup script is unavailable." >&2
      [ "$baf_status" -ne 0 ] || baf_status=1
    fi
  fi

  rm -rf "$baf_workdir"
  printf 'build_id=%s\nexit_code=%s\n' "$BUILD_ID" "$baf_status" > reports/baf/status.txt
  exit "$baf_status"
}

trap baf_finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

echo "Starting InvisiRisk BAF for TeamCity build $BUILD_ID"
curl --fail --show-error --silent --location --retry 3 \
  --connect-timeout 15 --max-time 120 \
  "${API_URL%/}/pse/bitbucket-setup/pse_startup" \
  --output "$baf_workdir/startup.sh"

# The current portal returns data.scan_id; the vendor startup expects id.
# Supplying SCAN_ID makes startup reuse this scan instead of parsing a new one.
echo "Creating the InvisiRisk scan"
python3 -c 'import json, os, sys; json.dump({"api_key": os.environ["APP_TOKEN"]}, sys.stdout)' |
  curl --fail --show-error --silent --location \
    --connect-timeout 15 --max-time 60 \
    --header 'Content-Type: application/json' \
    --data-binary @- \
    "${API_URL%/}/utilityapi/v1/scan" \
    --output "$baf_workdir/scan.json"
SCAN_ID=$(python3 - "$baf_workdir/scan.json" <<'PY'
import json
import sys
import uuid

with open(sys.argv[1]) as response:
    payload = json.load(response)
scan_id = payload.get("data", {}).get("scan_id") or payload.get("id")
if payload.get("success") is False or not scan_id:
    sys.exit("InvisiRisk did not return a scan ID")
print(uuid.UUID(scan_id))
PY
)
export SCAN_ID

baf_started=true
# Keep SCAN_ID and proxy exports in this shell so cleanup can end the same scan.
# The upstream script also exports its CA path as NODE_EXTRA_CA_CERTS.
source "$baf_workdir/startup.sh"
# The vendor ERR trap rewrites every failure to exit 1. Preserve build exit codes.
trap - ERR

: "${SCAN_ID:?BAF startup did not return a scan ID}"
: "${PSE_PROXY_IP:?BAF startup did not return a proxy IP}"
baf_ca_certificate="${NODE_EXTRA_CA_CERTS:-/etc/ssl/certs/pse.pem}"
test -s "$baf_ca_certificate"

echo "Installing npm dependencies through the BAF proxy"
export npm_config_proxy="http://${PSE_PROXY_IP}:3128"
export npm_config_https_proxy="$npm_config_proxy"
export NODE_EXTRA_CA_CERTS="$baf_ca_certificate"
node --version
npm --version
# Use a fresh cache so this job exercises BAF instead of reusing downloaded tarballs.
npm ci --omit=dev --no-audit --no-fund --cache "$baf_workdir/npm-cache"
npm ls --omit=dev --json > reports/baf/dependencies.json

echo "BAF-protected dependency build completed"
