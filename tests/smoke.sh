#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")/.."

test_dir=$(mktemp -d)
export COMPOSE_PROJECT_NAME="dind-smoke-$$"
export DIND_IMAGE="${DIND_SMOKE_IMAGE:-dind-smoke:local}"
export SSH_PORT=38222 SERVICE_PORT=38777 DIND_SERVICE_PORT=38778
export SSH_AUTHORIZED_KEYS="$test_dir/key.pub" GH_TOKEN= GHCR_TOKEN=
compose() {
    if [ -n "${DIND_SMOKE_RELEASE_FILE:-}" ]; then
        docker compose --project-directory "$PWD" -f "$DIND_SMOKE_RELEASE_FILE" -f "$PWD/tests/compose.test.yml" "$@"
    else
        ./compose -f tests/compose.test.yml "$@"
    fi
}
cleanup() {
    compose down -v || true
    rm -f "$test_dir/key" "$test_dir/key.pub" "$test_dir/known_hosts"
    rmdir "$test_dir"
}
trap cleanup EXIT
ssh-keygen -q -t ed25519 -N '' -f "$test_dir/key"
if [ -n "${DIND_SMOKE_RELEASE_FILE:-}" ]; then
    compose up -d
else
    compose up -d --build
fi

agent=$COMPOSE_PROJECT_NAME
for _ in $(seq 1 30); do
    if ssh -o BatchMode=yes -o ConnectTimeout=2 -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile="$test_dir/known_hosts" -i "$test_dir/key" \
        -p "$SSH_PORT" agent@127.0.0.1 'docker version --format "{{.Server.Version}}" && docker compose version'; then
        break
    fi
    sleep 1
done
# Fail if SSH has not become usable.
ssh -o BatchMode=yes -o ConnectTimeout=2 -o StrictHostKeyChecking=yes \
    -o UserKnownHostsFile="$test_dir/known_hosts" -i "$test_dir/key" \
    -p "$SSH_PORT" agent@127.0.0.1 'docker info >/dev/null && docker compose version'

docker exec -u agent "$agent" sh -ec 'test -r "$HOME/.codex/AGENTS.md" && test -r "$HOME/.claude/CLAUDE.md" && cmp "$HOME/.codex/AGENTS.md" "$HOME/.claude/CLAUDE.md" && grep -q "in English" "$HOME/.codex/AGENTS.md"'
docker exec -u agent "$agent" sh -ec 'mkdir -p /workspaces/smoke && printf shared-ok > /workspaces/smoke/probe'
docker exec -u agent "$agent" docker run -d --name nested-smoke \
    -p 7778:6379 -v /workspaces/smoke:/probe:ro redis:7-alpine
for _ in $(seq 1 30); do
    if [ "$(docker exec -u agent "$agent" docker exec nested-smoke redis-cli ping 2>/dev/null || true)" = PONG ]; then break; fi
    sleep 1
done
[ "$(docker exec -u agent "$agent" docker exec nested-smoke redis-cli ping)" = PONG ]
[ "$(docker exec -u agent "$agent" docker exec nested-smoke cat /probe/probe)" = shared-ok ]
docker exec -u agent "$agent" node -e 'const s=require("net").connect(7778,"dind",()=>s.write("*1\r\n$4\r\nPING\r\n"));s.on("data",b=>{if(b.toString().trim()!=="+PONG")process.exit(1);s.end()});s.on("error",()=>process.exit(1));setTimeout(()=>process.exit(1),5000).unref()'
if docker ps -a --format '{{.Names}}' | grep -Fxq nested-smoke; then
    echo 'Nested container is visible to the host daemon' >&2; exit 1
fi
if docker exec -u agent "$agent" docker ps -a --format '{{.Names}}' | grep -Fxq "$agent"; then
    echo 'Host agent container is visible to the inner daemon' >&2; exit 1
fi
printf '%s\n' 'Smoke test passed: SSH, Docker, Compose, Redis, network, bind mount and daemon separation.'
