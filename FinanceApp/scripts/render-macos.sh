#!/usr/bin/env bash
# Renderiza as telas principais em PNG (claro/escuro) com SwiftUI no macOS, sem Xcode: `swiftc` + SDK do macOS +
# `ImageRenderer`. Serve para conferir layout, cores dos tokens e valores extremos antes de abrir o Simulador.
#
# LIMITES (honestidade): não é o iOS (tipografia e controles nativos diferem); ScrollView/List viram pilhas;
# Picker segmentado, Toggle e DatePicker aparecem como "proibido" amarelo; Dynamic Type não é aplicado pelo renderer.
# Uso: FinanceApp/scripts/render-macos.sh [pasta-destino]      (padrão: FinanceApp/build/macos-preview)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$ROOT/build/macos-preview}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/financeapp-render.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
SDK="$(xcrun --sdk macosx --show-sdk-path)"
mkdir -p "$OUT" "$WORK/src"

# Cores: lê os Color Sets gerados (os mesmos valores do Asset Catalog) e cria uma tabela claro/escuro.
python3 - "$ROOT" "$WORK/src/HarnessColors.swift" <<'PY'
import json, pathlib, sys
root, out = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
rows = []
for d in sorted((root / "Assets/Assets.xcassets/Colors").glob("*.colorset")):
    j = json.load(open(d / "Contents.json"))
    def hx(e):
        c = e["color"]["components"]; return c["red"][2:] + c["green"][2:] + c["blue"][2:]
    light = [hx(e) for e in j["colors"] if "appearances" not in e][0]
    dark = [hx(e) for e in j["colors"] if "appearances" in e][0]
    rows.append(f'    "{d.stem}": ("{light}", "{dark}")')
out.write_text("""import SwiftUI
enum Harness {
  nonisolated(unsafe) static var dark = false
  static let table: [String: (String, String)] = [
""" + ",\n".join(rows) + """
  ]
  static func color(_ name: String) -> Color {
    let (l, d) = table[name]!
    let v = UInt32(dark ? d : l, radix: 16)!
    return Color(.sRGB, red: Double((v >> 16) & 255)/255, green: Double((v >> 8) & 255)/255, blue: Double(v & 255)/255)
  }
}
""")
PY

cp "$ROOT/scripts/render-macos/Shims.swift" "$WORK/src/Shims.swift"
cp "$ROOT/scripts/render-macos/main.swift" "$WORK/src/main.swift"

find "$ROOT/Core" "$ROOT/App" -name '*.swift' | sort | while IFS= read -r f; do
  base="$(echo "${f#"$ROOT"/}" | tr '/' '_')"
  case "$f" in
    */FinancasApp.swift) continue ;;
    */Design/Tokens.swift)   # Color("nome") -> tabela em código (Asset Catalog não compila sem actool)
      sed -E 's/static let ([A-Za-z]+) = Color\("([A-Za-z]+)"\)/static var \1: Color { Harness.color("\2") }/; s/Color\(token\)/Harness.color(token)/' "$f" > "$WORK/src/$base" ;;
    */App/*) awk '/^#Preview/ { sub(/^#Preview[^{]*\{/, "@MainActor @ViewBuilder private func __preview" ++n "() -> some View {") } { print }' "$f" > "$WORK/src/$base" ;;
    *) cp "$f" "$WORK/src/$base" ;;
  esac
done

echo "==> Compilando (macOS, Swift 6)"
swiftc -swift-version 6 -D DEBUG -sdk "$SDK" -target "$(uname -m)-apple-macos14.0" -o "$WORK/render" "$WORK"/src/*.swift
echo "==> Renderizando em $OUT"
"$WORK/render" "$OUT"
