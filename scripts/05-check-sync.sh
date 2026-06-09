#!/usr/bin/env bash
# EL(Geth) · CL(Lighthouse Beacon) 동기화 상태 + 피어 점검
# 둘 다 동기화 완료여야 validator 가 정상 attestation 한다.
#   EL : eth_syncing      == false      → 완료
#   CL : is_syncing       == false      → 완료
set -euo pipefail

EL_URL="${EL_URL:-http://localhost:8545}"   # geth JSON-RPC (compose: 127.0.0.1:8545)
CL_URL="${CL_URL:-http://localhost:5052}"   # beacon REST  (compose: 127.0.0.1:5052)

have_jq() { command -v jq >/dev/null 2>&1; }
rc=0

# ── CL (Beacon) ────────────────────────────────────────────────
echo "▶ CL (Beacon @ ${CL_URL})"
if cl=$(curl -s --fail --max-time 5 "${CL_URL}/eth/v1/node/syncing" 2>/dev/null); then
  if have_jq; then
    is_syncing=$(echo "$cl" | jq -r '.data.is_syncing')
    head=$(echo "$cl" | jq -r '.data.head_slot')
    dist=$(echo "$cl" | jq -r '.data.sync_distance')
    peers=$(curl -s --max-time 5 "${CL_URL}/eth/v1/node/peer_count" | jq -r '.data.connected // "?"')
  else
    is_syncing=$(echo "$cl" | grep -o '"is_syncing":[a-z]*' | cut -d: -f2)
    head=$(echo "$cl" | grep -o '"head_slot":"[0-9]*"' | grep -o '[0-9]*')
    dist=$(echo "$cl" | grep -o '"sync_distance":"[0-9]*"' | grep -o '[0-9]*')
    peers=$(curl -s --max-time 5 "${CL_URL}/eth/v1/node/peer_count" | grep -o '"connected":"[0-9]*"' | grep -o '[0-9]*')
  fi
  if [ "$is_syncing" = "false" ]; then
    echo "  ✔ 동기화 완료 (head_slot=${head}, distance=${dist}, peers=${peers:-?})"
  else
    echo "  … 동기화 중   (head_slot=${head}, distance=${dist}, peers=${peers:-?})"
    rc=1
  fi
else
  echo "  ✘ 응답 없음 — beacon 컨테이너/포트 확인 (docker compose ps)"
  rc=1
fi

# ── EL (Geth) ──────────────────────────────────────────────────
echo "▶ EL (Geth @ ${EL_URL})"
if el=$(curl -s --fail --max-time 5 -X POST "${EL_URL}" \
          -H "Content-Type: application/json" \
          -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' 2>/dev/null); then
  # 동기화 완료 시 result == false, 동기화 중이면 currentBlock/highestBlock 객체
  if echo "$el" | grep -q '"result":false'; then
    echo "  ✔ 동기화 완료"
  else
    if have_jq; then
      cur=$(echo "$el" | jq -r '.result.currentBlock')
      hi=$(echo "$el" | jq -r '.result.highestBlock')
      printf "  … 동기화 중   (current=%d, highest=%d)\n" "$((cur))" "$((hi))"
    else
      echo "  … 동기화 중   ($el)"
    fi
    rc=1
  fi
else
  echo "  ✘ 응답 없음 — geth 컨테이너/포트 확인 (docker compose ps)"
  rc=1
fi

[ "$rc" -eq 0 ] && echo "✔ EL·CL 모두 동기화 완료 — validator 정상 동작 가능" \
               || echo "⚠ 아직 동기화 진행 중 — 잠시 후 다시 실행하세요"
exit "$rc"
