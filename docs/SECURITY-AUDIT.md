# Kuraudo セキュリティ監査レポート

**最終更新**: 2026年5月19日（v3.4 MEDIUM全件対応完了版）
**対象**: Kuraudo 全ソースコード
**監査範囲**: 暗号化実装、鍵管理、データ保護、認証、通信、情報漏洩、同期バックエンド

---

## 開発方針

Kuraudo は個人が開発・維持するオープンソースの無料アプリです。セキュリティ修正は対応しますが、定期的なアップデートは保証しません。気になる点は自分でビルドして使用することを推奨します（GPL-3.0）。

---

## 総合評価

暗号化の基本設計（Argon2id + AES-256-GCM）は堅実で、業界標準に準拠しています。ファイルフォーマットの設計も適切です。

2026年5月18日の外部静的解析レポートで指摘された **HIGH 3件と MEDIUM 4件はすべて対応完了**（v3.1〜v3.4）。LOW 3件は実害が限定的なため見送り。

---

## ✅ 修正済み（v3.1 — 2026年5月19日）

### H-01. マスターパスワード変更時に現在パスワードの確認なし ✅

**ファイル**: `settings_screen.dart` `_ChangePasswordDialog` / `vault_service.dart` `verifyMasterPassword()`
**問題**: パスワード変更ダイアログが新パスワードと確認用の2フィールドのみで、現在のマスターパスワードを要求していなかった。アンロック状態で画面を放置した場合、第三者がVaultのマスターパスワードを書き換えられる可能性があった。
**対応**:
- `VaultService.verifyMasterPassword(String)` を新設。アンロック中にメモリ保持している `_masterPassword` と比較する高速検証（Argon2id 再実行なし）
- `_ChangePasswordDialog` に「現在のパスワード」フィールドを追加し、submit時に `verifyMasterPassword()` で検証
- 新パスワードが現パスワードと同一の場合も拒否

### H-02. PINロックアウトの永続化（任意適用） ✅

**ファイル**: `lock_screen.dart` `_verifyPin()` / `settings_screen.dart` PINセクション / `main.dart`
**問題**: `_pinFailCount` がウィジェットの State フィールドとして保持されており、アプリ再起動で試行回数がリセットされていた。4桁PINは10,000通りしかないため、再起動を繰り返す総当たりが理論上可能だった。
**対応（ユーザー任意適用）**:
- 設定画面 → 簡易ロック解除セクションに「PINロックアウトを永続化」スイッチを追加
- **OFF（既定）**: 従来通り。5回失敗するとマスターパスワード入力に切替、再起動でカウンタリセット
- **ON**: 失敗回数と「ロック解除予定時刻」を `FlutterSecureStorage` に永続化。5回失敗ごとに段階的バックオフ（5分→10分→30分→60分）。再起動越しに保持される
- マスターパスワードでのアンロック成功時にカウンタ自動クリア
- 緊急脱出用に「失敗カウンタをリセット」ボタンを設定画面に提供（永続化ON時のみ表示）

**設計判断**: 端末紛失時の保護を強化するか、操作性を優先するかはユーザーの脅威モデル次第のため、任意適用とした。

### H-03. WebDAV が HTTP（非暗号化）接続を無警告で許可 ✅

**ファイル**: `webdav_backend.dart` `configure()` / `sync_screen.dart` `_showWebDAVConfigDialog()`
**問題**: WebDAV 設定画面が `http://` スキームを無警告で受け入れていた。同一ネットワーク上の攻撃者によって、Basic 認証のヘッダー（ユーザー名・パスワード）が MITM 傍受される可能性があった。Vault本体は AES-256-GCM 暗号化されるが、認証情報そのものは保護されない。
**対応**:
- `WebDAVHttpNotAllowedException` 例外クラスを新設
- `configure()` で URL スキーマを検証。`http://` の場合は既定で例外を投げる
- `configure(..., allowInsecureHttp: true)` でオプトイン可能
- UI 側（sync_screen.dart）で例外をキャッチし、リスクを明示した警告ダイアログを表示。ユーザーが「リスクを承知で続行」を選択した場合のみ HTTP 接続を許可
- 不正な URL スキーマ（`ftp://` 等）も `ArgumentError` で弾く

---

## ✅ 修正済み（v3.2 — 2026年5月19日）

### M-02. AutoType（xdotool）パスワードを stdin 化 ✅

