#!/usr/bin/env bash
# VM(Ubuntu LTS) 안에서 실행 — 필수 패키지(Docker·chrony·git) + 디렉토리
set -euo pipefail

echo "▶ 시스템 업데이트 + chrony(NTP)"
sudo apt-get update -y
sudo apt-get install -y chrony curl git
timedatectl | grep -i 'synchronized' || true

echo "▶ Docker Engine + Compose plugin"
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker "$USER"
  echo "  → docker 그룹 적용을 위해 재로그인 또는: newgrp docker"
fi

echo "▶ 데이터/시크릿 디렉토리"
cd "$(dirname "$0")/.."
# prometheus·grafana 는 named volume 사용(권한 문제 회피) → 여기서 만들지 않음
mkdir -p data/{geth,beacon,validator} jwt keys/validator_keys

echo "✔ Host 준비 완료."
echo "⚠ Docker 그룹 적용 — 지금 SSH를 끊었다 다시 접속하세요 (또는: newgrp docker)."
echo "   재접속 후: ./scripts/03-gen-jwt.sh"
