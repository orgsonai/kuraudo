# Kuraudo（蔵人）— 開発ハンドオフ資料

## プロジェクト概要
- **アプリ名**: Kuraudo（蔵人）
- **種別**: Google Drive同期型パスワードマネージャー
- **フレームワーク**: Flutter (Dart)
- **対象OS**: Linux / Android（Windows版は保留中）
- **ライセンス**: GPL-3.0
- **所属**: Zero to Ship プロジェクト
- **開発環境**: Arch Linux KDE Wayland
- **開発手法**: AI駆動開発（Claude） — 設計・コード生成・ドキュメント作成をAIが担当、人間は方針指示・変更要望・動作確認

## 完了済み
- フェーズ1〜5: 暗号化エンジン、UI8画面、Google Drive同期、インポート/エクスポート拡張、TOTP+Autofill基盤
- レスポンシブUI: PC2ペイン（左フォルダツリー+右カラム付き一覧） / スマホ1ペイン
- PC操作: クリック=フォーカス、ダブルクリック=編集、↑↓=フォーカス移動、Enter=編集、Alt+↑↓=順番変更
- カラム表示: タイトル/ユーザー名/カテゴリ/更新日
- フォルダ管理: エントリのcategoryフィールドベースの動的フォルダ（エントリ無しで自動消滅）、フォルダ名変更（全エントリ一括更新＋プルダウン選択対応）
- ソート: タイトル/作成日（新旧）/更新日（新旧）の6種、状態保存
- URL→ブラウザ連携（url_launcher）
- パスワード生成器: スペース/拡張特殊文字/20件バッチ（番号なし）、詳細設定（カスタム特殊文字・除外文字・プリセット4種）
- パスワード履歴: 表示/非表示ボタン付き
- バグ修正: AES-GCMバッファ、CSVマルチライン、Flutter互換性、Argon2名前衝突
- 公開管理: LICENSE/SECURITY.md/CONTRIBUTING.md/PRIVACY.md/.gitignore/CI-CD
- Store公開準備: MSIX設定、メタデータ、説明文テンプレート
- フェーズ5.5: Vault場所エクスプローラー選択、ゴミ箱機能（削除→ゴミ箱→完全削除）、メニュー位置修正、アニメーション即座化
- フェーズ6: エクスポートファイル保存/クリップボード選択、自動ロックタイムアウト設定（0〜30分+即時）、パスワード有効期限設定（30〜365日）、ダッシュボード統計（弱PW/重複PWバッジ）、パスワード期限切れ警告バー
- フェーズ7: 同期v2.0 UUID単位マージ（Vault.mergeWith + SyncManager.mergeSync + UI）
- フェーズ8: 重複パスワード検出ダイアログ、期限切れPW/重複PWを三点メニューからアクセス可能に
- フェーズ9: スマホ版自動ロック修正（ライフサイクル+操作タイマー二重方式）、即時ロック選択肢追加
- フェーズ10: PIN/生体認証による簡易ロック解除（local_auth + flutter_secure_storage）、設定画面トグル
- フェーズ11: Android Autofill Service 完全実装（KuraudoAutofillService.kt + MainActivity.kt + MethodChannel連携）
- フェーズ12: 同期時コンテンツベース重複検出（UUID不一致でもタイトル+ユーザー名+URLで重複スキップ）
- カテゴリ/フォルダUI改善: Autocomplete廃止→矢印プルダウンのみ、メニューからの新規フォルダ作成廃止、フォルダ名変更時プルダウン追加
- 手動インポート時の重複スキップ: コンテンツベース重複検出で既存エントリと照合、「重複スキップ/全てインポート」分岐
- クラウド同期画面に最終同期時刻を表示（相対時刻 + 絶対時刻）
- Windows/Linux デスクトップ自動入力: xdotool（Linux）/ PowerShell SendKeys（Windows）によるAutoType実装、エントリ詳細画面に「自動入力」ボタン、設定画面に使い方説明追加
- 検索ボックスにクリア（×）ボタン追加（PC版・モバイル版両方）
- クリップボードセキュリティ強化: バックグラウンド移行時＋アプリ終了時にクリップボード即クリア
- バックアップ世代管理を手動/自動分離: 各3世代保持（合計最大6つ）、ファイル名にlabel（manual/auto）を含む
- クリップボード完全クリア: Android 9+ clearPrimaryClip()で履歴ごと削除、設定画面にON/OFFトグル、バックグラウンド移行時・アプリ終了時にも即座クリア
- Argon2idパラメータ強化: デスクトップ64MB/4並列、モバイル32MB/2並列（OWASP推奨水準）
- パスワード強度評価強化: 辞書攻撃耐性（よく使われるPW、キーボードパターン、辞書単語、リート表記検出）
- PIN認証試行回数制限: 5回失敗でマスターパスワード強制
- エクスポートセキュリティ強化: マスターパスワード再確認、クリップボード30秒自動クリア、ファイル削除アクション

## 未完了
- スクリーンショット撮影
- Google Play 実際の公開申請
- Microsoft Store 公開（保留中 — Windowsビルド環境が必要）

## 実機テスト済み
- ✅ Google Drive同期（PC↔Android間、マージ同期確認済み）
- ✅ Android実機ビルド・動作確認
- ✅ 生体認証（指紋）動作確認
- ✅ PIN簡易ロック解除動作確認
- ✅ 自動ロック（スマホバックグラウンド＋即時ロック）
- ✅ Autofill Service 登録確認

## 技術仕様

