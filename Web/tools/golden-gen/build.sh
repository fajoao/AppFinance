#!/usr/bin/env bash
# Gera Web/test/golden/*.json compilando FinanceApp/Core/*.swift + este gerador com swiftc (precisa de macOS com Swift).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE="$HERE/../../../FinanceApp/Core"
OUT="$(mktemp -d "${TMPDIR:-/tmp}/golden.XXXXXX")"
trap 'rm -rf "$OUT"' EXIT
swiftc -swift-version 5 -O -o "$OUT/golden-gen" "$CORE"/*.swift "$HERE"/*.swift 2>&1 | grep -E "error:" -A3 || true
"$OUT/golden-gen" "$HERE/../../test/golden"
