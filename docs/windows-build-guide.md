# Windows ビルドガイド

KuraudoをWindows向けにビルドする手順。

## 必要な環境

### 必須
- **Windows 10 / 11 (64bit)**
- **Flutter SDK 3.22+** (https://docs.flutter.dev/get-started/install/windows)
- **Visual Studio 2022** with **Desktop development with C++** workload
  - VS Build Toolsのみでは不十分。GUIまたはコマンドライン経由でMSVCが必要
- **Git for Windows**

### 推奨
- **PowerShell 7+** (AutoType機能・クリップボードクリアで使用)

## 環境確認

```powershell
flutter doctor -v
```

以下が `[✓]` であればOK：
- Flutter (Channel stable)
- Windows Version
- Visual Studio - develop Windows apps

## ビルド

### デバッグビルド（開発・動作確認用）

```powershell
cd path\to\kuraudo

# 初回または依存変更時
flutter pub get

# 実行
flutter run -d windows
```

### リリースビルド

```powershell
flutter build windows --release
```

成果物: `build\windows\x64\runner\Release\kuraudo.exe`

実行可能ファイル単体では動かず、同フォルダの `.dll` 群と `data\` フォルダが必要です。配布時はフォルダごと配布するか、MSIXパッケージ化してください。

## Google Drive 同期を有効にする

### Google Cloud Console 側の設定

既存のOAuthクライアントID（Linux/Android用）にWindowsデスクトップ向けの設定を追加する、もしくは別のデスクトップ向けクライアントIDを発行します。

**重要**: Linuxと同じ「デスクトップアプリ」種別のクライアントIDが使えます。Loopbackリダイレクト方式（`http://localhost:43823`）で認証するため、Windows専用の設定追加は不要です。

詳細は `google-drive-oauth-guide.md` 参照。

### ビルド時のクライアントシークレット注入

```powershell
flutter build windows --release `
  --dart-define=GOOGLE_CLIENT_SECRET=<your-client-secret>
```

シークレットは**ソースコードにハードコードしない**でください。CIで使用する場合は環境変数経由で注入してください。

## MSIX パッケージ化（Microsoft Store 提出用）

`pubspec.yaml` に既に `msix: ^3.16.8` が dev依存として入っています。

```powershell
flutter pub run msix:create
```

設定は `pubspec.yaml` の `msix_config:` セクションを編集（必要なら追加）。

## トラブルシューティング

### `Visual Studio toolchain` が見つからない
`flutter doctor` で `[✗] Visual Studio - develop Windows apps` と出る場合：
- Visual Studio Installer から **Desktop development with C++** workload を追加インストール
- 既にインストール済みの場合は **Modify** で workload 確認

### CMake エラー
- Visual Studio 2022 が必須（2019以前は非対応の場合あり）
- `flutter clean` 後にリビルド

### `flutter_secure_storage` の依存エラー（Windows）
`flutter_secure_storage` はWindowsで `Credential Manager` を使用します。`win32` パッケージへの依存があるので、初回 `flutter pub get` 時にビルドツールチェーンが整っていないとエラーが出ることがあります。Visual Studio 2022 の Desktop C++ workload が確実に入っているか再確認してください。

### `webdav_client` のSSL/TLSエラー
Windows のシステム証明書ストアを使うため、信頼済みCAで署名された証明書を使うサーバーであれば問題なく接続できます。**自己署名証明書のWebDAVサーバーへの接続は現状サポートしていません**。

### Google Drive OAuth: ブラウザが開かない
Windows既定ブラウザ設定が壊れている可能性。`url_launcher` がエラーを出す場合は、Edge等を一時的に既定にしてからリトライ。

## デバッグTips

### コンソール出力の確認
リリースビルドではコンソールが出ないため、デバッグメッセージを確認したい場合：

```powershell
flutter run -d windows --release
```

または、フラグなしの `flutter run -d windows` （デバッグ）でログを確認。

### ファイル配置の確認

設定ファイル・バックアップは**Vaultファイルと同じフォルダ**に作られます（v3.0以降）。`%APPDATA%\com.zerotoship.kuraudo\` などには何も書きません。Vaultパス情報のみ Windows Credential Manager に保存されます。

確認コマンド（PowerShell）:
```powershell
# Vault フォルダを確認（仮に Z:\kuraudo\ に作成した場合）
Get-ChildItem Z:\kuraudo\

# Credential Manager を確認
cmdkey /list | Select-String kuraudo
```

## クロスプラットフォームの注意点

- **パス区切り**: コードは `Platform.pathSeparator` を使うので意識不要、ただしユーザーがパスを入力するUIでは `\\` のエスケープに注意
- **AutoType**: PowerShell の `[System.Windows.Forms.SendKeys]::SendWait()` を使用。PowerShell 5.1以降が必要（Windows 10標準で含まれる）
- **クリップボードクリア**: PowerShell `[System.Windows.Forms.Clipboard]::Clear()` を使用

---
*最終更新: 2026年5月10日*
