# Kuraudo（蔵人）

<p align="center">
  <strong>ローカル・ファースト × Google Drive同期のパスワードマネージャー</strong>
</p>

<p align="center">
  Argon2id + AES-256-GCM | Flutter | Linux · Android（Windows版は保留中）
</p>

---

## 特徴

- **商用レベルの暗号化** — Argon2id (KDF) + AES-256-GCM。データファイルが流出しても、マスターパスワードなしでは解読不可能
- **ローカル・ファースト** — データは常にローカルに保存。オフラインでも完全に動作
- **Google Drive同期** — ユーザー自身のDriveに暗号化ファイルをアップロード。開発者はデータに一切アクセスできない
- **クロスプラットフォーム** — Linux / Android を単一コードベースで対応（Windows版は保留中）
- **オープンソース** — ソースコードを公開。誰でも監査可能

## スクリーンショット

（開発中 — 後日追加予定）

## インストール

### Microsoft Store（Windows）
（保留中 — Windows環境でのビルドが必要です）

### GitHub Releases
[Releases](https://github.com/orgsonai/kuraudo/releases) から各プラットフォーム向けのインストーラーをダウンロード。

### ビルド

```bash
# リポジトリをクローン
git clone https://github.com/orgsonai/kuraudo.git
cd kuraudo

# 依存関係をインストール
flutter pub get

# 実行
flutter run

# リリースビルド
flutter build linux     # Linux
flutter build apk       # Android
# flutter build windows # Windows（保留中 — Windowsホストが必要）
```

#### 前提条件

- Flutter SDK 3.16+
- Dart SDK 3.2+
- （Linux）`clang`, `cmake`, `ninja-build`, `pkg-config`, `libgtk-3-dev`
- （Android）Android Studio + Android SDK
- （Windows — 保留中）Visual Studio 2022 + C++ Desktop workload

#### Google Drive同期を有効にする場合

1. [Google Cloud Console](https://console.cloud.google.com/) でプロジェクトを作成
2. Google Drive API を有効化
3. OAuth 2.0 クライアントIDを作成
4. `google-services.json`（Android）を `android/app/` に配置
5. ビルド時に `--dart-define` でシークレットを注入:

```bash
# デスクトップ（クライアントシークレットが必要）
flutter build linux --dart-define=GOOGLE_CLIENT_SECRET=your_secret
# flutter build windows --dart-define=GOOGLE_CLIENT_SECRET=your_secret  # 保留中

# Android（google-services.jsonを使用するためシークレット不要）
flutter build apk
```

詳細は [google-drive-oauth-guide.md](docs/google-drive-oauth-guide.md) を参照してください。

## セキュリティ

### 暗号化仕様

| 項目 | 仕様 |
|------|------|
| 鍵派生 | Argon2id（デスクトップ: 64MB/3回/4並列, モバイル: 32MB/3回/2並列） |
| 暗号化 | AES-256-GCM（認証付き暗号） |
| ノンス | 暗号化ごとにランダム生成（12バイト）。再利用禁止 |
| ソルト | 32バイト暗号学的乱数 |
| 認証タグ | 16バイト（GCM） |

### .kuraudo ファイルフォーマット

```
Offset  Size   Description
──────────────────────────────────
0x00    4      Magic Number ("KRAD")
0x04    2      Format Version (uint16 LE)
0x06    4      Argon2 Memory (KB, uint32 LE)
0x0A    4      Argon2 Iterations (uint32 LE)
0x0E    4      Argon2 Parallelism (uint32 LE)
0x12    32     Salt
0x32    12     Nonce
0x3E    ...    Encrypted Payload + GCM Tag (16B)
```

### 脆弱性の報告

セキュリティ上の問題を発見した場合は、**公開Issueではなく** [SECURITY.md](SECURITY.md) に記載の方法でご報告ください。

## 機能一覧

- パスワードの生成・保存・管理
- パスワード強度リアルタイム評価
- パスフレーズ生成
- パスワード履歴（世代管理、最大10件）
- アカウント紐付けビュー（同一メール/IDの横断表示）
- TOTP（二段階認証）対応
- Google Drive同期（タイムスタンプベース衝突回避）
- インポート: KeePassXC / Bitwarden (CSV/JSON) / 1Password / Chrome
- エクスポート: KeePass CSV / Bitwarden CSV / JSON
- Android Autofill Service対応（基盤）
- ダーク/ライトテーマ

## プロジェクト構成

```
kuraudo/
├── lib/
│   ├── core/           # 暗号化エンジン, ファイルフォーマット, パスワード/TOTP生成
│   ├── models/         # データモデル (VaultEntry, Vault)
│   ├── services/       # Vault管理, CSV入出力, Google Drive, 同期, Autofill
│   └── ui/             # テーマ, 画面 (8画面), ウィジェット
├── test/               # テスト
├── pubspec.yaml
├── LICENSE             # GPL-3.0
├── SECURITY.md         # 脆弱性報告手順
├── CONTRIBUTING.md     # コントリビューション方針
├── PRIVACY.md          # プライバシーポリシー
└── README.md
```

## ロードマップ

- [x] コアエンジン（暗号化 + ファイルフォーマット + パスワード生成）
- [x] UI/UX + KeePassXCインポート
- [x] Google Drive同期（UUID単位マージ）
- [x] エクスポート拡張（Bitwarden/1Password/Chrome対応）
- [x] TOTP + Autofill基盤（Android）
- [x] PIN/生体認証による簡易ロック解除
- [x] セキュリティ監査・修正
- [ ] Google Play 公開
- [ ] Microsoft Store 公開（保留中）

> 個人プロジェクトのため、上記以降の機能追加・アップデートは予定していません。バグ修正は随時対応します。

## コントリビューション

Issue報告は歓迎します。PRについては [CONTRIBUTING.md](CONTRIBUTING.md) をご覧ください。

## ライセンス

[GPL-3.0](LICENSE) — Copyright (c) 2026 Zero to Ship

## リンク

- [Zero to Ship](https://zero-to-ship-app.vercel.app) — プロジェクトホーム
- [方針設計書](docs/kuraudo-spec-v1.docx) — 詳細な技術仕様
