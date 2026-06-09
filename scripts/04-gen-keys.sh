#!/usr/bin/env bash
# 검증자 키 생성 — 네트워크 차단된 일회성 컨테이너에서
# 산출: keys/validator_keys/keystore-*.json (VC import용)
#       keys/validator_keys/deposit_data-*.json (Launchpad 업로드용)
set -euo pipefail
cd "$(dirname "$0")/.."

WITHDRAWAL="${1:-}"
if [ -z "$WITHDRAWAL" ]; then
  echo "사용법: ./scripts/04-gen-keys.sh 0xYourWithdrawalAddress [--compounding]"
  echo "  기본 0x01(Execution) credential · --compounding 시 0x02"
  exit 1
fi
shift || true

docker run -it --rm --network none \
  -v "$(pwd)/keys/validator_keys:/app/validator_keys" \
  ghcr.io/ethstaker/ethstaker-deposit-cli:v1.3.0 \
  new-mnemonic \
  --num_validators 1 \
  --chain hoodi \
  --withdrawal_address "$WITHDRAWAL" \
  "$@"

echo "✔ keys/validator_keys/ 확인 — 니모닉은 오프라인 백업, 서버에 남기지 말 것"
