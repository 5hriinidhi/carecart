#!/bin/sh
# Preflight for CareCart local dev. Runs in git-bash (Windows), bash, or zsh.
#   sh scripts/check-env.sh
# Non-fatal: prints PASS/WARN/FAIL per check and a summary. Exit 1 if any FAIL.

fail=0
say()  { printf '%s %s\n' "$1" "$2"; }
pass() { say "PASS" "$1"; }
warn() { say "WARN" "$1"; }
bad()  { say "FAIL" "$1"; fail=1; }

echo "== CareCart environment check =="

# --- Docker ---
if command -v docker >/dev/null 2>&1; then
  pass "docker found: $(docker --version 2>/dev/null)"
  if docker info >/dev/null 2>&1; then
    pass "docker daemon is running"
  else
    bad "docker daemon not running - start Docker Desktop"
  fi
else
  bad "docker not installed - https://docs.docker.com/get-docker/"
fi

# --- Compose v2 (not the old hyphenated v1) ---
if docker compose version >/dev/null 2>&1; then
  pass "compose v2: $(docker compose version 2>/dev/null | head -1)"
elif command -v docker-compose >/dev/null 2>&1; then
  bad "only Compose v1 (docker-compose) found - install Compose v2. This repo's compose file needs it."
else
  bad "docker compose not available"
fi

# --- pinned tool versions (from /.tool-versions) ---
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tv="$root/.tool-versions"
pin_flutter=$(sed -n 's/^flutter \([0-9.]*\).*/\1/p' "$tv" 2>/dev/null)
pin_python=$(sed -n 's/^python \([0-9.]*\).*/\1/p' "$tv" 2>/dev/null)

check_ver() {  # name  actual  pinned
  if [ -z "$2" ]; then warn "$1 not found on PATH (pinned $3)"; return; fi
  if [ "$2" = "$3" ]; then pass "$1 $2 (matches pin)";
  else warn "$1 $2 != pinned $3 - version drift; use asdf/mise/fvm or match by hand"; fi
}

fl=$(flutter --version 2>/dev/null | sed -n 's/^Flutter \([0-9.]*\).*/\1/p')
py=$( { python --version 2>&1 || python3 --version 2>&1; } | sed -n 's/^Python \([0-9.]*\).*/\1/p')
check_ver "flutter" "$fl" "$pin_flutter"
check_ver "python"  "$py" "$pin_python"

# --- backend/.env ---
if [ -f "$root/backend/.env" ]; then
  pass "backend/.env exists"
else
  bad "backend/.env missing - run: cp backend/.env.example backend/.env"
fi

echo "== $( [ "$fail" -eq 0 ] && echo 'ready' || echo 'blockers above' ) =="
exit "$fail"
