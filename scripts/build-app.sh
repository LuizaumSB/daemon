#!/usr/bin/env bash
# Compila o Daemon e monta build/Daemon.app.
# Um .app é só uma pasta com estrutura fixa:
#   Daemon.app/Contents/Info.plist      ficha do app (nome, id, sem ícone no Dock)
#   Daemon.app/Contents/MacOS/Daemon    o executável
#   Daemon.app/Contents/Resources/      ícone e outros arquivos
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${1:-release}"

swift build -c "$CONFIG" --arch arm64
BIN="$(swift build -c "$CONFIG" --arch arm64 --show-bin-path)/Daemon"

APP="build/Daemon.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Daemon"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

# Assinatura. O macOS guarda as permissões (ex.: acesso a Documentos) atreladas à
# assinatura do app. A ad-hoc ("-") muda a cada build, então ele esquece e pergunta de
# novo. Com um certificado local fixo, a assinatura é sempre a mesma e ele lembra.
# Como criar o certificado: Acesso às Chaves ▸ Assistente de Certificado ▸ Criar um
# Certificado… ▸ nome "Daemon Local Signing", Raiz Autoassinada, Assinatura de Código.
IDENTITY="Daemon Local Signing"
if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
  codesign --force --sign "$IDENTITY" "$APP"
else
  echo "Aviso: certificado \"$IDENTITY\" não encontrado; assinando ad-hoc (o macOS vai pedir permissões de novo a cada build)."
  codesign --force --sign - "$APP"
fi

echo "Pronto: $APP  (abra com: open $APP)"
