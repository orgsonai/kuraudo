#!/bin/bash
# Kuraudo AppImage作成スクリプト
# 
# 前提: flutter build linux --release が完了していること
# 使い方: bash build_appimage.sh

set -e

APP_NAME="Kuraudo"
APP_VERSION="0.1.0"
BUNDLE_DIR="build/linux/x64/release/bundle"

if [ ! -d "$BUNDLE_DIR" ]; then
  echo "エラー: $BUNDLE_DIR が見つかりません"
  echo "先に flutter build linux --release を実行してください"
  exit 1
fi

# appimagetool をダウンロード（未取得の場合）
if [ ! -f appimagetool ]; then
  echo "appimagetool をダウンロード中..."
  wget -q "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage" -O appimagetool
  chmod +x appimagetool
fi

# AppDir を構築
rm -rf AppDir
mkdir -p AppDir/usr/bin
mkdir -p AppDir/usr/share/icons/hicolor/512x512/apps

# バンドルをコピー
cp -r "$BUNDLE_DIR"/* AppDir/usr/bin/

# アイコン
cp assets/icon.png AppDir/usr/share/icons/hicolor/512x512/apps/kuraudo.png
cp assets/icon.png AppDir/kuraudo.png

# .desktop ファイル
cat > AppDir/kuraudo.desktop << EOF
[Desktop Entry]
Type=Application
Name=Kuraudo
Comment=Password Manager with Google Drive Sync
Exec=kuraudo
Icon=kuraudo
Categories=Utility;Security;
Terminal=false
EOF

# AppRun
cat > AppDir/AppRun << 'EOF'
#!/bin/bash
SELF=$(readlink -f "$0")
HERE=${SELF%/*}
export LD_LIBRARY_PATH="${HERE}/usr/bin/lib:${LD_LIBRARY_PATH}"
exec "${HERE}/usr/bin/kuraudo" "$@"
EOF
chmod +x AppDir/AppRun

# AppImage 生成
echo "AppImage を生成中..."
ARCH=x86_64 ./appimagetool AppDir "${APP_NAME}-${APP_VERSION}-x86_64.AppImage"

echo ""
echo "=== 完了 ==="
echo "生成: ${APP_NAME}-${APP_VERSION}-x86_64.AppImage"

# 後片付け
rm -rf AppDir
