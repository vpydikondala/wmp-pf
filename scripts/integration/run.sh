#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$ROOT"

cleanup() {
  docker compose -f docker-compose.integration.yml --env-file .integration.env down -v --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

touch .integration.env
docker compose -f docker-compose.integration.yml --env-file .integration.env up -d --build localstack postgres mock-meraki

for _ in $(seq 1 60); do
  if curl -fsS http://localhost:4566/_localstack/health >/dev/null \
     && curl -fsS http://localhost:8081/health >/dev/null \
     && docker compose -f docker-compose.integration.yml exec -T postgres pg_isready -U platform_admin -d occupancy >/dev/null; then
    break
  fi
  sleep 2
done

./scripts/integration/init-localstack.sh

docker compose -f docker-compose.integration.yml --env-file .integration.env up -d --build inbound processor outbound

for _ in $(seq 1 60); do
  if curl -fsS http://localhost:8080/health >/dev/null; then break; fi
  sleep 2
done

python -m pip install -r tests/integration/requirements.txt
AWS_ENDPOINT_URL=http://localhost:4566 pytest -q tests/integration
