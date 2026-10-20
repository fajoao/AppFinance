#!/usr/bin/env bash
# Gera as capturas do critério de aceite visual: 3 iPhones x claro/escuro x Dynamic Type normal/maior x telas principais.
# Requer Xcode + Simulador iOS + projeto gerado (xcodegen). NÃO roda só com Command Line Tools.
#
# Uso: FinanceApp/scripts/capture-screenshots.sh [pasta-destino]      (padrão: Docs/screenshots)
# Variáveis: DEVICES="iPhone 12;iPhone 17 Pro Max"  SCREENS="home plan.bills"  SKIP_BUILD=1  BUNDLE_ID=...  APP_PATH=...  ONLY_NORMAL_TEXT=1
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APPDIR="$ROOT/FinanceApp"
DEST="${1:-$ROOT/Docs/screenshots}"
BUNDLE_ID="${BUNDLE_ID:-com.example.financas}"   # no project-free.yml use BUNDLE_ID=com.fabiojoao.financas
DERIVED="$ROOT/build"
IFS=';' read -r -a DEVICE_LIST <<< "${DEVICES:-iPhone SE (3rd generation);iPhone 16;iPhone 16 Pro Max}"
read -r -a SCREEN_LIST <<< "${SCREENS:-home transactions new plan.budget plan.bills plan.goals wallet.accounts wallet.cards plan.more plan.debts plan.debts.simulator plan.cashflow reports tax wallet.investments wallet.networth family insights scan settings.openfinance}"
if [[ -n "${ONLY_NORMAL_TEXT:-}" ]]; then SIZES=("large"); else SIZES=("large" "accessibility-extra-extra-extra-large"); fi

if [[ -z "${SKIP_BUILD:-}" ]]; then
  echo "==> Compilando para o Simulador"
  xcodebuild -project "$APPDIR/FinanceApp.xcodeproj" -scheme FinanceApp \
    -destination "generic/platform=iOS Simulator" -derivedDataPath "$DERIVED" -quiet build
fi
APP="${APP_PATH:-$DERIVED/Build/Products/Debug-iphonesimulator/FinanceApp.app}"
[[ -d "$APP" ]] || { echo "App não encontrado em $APP" >&2; exit 1; }

for device in "${DEVICE_LIST[@]}"; do
  udid="$(xcrun simctl list devices available | grep -F "    $device (" | head -1 | grep -oE '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}' || true)"
  if [[ -z "$udid" ]]; then echo "!! Simulador '$device' não encontrado; pulando." >&2; continue; fi
  slug="$(echo "$device" | tr ' ()' '___' | tr -s '_')"
  echo "==> $device ($udid)"
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl status_bar "$udid" override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 || true
  xcrun simctl install "$udid" "$APP"
  for appearance in light dark; do
    xcrun simctl ui "$udid" appearance "$appearance"
    for size in "${SIZES[@]}"; do
      xcrun simctl ui "$udid" content_size "$size"
      label="$([[ "$size" == large ]] && echo normal || echo texto-grande)"
      out="$DEST/$slug/$appearance-$label"
      mkdir -p "$out"
      for screen in "${SCREEN_LIST[@]}"; do
        xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true
        seed="-seedDemo"; [[ "$screen" == family ]] && seed="-seedFamily"   # só a tela de família precisa do grupo familiar
        xcrun simctl launch "$udid" "$BUNDLE_ID" -uiTesting "$seed" -fixedToday 2026-10-19 -mockOpenFinance \
          -appearance "$appearance" -startScreen "$screen" >/dev/null
        sleep 2
        xcrun simctl io "$udid" screenshot "$out/$screen.png" >/dev/null
        echo "    $slug/$appearance-$label/$screen.png"
      done
    done
  done
  xcrun simctl ui "$udid" content_size large
  xcrun simctl status_bar "$udid" clear || true
done
echo "==> Capturas em $DEST"
