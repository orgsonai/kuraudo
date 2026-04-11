# Kuraudo — Store公開メタデータ

## Microsoft Store（保留中 — Windowsビルド環境が必要）

### アプリ情報
- **表示名**: Kuraudo — パスワードマネージャー
- **カテゴリ**: セキュリティ
- **価格**: 無料
- **対象年齢**: 全年齢

### 説明文（日本語）
```
Kuraudo（蔵人）は、商用レベルの暗号化を備えたオープンソースのパスワードマネージャーです。

■ 特徴
• Argon2id + AES-256-GCM による強力な暗号化
• Google Drive同期 — あなた自身のDriveに暗号化ファイルを保存
• ローカル・ファースト — オフラインでも完全に動作
• クロスプラットフォーム — Linux / Android（Windows版は保留中）
• オープンソース — ソースコードを公開、誰でも監査可能

■ 機能
• パスワード・パスフレーズ生成（強度評価付き）
• パスワード履歴管理（最大10世代）
• アカウント紐付けビュー（同一ID/メールの横断表示）
• TOTP（二段階認証）対応
• KeePassXC / Bitwarden / 1Password / Chrome からのインポート
• KeePass CSV / Bitwarden CSV / JSON エクスポート

■ セキュリティ
• ゼロ知識設計 — 開発者を含む第三者がデータを読むことは不可能
• 暗号化はすべてローカルで実行
• クリップボード自動クリア（30秒）
• マスターパスワードなしではファイルを解読不可能

■ オープンソース
ソースコードはGitHubで公開しています。
https://github.com/orgsonai/kuraudo
```

### 説明文（英語）
```
Kuraudo is an open-source password manager with commercial-grade encryption.

Features:
• Argon2id + AES-256-GCM encryption
• Google Drive sync — your data stays in YOUR Drive
• Local-first — works fully offline
• Cross-platform — Linux / Android (Windows on hold)
• Open source — audit the code yourself

• Password & passphrase generator with strength meter
• Password history (up to 10 generations)
• Account linking view (cross-reference by email/username)
• TOTP (2FA) support
• Import from KeePassXC / Bitwarden / 1Password / Chrome
• Export to KeePass CSV / Bitwarden CSV / JSON

Security:
• Zero-knowledge design
• All encryption happens locally
• Auto-clear clipboard (30 seconds)
• Impossible to decrypt without master password

Open Source: https://github.com/orgsonai/kuraudo
```

### スクリーンショット要件
- **最低1枚**: 1366x768以上
- 推奨: 4〜5枚（ロック画面、エントリ一覧、詳細画面、パスワード生成器、設定画面）

### プライバシーポリシーURL
`https://github.com/orgsonai/kuraudo/blob/main/PRIVACY.md`

### 利用規約URL
`https://github.com/orgsonai/kuraudo/blob/main/TERMS.md`

---

## Google Play（公開済み）

### アプリ情報
- **パッケージ名**: com.zerotoship.kuraudo
- **ステータス**: クローズドテスト公開中（2026年4月10日〜）
- **カテゴリ**: ツール
- **価格**: 無料
- **コンテンツレーティング**: 13歳以上対象
- **バージョン**: 0.1.0

### Play App Signing
- **Play管理SHA-1**: `6283e5f1d36b37f3dd07b585ceba9366d5bb4554`
- **自分のkeystore SHA-1**: `D6:DF:D7:EC:2B:D7:02:F2:AD:5B:03:CD:B1:1B:92:DF:49:3C:4E:70`
- Google Cloud ConsoleのAndroid OAuthクライアントIDに両方登録済み

### Data Safety（データセーフティ）申告
- **データ収集**: なし
- **データ共有**: なし
- **暗号化**: はい（AES-256-GCM）
- **データ削除**: ユーザーがアプリを削除するとすべてのローカルデータが削除される
- **Google Drive**: ユーザーが明示的に有効化した場合のみ、ユーザー自身のDriveに暗号化データを保存

### 登録料
- $25（一回きり・支払済み）

---

## Linux (Snap Store / Flathub)

### Snap Store
- **名前**: kuraudo
- **概要**: Open-source password manager with Google Drive sync
- **ライセンス**: GPL-3.0
- **confinement**: strict

### AppImage
- **ファイル名**: Kuraudo-0.1.0-x86_64.AppImage
- **.desktop ファイル**:
```ini
[Desktop Entry]
Type=Application
Name=Kuraudo
Comment=Password Manager with Google Drive Sync
Exec=kuraudo
Icon=kuraudo
Categories=Utility;Security;
```

---

## ビルドコマンドまとめ

```bash
# Windows MSIX（保留中 — Windowsホストが必要）
# flutter build windows --release
# flutter pub run msix:create --store

# Linux
flutter build linux --release

# Android APK
flutter build apk --release

# Android App Bundle（Play Store用）
flutter build appbundle --release
```
