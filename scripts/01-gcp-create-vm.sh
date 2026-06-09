#!/usr/bin/env bash
# [선택 / CLI 대안] GCP Compute Engine VM 생성 + P2P 방화벽 규칙
# 워크샵 기본 경로는 Console UI 생성입니다 (README §1). 이 스크립트는 CLI 선호자용.
# 사전: gcloud 설치 + 인증(gcloud auth login) + 프로젝트 설정
#   또는 GCP Cloud Shell 에서 그대로 실행 (gcloud 기본 제공)
set -euo pipefail

# ── 설정 (필요시 수정) ──────────────────────────────────────────
PROJECT="$(gcloud config get-value project)"
ZONE="us-central1-a"              # 아이오와 리전
INSTANCE="ethereum-validator-hoodi"
MACHINE="e2-standard-4"           # 4 vCPU / 16GB (실습 최소) · 권장 e2-standard-8
DISK_SIZE="200GB"
DISK_TYPE="pd-ssd"                # NVMe급 IOPS — pd-standard 금지(동기화 못 따라감)

echo "▶ Creating VM ${INSTANCE} in ${ZONE} (project ${PROJECT})"
gcloud compute instances create "${INSTANCE}" \
  --zone="${ZONE}" \
  --machine-type="${MACHINE}" \
  --image-family=ubuntu-2204-lts \
  --image-project=ubuntu-os-cloud \
  --boot-disk-size="${DISK_SIZE}" \
  --boot-disk-type="${DISK_TYPE}" \
  --tags=eth-node

echo "▶ Opening P2P ports (30303, 9000) for tag eth-node"
gcloud compute firewall-rules create eth-p2p \
  --direction=INGRESS --action=ALLOW \
  --rules=tcp:30303,udp:30303,tcp:9000,udp:9000 \
  --target-tags=eth-node || echo "  (rule eth-p2p already exists)"

echo "✔ Done. SSH 접속:"
echo "  gcloud compute ssh ${INSTANCE} --zone=${ZONE}"
echo
echo "⚠ 실습 후 과금 중단 — VM 삭제:"
echo "  gcloud compute instances delete ${INSTANCE} --zone=${ZONE}"
