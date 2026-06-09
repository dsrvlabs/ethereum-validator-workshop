# Ethereum Validator Workshop — Hoodi on GCP

Google Cloud VM 한 대에 **Geth(EL) + Lighthouse(CL/VC) + MEV-Boost + 모니터링**을 Docker Compose로 구성하여 **Hoodi 테스트넷 검증자**를 활성화하는 핸즈온 실습입니다.

> 본 구성은 실습을 위한 단일 VM 환경입니다. 실제 운영 환경에서는 클라이언트·리전·키를 분산하시기 바랍니다.

## 0. 사전 준비

- GCP 프로젝트 및 결제 계정 
- 로컬에 `gcloud` 설치 후 `gcloud auth login`, **또는** GCP **Cloud Shell**(브라우저, gcloud 내장)
- Hoodi 실습용 ETH (강사 사전 준비분 또는 pk910 PoW faucet)
- 보상을 수령할 본인 소유 EOA 주소 1개 (fee recipient 및 withdrawal 용도)

## 1. 실습 준비 — Cloud (GCP Console UI)

**① VM 생성** — Compute Engine → VM 인스턴스 → **인스턴스 만들기**

| 설정 | 값 |
|------|-----|
| 이름 | `ethereum-validator-hoodi` |
| 리전 · 영역 | `us-central1` (아이오와) |
| 머신 유형 | E2 · `e2-standard-4` (4 vCPU·16GB) |
| 부팅 디스크 | Ubuntu LTS |
| 디스크 유형·크기 | **SSD 영구 디스크 · 200GB** (pd-standard·Local SSD 금지) |
| 네트워크 태그 | `eth-node` |

**② 방화벽** — VPC 네트워크 → 방화벽 → **방화벽 규칙 만들기**

| 항목 | 값 |
|------|-----|
| 방향 | 인그레스(수신) |
| 대상 | 지정된 태그: `eth-node` |
| 소스 IPv4 | `0.0.0.0/0` |
| 프로토콜·포트 | tcp `30303,9000` · udp `30303,9000` |
| 작업 | 허용 |

**③ 접속 및 준비** — VM 목록의 **SSH 버튼**(브라우저)으로 접속한 뒤, 빈 Ubuntu 환경 기준으로 다음을 수행합니다.

```bash
# 1) 필수 패키지 설치 (clone에 git 필요)
sudo apt update && sudo apt install -y git

# 2) 저장소 clone
git clone https://github.com/dsrvlabs/ethereum-validator-workshop.git
cd ethereum-validator-workshop
chmod +x scripts/*.sh                  # 실행 권한 보장

# 3) Docker · chrony · 디렉토리 일괄 설치
./scripts/02-host-setup.sh

# 4) 환경변수 — FEE_RECIPIENT(본인 EOA) 입력 필수
cp .env.example .env && nano .env
```

> ⚠ **`02-host-setup.sh` 실행 직후 SSH를 재접속**하시기 바랍니다 (브라우저 SSH 창을 닫았다 다시 열기). `usermod -aG docker` 는 새 로그인 세션부터 적용되므로, 재접속 전에는 `docker` 명령이 권한 거부됩니다. (임시 적용은 `newgrp docker` 로도 가능합니다.)

> CLI 사용을 선호하는 경우 `./scripts/01-gcp-create-vm.sh` 로 ①②를 한 번에 처리할 수 있습니다.

> **방화벽 원칙** — GCP 방화벽(VPC)에서는 P2P 포트(30303·9000)만 공개합니다.
> RPC(8545)·Engine(8551)·Grafana(3000)는 compose에서 `127.0.0.1` 에 바인딩되어 외부로 노출되지 않습니다.

## 2. Fullnode setup (EL + CL)

> SSH 재접속을 완료한 뒤 진행합니다 (docker 그룹 적용). `docker run --rm hello-world` 또는 `docker ps` 로 확인합니다.

```bash
./scripts/03-gen-jwt.sh                 # EL↔CL 공유 JWT

docker compose --profile core up -d geth beacon
docker compose logs -f beacon           # "Synced" 확인 (checkpoint sync로 수 분)

# 동기화 확인 — EL·CL 한 번에 (is_syncing/eth_syncing == false 면 완료)
./scripts/05-check-sync.sh

# (수동) 개별 확인
curl -s localhost:5052/eth/v1/node/syncing
curl -s -X POST localhost:8545 -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}'
```

## 3. VC setup (키 → 예치 → 활성화)

```bash
# 3-1) 키 생성 (네트워크 차단). 기본 0x01, 복리형이면 --compounding(0x02)
#      ↓ 주소는 예시 — 반드시 본인 EOA(출금) 주소로 교체
./scripts/04-gen-keys.sh 0x0dC0CA2fC216177041DbE01d8C1DeA9621eb8801

# 3-2) Launchpad 에서 deposit_data-*.json 업로드 + 32 ETH 예치
#      https://hoodi.launchpad.ethereum.org

# 3-3) keystore import (비밀번호 입력)
./scripts/06-import-keys.sh
#   ↑ 아래 명령을 감싼 스크립트 (사전 점검 + 비밀번호 1회 입력)
#   docker compose --profile core run --rm validator lighthouse account validator import \
#     --network hoodi --datadir /data --directory /keys/validator_keys --reuse-password

# 3-4) Validator Client 기동
docker compose --profile core up -d validator
docker compose logs -f validator        # "Successfully published attestation"

# 3-5) 상태 확인 — pending_queued → active_ongoing
#      https://hoodi.beaconcha.in  (pubkey 검색)
```