**ファイル**: `autofill_service.dart` `_autoTypeLinux()` / `_xdotoolTypeViaStdin()`
**問題**: Linux AutoType でパスワードを `xdotool` のコマンドライン引数として渡していた。`/proc/[pid]/cmdline` や `ps aux` から、同一 UID の別プロセスが短時間ながらパスワードを参照可能だった。
**対応**:
- `Process.start('xdotool', [..., '--file', '-'])` で起動し、stdin から入力テキストを書き込む方式に変更
- 専用ヘルパー `_xdotoolTypeViaStdin()` を新設、例外時にも stdin が確実に閉じられるよう保護
- xdotool 3.20160805 以降の `--file` オプションを利用（Arch Linux / Ubuntu 20.04 以降は標準対応）
- ユーザー影響: なし。挙動は表面上同じ

### M-03. デスクトップ OAuth に state パラメータ追加（CSRF 防止） ✅

**ファイル**: `google_drive_service.dart` `_signInDesktop()`
**問題**: デスクトップ用 OAuth で `state` パラメータが欠如。ローカルポート 43823 が開いている間、悪意あるページが偽の認証コードを送り込めるリスクがあった。
**対応**:
- `Random.secure()` で 128bit のランダム nonce を生成
- `base64Url` でエンコードして認証URLに `state=...` として付与
- リダイレクト時に `request.uri.queryParameters['state']` を検証
- 不一致または欠落時はトークン交換に進まず、ブラウザに HTTP 400 + エラー画面（赤色）を返す
- ユーザー影響: なし。Google ログインのフローは見た目同じ

---

## ✅ 修正済み（v3.3 — 2026年5月19日）

### M-01. セキュリティ重要設定の SecureStorage 移行（ハイブリッド方式） ✅

**ファイル**: `main.dart` `_loadSettings()` / `_loadSecuritySettings()` / `_migrateSecuritySettings()` / `_saveSecuritySetting()`
**問題**: `kuraudo_settings.json` に `autoLockMinutes` `pinEnabled` `biometricEnabled` 等のセキュリティ重要設定が平文 JSON で保存されていた。ファイルシステムにアクセスできる攻撃者が `autoLockMinutes: 0` 等に書き換えることでロック機能を無効化できる懸念があった。
**対応**:
- セキュリティ重要項目（autoLockMinutes / clipboardAutoClear / pinEnabled / biometricEnabled / pinThresholdMinutes / pinLockoutPersistent）を `FlutterSecureStorage` に移行
- 非セキュリティ項目（themeMode / passwordExpiryDays / autoSync* / syncBackend）は引き続き平文 JSON
- 初回起動時の自動マイグレーション機構（`kuraudo_sec_migration_v1_done` フラグで制御）
- マイグレーション時に旧 JSON ファイルからセキュリティ項目を削除（改ざんの誘因を残さない）
- SecureStorage 読み込み失敗時は安全側の既定値にフォールバック
- **挙動変化**: 設定スコープが「Vaultフォルダ単位」から「端末単位」に変更（業界標準に準拠）
- **追記（2026-09-10）**: OS のキーリングが使えない環境（Linux で Secret Service が無い・開けない等）では SecureStorage の読み書きが失敗し、Vault パスと設定が起動のたびに失われていた。Vault パスはアプリ設定ファイル（`kuraudo_app_config.json`）へ移動。セキュリティ設定は、設定画面の確認ダイアログでユーザーが同意した場合に限り autoLockMinutes / clipboardAutoClear のみ同ファイルに保存する（その環境では改ざん耐性が下がる）。キーリングが使える環境では従来どおりキーリングのみを読み、ファイルの値は使わない。PIN・生体認証はキーリング必須のため、その環境では無効化

---

## ✅ 修正済み（v3.4 — 2026年5月19日）

### M-04. Android Autofill キャッシュからパスワード保護（A2方式） ✅

