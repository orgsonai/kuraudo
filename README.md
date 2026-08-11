# Kuraudo（蔵人）

ローカル・ファーストで使える、Argon2id + AES-256-GCM対応のパスワードマネージャーです。Google Drive、WebDAV、ローカルパスによる任意の同期に対応しています。

対応プラットフォームは Linux、Android、Windows です。機能や暗号化仕様の詳細は [プロジェクト詳細](docs/README.md) を参照してください。

## Linuxへのインストール

### GitHub Releasesからインストール

[GitHub Releases](https://github.com/orgsonai/kuraudo/releases) に対応形式が公開されている場合は、使用しているディストリビューション向けのファイルをダウンロードします。

Debian / Ubuntu:

```bash
sudo apt install ./kuraudo_<version>_amd64.deb
```

Fedora / RHEL系:

```bash
sudo dnf install ./kuraudo-<version>.x86_64.rpm
```

Arch Linux:

```bash
sudo pacman -U ./kuraudo-<version>-1-x86_64.pkg.tar.zst
```

AppImageはインストール不要です。

```bash
chmod +x Kuraudo-<version>-x86_64.AppImage
./Kuraudo-<version>-x86_64.AppImage
```

### ソースからLinuxパッケージを作成

共通の前提条件:

- Flutter SDK 3.16以上
- `clang`、`cmake`、`ninja`、`pkg-config`、GTK 3開発ファイル
- 作成形式に応じて `dpkg-deb`、`rpmbuild`、または `makepkg`

```bash
git clone https://github.com/orgsonai/kuraudo.git
cd kuraudo
flutter pub get
flutter build linux --release
```

必要な形式だけを作成します。生成物は `dist/` に保存されます。

```bash
./build_linux_packages.sh deb   # Debian / Ubuntu
./build_linux_packages.sh rpm   # Fedora / RHEL系
./build_linux_packages.sh arch  # Arch Linux
./build_linux_packages.sh all   # 3形式すべて
```

AppImageを作成する場合:

```bash
./build_appimage.sh
```

`pubspec.yaml` のバージョンとLinuxビルド成果物のバージョンが異なる場合、パッケージ作成は停止します。バージョン変更後は必ず `flutter build linux --release` を再実行してください。

### 起動・更新・削除

パッケージ版はアプリメニューまたは次のコマンドで起動できます。

```bash
kuraudo
```

更新時は新しいパッケージに対して、インストール時と同じ `apt install`、`dnf install`、または `pacman -U` を実行します。

削除方法:

```bash
sudo apt remove kuraudo      # Debian / Ubuntu
sudo dnf remove kuraudo      # Fedora / RHEL系
sudo pacman -R kuraudo       # Arch Linux
```

## Android / Windows

Android APKの作成:

```bash
flutter build apk --release
```

WindowsのビルドにはWindowsホストとVisual Studio 2022のC++ Desktop workloadが必要です。

```powershell
flutter build windows --release
dart run msix:create
```

詳細は [Windowsビルドガイド](docs/windows-build-guide.md) と [Androidビルドガイド](docs/android-build-guide.md) を参照してください。

## ライセンス

[GPL-3.0](LICENSE)