> 예치 후 검증자는 churn limit이 적용되는 **활성화 대기열(entry queue)** 을 거쳐 활성화됩니다. 혼잡 시 수일 이상 소요될 수 있으며, 실시간 대기열 현황은 validatorqueue.com 에서 확인합니다.

## 4. MEV-Boost (선택)

MEV-Boost는 **CL(beacon)과 VC** 양쪽에 플래그가 필요합니다 (EL/geth는 변경하지 않습니다). 기본 compose에는 두 플래그가 주석 처리되어 있으므로, 이 단계에서 해제합니다.

이 단계는 설정을 변경한 뒤 노드를 **내렸다 다시 올리는** 실습입니다 (플래그 적용에는 컨테이너 재생성이 필요합니다).

```bash
# 1) docker-compose.yml 에서 두 줄의 주석(#) 해제:
#      beacon:    - --builder=http://mev-boost:18550
#      validator: - --builder-proposals
# 2) .env 의 MEV_RELAYS 확인 (Flashbots+Aestus 기본 입력)

# 3) mev-boost 기동
docker compose --profile mev up -d mev-boost

# 4) beacon·validator 를 내렸다 → 다시 올린다 (새 플래그 적용)
docker compose stop beacon validator
docker compose --profile core up -d beacon validator

# 5) 동작 확인
curl -s localhost:18550/eth/v1/builder/status            # 200 OK
docker compose logs -f beacon | grep -i builder          # builder 등록 로그
```

> 검증자 듀티 도중 stop→up 사이에 발생하는 짧은 다운타임은 테스트넷에서 무해합니다. 메인넷에서도 다운타임은 복구가 가능하지만, **같은 키를 두 곳에서 동시에 실행하지 않도록** 항상 stop 후 up 하시기 바랍니다.

> 플래그를 해제하지 않으면 mev-boost가 기동되어 있어도 검증자는 builder를 사용하지 않습니다(로컬 빌딩). 반대로 플래그만 해제하고 mev-boost가 없으면 beacon이 builder를 찾지 못해 로컬 빌딩으로 폴백합니다.

사용 가능한 Hoodi relay 예시는 다음과 같습니다 (출처: ethstaker-guides, 2026-06 기준 — 실습 전 재확인을 권장합니다).

| Relay | URL |
|-------|-----|
| Flashbots | `https://0xafa4...@boost-relay-hoodi.flashbots.net` |
| Aestus | `https://0x98f0...@hoodi.aestus.live` |
| Titan | `https://0xaa58...@hoodi.titanrelay.xyz` |
| bloXroute | `https://0x821f...@bloxroute.hoodi.blxrbdn.com` |

## 5. Monitoring

```bash
docker compose --profile monitoring up -d
```

콘솔 SSH 버튼만 사용하여 SSH 터널이 불가능한 경우, Grafana는 방화벽 규칙을 통해 접속합니다.

- VPC 네트워크 → 방화벽 → 규칙 만들기: 대상 태그 `eth-node`, **소스 IPv4 = 본인 IP/32**, tcp `3000` 허용
- 브라우저로 `http://<VM_EXTERNAL_IP>:3000` 접속 (admin / `.env` 의 GRAFANA_PASSWORD)

> 위는 실습 편의를 위한 구성입니다. 운영 환경에서는 compose의 grafana 포트를 `127.0.0.1:3000:3000` 으로 두고 SSH 터널을 사용하시기 바랍니다.

핵심 지표: 피어 수 · 슬롯 거리 · 어테스테이션 적중률 · 디스크 여유 · NTP 오프셋.

## 운영 체크리스트

- [ ] 슬래싱 보호 DB는 절대 비활성화하지 않습니다 (validator 볼륨 영속).
- [ ] **같은 키를 두 곳에서 동시에 실행하지 않습니다** — `docker compose` 복제·페일오버에 주의합니다.
- [ ] 클라이언트 버전을 정기적으로 확인하고, mandatory 업그레이드·하드포크 시 즉시 갱신합니다. 갱신 시 프로파일을 명시해야 적용됩니다: `docker compose --profile core pull && docker compose --profile core up -d` (mev·monitoring 사용 중이면 해당 `--profile` 도 함께 지정).
- [ ] 마이그레이션 시에는 EIP-3076 export/import 및 기존 인스턴스의 완전 종료를 확인합니다.

## 정리 (과금 중단)

```bash
docker compose --profile core --profile mev --profile monitoring down
# 또는 Console: VM 인스턴스 목록 → 인스턴스 선택 → 삭제
gcloud compute instances delete ethereum-validator-hoodi --zone=us-central1-a
```

## 디렉토리

```
.
├── docker-compose.yml      # EL/CL/VC/MEV/모니터링 (profiles)
├── .env.example            # 버전·fee recipient·relay 설정
├── prometheus.yml          # 스크레이프 타깃
└── scripts/
    ├── 01-gcp-create-vm.sh # GCP VM + 방화벽
    ├── 02-host-setup.sh    # Docker + 디렉토리
    ├── 03-gen-jwt.sh       # JWT 시크릿
    ├── 04-gen-keys.sh      # 검증자 키 생성
    ├── 05-check-sync.sh    # EL·CL 동기화 · 피어 점검
    └── 06-import-keys.sh   # keystore import (VC)
```

⚠ `.env` · `jwt/` · `keys/` · `data/` 는 `.gitignore` 처리되어 있습니다 — **절대 커밋하지 마십시오**.