**ファイル**: `vault_service.dart` / `autofill_service.dart` / `main.dart` / `MainActivity.kt` / `KuraudoAutofillService.kt`
**問題**: Vault 解錠時に `updateNativeCache()` で全エントリ（パスワード平文含む）を Kotlin 側に送り、`KuraudoAutofillService.cachedEntries` で companion object として保持していた。Vault ロック中もパスワード平文が Android プロセスメモリに常駐し、メモリダンプ攻撃や root 化端末からの参照リスクがあった。
**対応**: A2 方式（Vault ロック時に確実にキャッシュをクリア）
- `VaultService` に `onLocked` コールバックを追加。`lock()` 内で呼び出し
- `AutofillService.clearNativeCache()` を新設、Android のみで `MethodChannel('clearAutofillCache')` を発火
- Kotlin 側に `clearAutofillCache` ハンドラと `clearCachedEntries()` を追加、`cachedEntries = emptyList()` で空に
- アプリ完全終了 (`detached` ライフサイクル) でも念のためクリア
- ロック中は `cachedEntries.isEmpty()` のため `onFillRequest` で候補が生成されない
- **ユーザー影響**: Vault ロック中は autofill 候補が表示されなくなる（解錠後は従来通り）
- **残存リスク**: 解錠中のメモリ常駐は Dart 側 `_masterPassword` と同水準（言語仕様上の既知制約）

---

## 🟡 残存項目（見送り）

2026年5月18日の外部静的解析で指摘された LOW 項目は実害が限定的なため、今回のスコープ外:

### L-01. マスターパスワード最低長12文字化
パスワードマネージャー業界標準は12〜16文字。Kuraudo は現状 8文字最低。Argon2id のコストが高いため実用上のブルートフォース耐性は十分だが、ベストプラクティス的には12文字以上推奨。新規 Vault 作成時のみ警告を出す形での将来対応を検討。

### L-02. デスクトップ OAuth の PKCE 化
RFC 8252 に準拠した PKCE への移行で client_secret 不要になる。Google 自身が「デスクトップアプリのシークレットは public」と認めており実害は限定的。

### L-03. クリップボード Timer のキャンセル機構
`Timer?` でキャンセル可能化することで、複数コピー時の競合状態を解消できる。実害は軽微。

---

## 🟡 既知の制限事項（Dart/Flutter言語の制約）

### マスターパスワードがメモリに平文保持

**ファイル**: `vault_service.dart`
**内容**: `_masterPassword` が String 型で保持される
**理由**: Dart の文字列はイミュータブルでGCに依存するため、明示的なゼロ化が言語仕様上不可能
**現状対応**: `lock()` 時に `_masterPassword = null` で参照を切っている（これが Dart で取れる最善策）
**補足**: 端末がroot化されていなければ実用上のリスクは限定的

---

## ✅ 修正済み（過去のバージョン）

### Argon2idパラメータ強化 ✅
デスクトップ: 64MB/3回/4並列、モバイル: 32MB/3回/2並列（OWASP推奨水準）。ヘッダーにKDFパラメータを保存し後方互換確保。

### パスワード強度評価の強化 ✅
辞書攻撃耐性を追加。よく使われるパスワード（トップ50）、キーボードパターン、辞書単語、リート表記を検出。

### PIN認証の試行回数制限 ✅
5回失敗でPIN入力を無効化（H-02 で永続化版も追加）。

### エクスポート時のセキュリティ強化 ✅
エクスポート前にマスターパスワード再確認を要求。クリップボード経由時は30秒後に自動クリア。

### OAuthクライアントシークレットのハードコード回避 ✅
`--dart-define=GOOGLE_CLIENT_SECRET=xxx` でビルド時注入。

### OAuthトークンの暗号化保存 ✅
`flutter_secure_storage` による保存。

### 派生鍵の完全メモリクリア ✅
`passwordBytes.fillRange(0, length, 0)` を実装。

### クリップボードクリアのタイミング ✅
Android 9+ で `clearPrimaryClip()` による履歴ごと完全削除。バックグラウンド移行時・アプリ終了時に即座クリア。

### Linux クリップボード対応 ✅
wl-copy / xclip / xsel を自動検出してクリア。Wayland/X11 両対応。

---

## 🟢 許容済みの軽微な項目

### 非セキュリティ設定の平文保存（v3.3で再分類）
**ファイル**: `main.dart`
**現状**: v3.3 で `kuraudo_settings.json` のセキュリティ重要項目（autoLockMinutes 等）は SecureStorage へ移行済み。残った項目は `themeMode` `passwordExpiryDays` `autoSyncEnabled` `realtimeSyncEnabled` `syncBackend` のみ。
**判断**: これらはセキュリティ影響がないため平文 JSON で保持。バックアップ・同期しても問題ない。

### ファイルヘッダーのHMAC不足
**ファイル**: `kuraudo_file.dart`
**判断**: AES-GCM の認証タグが復号時に改ざんを検出するため、実用上の影響はない。

---

