#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

LABEL="CHATWOOT-F4-HOOK-INBOX-IDOR"
WITNESS="VICTIM-INBOX-NAME-LEAK"
PROJECT="cwlab4"
BASE_URL="http://127.0.0.1:28240"
SLOT_FD=""

down() {
  echo "== docker compose -p ${PROJECT} down -v --remove-orphans =="
  docker compose -p "${PROJECT}" down -v --remove-orphans || true
}

release_slot() {
  if [[ -n "${SLOT_FD}" ]]; then
    eval "exec ${SLOT_FD}>&-"
    SLOT_FD=""
  fi
}

cleanup() {
  local status=$?
  down
  release_slot
  exit "${status}"
}
trap cleanup EXIT

# flock(2) locks live on the open file description, so bash keeps the slot held
# through the inherited fd after the helper exits. macOS has no flock(1).
try_lock() {
  if command -v flock >/dev/null 2>&1; then
    flock -n "$1"
  else
    python3 -c 'import fcntl, sys; fcntl.flock(int(sys.argv[1]), fcntl.LOCK_EX | fcntl.LOCK_NB)' "$1" 2>/dev/null
  fi
}

# Two Chatwoot stacks fit the Docker VM; a third starves Postgres and Puma.
acquire_slot() {
  local i fd
  while true; do
    for i in 1 2; do
      # bash 3.2 has no {var}> redirection, so the slot fds are fixed at 10 + i.
      fd=$((10 + i))
      eval "exec ${fd}>/tmp/chatwoot-lab-slot-${i}.lock"
      if try_lock "${fd}"; then
        SLOT_FD="${fd}"
        echo "== chatwoot lab slot ${i} acquired (fd ${fd}) =="
        return 0
      fi
      eval "exec ${fd}>&-"
    done
    echo "== all chatwoot lab slots busy; retrying in 15s =="
    sleep 15
  done
}

wait_ready() {
  local i code
  for i in $(seq 1 210); do
    code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 3 "${BASE_URL}/api/v1/profile" || true)"
    if [[ "${code}" == "401" ]]; then
      echo "== chatwoot ready attempt=${i} =="
      return 0
    fi
    sleep 2
  done
  return 1
}

fail() {
  echo "FAIL ${LABEL} $1 ${WITNESS}" | tee poc-last-run.txt
  docker compose -p "${PROJECT}" logs --tail=40 prepare seed rails sidekiq 2>&1 || true
  exit 1
}

acquire_slot

docker compose -p "${PROJECT}" down -v --remove-orphans >/dev/null 2>&1 || true

if ! docker compose -p "${PROJECT}" up -d --build; then
  fail "compose-up-failed"
fi

wait_ready || fail "server-not-ready"

set +e
python3 poc.py 2>&1 | tee poc-last-run.txt
rc=${PIPESTATUS[0]}
set -e
exit "${rc}"
