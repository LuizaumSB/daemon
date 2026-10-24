#!/usr/bin/env bash
# Gera o ícone do app a partir do próprio mascote (CubeMascot.swift), em vetor:
#   Resources/Brand/icon-dark-mode.png e icon-light-mode.png (1024 px)
#   Resources/AppIcon.icns (a versão de fundo escuro; o .icns só guarda uma)
# Rode de novo sempre que mudar o visual do mascote (MascotStyle).
set -euo pipefail

cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Compila um programinha com o desenho do mascote e o que monta o ícone.
mkdir -p "$TMP/src"
cp scripts/icon/main.swift "$TMP/src/main.swift"
swiftc -O -o "$TMP/render" Sources/DaemonUI/CubeMascot.swift "$TMP/src/main.swift"
"$TMP/render" Resources/Brand/icon-dark-mode.png Resources/Brand/icon-light-mode.png

# .icns = vários tamanhos do mesmo desenho (16 a 1024 px).
SET="$TMP/AppIcon.iconset"
mkdir "$SET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/Brand/icon-dark-mode.png --out "$SET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) Resources/Brand/icon-dark-mode.png --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o Resources/AppIcon.icns
echo "Pronto: Resources/AppIcon.icns"