### 暗号化
- KDF: Argon2id (desktop: 64MB/3回/4並列, mobile: 32MB/3回/2並列)
- 暗号化: AES-256-GCM (nonce: 12B, tag: 16B, ソルト: 32B)
- パッケージ: `argon2`(純Dart) + `pointycastle`(AES-GCM)
- import衝突回避: `hide Argon2Parameters, Argon2BytesGenerator`
- KDFパラメータはファイルヘッダーに保存されるため、変更後も旧ファイルの読み込みは維持される

### .kuraudoファイル
Header 62B: Magic"KRAD"(4) + Version(2) + KDFParams(12) + Salt(32) + Nonce(12) → Encrypted Payload + GCM Tag(16)

### 依存パッケージ
pointycastle, argon2, uuid, path_provider, google_sign_in, googleapis, http, connectivity_plus, cupertino_icons, url_launcher, local_auth, flutter_secure_storage, msix(dev)

### 自動ロック仕組み
- `WidgetsBindingObserver` でライフサイクル監視（paused/hidden/inactive/resumed）
- `Listener` ウィジェットでフォアグラウンド操作検知 → `_lastInteractionTime` リセット
- `_checkAutoLock()`: バックグラウンド経過時間 or 無操作時間が閾値超過でロック
- 短時間ロック（PIN/生体有効＋閾値以内）→ `_quickLocked = true`（Vaultメモリ保持、画面ロックのみ）
- 長時間ロック → `VaultService.lock()` でメモリ消去、マスターPW必須

### PIN/生体認証
- PIN: `flutter_secure_storage` で4桁PINを暗号化保存
- 生体認証: `local_auth` パッケージ（`FlutterFragmentActivity` 必須）
- quickLocked時に `didUpdateWidget` で生体認証を自動トリガー
- 「マスターパスワードで解除」リンクで完全ロック画面に切替可能

### Autofill Service（Android）
- `KuraudoAutofillService.kt`: AutofillServiceを継承、フォーム解析＋候補表示
- `MainActivity.kt`: `FlutterFragmentActivity` 継承、MethodChannel連携
- フォーム解析: autofillHints → inputType → HTML属性 → idEntry の優先順で検出
- マッチング: URL/ドメイン完全一致 → 部分一致 → タイトル一致
- キャッシュ: Vault解錠時＋保存時にFlutter→Kotlin側へエントリ送信

### 同期マージ
- UUID一致: updatedAtが新しい方を採用
- UUID不一致: コンテンツベース重複検出（タイトル+ユーザー名+URL正規化）
- コンテンツ重複時: ローカルUUIDを維持し中身のみ更新（新しい方を採用）

## ファイル構成
```
lib/core/          crypto_engine / kuraudo_file / password_generator / totp_generator
lib/models/        vault_entry (VaultEntry, PasswordRecord, Vault, MergeResult)
lib/services/      vault_service / csv_importer / google_drive_service / sync_manager / autofill_service
lib/ui/screens/    lock / home / entry_detail / entry_edit / account_link / import / settings / sync
lib/ui/widgets/    password_generator_sheet / totp_display / responsive_layout
lib/ui/theme/      kuraudo_theme
lib/               main.dart / kuraudo.dart(barrel)
android/app/src/main/kotlin/com/zerotoship/kuraudo/
                   MainActivity.kt / KuraudoAutofillService.kt
android/app/src/main/res/xml/
                   autofill_service.xml
docs/              kuraudo-spec-v1.docx / store-metadata.md / android-setup.md / android-build-guide.md
```

## 修正時の注意
- 既存コードをベースに修正（新規書き直しはしない）
- Flutter最新版: `CardThemeData`, `DialogThemeData`
- KDFパラメータ: desktop 64MB/3回/4並列、mobile 32MB/3回/2並列（OWASP推奨水準）
- OAuthシークレット: `--dart-define=GOOGLE_CLIENT_SECRET=xxx` でビルド時注入（ソースに含めない）
- PC版: home_screenの`_pcList`がカラム付きテーブル表示
- UI状態は`kuraudo_ui_state.json`に永続化
- アプリ設定は`kuraudo_settings.json`に永続化（autoLockMinutes, passwordExpiryDays, lastVaultPath, pinEnabled, biometricEnabled, pinThresholdMinutes）
- パスワード生成: 各文字種からrequiredに1文字確保→シャッフルで保証、customSymbols/excludeChars対応
- エントリ削除はゴミ箱経由（deletedAtフィールド）、activeEntriesでゴミ箱除外
- フォルダはエントリのcategoryフィールドで管理（エントリ無し→フォルダ自動消滅）
- ポップアップメニューはpopUpAnimationStyle: AnimationStyle(duration: Duration.zero)で即座表示
- メニュー位置はBuilder + overlay基準のRelativeRectで正確に計算
- Android: MainActivityは `FlutterFragmentActivity` を継承（local_auth要件）
- Android: minSdk = 26（Autofill API要件）
- Autofillキャッシュ: Vault解錠時＋エントリ保存時にnative側へ自動送信
- デスクトップAutoType: Linux=xdotool、Windows=PowerShell SendKeys。未インストール時はクリップボードフォールバック
- 検索ボックス: TextEditingController (_searchCtrl) でクリアボタン制御
- クリップボード: copyToClipboardSensitive()（Android 13+ IS_SENSITIVE対応）、copyAndScheduleClear()、clearClipboardFully()（Linux: Wayland wl-copy --clear / X11 xclip -i /dev/null を自動検出、Windows: PowerShell、Android: clearPrimaryClip）を共通関数として使用。設定のclipboardAutoClearで制御

---
*最終更新: 2026年4月3日*
