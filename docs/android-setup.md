# Android設定メモ

## android/app/src/main/AndroidManifest.xml に追記が必要

### <manifest> 直下に追加:
```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

### <application> の前に追加（url_launcher用）:
```xml
<queries>
    <intent>
        <action android:name="android.intent.action.VIEW" />
        <data android:scheme="https" />
    </intent>
</queries>
```

## android/app/build.gradle.kts
- minSdk を 21 以上に設定（google_sign_in要件）
- targetSdk を 34 に設定

## Google Play 公開時
- android/key.properties を作成（署名鍵の設定）
- google-services.json を android/app/ に配置
