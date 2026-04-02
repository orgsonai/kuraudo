# Kuraudo — Android化ガイド

## 前提条件

- Android Studio がインストール済み
- Android SDK（API 34推奨）
- Java 17（`flutter doctor`で確認）
- Android実機 or エミュレータ

```bash
# 環境確認
flutter doctor
```

---

## 手順

### 1. Androidプロジェクトの確認

Flutterプロジェクトなら`android/`フォルダは既にあるはずです。

```bash
ls android/app/src/main/AndroidManifest.xml
```

### 2. AndroidManifest.xml を編集

`android/app/src/main/AndroidManifest.xml` を開いて以下を確認・追加：

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <!-- インターネット権限（必須） -->
    <uses-permission android:name="android.permission.INTERNET"/>

    <!-- url_launcher用（ブラウザでURL開く） -->
    <queries>
        <intent>
            <action android:name="android.intent.action.VIEW" />
            <data android:scheme="https" />
        </intent>
    </queries>

    <application
        android:label="Kuraudo"
        ...>
        <!-- 既存の内容はそのまま -->
    </application>
</manifest>
```

### 3. build.gradle.kts を編集

`android/app/build.gradle.kts` を確認：

```kotlin
android {
    // ...
    defaultConfig {
        applicationId = "com.zerotoship.kuraudo"
        minSdk = 21          // ← 21以上（google_sign_in要件）
        targetSdk = 34       // ← 最新推奨
        // ...
    }
}
```

### 4. Google Cloud ConsoleでAndroid用OAuthクライアントIDを確認

既にAndroid用のクライアントIDを作成済みなら、SHA-1フィンガープリントが正しいか確認します。

```bash
# デバッグ用SHA-1を取得
keytool -list -v \
  -keystore ~/.android/debug.keystore \
  -alias androiddebugkey \
  -storepass android \
  -keypass android 2>/dev/null | grep SHA1
```

→ この値がGoogle Cloud Consoleに登録したSHA-1と一致している必要があります。

**一致していない場合：**
1. Google Cloud Console → APIとサービス → 認証情報
2. Android用クライアントIDを編集
3. SHA-1フィンガープリントを↑の値に更新

### 5. ビルド・実行

```bash
# デバッグ実行（実機接続 or エミュレータ起動後）
flutter run

# デバイス一覧
flutter devices

# リリースAPKビルド
flutter build apk --release

# Play Store用App Bundle
flutter build appbundle --release
```

APKの場所: `build/app/outputs/flutter-apk/app-release.apk`

### 6. 実機にインストール

```bash
# USBデバッグをONにした実機に直接インストール
flutter install
```

または APKを実機に転送して手動インストール。

---

## Google Drive同期のテスト（Android）

Androidでは`google_sign_in`パッケージが使われるため、Linuxとは認証方式が異なります。

1. アプリを起動
2. 三点メニュー → クラウド同期
3. 「Googleアカウントでサインイン」をタップ
4. Googleのアカウント選択画面が表示される（ネイティブUI）
5. アカウントを選択→権限を許可
6. 同期が使えるようになる

**注意**: テスト段階では、OAuth同意画面で「テストユーザー」に登録したGoogleアカウントでのみ動作します。

---

## トラブルシューティング

### `PlatformException(sign_in_failed, ...)`
- SHA-1がGoogle Cloud Consoleの登録と一致しているか確認
- パッケージ名が`com.zerotoship.kuraudo`になっているか確認
- Google Drive APIが有効になっているか確認

### `minSdk`エラー
- `android/app/build.gradle.kts`の`minSdk`を21以上に設定

### Argon2がAndroidで動かない
- `argon2`パッケージは純Dart実装なのでAndroidでも動くはず
- もし問題があれば`flutter clean && flutter pub get`を試す

### ビルドが遅い
- 初回は依存関係のダウンロードで10-20分かかることがある
- 2回目以降はキャッシュが効くため高速

---

## リリース署名（Google Play公開時のみ）

```bash
# 署名鍵を生成
keytool -genkey -v -keystore ~/kuraudo-release.keystore \
  -alias kuraudo -keyalg RSA -keysize 2048 -validity 10000
```

`android/key.properties` を作成：
```properties
storePassword=あなたのパスワード
keyPassword=あなたのパスワード
keyAlias=kuraudo
storeFile=/home/あなた/kuraudo-release.keystore
```

`android/app/build.gradle.kts` に署名設定を追加（Flutter公式ドキュメント参照）。

**key.propertiesとkeystoreは絶対にGitにコミットしないこと！**
