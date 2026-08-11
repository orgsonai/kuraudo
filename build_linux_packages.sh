#!/usr/bin/env bash
# Kuraudo Linuxパッケージ作成スクリプト
#
# 使い方:
#   flutter build linux --release
#   ./build_linux_packages.sh all       # deb/rpm/archを作成
#   ./build_linux_packages.sh deb       # Debian/Ubuntu用のみ
#   ./build_linux_packages.sh rpm arch  # Fedora/RHEL系とArch系

set -euo pipefail

readonly PACKAGE_NAME="kuraudo"
readonly VERSION="$(sed -n "s/^version: *['\"]\{0,1\}\([^+'\"]*\).*/\1/p" pubspec.yaml | head -n 1)"
readonly OUTPUT_DIR="$(pwd)/dist"

case "$(uname -m)" in
  x86_64|amd64)
    readonly FLUTTER_ARCH="x64" DEB_ARCH="amd64" RPM_ARCH="x86_64" ARCH_ARCH="x86_64"
    ;;
  aarch64|arm64)
    readonly FLUTTER_ARCH="arm64" DEB_ARCH="arm64" RPM_ARCH="aarch64" ARCH_ARCH="aarch64"
    ;;
  *)
    echo "エラー: 未対応のCPUアーキテクチャです: $(uname -m)" >&2
    exit 1
    ;;
esac

readonly BUNDLE_DIR="$(pwd)/build/linux/${FLUTTER_ARCH}/release/bundle"

if [[ -z "$VERSION" ]]; then
  echo "エラー: pubspec.yamlからバージョンを取得できません" >&2
  exit 1
fi
if [[ ! -d "$BUNDLE_DIR" ]]; then
  echo "エラー: $BUNDLE_DIR が見つかりません" >&2
  echo "先に flutter build linux --release を実行してください" >&2
  exit 1
fi

readonly BUNDLE_VERSION_FILE="$BUNDLE_DIR/data/flutter_assets/version.json"
if [[ ! -f "$BUNDLE_VERSION_FILE" ]]; then
  echo "エラー: ビルド済みバージョンを確認できません" >&2
  echo "flutter build linux --release を再実行してください" >&2
  exit 1
fi
readonly BUNDLE_VERSION="$(sed -n 's/.*"version":"\([^"]*\)".*/\1/p' "$BUNDLE_VERSION_FILE")"
if [[ "$BUNDLE_VERSION" != "$VERSION" ]]; then
  echo "エラー: ビルド済みアプリのバージョンが古いです" >&2
  echo "  pubspec.yaml: $VERSION" >&2
  echo "  Linuxバンドル: $BUNDLE_VERSION" >&2
  echo "flutter build linux --release を再実行してください" >&2
  exit 1
fi

make_payload() {
  local root="$1"
  install -d "$root/opt/kuraudo" "$root/usr/bin" \
    "$root/usr/share/applications" "$root/usr/share/icons/hicolor/512x512/apps"
  cp -a "$BUNDLE_DIR/." "$root/opt/kuraudo/"
  ln -s /opt/kuraudo/kuraudo "$root/usr/bin/kuraudo"
  install -m 644 assets/icon.png \
    "$root/usr/share/icons/hicolor/512x512/apps/kuraudo.png"
  install -m 644 packaging/linux/kuraudo.desktop \
    "$root/usr/share/applications/kuraudo.desktop"
}

build_deb() {
  command -v dpkg-deb >/dev/null || {
    echo "エラー: .deb作成には dpkg-deb が必要です" >&2; return 1;
  }
  local work
  work="$(mktemp -d)"
  trap 'rm -rf "$work"' RETURN
  make_payload "$work/root"
  install -d "$work/root/DEBIAN"
  sed -e "s/@VERSION@/$VERSION/g" -e "s/@ARCH@/$DEB_ARCH/g" \
    packaging/linux/debian-control > "$work/root/DEBIAN/control"
  dpkg-deb --root-owner-group --build "$work/root" \
    "$OUTPUT_DIR/${PACKAGE_NAME}_${VERSION}_${DEB_ARCH}.deb"
}

build_rpm() {
  command -v rpmbuild >/dev/null || {
    echo "エラー: .rpm作成には rpmbuild が必要です" >&2; return 1;
  }
  local work payload
  work="$(mktemp -d)"
  trap 'rm -rf "$work"' RETURN
  install -d "$work"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
  payload="$work/SOURCES/kuraudo-$VERSION"
  make_payload "$payload"
  tar -C "$work/SOURCES" -czf "$work/SOURCES/kuraudo-$VERSION.tar.gz" "kuraudo-$VERSION"
  sed -e "s/@VERSION@/$VERSION/g" packaging/linux/kuraudo.spec > "$work/SPECS/kuraudo.spec"
  rpmbuild --define "_topdir $work" --target "$RPM_ARCH" -bb "$work/SPECS/kuraudo.spec"
  cp "$work/RPMS/$RPM_ARCH/"*.rpm "$OUTPUT_DIR/"
}

build_arch() {
  command -v makepkg >/dev/null || {
    echo "エラー: Archパッケージ作成には makepkg が必要です" >&2; return 1;
  }
  local work payload
  work="$(mktemp -d)"
  trap 'rm -rf "$work"' RETURN
  payload="$work/kuraudo-$VERSION"
  make_payload "$payload"
  tar -C "$work" -czf "$work/kuraudo-$VERSION.tar.gz" "kuraudo-$VERSION"
  cp packaging/linux/PKGBUILD "$work/PKGBUILD"
  sed -i "s/@VERSION@/$VERSION/g; s/@ARCH@/$ARCH_ARCH/g" "$work/PKGBUILD"
  (cd "$work" && makepkg --force --noconfirm)
  cp "$work/"*.pkg.tar.* "$OUTPUT_DIR/"
}

mkdir -p "$OUTPUT_DIR"
targets=("${@:-all}")
if [[ " ${targets[*]} " == *" all "* ]]; then
  targets=(deb rpm arch)
fi
for target in "${targets[@]}"; do
  case "$target" in
    deb) build_deb ;;
    rpm) build_rpm ;;
    arch) build_arch ;;
    *) echo "エラー: 未知の形式 '$target' (deb, rpm, arch, all)" >&2; exit 2 ;;
  esac
done

echo "完了: $OUTPUT_DIR"
