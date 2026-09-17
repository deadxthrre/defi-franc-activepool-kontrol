#!/usr/bin/env bash
# Run the Kontrol ActivePool proofs without GitHub-hosted Actions.
# Works on any machine with Docker (or Podman) and a network connection.
#
#   ./run-kontrol-docker.sh            # build + prove everything
#   ./run-kontrol-docker.sh build      # just the build
#
# The Kontrol image ships K + kevm + kontrol, so nothing is installed
# on the host. Artifacts land in ./out/proofs (and the XML reports in ./).
set -euo pipefail

IMAGE="${KONTROL_IMAGE:-runtimeverificationinc/kontrol:ubuntu-jammy-1.0.255}"
ENGINE="${CONTAINER_ENGINE:-docker}"
CMD="${1:-prove}"

if ! command -v "${ENGINE}" >/dev/null 2>&1; then
  echo "error: ${ENGINE} not found. Install Docker (or set CONTAINER_ENGINE=podman)." >&2
  exit 1
fi

run() {
  "${ENGINE}" run --rm \
    -v "$(pwd)":/work \
    -w /work \
    "${IMAGE}" \
    bash -lc "$1"
}

echo "==> kontrol build"
run "kontrol build --verbose"

if [ "${CMD}" = "build" ]; then
  echo "==> build only; done."
  exit 0
fi

echo "==> kontrol prove: permissionless drain (ETH)"
run "kontrol prove --match-test 'ActivePoolPropertiesTest.check_external_attacker_cannot_send_eth' --reinit --workers 2 --xml-test-report --xml-test-report-name kontrol-prove-eth.xml"

echo "==> kontrol prove: ERC20 + cross-asset drain"
run "kontrol prove --match-test 'ActivePoolPropertiesTest.check_external_attacker_cannot_send_erc20' --match-test 'ActivePoolPropertiesTest.check_sp_of_other_asset_cannot_drain' --reinit --workers 2 --xml-test-report --xml-test-report-name kontrol-prove-erc20.xml"

echo "==> kontrol prove: accounting invariants"
run "kontrol prove --match-test 'ActivePoolPropertiesTest.check_authorized_sp_eth_withdraw_decreases_balance_by_amount' --match-test 'ActivePoolPropertiesTest.check_cannot_send_more_than_recorded_balance' --match-test 'ActivePoolPropertiesTest.check_received_erc20_deposit_tracking' --reinit --workers 2 --xml-test-report --xml-test-report-name kontrol-prove-accounting.xml"

echo
echo "==> Done. Proof state under out/proofs/, reports: kontrol-prove-*.xml"