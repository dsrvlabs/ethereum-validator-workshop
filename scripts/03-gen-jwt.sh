#!/usr/bin/env bash
# EL ↔ CL 공유 JWT 시크릿(32바이트) 생성
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -f jwt/jwt.hex ]; then
  echo "jwt/jwt.hex 이미 존재 — 건너뜀 (덮어쓰면 동기화 깨짐)"
  exit 0
fi

openssl rand -hex 32 > jwt/jwt.hex
chmod 640 jwt/jwt.hex
echo "✔ jwt/jwt.hex 생성 — geth · beacon 양쪽 컨테이너에 :ro 로 마운트됨"
