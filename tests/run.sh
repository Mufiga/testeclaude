#!/usr/bin/env bash
# Roda os testes de lógica fora do Roblox, com um ambiente falso.
#   ./tests/run.sh
# Precisa do binário "luau" no PATH (https://github.com/luau-lang/luau/releases).
set -euo pipefail
cd "$(dirname "$0")/.."
LUAU="${LUAU:-luau}"
python3 tests/build_server.py && "$LUAU" tests/run_tests.luau
python3 tests/build_client.py && "$LUAU" tests/run_client.luau
