import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kuraudo/services/secret_store.dart';

void main() {
  // テストではキーリング（プラグイン）が使えないため、暗号化ファイル側が選ばれる
  TestWidgetsFlutterBinding.ensureInitialized();

  test('キーリングが無くてもマスターパスワードで暗号化して保存・復元できる', () async {
    final dir = await Directory.systemTemp.createTemp('kuraudo_secret_store');
    final store = SecretStore.instance;
    store.directoryOverride = dir;
    addTearDown(() async {
      store.lock();
      store.directoryOverride = null;
      await dir.delete(recursive: true);
    });

    await store.unlock('master-password');
    await store.write(key: 'kuraudo_oauth_refresh_token', value: 'token-123');
    store.lock();

    // 施錠中は読めない
    expect(await store.read(key: 'kuraudo_oauth_refresh_token'), isNull);

    // 解錠し直すと復元できる
    await store.unlock('master-password');
    expect(await store.read(key: 'kuraudo_oauth_refresh_token'), 'token-123');

    // ファイルに平文で残っていない
    final bytes =
        await File('${dir.path}${Platform.pathSeparator}kuraudo_secrets.enc')
            .readAsBytes();
    expect(String.fromCharCodes(bytes).contains('token-123'), isFalse);

    await store.delete(key: 'kuraudo_oauth_refresh_token');
    expect(await store.read(key: 'kuraudo_oauth_refresh_token'), isNull);
  });

  test('マスターパスワードが違うと復号できず、空から作り直す', () async {
    final dir = await Directory.systemTemp.createTemp('kuraudo_secret_store');
    final store = SecretStore.instance;
    store.directoryOverride = dir;
    addTearDown(() async {
      store.lock();
      store.directoryOverride = null;
      await dir.delete(recursive: true);
    });

    await store.unlock('password-a');
    await store.write(key: 'webdav_password', value: 'secret');
    store.lock();

    await store.unlock('password-b');
    expect(await store.read(key: 'webdav_password'), isNull);
  });
}
