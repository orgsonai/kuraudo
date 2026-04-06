#!/bin/bash
# Kuraudo セットアップスクリプト
#
# 使い方:
#   1. このzipを解凍
#   2. cd kuraudo_full
#   3. flutter create . --project-name kuraudo --org com.zerotoship
#   4. bash setup.sh
#   5. flutter pub get
#   6. flutter run

set -e

echo "=== Kuraudo セットアップ ==="

# [1/5] Android ファイルを配置確認
KOTLIN_DIR="android/app/src/main/kotlin/com/zerotoship/kuraudo"
if [ -d "android" ]; then
  echo "[1/5] Android ファイルを確認..."
  mkdir -p "$KOTLIN_DIR"
  
  # Kotlin ファイル確認
  if [ -f "$KOTLIN_DIR/MainActivity.kt" ]; then
    echo "  → Kotlin ファイル配置済み"
  else
    echo "  ⚠ $KOTLIN_DIR/MainActivity.kt が見つかりません"
  fi

  # autofill_service.xml 確認
  mkdir -p android/app/src/main/res/xml
  if [ -f "android/app/src/main/res/xml/autofill_service.xml" ]; then
    echo "  → autofill_service.xml 配置済み"
  else
    echo "  ⚠ android/app/src/main/res/xml/autofill_service.xml が見つかりません"
  fi

  # AndroidManifest.xml 確認
  if [ -f "android/app/src/main/AndroidManifest.xml" ]; then
    echo "  → AndroidManifest.xml 配置済み"
  else
    echo "  ⚠ android/app/src/main/AndroidManifest.xml が見つかりません"
  fi

  # settings.gradle.kts を配置（flutter create が生成したものを上書き）
  if [ -f "android/settings_gradle.kts" ]; then
    cp android/settings_gradle.kts android/settings.gradle.kts
    echo "  → settings.gradle.kts 配置完了"
  fi

  echo "  → Android 配置確認完了"
else
  echo "[1/5] android/ ディレクトリがありません（flutter create . を先に実行してください）"
fi

# [2/5] Android build.gradle.kts をリリース署名対応版に上書き
GRADLE_FILE="android/app/build.gradle.kts"
GRADLE_SRC="android_app_build.gradle.kts"
if [ -f "$GRADLE_SRC" ]; then
  echo "[2/5] Android build.gradle.kts をリリース署名対応版に上書き..."
  cp "$GRADLE_SRC" "$GRADLE_FILE"
  echo "  → build.gradle.kts 上書き完了（リリース署名 + minSdk=26）"
elif [ -f "$GRADLE_FILE" ]; then
  echo "[2/5] Android minSdk を 26 に変更..."
  sed -i 's/minSdk = flutter.minSdkVersion/minSdk = 26/' "$GRADLE_FILE"
  echo "  → minSdk = 26 に変更完了（署名設定は手動で追加してください）"
fi

# [3/5] assets ディレクトリを作成（pubspec.yaml で参照）
echo "[3/5] assets ディレクトリ確認..."
mkdir -p assets
if [ -f "assets/icon.png" ]; then
  echo "  → assets/icon.png 存在確認OK"
fi

# [4/5] .gitignore を作成
echo "[4/5] .gitignore を確認..."
if [ ! -f ".gitignore" ]; then
  cat > .gitignore << 'EOF'
.dart_tool/
.packages
build/
*.iml
.idea/
.env
google-services.json
*.jks
*.keystore
key.properties
EOF
  echo "  → .gitignore 作成完了"
fi

# [5/5] Linux CMakeLists.txt の警告抑制
LINUX_CMAKE="linux/CMakeLists.txt"
if [ -f "$LINUX_CMAKE" ]; then
  if ! grep -q "Wno-error=deprecated" "$LINUX_CMAKE"; then
    echo "[5/5] Linux CMakeLists.txt に警告抑制を追加..."
    sed -i '/cmake_minimum_required/a set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wno-error=deprecated-literal-operator")' "$LINUX_CMAKE"
    echo "  → 警告抑制追加完了"
  fi
fi

echo ""
echo "=== セットアップ完了 ==="
echo ""
echo "次のステップ:"
echo "  flutter pub get"
echo "  flutter run                    # デバッグ実行"
echo "  flutter run -d linux           # Linux"
echo ""
echo "Google Drive同期を有効にする場合:"
echo "  flutter run --dart-define=GOOGLE_CLIENT_SECRET=your_secret"
echo ""
echo "リリースビルド（署名設定が必要）:"
echo "  1. keytool -genkey -v -keystore ~/kuraudo-release.keystore -alias kuraudo -keyalg RSA -keysize 2048 -validity 10000"
echo "  2. android/key.properties を作成（storePassword, keyPassword, keyAlias, storeFile を記入）"
echo "  3. flutter build appbundle --release   # Play Store用"
echo "  4. flutter build apk --release         # APK"
echo ""
echo "  ※ key.properties と .keystore は絶対にGitにコミットしないこと！"
echo ""
echo "Linux/Windowsビルド:"
echo "  flutter build linux --release --dart-define=GOOGLE_CLIENT_SECRET=your_secret"
echo "  flutter build windows --release --dart-define=GOOGLE_CLIENT_SECRET=your_secret"