## 🔵 同期バックエンドのセキュリティ考慮

### WebDAV認証情報の保管 ✅
サーバーURL、ユーザー名、パスワード、リモートパスを SecureStorage に保存。Android Keystore / Linux Secret Service / Windows Credential Manager 経由。

### キーリングが無い環境の認証情報保管（2026-09-12） ✅
**ファイル**: `secret_store.dart`
OS のキーリングが使えない環境（KDE ウォレットを無効にした Linux 等）では、同期の認証情報を Vault と同じ Argon2id + AES-256-GCM で暗号化し、アプリ設定フォルダの `kuraudo_secrets.enc` に保存する。
- 復号鍵はマスターパスワードから派生（Argon2id は解錠時の 1 回のみ）。Vault 施錠時に鍵と平文をメモリから破棄
- 解錠していない間は読み書きできない（施錠中の書き込みは無視される）
- ノンスは保存のたびに新規生成。書き込みは一時ファイル経由で置き換え
- マスターパスワード変更時は `onMasterPasswordChanged` 経由で再暗号化
- 端末内に留め、同期・バックアップの対象にしない
- PIN はこの仕組みの対象外（解錠前に必要なため、引き続きキーリングが必要）

### WebDAV通信の暗号化（H-03で対応） ✅
HTTPS を必須化。HTTP は明示的同意が必要に。

### WebDAV自己署名証明書（未対応）
TOFU 方式の証明書ピン留めなど、適切な実装が必要なため、安易にバイパスを許可しない方針。

### ローカルパス同期先のアクセス権
ファイルパーミッションは OS のデフォルトに依存。Vault は AES-256-GCM 暗号化済みのため、ファイルが他者に読まれてもマスターパスワードがなければ復号不可。

### 同期バックエンド切り替え時の旧情報
バックエンド切り替え時、旧バックエンドの認証情報は SecureStorage に残ったまま。ユーザーが意図的に切り替えただけかもしれないので、自動削除はしない。明示的な「切断」操作で削除される設計。

### WebDAV接続情報の名前空間衝突
SecureStorage キーは `webdav_*`、`localpath_*`、`gdrive_*` でプレフィックス分離済み。

---

## ✅ 設計の良好な点

- **AES-256-GCM**: 認証付き暗号化で改ざん検出が組み込まれている
- **Argon2id**: 最新の鍵導出関数（bcrypt/PBKDF2より優秀）
- **ソルト/ノンス**: 暗号化ごとにランダム生成、再利用なし
- **ゼロ知識設計**: サーバーにパスワードを一切送信しない
- **OAuthトークン**: `flutter_secure_storage` で暗号化保存
- **OAuthシークレット**: ビルド時注入（ソースに含まれない）
- **クリップボード自動クリア**: 30秒で実装済み（エクスポート時も同様）
- **外部依存の最小化**: 暗号化は純Dart実装（`argon2` + `pointycastle`）のみ使用
- **PIN総当たり対策**: 5回失敗で MP 強制 + 任意で永続化バックオフ（v3.1）
- **マスターパスワード変更の権限確認**（v3.1）: 現パスワード必須化で勝手な書き換えを防止
- **WebDAV HTTPS 強制**（v3.1）: HTTP は明示同意が必要
- **AutoType の秘密保護**（v3.2）: xdotool 入力を stdin 経由化、/proc/cmdline に出さない
- **OAuth CSRF 防止**（v3.2）: state nonce 検証で偽コード送り込みを拒否
- **セキュリティ設定の改ざん耐性**（v3.3）: 自動ロック・PIN 等の重要設定を SecureStorage 保護
- **Autofill キャッシュのロック時消去**（v3.4）: Vault ロック時に Android ネイティブキャッシュをクリア
- **エクスポート保護**: マスターパスワード再確認 + ファイル削除オプション
- **辞書攻撃対応の強度評価**: よく使われるPW・パターン・リート表記を検出
- **OS既定領域への保存は最小限**: 設定・バックアップは Vault と同じフォルダ、認証情報は OS のキーストアに格納。OS 標準のアプリ設定フォルダには Vault のパスポインタ（と、キーリングが使えない環境で同意を得た自動ロック・クリップボード設定）のみ置く
- **複数バックエンド対応のキー分離**: SecureStorage のキーをバックエンド毎にプレフィックスで分離（混在防止）

---

*Kuraudo Security Audit — 2026年5月19日（v3.4更新 - MEDIUM全件対応完了）*
