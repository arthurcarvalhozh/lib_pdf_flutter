#!/usr/bin/env bash
# Mede a geração do relatório de exemplo num aparelho Android conectado por
# adb: lib_pdf contra o método atual (foto do gráfico + package:pdf).
#
# Instala o app de exemplo (id próprio, não mexe nos apps de produção), roda
# a medida, guarda o resultado em benchmark/results/ e desinstala o app.
#
# Uso: benchmark/run_android.sh [serial-do-aparelho]
set -euo pipefail

APP=br.com.libpdf.lib_pdf_example
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FLUTTER=(fvm flutter)
command -v fvm >/dev/null || FLUTTER=(flutter)
if [[ $# -ge 1 ]]; then export ANDROID_SERIAL="$1"; fi

cd "$ROOT/example"
"${FLUTTER[@]}" build apk --profile --dart-define=BENCH=true

trap 'adb uninstall "$APP" >/dev/null 2>&1 || true' EXIT
adb install -r build/app/outputs/flutter-apk/app-profile.apk >/dev/null
adb logcat -c
adb shell am start -n "$APP/.MainActivity" >/dev/null

for _ in $(seq 1 90); do
  adb logcat -d | grep -q 'BENCH FIM' && break
  sleep 2
done

mkdir -p "$ROOT/benchmark/results"
model="$(adb shell getprop ro.product.model | tr -d '\r ')"
out="$ROOT/benchmark/results/$(date +%Y-%m-%d_%H%M)_${model}.txt"
{
  echo "aparelho: $model"
  echo "commit: $(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo 'sem commit')"
  adb logcat -d | grep 'BENCH ' | sed 's/.*BENCH //'
} | tee "$out"

grep -q '^FIM$' "$out" || { echo 'A medida não terminou em 3 minutos.' >&2; exit 1; }
