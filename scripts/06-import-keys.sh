#!/usr/bin/env bash
# 검증자 keystore import — VC(Lighthouse) 가 서명할 키를 validator datadir 로 들여온다
#   읽기: keys/validator_keys/keystore-*.json  (04-gen-keys.sh 산출물, :ro 마운트)
#   쓰기: data/validator/                       (import 된 validator_definitions.yml + secrets)
# keystore 비밀번호를 대화형으로 입력받는다 (키 생성 시 정한 그 비밀번호).
set -euo pipefail
cd "$(dirname "$0")/.."

KEYS_DIR="keys/validator_keys"

# ── 사전 점검 ───────────────────────────────────────────────────
if ! ls "${KEYS_DIR}"/keystore-*.json >/dev/null 2>&1; then
  echo "✘ ${KEYS_DIR}/keystore-*.json 이 없습니다."
  echo "  먼저 ./scripts/04-gen-keys.sh 0x0dC0CA2fC216177041DbE01d8C1DeA9621eb8801 (본인 주소) 로 키를 생성하세요."
  exit 1
fi

n=$(ls "${KEYS_DIR}"/keystore-*.json 2>/dev/null | wc -l | tr -d ' ')
echo "▶ keystore ${n}개 발견 — import 시작 (비밀번호 입력 대기)"

# ── import (네트워크 차단된 일회성 컨테이너) ────────────────────
# --directory 안의 keystore-*.json 를 datadir(/data) 로 들여온다.
docker compose --profile core run --rm \
  validator lighthouse account validator import \
  --network hoodi \
  --datadir /data \
  --directory /keys/validator_keys \
  --reuse-password

echo "✔ import 완료 — 'lighthouse account validator list' 로 확인 가능"
echo "  다음: docker compose --profile core up -d validator   (VC 기동)"
