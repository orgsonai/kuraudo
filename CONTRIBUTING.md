# Contributing to Kuraudo

## コントリビューション方針

<<<<<<< HEAD
Kuraudo は個人プロジェクト（[Zero to Ship](https://zero-to-ship.vercel.app)）から生まれたアプリです。コミュニティからの協力を歓迎しますが、開発方針の最終判断は開発者が行います。
=======
Kuraudo は個人プロジェクト（[Zero to Ship](https://zero-to-ship-app.vercel.app)）から生まれたアプリです。コミュニティからの協力を歓迎しますが、開発方針の最終判断は開発者が行います。
>>>>>>> a28cd27 (fix: URLをorgsonai/zero-to-ship-appに修正)

## Issue

### 歓迎するもの

- **バグ報告** — 再現手順を含めて報告いただけると助かります
- **セキュリティの懸念** — [SECURITY.md](SECURITY.md) に従ってください（公開Issueは使わないでください）
- **機能リクエスト** — 「こういう機能があると便利」という提案
- **翻訳の改善** — 日本語/英語の表現の修正

### Issue テンプレート

バグ報告時は以下の情報を含めてください:

- OS とバージョン（例: Windows 11 23H2, Ubuntu 24.04, Android 14）
- Kuraudo のバージョン
- 再現手順
- 期待される動作と実際の動作
- スクリーンショット（可能であれば）

## Pull Request

### 受け付けるもの

- バグ修正
- タイポ修正
- ドキュメントの改善

### 要相談（先にIssueで議論してください）

- 新機能の追加
- UIの大幅な変更
- 依存パッケージの追加・変更
- 暗号化関連コードの変更

暗号化に関する変更は特に慎重に扱います。`lib/core/` 以下のコードを変更するPRは、変更理由の詳細な説明を求めます。

### PR のガイドライン

1. フォークしてブランチを作成してください
2. 既存のコードスタイルに合わせてください
3. 変更内容を説明するコミットメッセージを書いてください
4. テストがある場合は `flutter test` が通ることを確認してください

## 開発環境

```bash
# セットアップ
<<<<<<< HEAD
git clone https://github.com/zerotoship/kuraudo.git
=======
git clone https://github.com/orgsonai/kuraudo.git
>>>>>>> a28cd27 (fix: URLをorgsonai/zero-to-ship-appに修正)
cd kuraudo
flutter pub get
flutter run
```

### コードスタイル

- Dart の標準的なスタイルに従う（`dart format`）
- ファイル先頭に `///` ドキュメントコメントを記載
- 日本語コメント推奨（UIの文字列は日本語）

## ライセンス

コントリビューションは [GPL-3.0](LICENSE) の下で提供されます。PRを送信することで、このライセンスに同意したものとみなします。

## 行動規範

- 敬意を持ったコミュニケーションをお願いします
- 建設的なフィードバックを心がけてください
- パスワード管理アプリという性質上、セキュリティに対する慎重さを尊重してください
