#!/usr/bin/env bash
# Verificação de TIPOS do app (Core + App) com swiftc e o SDK do macOS. Não há SDK do iOS nas Command Line Tools.
#
# O QUE ISTO PROVA: a sintaxe e os tipos de SwiftUI/Charts/Observation/LocalAuthentication/UserNotifications
#   estão coerentes com o SDK do macOS (14+), em Swift 6 com -warnings-as-errors.
# Também verifica a extensão de widgets (Widgets/ + Core) e os App Intents (App/Services/QuickAddIntent.swift).
# O QUE NÃO PROVA: que compila, linka ou roda no iOS. Código dentro de `#if os(iOS)` (UIKit, keyboardType,
#   navigationBarTitleDisplayMode...) NÃO é verificado aqui. Use xcodebuild/Xcode para isso.
#
# Como as Command Line Tools não trazem o plugin de macros do SwiftUI, cada `#Preview { ... }` é convertido,
# numa cópia temporária, em uma função `@ViewBuilder` com o mesmo corpo (assim o corpo da prévia continua sendo
# verificado). Convenção: `#Preview(...) {` começa na coluna 0 e termina com `}` na coluna 0.
#
# Uso: FinanceApp/scripts/typecheck-app.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$(mktemp -d "${TMPDIR:-/tmp}/financeapp-typecheck.XXXXXX")"
trap 'rm -rf "$OUT"' EXIT

SDK="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
ARCH="$(uname -m)"
TARGET="${ARCH}-apple-macos14.0"
LANG_MODE="${SWIFT_LANGUAGE_MODE:-6}"

mkdir -p "$OUT/src"
count=0
while IFS= read -r f; do
  rel="${f#"$ROOT"/}"
  dest="$OUT/src/${rel//\//__}"
  case "$f" in
    "$ROOT"/App/*)
      awk '/^#Preview/ { sub(/^#Preview[^{]*\{/, "@MainActor @ViewBuilder private func __preview" ++n "() -> some View {") } { print }' "$f" > "$dest" ;;
    *) cp "$f" "$dest" ;;
  esac
  count=$((count + 1))
done < <(find "$ROOT/Core" "$ROOT/App" -name '*.swift' | sort)

echo "==> swiftc -typecheck: $count arquivos, alvo $TARGET, Swift language mode $LANG_MODE"
echo "    SDK: $SDK"
swiftc -typecheck -parse-as-library -D DEBUG -swift-version "$LANG_MODE" -warnings-as-errors \
  -sdk "$SDK" -target "$TARGET" "$OUT"/src/*.swift
# Extensão de widgets (WidgetKit): Core + Widgets/ num módulo à parte (como o alvo FinanceWidgets).
if [ -d "$ROOT/Widgets" ]; then
  mkdir -p "$OUT/widgets"
  cp "$ROOT"/Core/*.swift "$ROOT"/Widgets/*.swift "$OUT/widgets/"
  echo "==> swiftc -typecheck (extensão de widgets): $(ls "$OUT/widgets" | wc -l | tr -d ' ') arquivos"
  swiftc -typecheck -parse-as-library -D DEBUG -swift-version "$LANG_MODE" -warnings-as-errors \
    -sdk "$SDK" -target "$TARGET" "$OUT"/widgets/*.swift
fi
# Apple Watch (app + complicação) contra o SDK watchOS Simulator, se existir (Xcode com o SDK do watchOS; o runtime não é necessário).
if [ -d "$ROOT/Watch" ] && WSDK="$(xcrun --sdk watchsimulator --show-sdk-path 2>/dev/null)" && [ -d "$WSDK" ]; then
  for part in App Complication; do
    echo "==> swiftc -typecheck (watchOS Simulator, Watch/$part + Core)"
    swiftc -typecheck -parse-as-library -swift-version "$LANG_MODE" -warnings-as-errors \
      -sdk "$WSDK" -target "arm64-apple-watchos10.0-simulator" "$ROOT"/Core/*.swift "$ROOT/Watch/$part"/*.swift
  done
else
  echo "==> (pulado) SDK do watchOS Simulator não encontrado: o alvo do relógio não foi verificado"
fi
echo "==> OK: tipos coerentes com o SDK do macOS. (Isto NÃO prova que compila ou roda no iOS.)"
